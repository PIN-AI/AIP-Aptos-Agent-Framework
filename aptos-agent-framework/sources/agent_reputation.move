/// Aptos Agent Framework - Reputation Module
/// Implements tokenized reputation system with "core immutable, state mutable" design
module aaf::agent_reputation {
    use std::signer;
    use std::string::String;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use aaf::agent::{Self, Agent};

    // ==================== Constants ====================

    /// Maximum number of response records (prevent unlimited growth)
    const MAX_RESPONSES: u64 = 100;

    // ==================== Data Structures ====================

    /// Response record attached to a reputation
    /// Stored as independent object to avoid main NFT bloat
    struct ResponseRecord has key {
        reputation: address,       // Associated reputation NFT address
        responder: address,
        response_uri: String,
        response_hash: vector<u8>,
        timestamp: u64,
        index: u64,               // Response index (nth response)
    }

    /// Reputation NFT: Core data immutable, state data mutable
    struct ReputationNFT has key {
        // ===== Immutable Core (set at creation) =====
        agent: address,
        issuer: address,
        score: u8,                  // 0-100
        context_hash: vector<u8>,   // Hash of task/interaction context
        file_uri: String,           // Off-chain detailed feedback
        file_hash: vector<u8>,      // Hash of file_uri content
        issued_at: u64,
        feedback_index: u64,        // Monotonic index for this issuer->agent

        // ===== Mutable State =====
        revoked: bool,
        response_count: u64,        // Response count tracker
    }

    /// Issuer capability store (using Table instead of per-address resource)
    struct IssuerCapabilityStore has key {
        issuers: Table<address, bool>,
    }

    /// ✅ NEW: Governance config to avoid hardcoded admin address
    struct GovernanceConfig has key {
        admin: address,
    }

    // ==================== Events ====================

    #[event]
    struct ReputationIssued has drop, store {
        reputation_obj: address,
        agent: address,
        issuer: address,
        score: u8,
        context_hash: vector<u8>,  // Keep hash for indexing
        file_hash: vector<u8>,     // Keep hash for verification
        feedback_index: u64,
        issued_at: u64,
    }

    #[event]
    struct ReputationRevoked has drop, store {
        reputation_obj: address,
        agent: address,
        issuer: address,
        timestamp: u64,
    }

    #[event]
    struct ResponseAppended has drop, store {
        reputation_obj: address,
        response_obj: address,
        agent: address,
        responder: address,
        response_hash: vector<u8>,  // Keep hash for verification
        index: u64,
        timestamp: u64,
    }

    #[event]
    struct GovernanceTransferred has drop, store {
        old_admin: address,
        new_admin: address,
        timestamp: u64,
    }

    // ==================== Error Codes ====================

    const E_SCORE_OUT_OF_RANGE: u64 = 0x20001;
    const E_ISSUER_FORBIDDEN: u64 = 0x20002;
    const E_NOT_ISSUER: u64 = 0x20003;
    const E_ALREADY_REVOKED: u64 = 0x20004;
    const E_NOT_ADMIN: u64 = 0x20005;
    const E_CAPABILITY_EXISTS: u64 = 0x20006;
    const E_TOO_MANY_RESPONSES: u64 = 0x20007;
    const E_INVALID_FILE_URI: u64 = 0x20008;

    // ==================== Module Initialization ====================

    /// Initialize issuer capability store on module deployment
    fun init_module(deployer: &signer) {
        init_internal(deployer);
    }

    /// Internal initialization logic (exposed for testing)
    #[test_only]
    public fun init_for_test(deployer: &signer) {
        init_internal(deployer);
    }

    /// Common initialization logic
    fun init_internal(deployer: &signer) {
        let deployer_addr = signer::address_of(deployer);
        
        // Only initialize if not already done
        if (!exists<IssuerCapabilityStore>(deployer_addr)) {
            move_to(deployer, IssuerCapabilityStore {
                issuers: table::new(),
            });
        };

        if (!exists<GovernanceConfig>(deployer_addr)) {
            move_to(deployer, GovernanceConfig {
                admin: deployer_addr,
            });
        };
    }

    // ==================== Public Functions ====================

    /// Issue a soulbound reputation NFT to an agent and return its address (internal version)
    ///
    /// # Parameters
    /// - issuer: Issuer signer
    /// - agent: Agent object
    /// - score: Score (0-100)
    /// - context_hash: Task context hash
    /// - file_uri: Off-chain detailed feedback URI
    /// - file_hash: File content hash
    /// - gated: Whether issuer capability is required (credentialed mode)
    ///
    /// # Returns
    /// Address of the created reputation NFT
    public fun issue_reputation_internal(
        issuer: &signer,
        agent: Object<Agent>,
        score: u8,
        context_hash: vector<u8>,
        file_uri: String,
        file_hash: vector<u8>,
        gated: bool
    ): address acquires IssuerCapabilityStore {
        // Input validation
        assert!(score <= 100, E_SCORE_OUT_OF_RANGE);
        assert!(!std::string::is_empty(&file_uri), E_INVALID_FILE_URI);

        let issuer_addr = signer::address_of(issuer);
        let agent_addr = object::object_address(&agent);

        // Gated check
        if (gated) {
            let store = borrow_global<IssuerCapabilityStore>(@aaf);
            assert!(table::contains(&store.issuers, issuer_addr), E_ISSUER_FORBIDDEN);
        };

        // Verify agent's feedback authorization and consume quota
        let feedback_index = agent::verify_and_consume_feedback_auth(agent, issuer_addr);

        // Create reputation NFT object
        let constructor_ref = object::create_object(issuer_addr);
        let object_signer = object::generate_signer(&constructor_ref);
        let reputation_addr = signer::address_of(&object_signer);

        let now = timestamp::now_seconds();

        // Create reputation resource
        move_to(&object_signer, ReputationNFT {
            agent: agent_addr,
            issuer: issuer_addr,
            score,
            context_hash: copy context_hash,
            file_uri,
            file_hash: copy file_hash,
            issued_at: now,
            feedback_index,
            revoked: false,
            response_count: 0,
        });

        // Completely disable transfer (true soulbound)
        object::set_untransferable(&constructor_ref);

        // Emit event
        event::emit(ReputationIssued {
            reputation_obj: reputation_addr,
            agent: agent_addr,
            issuer: issuer_addr,
            score,
            context_hash,  // Keep hash for indexing
            file_hash,     // Keep hash for verification
            feedback_index,
            issued_at: now,
        });

        // Return the reputation address
        reputation_addr
    }

    // ==================== Public Entry Functions ====================

    /// Issue a soulbound reputation NFT to an agent (transaction entry point)
    ///
    /// # Parameters
    /// - issuer: Issuer signer
    /// - agent: Agent object
    /// - score: Score (0-100)
    /// - context_hash: Task context hash
    /// - file_uri: Off-chain detailed feedback URI
    /// - file_hash: File content hash
    /// - gated: Whether issuer capability is required (credentialed mode)
    ///
    /// # Note
    /// This is the transaction entry point. The created reputation address can be obtained
    /// from the ReputationIssued event. For composable calls and testing, use
    /// `issue_reputation_internal` instead which returns the reputation address.
    public entry fun issue_reputation(
        issuer: &signer,
        agent: Object<Agent>,
        score: u8,
        context_hash: vector<u8>,
        file_uri: String,
        file_hash: vector<u8>,
        gated: bool
    ) acquires IssuerCapabilityStore {
        // Delegate to internal function (discard return value for entry function)
        issue_reputation_internal(issuer, agent, score, context_hash, file_uri, file_hash, gated);
    }

    /// Issuer revokes their previously issued reputation
    public entry fun revoke_reputation(
        issuer: &signer,
        reputation_addr: address
    ) acquires ReputationNFT {
        let reputation = borrow_global_mut<ReputationNFT>(reputation_addr);
        assert!(reputation.issuer == signer::address_of(issuer), E_NOT_ISSUER);
        assert!(!reputation.revoked, E_ALREADY_REVOKED);

        reputation.revoked = true;

        event::emit(ReputationRevoked {
            reputation_obj: reputation_addr,
            agent: reputation.agent,
            issuer: reputation.issuer,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Append response record to a reputation
    /// Creates independent ResponseRecord object to avoid main NFT bloat
    public entry fun append_response(
        responder: &signer,
        reputation_addr: address,
        response_uri: String,
        response_hash: vector<u8>
    ) acquires ReputationNFT {
        let reputation = borrow_global_mut<ReputationNFT>(reputation_addr);

        // Check response count limit
        assert!(reputation.response_count < MAX_RESPONSES, E_TOO_MANY_RESPONSES);

        let responder_addr = signer::address_of(responder);
        let now = timestamp::now_seconds();

        // Create independent response object
        let constructor_ref = object::create_object(responder_addr);
        let object_signer = object::generate_signer(&constructor_ref);
        let response_addr = signer::address_of(&object_signer);

        let index = reputation.response_count;

        move_to(&object_signer, ResponseRecord {
            reputation: reputation_addr,
            responder: responder_addr,
            response_uri,
            response_hash: copy response_hash,
            timestamp: now,
            index,
        });

        // Update counter
        reputation.response_count = reputation.response_count + 1;

        event::emit(ResponseAppended {
            reputation_obj: reputation_addr,
            response_obj: response_addr,
            agent: reputation.agent,
            responder: responder_addr,
            response_hash,  // Keep hash for verification
            index,
            timestamp: now,
        });
    }

    /// Grant issuer capability
    /// Admin function (can be replaced with DAO governance in future)
    public entry fun grant_issuer_capability(
        admin: &signer,
        issuer: address
    ) acquires IssuerCapabilityStore, GovernanceConfig {
        // ✅ Fixed: Use configurable admin address instead of hardcoded @aaf
        let config = borrow_global<GovernanceConfig>(@aaf);
        assert!(signer::address_of(admin) == config.admin, E_NOT_ADMIN);

        let store = borrow_global_mut<IssuerCapabilityStore>(@aaf);
        assert!(!table::contains(&store.issuers, issuer), E_CAPABILITY_EXISTS);

        table::add(&mut store.issuers, issuer, true);
    }

    /// Revoke issuer capability
    public entry fun revoke_issuer_capability(
        admin: &signer,
        issuer: address
    ) acquires IssuerCapabilityStore, GovernanceConfig {
        // ✅ Fixed: Use configurable admin address
        let config = borrow_global<GovernanceConfig>(@aaf);
        assert!(signer::address_of(admin) == config.admin, E_NOT_ADMIN);

        let store = borrow_global_mut<IssuerCapabilityStore>(@aaf);
        if (table::contains(&store.issuers, issuer)) {
            table::remove(&mut store.issuers, issuer);
        };
    }

    /// ✅ NEW: Transfer governance to new admin
    public entry fun transfer_governance(
        admin: &signer,
        new_admin: address
    ) acquires GovernanceConfig {
        let config = borrow_global_mut<GovernanceConfig>(@aaf);
        let old_admin = config.admin;
        assert!(signer::address_of(admin) == old_admin, E_NOT_ADMIN);

        config.admin = new_admin;

        event::emit(GovernanceTransferred {
            old_admin,
            new_admin,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ==================== View Functions ====================

    #[view]
    /// Get reputation core data
    public fun get_reputation(reputation_addr: address): (address, address, u8, bool, u64, u64) acquires ReputationNFT {
        let reputation = borrow_global<ReputationNFT>(reputation_addr);
        (
            reputation.agent,
            reputation.issuer,
            reputation.score,
            reputation.revoked,
            reputation.issued_at,
            reputation.response_count
        )
    }

    #[view]
    /// Get response record info
    public fun get_response(response_addr: address): (address, address, String, u64, u64) acquires ResponseRecord {
        let response = borrow_global<ResponseRecord>(response_addr);
        (
            response.reputation,
            response.responder,
            response.response_uri,
            response.timestamp,
            response.index
        )
    }

    #[view]
    /// Check if address has issuer capability
    public fun has_issuer_capability(issuer: address): bool acquires IssuerCapabilityStore {
        let store = borrow_global<IssuerCapabilityStore>(@aaf);
        table::contains(&store.issuers, issuer)
    }

    #[view]
    /// Get current governance admin
    public fun get_admin(): address acquires GovernanceConfig {
        let config = borrow_global<GovernanceConfig>(@aaf);
        config.admin
    }
}

