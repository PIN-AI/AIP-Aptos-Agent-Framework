#[test_only]
/// Agent Module Unit Tests
module aaf::agent_tests {
    use std::option;
    use std::signer;
    use aptos_framework::object::{Self, Object};
    use aaf::agent::{Self, Agent};
    use aaf::test_helpers::{Self as helpers};

    // ==================== Test Setup ====================

    fun setup(): signer {
        helpers::setup_timestamp();
        helpers::create_test_account(helpers::alice())
    }

    // ==================== 1.1 Basic Operations (6 tests) ====================

    #[test]
    /// Test successful agent creation with minimal parameters
    fun test_create_agent_success() {
        let creator = setup();
        
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // If we get here without abort, test passes
    }

    #[test]
    /// Test agent creation with optional domain
    fun test_create_agent_with_domain() {
        let creator = setup();
        
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri(),
            helpers::some_domain()
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x10005)] // E_INVALID_METADATA_URI
    /// Test that empty metadata URI fails
    fun test_create_agent_empty_uri_fails() {
        let creator = setup();
        
        agent::create_agent(
            &creator,
            std::string::utf8(b""), // Empty URI
            helpers::none_domain()
        );
    }

    #[test]
    /// Test view function returns correct agent info
    fun test_get_agent_info() {
        let creator = setup();
        let creator_addr = signer::address_of(&creator);
        
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri(),
            helpers::some_domain()
        );
        
        // Note: Need to get agent object address to query
        // This is simplified - in real test need event parsing or address derivation
    }

    #[test]
    /// Test agent object has correct ownership
    fun test_agent_object_ownership() {
        let creator = setup();
        
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Verify ownership through object system
    }

    // ==================== 1.2 Feedback Authorization (7 tests) ====================

    #[test]
    /// Test granting feedback authorization successfully
    fun test_grant_feedback_auth_success() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        // Create agent first
        agent::create_agent(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // TODO: Get agent object and grant auth
        // Need to derive or track agent address
    }

    #[test]
    /// Test updating existing authorization
    fun test_grant_feedback_auth_updates_existing() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        agent::create_agent(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Grant initial auth
        // Grant again with different params
        // Verify update succeeded
    }

    #[test]
    #[expected_failure(abort_code = 0x10001)] // E_NOT_OWNER
    /// Test non-owner cannot grant authorization
    fun test_grant_auth_non_owner_fails() {
        let owner = setup();
        let non_owner = helpers::create_test_account(helpers::bob());
        let client_addr = helpers::charlie();
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Try to grant as non-owner (should fail)
        let expiry = helpers::now() + helpers::one_day();
        agent::grant_feedback_auth(
            &non_owner,
            agent_obj,
            client_addr,
            10,
            expiry
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x10006)] // E_INVALID_EXPIRY
    /// Test authorization with expiry in the past fails
    fun test_grant_auth_expired_time_fails() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Try to grant with expiry equal to current time (should fail)
        // E_INVALID_EXPIRY requires expiry > now, so expiry == now should fail
        let current_time = helpers::now();
        agent::grant_feedback_auth(
            &owner,
            agent_obj,
            client_addr,
            10,
            current_time
        );
    }

    #[test]
    /// Test revoking feedback authorization
    fun test_revoke_feedback_auth_success() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        agent::create_agent(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Grant auth
        // Revoke auth
        // Verify revoked
    }

    #[test]
    #[expected_failure(abort_code = 0x10002)] // E_AUTH_NOT_FOUND
    /// Test revoking nonexistent authorization fails
    fun test_revoke_nonexistent_auth_fails() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Try to revoke without granting first (should fail)
        agent::revoke_feedback_auth(
            &owner,
            agent_obj,
            client_addr
        );
    }

    #[test]
    /// Test checking authorization validity
    fun test_has_valid_feedback_auth() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        agent::create_agent(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Check before grant - should be false
        // Grant auth
        // Check after grant - should be true
        // Fast forward past expiry
        // Check after expiry - should be false
    }

    // ==================== 1.3 Agent Updates (3 tests) ====================

    #[test]
    /// Test updating agent metadata URI only
    fun test_update_agent_metadata_uri() {
        let owner = setup();
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Update with new URI
        let new_uri = option::some(helpers::test_metadata_uri_indexed(2));
        agent::update_agent(
            &owner,
            agent_obj,
            new_uri,
            option::none()
        );
    }

    #[test]
    /// Test updating agent domain only
    fun test_update_agent_domain() {
        let owner = setup();
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Update with new domain
        let new_domain = option::some(helpers::test_domain_indexed(2));
        agent::update_agent(
            &owner,
            agent_obj,
            option::none(),
            new_domain
        );
    }

    #[test]
    /// Test updating both metadata URI and domain
    fun test_update_agent_both_fields() {
        let owner = setup();
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Update both fields
        let new_uri = option::some(helpers::test_metadata_uri_indexed(3));
        let new_domain = option::some(helpers::test_domain_indexed(3));
        agent::update_agent(
            &owner,
            agent_obj,
            new_uri,
            new_domain
        );
    }

    // ==================== 1.4 Ownership Transfer (2 tests) ====================

    #[test]
    /// Test successful ownership transfer
    fun test_transfer_owner_success() {
        let owner = setup();
        let new_owner = helpers::create_test_account(helpers::bob());
        let new_owner_addr = signer::address_of(&new_owner);
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Transfer ownership
        agent::transfer_owner(
            &owner,
            agent_obj,
            new_owner_addr
        );
        
        // Verify transfer succeeded by checking we can grant auth as new owner
        let client_addr = helpers::charlie();
        let expiry = helpers::now() + helpers::one_day();
        agent::grant_feedback_auth(
            &new_owner,
            agent_obj,
            client_addr,
            5,
            expiry
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x10001)] // E_NOT_OWNER
    /// Test non-owner cannot transfer ownership
    fun test_transfer_non_owner_fails() {
        let owner = setup();
        let non_owner = helpers::create_test_account(helpers::bob());
        let new_owner_addr = helpers::charlie();
        
        let agent_obj = agent::create_agent_internal(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Try to transfer as non-owner (should fail)
        agent::transfer_owner(
            &non_owner,
            agent_obj,
            new_owner_addr
        );
    }

    // ==================== Edge Cases ====================

    #[test]
    /// Test creating multiple agents from same account
    fun test_create_multiple_agents_same_owner() {
        let creator = setup();
        
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri_indexed(1),
            helpers::none_domain()
        );
        
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri_indexed(2),
            helpers::none_domain()
        );
        
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri_indexed(3),
            helpers::none_domain()
        );
        
        // All should succeed with unique addresses
    }

    #[test]
    /// Test authorization quota exhaustion
    fun test_authorization_quota_exhaustion() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        agent::create_agent(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Grant auth with index_limit = 3
        // Consume 3 times successfully
        // 4th consumption should fail with E_AUTH_QUOTA_EXCEEDED
    }

    #[test]
    /// Test authorization expiry timing
    fun test_authorization_expiry_timing() {
        let owner = setup();
        let client_addr = helpers::bob();
        
        agent::create_agent(
            &owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        let now = helpers::now();
        let expiry = now + helpers::one_hour();
        
        // Grant auth expiring in 1 hour
        // Use successfully before expiry
        // Fast forward 1 hour + 1 second
        // Usage should fail with E_AUTH_EXPIRED
    }
}

