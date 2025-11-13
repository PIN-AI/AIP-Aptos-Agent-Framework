#[test_only]
/// Validation Module Unit Tests
module aaf::validation_tests {
    use std::signer;
    use aaf::agent_validation;
    use aaf::test_helpers::{Self as helpers};

    // ==================== Test Setup ====================

    fun setup(): (signer, signer, signer) {
        helpers::setup_timestamp();
        let requester = helpers::create_test_account(helpers::alice());
        let validator = helpers::create_test_account(helpers::bob());
        let agent_owner = helpers::create_test_account(helpers::charlie());
        
        // Initialize validation module global resources
        let admin = helpers::create_test_account(helpers::admin());
        agent_validation::init_for_test(&admin);
        
        (requester, validator, agent_owner)
    }

    // ==================== 3.1 Request Creation (6 tests) ====================

    #[test]
    /// Test creating validation request successfully
    fun test_request_validation_success() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let agent_addr = helpers::charlie();
        
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day() // TTL = 1 day
        );
        
        // If no abort, test passes
    }

    #[test]
    /// Test request ID uniqueness based on parameters
    fun test_request_validation_generates_unique_id() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let agent_addr1 = helpers::charlie();
        let agent_addr2 = helpers::dave();
        
        // Create two requests with different agents (should succeed)
        agent_validation::request_validation(
            &requester,
            agent_addr1,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        agent_validation::request_validation(
            &requester,
            agent_addr2,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // Both should succeed with unique request IDs
    }

    #[test]
    #[expected_failure(abort_code = 0x30001)] // E_REQUEST_EXISTS
    /// Test duplicate request (same params + timestamp) fails
    fun test_request_validation_duplicate_fails() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let agent_addr = helpers::charlie();
        let data_hash = helpers::test_data_hash();
        
        // First request
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator_addr,
            data_hash,
            helpers::one_day()
        );
        
        // Try to create duplicate request at same timestamp (should fail)
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator_addr,
            data_hash,
            helpers::one_day()
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x30007)] // E_INVALID_TTL
    /// Test request with TTL = 0 fails
    fun test_request_validation_invalid_ttl_fails() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let agent_addr = helpers::charlie();
        
        // Try to create request with TTL = 0 (should fail)
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            0 // Invalid TTL
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x30007)] // E_INVALID_TTL
    /// Test request with TTL > 30 days fails
    fun test_request_validation_ttl_exceeds_max_fails() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let agent_addr = helpers::charlie();
        
        // Try to create request with TTL > max (should fail)
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_month() + 1 // 30 days + 1 second
        );
    }

    #[test]
    /// Test request emits event (event testing framework needed)
    fun test_request_validation_emits_event() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let agent_addr = helpers::charlie();
        
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_week()
        );
        
        // TODO: Check event emission when event testing framework available
    }

    // ==================== 3.2 Validation Response (6 tests) ====================

    #[test]
    /// Test validator responds to request successfully
    fun test_respond_validation_success() {
        let (requester, validator, _agent_owner) = setup();
        let validator_addr = signer::address_of(&validator);
        let agent_addr = helpers::charlie();
        
        // Create request and get request_id
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // Respond
        agent_validation::respond_validation(
            &validator,
            request_id,
            85, // score
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x30003)] // E_REQUEST_NOT_FOUND
    /// Test responding to nonexistent request fails
    fun test_respond_nonexistent_request_fails() {
        let (_requester, validator, _agent_owner) = setup();
        
        // Try to respond to nonexistent request (should fail)
        let fake_request_id = x"deadbeef";
        
        agent_validation::respond_validation(
            &validator,
            fake_request_id,
            75,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x30005)] // E_REQUEST_EXPIRED
    /// Test responding to expired request fails
    fun test_respond_expired_request_fails() {
        let (requester, validator, _agent_owner) = setup();
        let validator_addr = signer::address_of(&validator);
        let agent_addr = helpers::charlie();
        
        // Create request with 1 hour TTL
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_hour()
        );
        
        // Fast forward past TTL
        helpers::fast_forward(helpers::one_hour() + 1);
        
        // Try to respond after expiry (should fail)
        agent_validation::respond_validation(
            &validator,
            request_id,
            80,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x30004)] // E_NOT_VALIDATOR
    /// Test wrong validator cannot respond
    fun test_respond_wrong_validator_fails() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let wrong_validator = helpers::create_test_account(helpers::dave());
        let agent_addr = helpers::charlie();
        
        // Create request for specific validator
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // Try to respond as wrong validator (should fail)
        agent_validation::respond_validation(
            &wrong_validator,
            request_id,
            90,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x30002)] // E_RESPONSE_OUT_OF_RANGE
    /// Test response with score > 100 fails
    fun test_respond_invalid_score_fails() {
        let (requester, validator, _agent_owner) = setup();
        let validator_addr = signer::address_of(&validator);
        let agent_addr = helpers::charlie();
        
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // Try to respond with invalid score (should fail)
        agent_validation::respond_validation(
            &validator,
            request_id,
            101, // score > 100
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
    }

    #[test]
    /// Test responding moves request from pending to completed
    fun test_respond_validation_moves_to_completed() {
        let (requester, validator, _agent_owner) = setup();
        let validator_addr = signer::address_of(&validator);
        let agent_addr = helpers::charlie();
        
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // Check is pending before response
        assert!(agent_validation::is_pending(request_id), 0);
        
        // Respond
        agent_validation::respond_validation(
            &validator,
            request_id,
            88,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
        
        // Check is no longer pending
        assert!(!agent_validation::is_pending(request_id), 1);
    }

    // ==================== 3.3 Query Functions (3 tests) ====================

    #[test]
    /// Test get_validation_status returns correct data
    fun test_get_validation_status() {
        let (requester, validator, _agent_owner) = setup();
        let validator_addr = signer::address_of(&validator);
        let agent_addr = helpers::charlie();
        
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        let score = 92;
        
        agent_validation::respond_validation(
            &validator,
            request_id,
            score,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
        
        // Query status
        let (returned_agent, returned_validator, returned_score, _timestamp) = 
            agent_validation::get_validation_status(request_id);
        
        assert!(returned_agent == agent_addr, 0);
        assert!(returned_validator == validator_addr, 1);
        assert!(returned_score == score, 2);
    }

    #[test]
    /// Test is_pending correctly identifies pending requests
    fun test_is_pending() {
        let (requester, validator, _agent_owner) = setup();
        let validator_addr = signer::address_of(&validator);
        let agent_addr = helpers::charlie();
        
        // Create request and get request_id
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // After request - should be pending
        assert!(agent_validation::is_pending(request_id), 0);
        
        // After response
        agent_validation::respond_validation(
            &validator,
            request_id,
            85,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
        
        // No longer pending
        assert!(!agent_validation::is_pending(request_id), 1);
    }

    #[test]
    /// Test get_pending_request returns correct info
    fun test_get_pending_request() {
        let (requester, _validator, _agent_owner) = setup();
        let validator_addr = helpers::bob();
        let agent_addr = helpers::charlie();
        let ttl = helpers::one_week();
        
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            ttl
        );
        
        // Query pending request
        let (returned_agent, returned_validator, _created_at, returned_ttl) = 
            agent_validation::get_pending_request(request_id);
        
        assert!(returned_agent == agent_addr, 0);
        assert!(returned_validator == validator_addr, 1);
        assert!(returned_ttl == ttl, 2);
    }

    // ==================== Edge Cases ====================

    #[test]
    /// Test multiple concurrent validation requests
    fun test_multiple_concurrent_requests() {
        let (requester, _validator, _agent_owner) = setup();
        let validator1 = helpers::bob();
        let validator2 = helpers::charlie();
        let validator3 = helpers::dave();
        let agent_addr = helpers::alice();
        
        // Create 3 parallel requests with different validators
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator1,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator2,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator3,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // All should succeed with unique request IDs
    }

    #[test]
    /// Test validation with maximum TTL (30 days)
    fun test_validation_max_ttl() {
        let (requester, validator, _agent_owner) = setup();
        let validator_addr = signer::address_of(&validator);
        let agent_addr = helpers::charlie();
        
        // Create request with max TTL
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_month() // 30 days = max
        );
        
        // Fast forward to just before expiry
        helpers::fast_forward(helpers::one_month() - 1);
        
        // Should still be able to respond
        agent_validation::respond_validation(
            &validator,
            request_id,
            95,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
    }
}

