/// Aptos Agent Framework - Validation Module
/// Provides request/response interface for third-party validation
module aaf::agent_validation {
    use std::signer;
    use std::string::String;
    use std::vector;
    use std::bcs;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};
    use aptos_std::aptos_hash;

    // ==================== Data Structures ====================

    /// Pending request info
    struct RequestInfo has store, drop {
        agent: address,
        validator: address,
        data_hash: vector<u8>,
        created_at: u64,
        ttl_secs: u64,
    }

    /// Completed validation record
    struct ValidationRecord has store, drop {
        agent: address,
        validator: address,
        data_hash: vector<u8>,
        response: u8,           // 0-100 score
        response_uri: String,
        response_hash: vector<u8>,
        responded_at: u64,
    }

    /// Global validation registry
    struct ValidationRegistry has key {
        pending: Table<vector<u8>, RequestInfo>,
        completed: Table<vector<u8>, ValidationRecord>,
    }

    // ==================== Events ====================

    #[event]
    struct ValidationRequested has drop, store {
        request_id: vector<u8>,
        agent: address,
        validator: address,
        data_hash: vector<u8>,  // Keep hash for indexing
        created_at: u64,
        ttl_secs: u64,
    }

    #[event]
    struct ValidationResponded has drop, store {
        request_id: vector<u8>,
        agent: address,
        validator: address,
        response: u8,
        response_hash: vector<u8>,  // Keep hash for verification
        responded_at: u64,
    }

    // ==================== Error Codes ====================

    const E_REQUEST_EXISTS: u64 = 0x30001;
    const E_RESPONSE_OUT_OF_RANGE: u64 = 0x30002;
    const E_REQUEST_NOT_FOUND: u64 = 0x30003;
    const E_NOT_VALIDATOR: u64 = 0x30004;
    const E_REQUEST_EXPIRED: u64 = 0x30005;
    const E_VALIDATION_NOT_FOUND: u64 = 0x30006;
    const E_INVALID_TTL: u64 = 0x30007;

    // ==================== Module Initialization ====================

    /// ✅ Fixed: Single initialization point - automatically called on deployment
    fun init_module(deployer: &signer) {
        move_to(deployer, ValidationRegistry {
            pending: table::new(),
            completed: table::new(),
        });
    }

    #[test_only]
    /// Initialize validation registry for testing
    public fun init_for_test(deployer: &signer) {
        if (!exists<ValidationRegistry>(signer::address_of(deployer))) {
            move_to(deployer, ValidationRegistry {
                pending: table::new(),
                completed: table::new(),
            });
        };
    }

    // ==================== Public Functions ====================

    /// Request validation for agent's work and return request_id (internal version)
    ///
    /// # Parameters
    /// - _requester: Requester signer (currently unused, reserved for future access control)
    /// - agent_addr: Agent address
    /// - validator: Validator address
    /// - data_hash: Hash of data to validate
    /// - ttl_secs: Request time-to-live (seconds)
    ///
    /// # Returns
    /// request_id that uniquely identifies this validation request
    public fun request_validation_internal(
        _requester: &signer,
        agent_addr: address,
        validator: address,
        data_hash: vector<u8>,
        ttl_secs: u64
    ): vector<u8> acquires ValidationRegistry {
        // Input validation
        assert!(ttl_secs > 0 && ttl_secs <= 2592000, E_INVALID_TTL); // Max 30 days

        let now = timestamp::now_seconds();

        // Generate globally unique request_id
        let request_id = compute_request_id(agent_addr, validator, &data_hash, now);

        let registry = borrow_global_mut<ValidationRegistry>(@aaf);
        assert!(!table::contains(&registry.pending, request_id), E_REQUEST_EXISTS);

        // Add to pending table
        table::add(&mut registry.pending, request_id, RequestInfo {
            agent: agent_addr,
            validator,
            data_hash: copy data_hash,
            created_at: now,
            ttl_secs,
        });

        // Emit event
        event::emit(ValidationRequested {
            request_id: copy request_id,
            agent: agent_addr,
            validator,
            data_hash,  // Keep hash for indexing
            created_at: now,
            ttl_secs,
        });

        // Return request_id
        request_id
    }

    // ==================== Public Entry Functions ====================

    /// Request validation for agent's work (transaction entry point)
    ///
    /// # Parameters
    /// - _requester: Requester signer (currently unused, reserved for future access control)
    /// - agent_addr: Agent address
    /// - validator: Validator address
    /// - data_hash: Hash of data to validate
    /// - ttl_secs: Request time-to-live (seconds)
    ///
    /// # Note
    /// This is the transaction entry point. The request_id can be obtained from the
    /// ValidationRequested event. For composable calls and testing, use
    /// `request_validation_internal` instead which returns the request_id.
    public entry fun request_validation(
        _requester: &signer,
        agent_addr: address,
        validator: address,
        data_hash: vector<u8>,
        ttl_secs: u64
    ) acquires ValidationRegistry {
        // Delegate to internal function (discard return value for entry function)
        request_validation_internal(_requester, agent_addr, validator, data_hash, ttl_secs);
    }

    /// Validator responds to pending request
    public entry fun respond_validation(
        responder: &signer,
        request_id: vector<u8>,
        response: u8,
        response_uri: String,
        response_hash: vector<u8>
    ) acquires ValidationRegistry {
        // Input validation
        assert!(response <= 100, E_RESPONSE_OUT_OF_RANGE);

        let registry = borrow_global_mut<ValidationRegistry>(@aaf);
        assert!(table::contains(&registry.pending, request_id), E_REQUEST_NOT_FOUND);

        let info = table::remove(&mut registry.pending, request_id);

        // Verify responder is the designated validator
        assert!(info.validator == signer::address_of(responder), E_NOT_VALIDATOR);

        // Verify request not expired
        let now = timestamp::now_seconds();
        assert!(now <= info.created_at + info.ttl_secs, E_REQUEST_EXPIRED);

        // Store completed validation
        table::add(&mut registry.completed, request_id, ValidationRecord {
            agent: info.agent,
            validator: info.validator,
            data_hash: info.data_hash,
            response,
            response_uri,
            response_hash: copy response_hash,
            responded_at: now,
        });

        // Emit event
        event::emit(ValidationResponded {
            request_id,
            agent: info.agent,
            validator: info.validator,
            response,
            response_hash,  // Keep hash for verification
            responded_at: now,
        });
    }

    // ==================== View Functions ====================

    #[view]
    /// Get completed validation status
    public fun get_validation_status(
        request_id: vector<u8>
    ): (address, address, u8, u64) acquires ValidationRegistry {
        let registry = borrow_global<ValidationRegistry>(@aaf);
        assert!(table::contains(&registry.completed, request_id), E_VALIDATION_NOT_FOUND);

        let record = table::borrow(&registry.completed, request_id);
        (record.agent, record.validator, record.response, record.responded_at)
    }

    #[view]
    /// Check if request is still pending
    public fun is_pending(request_id: vector<u8>): bool acquires ValidationRegistry {
        let registry = borrow_global<ValidationRegistry>(@aaf);
        table::contains(&registry.pending, request_id)
    }

    #[view]
    /// Get pending request details
    public fun get_pending_request(
        request_id: vector<u8>
    ): (address, address, u64, u64) acquires ValidationRegistry {
        let registry = borrow_global<ValidationRegistry>(@aaf);
        assert!(table::contains(&registry.pending, request_id), E_REQUEST_NOT_FOUND);

        let info = table::borrow(&registry.pending, request_id);
        (info.agent, info.validator, info.created_at, info.ttl_secs)
    }

    // ==================== Helper Functions ====================

    /// Compute globally unique request_id
    /// request_id = SHA3-256(agent || validator || data_hash || timestamp)
    fun compute_request_id(
        agent: address,
        validator: address,
        data_hash: &vector<u8>,
        timestamp: u64
    ): vector<u8> {
        let input = vector::empty<u8>();
        vector::append(&mut input, bcs::to_bytes(&agent));
        vector::append(&mut input, bcs::to_bytes(&validator));
        vector::append(&mut input, *data_hash);
        vector::append(&mut input, bcs::to_bytes(&timestamp));

        aptos_hash::keccak256(input)
    }
}

