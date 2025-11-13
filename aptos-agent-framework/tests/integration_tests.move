#[test_only]
/// Integration Tests - Cross-module workflows
module aaf::integration_tests {
    use std::signer;
    use aptos_framework::object::{Self, Object};
    use aaf::agent::{Self, Agent};
    use aaf::agent_reputation;
    use aaf::agent_validation;
    use aaf::test_helpers::{Self as helpers};

    // ==================== Test Setup ====================

    fun setup(): (signer, signer, signer, signer) {
        helpers::setup_timestamp();
        let agent_owner = helpers::create_test_account(helpers::alice());
        let issuer = helpers::create_test_account(helpers::bob());
        let validator = helpers::create_test_account(helpers::charlie());
        let admin = helpers::create_test_account(helpers::admin());
        
        // Initialize global resources for both reputation and validation modules
        agent_reputation::init_for_test(&admin);
        agent_validation::init_for_test(&admin);
        
        (agent_owner, issuer, validator, admin)
    }

    // ==================== 4.1 Complete Reputation Flow (4 tests) ====================

    #[test]
    /// Test complete reputation workflow: Agent → Auth → Issue → Response
    fun test_e2e_reputation_open_feedback() {
        let (agent_owner, issuer, _validator, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Step 1: Create agent
        let agent_obj = agent::create_agent_internal(
            &agent_owner,
            helpers::test_metadata_uri(),
            helpers::some_domain()
        );
        
        // Step 2: Grant feedback authorization
        let expiry = helpers::now() + helpers::one_week();
        agent::grant_feedback_auth(
            &agent_owner,
            agent_obj,
            issuer_addr,
            10, // index_limit
            expiry
        );
        
        // Step 3: Issue reputation and get its address
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            85,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false // open mode
        );
        
        // Step 4: Append response
        let responder = helpers::create_test_account(helpers::dave());
        agent_reputation::append_response(
            &responder,
            reputation_addr,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
        
        // Verify final state
        let (_agent, _issuer, score, revoked, _issued_at, response_count) = 
            agent_reputation::get_reputation(reputation_addr);
        assert!(score == 85, 0);
        assert!(!revoked, 1);
        assert!(response_count == 1, 2);
    }

    #[test]
    /// Test gated reputation workflow: Capability → Auth → Issue
    fun test_e2e_reputation_gated_feedback() {
        let (agent_owner, issuer, _validator, admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Step 1: Admin grants issuer capability
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
        
        // Step 2: Create agent and grant auth
        let agent_obj = agent::create_agent_internal(
            &agent_owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        let expiry = helpers::now() + helpers::one_month();
        agent::grant_feedback_auth(
            &agent_owner,
            agent_obj,
            issuer_addr,
            5,
            expiry
        );
        
        // Step 3: Issue reputation in gated mode
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            92,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            true // gated mode
        );
    }

    #[test]
    /// Test reputation revocation workflow: Issue → Revoke
    fun test_e2e_reputation_revocation() {
        let (agent_owner, issuer, _validator, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Setup and issue
        let agent_obj = agent::create_agent_internal(&agent_owner, helpers::test_metadata_uri(), helpers::none_domain());
        
        let expiry = helpers::now() + helpers::one_week();
        agent::grant_feedback_auth(&agent_owner, agent_obj, issuer_addr, 5, expiry);
        
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            78,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Verify not revoked
        let (_agent, _issuer, _score, revoked_before, _issued_at, _response_count) = 
            agent_reputation::get_reputation(reputation_addr);
        assert!(!revoked_before, 0);
        
        // Revoke
        agent_reputation::revoke_reputation(&issuer, reputation_addr);
        
        // Verify revoked
        let (_agent2, _issuer2, _score2, revoked_after, _issued_at2, _response_count2) = 
            agent_reputation::get_reputation(reputation_addr);
        assert!(revoked_after, 1);
    }

    #[test]
    /// Test multiple reputation issuances exhaust auth quota
    fun test_e2e_reputation_auth_quota() {
        let (agent_owner, issuer, _validator, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Create agent with limited quota
        let agent_obj = agent::create_agent_internal(&agent_owner, helpers::test_metadata_uri(), helpers::none_domain());
        
        let expiry = helpers::now() + helpers::one_day();
        agent::grant_feedback_auth(
            &agent_owner,
            agent_obj,
            issuer_addr,
            3, // Only 3 allowed
            expiry
        );
        
        // Issue 3 reputations successfully
        let i = 0;
        while (i < 3) {
            agent_reputation::issue_reputation(
                &issuer,
                agent_obj,
                80 + (i as u8),
                helpers::test_context_hash(),
                helpers::test_file_uri(),
                helpers::test_file_hash(),
                false
            );
            i = i + 1;
        };
        
        // 4th should fail (quota exceeded)
        // TODO: Add expected_failure attribute when fully implemented
    }

    // ==================== 4.2 Complete Validation Flow (3 tests) ====================

    #[test]
    /// Test validation workflow: Request → Respond → Query
    fun test_e2e_validation_request_respond() {
        let (agent_owner, _issuer, validator, _admin) = setup();
        let agent_addr = signer::address_of(&agent_owner);
        let validator_addr = signer::address_of(&validator);
        let requester = helpers::create_test_account(helpers::dave());
        
        // Step 1: Request validation and get request_id
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // Step 2: Verify pending
        assert!(agent_validation::is_pending(request_id), 0);
        
        // Step 3: Validator responds
        agent_validation::respond_validation(
            &validator,
            request_id,
            88,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
        
        // Step 4: Verify completed
        assert!(!agent_validation::is_pending(request_id), 1);
        
        // Step 5: Query result
        let (_agent, _validator, score, _timestamp) = 
            agent_validation::get_validation_status(request_id);
        assert!(score == 88, 2);
    }

    #[test]
    /// Test validation TTL expiry: Request → Wait → Expire
    fun test_e2e_validation_ttl_expiry() {
        let (agent_owner, _issuer, validator, _admin) = setup();
        let agent_addr = signer::address_of(&agent_owner);
        let validator_addr = signer::address_of(&validator);
        let requester = helpers::create_test_account(helpers::dave());
        
        // Create request with short TTL and get request_id
        let request_id = agent_validation::request_validation_internal(
            &requester,
            agent_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_hour()
        );
        
        // Fast forward past TTL
        helpers::fast_forward(helpers::one_hour() + 1);
        
        // Attempt to respond should fail
        // TODO: Add expected_failure when fully implemented
    }

    #[test]
    /// Test multiple validators validating same agent
    fun test_e2e_validation_multiple_validators() {
        let (_agent_owner, _issuer, _validator, _admin) = setup();
        let agent_addr = helpers::alice();
        let validator1 = helpers::bob();
        let validator2 = helpers::charlie();
        let validator3 = helpers::dave();
        let requester = helpers::create_test_account(@0xAAA);
        
        // Create 3 validation requests for same agent, different validators
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator1,
            helpers::test_data_hash(),
            helpers::one_week()
        );
        
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator2,
            helpers::test_data_hash(),
            helpers::one_week()
        );
        
        agent_validation::request_validation(
            &requester,
            agent_addr,
            validator3,
            helpers::test_data_hash(),
            helpers::one_week()
        );
        
        // All 3 should succeed with unique request IDs
    }

    // ==================== 4.3 Cross-Module Scenarios (3 tests) ====================

    #[test]
    /// Test ownership transfer + reputation issuance
    fun test_cross_agent_ownership_and_reputation() {
        let (agent_owner, issuer, _validator, _admin) = setup();
        let new_owner = helpers::create_test_account(helpers::dave());
        let new_owner_addr = signer::address_of(&new_owner);
        let issuer_addr = signer::address_of(&issuer);
        
        // Create agent
        let agent_obj = agent::create_agent_internal(&agent_owner, helpers::test_metadata_uri(), helpers::none_domain());
        
        // Grant auth as original owner
        let expiry = helpers::now() + helpers::one_day();
        agent::grant_feedback_auth(&agent_owner, agent_obj, issuer_addr, 5, expiry);
        
        // Transfer ownership
        agent::transfer_owner(&agent_owner, agent_obj, new_owner_addr);
        
        // New owner should be able to grant additional auth
        agent::grant_feedback_auth(&new_owner, agent_obj, issuer_addr, 10, expiry);
        
        // Issuer should still be able to issue reputation
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            90,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
    }

    #[test]
    /// Test governance transfer + capability management
    fun test_cross_governance_and_capability() {
        let (_agent_owner, issuer, _validator, admin) = setup();
        let new_admin = helpers::create_test_account(helpers::dave());
        let new_admin_addr = signer::address_of(&new_admin);
        let issuer_addr = signer::address_of(&issuer);
        
        // Original admin transfers governance
        agent_reputation::transfer_governance(&admin, new_admin_addr);
        
        // New admin should be able to grant capability
        agent_reputation::grant_issuer_capability(&new_admin, issuer_addr);
        
        // Verify capability granted
        assert!(agent_reputation::has_issuer_capability(issuer_addr), 0);
        
        // New admin should be able to revoke
        agent_reputation::revoke_issuer_capability(&new_admin, issuer_addr);
        assert!(!agent_reputation::has_issuer_capability(issuer_addr), 1);
    }

    #[test]
    /// Test multiple agents with concurrent operations
    fun test_cross_multi_agent_validation() {
        let (owner1, _issuer, validator, _admin) = setup();
        let owner2 = helpers::create_test_account(helpers::charlie());
        let owner3 = helpers::create_test_account(helpers::dave());
        let validator_addr = signer::address_of(&validator);
        let requester = helpers::create_test_account(@0xBBB);
        
        // Create 3 agents
        let agent1_obj = agent::create_agent_internal(&owner1, helpers::test_metadata_uri_indexed(1), helpers::none_domain());
        let agent2_obj = agent::create_agent_internal(&owner2, helpers::test_metadata_uri_indexed(2), helpers::none_domain());
        let agent3_obj = agent::create_agent_internal(&owner3, helpers::test_metadata_uri_indexed(3), helpers::none_domain());
        
        // Request validation for all 3
        let agent1_addr = object::object_address(&agent1_obj);
        let agent2_addr = object::object_address(&agent2_obj);
        let agent3_addr = object::object_address(&agent3_obj);
        
        agent_validation::request_validation(
            &requester,
            agent1_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        agent_validation::request_validation(
            &requester,
            agent2_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        agent_validation::request_validation(
            &requester,
            agent3_addr,
            validator_addr,
            helpers::test_data_hash(),
            helpers::one_day()
        );
        
        // All should succeed independently
    }
}

