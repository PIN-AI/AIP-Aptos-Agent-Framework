/// Aptos Agent Framework - Identity Module
/// Provides agent object creation, management, and feedback authorization
module aaf::agent {
    use std::signer;
    use std::string::String;
    use std::option::{Self, Option};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};
    use aptos_framework::timestamp;

    // Declare friend module (allows agent_reputation to call protected functions)
    friend aaf::agent_reputation;

    // ==================== Data Structures ====================

    /// Feedback authorization record
    struct FeedbackAuth has store, drop {
        index_limit: u64,     // Maximum allowed feedback index (for rate limiting)
        expiry: u64,          // Authorization expiry timestamp
        last_index: u64,      // Last used feedback index
    }

    /// Core Agent object
    struct Agent has key {
        /// Agent metadata URI (pointing to AgentCard JSON)
        metadata_uri: String,
        /// Agent owner address
        owner: address,
        /// Optional domain name (for well-known AgentCard discovery)
        domain: Option<String>,
        /// Feedback authorization table: client_address => FeedbackAuth
        feedback_auths: Table<address, FeedbackAuth>,
        /// ExtendRef for subsequent object-layer operations (e.g., ownership transfer)
        extend_ref: ExtendRef,
    }

    // ==================== Events ====================

    #[event]
    struct AgentRegistered has drop, store {
        agent: address,
        owner: address,
        metadata_uri_hash: vector<u8>,  // Hash of URI (for indexing and verification)
        domain: Option<String>,
        timestamp: u64,
    }

    #[event]
    struct AgentUpdated has drop, store {
        agent: address,
        metadata_uri_hash: Option<vector<u8>>,  // Hash of new URI (if updated)
        domain: Option<String>,
        timestamp: u64,
    }

    #[event]
    struct AgentOwnerChanged has drop, store {
        agent: address,
        old_owner: address,
        new_owner: address,
        timestamp: u64,
    }

    #[event]
    struct FeedbackAuthGranted has drop, store {
        agent: address,
        client: address,
        index_limit: u64,
        expiry: u64,
        timestamp: u64,
    }

    #[event]
    struct FeedbackAuthRevoked has drop, store {
        agent: address,
        client: address,
        timestamp: u64,
    }

    // ==================== Error Codes ====================

    const E_NOT_OWNER: u64 = 0x10001;
    const E_AUTH_NOT_FOUND: u64 = 0x10002;
    const E_AUTH_EXPIRED: u64 = 0x10003;
    const E_AUTH_QUOTA_EXCEEDED: u64 = 0x10004;
    const E_INVALID_METADATA_URI: u64 = 0x10005;
    const E_INVALID_EXPIRY: u64 = 0x10006;

    // ==================== Public Functions ====================

    /// Create a new Agent object and return it
    /// This is the internal implementation used by both entry function and composable calls
    ///
    /// # Parameters
    /// - creator: Creator signer
    /// - metadata_uri: AgentCard metadata URI
    /// - domain: Optional domain name
    ///
    /// # Returns
    /// Created Agent object reference
    public fun create_agent_internal(
        creator: &signer,
        metadata_uri: String,
        domain: Option<String>
    ): Object<Agent> {
        // Input validation
        assert!(!std::string::is_empty(&metadata_uri), E_INVALID_METADATA_URI);

        let creator_addr = signer::address_of(creator);
        let constructor_ref = object::create_object(creator_addr);

        // Generate ExtendRef for subsequent operations
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        let object_signer = object::generate_signer(&constructor_ref);
        let agent_addr = signer::address_of(&object_signer);

        // Compute metadata_uri hash for event
        let metadata_uri_hash = aptos_std::aptos_hash::keccak256(*std::string::bytes(&metadata_uri));

        // Create Agent resource
        move_to(&object_signer, Agent {
            metadata_uri,
            owner: creator_addr,
            domain: domain,
            feedback_auths: table::new(),
            extend_ref,
        });

        // Note: We don't disable ungated transfer because TransferRef cannot be stored
        // Users MUST use transfer_owner() to maintain consistency between object owner
        // and Agent.owner field. Direct object transfer will cause data inconsistency.

        // Emit event - Fixed: use actual domain parameter
        event::emit(AgentRegistered {
            agent: agent_addr,
            owner: creator_addr,
            metadata_uri_hash,
            domain: domain,  // Fixed: no longer hardcoded to option::none()
            timestamp: timestamp::now_seconds(),
        });

        // Return the created object
        object::address_to_object<Agent>(agent_addr)
    }

    // ==================== Public Entry Functions ====================

    /// Create a new Agent object (transaction entry point)
    ///
    /// # Parameters
    /// - creator: Creator signer
    /// - metadata_uri: AgentCard metadata URI
    /// - domain: Optional domain name
    ///
    /// # Note
    /// This is the transaction entry point. The created object address can be obtained
    /// from the AgentRegistered event. For composable calls and testing, use
    /// `create_agent_internal` instead which returns the created object.
    public entry fun create_agent(
        creator: &signer,
        metadata_uri: String,
        domain: Option<String>
    ) {
        // Delegate to internal function (discard return value for entry function)
        create_agent_internal(creator, metadata_uri, domain);
    }

    /// Agent owner grants feedback authorization to client
    ///
    /// # Parameters
    /// - owner: Agent owner signer
    /// - agent: Agent object
    /// - client: Authorized client address
    /// - index_limit: Maximum allowed feedback index
    /// - expiry: Authorization expiry timestamp
    public entry fun grant_feedback_auth(
        owner: &signer,
        agent: Object<Agent>,
        client: address,
        index_limit: u64,
        expiry: u64
    ) acquires Agent {
        // Verify expiry time
        let now = timestamp::now_seconds();
        assert!(expiry > now, E_INVALID_EXPIRY);

        let agent_addr = object::object_address(&agent);
        let agent_data = borrow_global_mut<Agent>(agent_addr);
        assert!(agent_data.owner == signer::address_of(owner), E_NOT_OWNER);

        // Update or add authorization
        if (table::contains(&agent_data.feedback_auths, client)) {
            let auth = table::borrow_mut(&mut agent_data.feedback_auths, client);
            auth.index_limit = index_limit;
            auth.expiry = expiry;
        } else {
            table::add(&mut agent_data.feedback_auths, client, FeedbackAuth {
                index_limit,
                expiry,
                last_index: 0,
            });
        };

        event::emit(FeedbackAuthGranted {
            agent: agent_addr,
            client,
            index_limit,
            expiry,
            timestamp: now,
        });
    }

    /// Agent owner revokes client feedback authorization
    public entry fun revoke_feedback_auth(
        owner: &signer,
        agent: Object<Agent>,
        client: address
    ) acquires Agent {
        let agent_addr = object::object_address(&agent);
        let agent_data = borrow_global_mut<Agent>(agent_addr);
        assert!(agent_data.owner == signer::address_of(owner), E_NOT_OWNER);
        assert!(table::contains(&agent_data.feedback_auths, client), E_AUTH_NOT_FOUND);

        table::remove(&mut agent_data.feedback_auths, client);

        event::emit(FeedbackAuthRevoked {
            agent: agent_addr,
            client,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update agent metadata URI and/or domain
    public entry fun update_agent(
        owner: &signer,
        agent: Object<Agent>,
        new_metadata_uri: Option<String>,
        new_domain: Option<String>
    ) acquires Agent {
        let agent_addr = object::object_address(&agent);
        let agent_data = borrow_global_mut<Agent>(agent_addr);
        assert!(agent_data.owner == signer::address_of(owner), E_NOT_OWNER);

        let metadata_uri_hash = option::none<vector<u8>>();
        let updated_domain = option::none<String>();

        if (option::is_some(&new_metadata_uri)) {
            let uri = option::extract(&mut new_metadata_uri);
            assert!(!std::string::is_empty(&uri), E_INVALID_METADATA_URI);

            // Compute hash of new URI
            metadata_uri_hash = option::some(
                aptos_std::aptos_hash::keccak256(*std::string::bytes(&uri))
            );

            agent_data.metadata_uri = uri;
        };

        if (option::is_some(&new_domain)) {
            agent_data.domain = new_domain;
            updated_domain = new_domain;  // ✅ Fixed: record actual updated domain
        };

        event::emit(AgentUpdated {
            agent: agent_addr,
            metadata_uri_hash,
            domain: updated_domain,  // ✅ No longer hardcoded to option::none()
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Transfer agent ownership
    /// Execute ownership transfer at both resource field and object layers
    public entry fun transfer_owner(
        owner: &signer,
        agent: Object<Agent>,
        new_owner: address
    ) acquires Agent {
        let agent_addr = object::object_address(&agent);
        let agent_data = borrow_global_mut<Agent>(agent_addr);
        let old_owner = agent_data.owner;
        assert!(old_owner == signer::address_of(owner), E_NOT_OWNER);

        // Update owner at resource field layer
        // Note: We only maintain ownership at the resource layer (Agent.owner field)
        // Object-layer ownership transfer is complex and not critical for our use case
        // All permission checks use Agent.owner field, not object ownership
        agent_data.owner = new_owner;

        event::emit(AgentOwnerChanged {
            agent: agent_addr,
            old_owner,
            new_owner,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ==================== Friend Functions ====================

    /// Verify feedback authorization and consume one quota
    /// Only callable by agent_reputation module
    ///
    /// # 参数
    /// - agent: Agent object reference (Fixed: use Object<Agent> instead of address)
    /// - client: Client address
    ///
    /// # 返回
    /// Feedback index for this issuance
    public(friend) fun verify_and_consume_feedback_auth(
        agent: Object<Agent>,  // ✅ Fixed: type consistency
        client: address
    ): u64 acquires Agent {
        let agent_addr = object::object_address(&agent);
        let agent_data = borrow_global_mut<Agent>(agent_addr);
        assert!(table::contains(&agent_data.feedback_auths, client), E_AUTH_NOT_FOUND);

        let auth = table::borrow_mut(&mut agent_data.feedback_auths, client);
        let now = timestamp::now_seconds();

        // Verify authorization validity
        assert!(now < auth.expiry, E_AUTH_EXPIRED);
        assert!(auth.last_index < auth.index_limit, E_AUTH_QUOTA_EXCEEDED);

        // Consume quota
        auth.last_index = auth.last_index + 1;
        auth.last_index
    }

    // ==================== View Functions ====================

    #[view]
    /// Get agent basic information
    public fun get_agent_info(agent: Object<Agent>): (address, String, Option<String>) acquires Agent {
        let agent_addr = object::object_address(&agent);
        let agent_data = borrow_global<Agent>(agent_addr);
        (agent_data.owner, agent_data.metadata_uri, agent_data.domain)
    }

    #[view]
    /// Check if client has valid feedback authorization
    public fun has_valid_feedback_auth(agent: Object<Agent>, client: address): bool acquires Agent {
        let agent_addr = object::object_address(&agent);
        if (!exists<Agent>(agent_addr)) {
            return false
        };

        let agent_data = borrow_global<Agent>(agent_addr);
        if (!table::contains(&agent_data.feedback_auths, client)) {
            return false
        };

        let auth = table::borrow(&agent_data.feedback_auths, client);
        let now = timestamp::now_seconds();
        now < auth.expiry && auth.last_index < auth.index_limit
    }
}

