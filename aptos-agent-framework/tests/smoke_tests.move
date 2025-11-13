#[test_only]
/// Smoke Tests - Basic sanity checks that can run without object tracking
module aaf::smoke_tests {
    use std::string;
    use aaf::agent;
    use aaf::agent_reputation;
    use aaf::test_helpers::{Self as helpers};

    // ==================== Basic Sanity Tests ====================

    #[test]
    /// Test that test helpers work correctly
    fun test_helpers_basic_functions() {
        // Test time utilities
        helpers::setup_timestamp();
        let now = helpers::now();
        assert!(now >= 0, 0);
        
        // Test time constants
        assert!(helpers::one_hour() == 3600, 1);
        assert!(helpers::one_day() == 86400, 2);
        assert!(helpers::one_week() == 604800, 3);
        assert!(helpers::one_month() == 2592000, 4);
        
        // Test address functions
        let alice = helpers::alice();
        let bob = helpers::bob();
        assert!(alice != bob, 5);
    }

    #[test]
    /// Test creating test accounts
    fun test_create_accounts() {
        let alice = helpers::create_test_account(helpers::alice());
        let bob = helpers::create_test_account(helpers::bob());
        
        let alice_addr = std::signer::address_of(&alice);
        let bob_addr = std::signer::address_of(&bob);
        
        assert!(alice_addr == helpers::alice(), 0);
        assert!(bob_addr == helpers::bob(), 1);
        assert!(alice_addr != bob_addr, 2);
    }

    #[test]
    /// Test timestamp fast forward
    fun test_timestamp_fast_forward() {
        helpers::setup_timestamp();
        let start = helpers::now();
        
        helpers::fast_forward(helpers::one_hour());
        let after = helpers::now();
        
        assert!(after == start + helpers::one_hour(), 0);
    }

    #[test]
    /// Test string generators work
    fun test_string_generators() {
        let uri = helpers::test_metadata_uri();
        assert!(!string::is_empty(&uri), 0);
        
        let domain = helpers::test_domain();
        assert!(!string::is_empty(&domain), 1);
        
        let file_uri = helpers::test_file_uri();
        assert!(!string::is_empty(&file_uri), 2);
    }

    #[test]
    /// Test hash generators produce 32-byte hashes
    fun test_hash_generators() {
        let file_hash = helpers::test_file_hash();
        assert!(std::vector::length(&file_hash) == 32, 0);
        
        let context_hash = helpers::test_context_hash();
        assert!(std::vector::length(&context_hash) == 32, 1);
        
        let data_hash = helpers::test_data_hash();
        assert!(std::vector::length(&data_hash) == 32, 2);
        
        let response_hash = helpers::test_response_hash();
        assert!(std::vector::length(&response_hash) == 32, 3);
    }

    #[test]
    /// Test agent creation doesn't crash (address tracking issue prevents full test)
    fun test_agent_creation_basic() {
        helpers::setup_timestamp();
        let creator = helpers::create_test_account(helpers::alice());
        
        // Create agent - should not abort
        agent::create_agent(
            &creator,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Success if we reach here without abort
    }

    #[test]
    #[expected_failure(abort_code = 0x10005)]
    /// Test agent creation with empty URI fails
    fun test_agent_creation_empty_uri_fails() {
        helpers::setup_timestamp();
        let creator = helpers::create_test_account(helpers::alice());
        
        // Should fail with E_INVALID_METADATA_URI
        agent::create_agent(
            &creator,
            string::utf8(b""),
            helpers::none_domain()
        );
    }

    #[test]
    /// Test issuer capability management basics
    fun test_issuer_capability_basics() {
        helpers::setup_timestamp();
        let admin = helpers::create_test_account(helpers::admin());
        let issuer_addr = helpers::bob();
        
        // Initialize reputation module
        agent_reputation::init_for_test(&admin);
        
        // Should not have capability initially
        assert!(!agent_reputation::has_issuer_capability(issuer_addr), 0);
        
        // Grant capability
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
        
        // Should have capability now
        assert!(agent_reputation::has_issuer_capability(issuer_addr), 1);
        
        // Revoke capability
        agent_reputation::revoke_issuer_capability(&admin, issuer_addr);
        
        // Should not have capability anymore
        assert!(!agent_reputation::has_issuer_capability(issuer_addr), 2);
    }

    #[test]
    #[expected_failure(abort_code = 0x20005)]
    /// Test non-admin cannot grant capability
    fun test_grant_capability_non_admin_fails() {
        helpers::setup_timestamp();
        let admin = helpers::create_test_account(helpers::admin());
        let non_admin = helpers::create_test_account(helpers::bob());
        let issuer_addr = helpers::charlie();
        
        // Initialize with admin
        agent_reputation::init_for_test(&admin);
        
        // Should fail with E_NOT_ADMIN
        agent_reputation::grant_issuer_capability(&non_admin, issuer_addr);
    }

    #[test]
    /// Test governance transfer
    fun test_governance_transfer_basic() {
        helpers::setup_timestamp();
        let admin = helpers::create_test_account(helpers::admin());
        let new_admin_addr = helpers::bob();
        
        // Initialize
        agent_reputation::init_for_test(&admin);
        
        // Verify initial admin
        assert!(agent_reputation::get_admin() == helpers::admin(), 0);
        
        // Transfer governance
        agent_reputation::transfer_governance(&admin, new_admin_addr);
        
        // Verify new admin
        assert!(agent_reputation::get_admin() == new_admin_addr, 1);
    }

    #[test]
    #[expected_failure(abort_code = 0x20005)]
    /// Test non-admin cannot transfer governance
    fun test_governance_transfer_non_admin_fails() {
        helpers::setup_timestamp();
        let admin = helpers::create_test_account(helpers::admin());
        let non_admin = helpers::create_test_account(helpers::bob());
        let new_admin_addr = helpers::charlie();
        
        // Initialize with admin
        agent_reputation::init_for_test(&admin);
        
        // Should fail with E_NOT_ADMIN
        agent_reputation::transfer_governance(&non_admin, new_admin_addr);
    }

    #[test]
    /// Test multiple agent creations
    fun test_multiple_agent_creations() {
        helpers::setup_timestamp();
        let creator = helpers::create_test_account(helpers::alice());
        
        // Should be able to create multiple agents
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
        
        // All should succeed
    }

    #[test]
    /// Test creating agents from different accounts
    fun test_agents_from_different_creators() {
        helpers::setup_timestamp();
        let creator1 = helpers::create_test_account(helpers::alice());
        let creator2 = helpers::create_test_account(helpers::bob());
        let creator3 = helpers::create_test_account(helpers::charlie());
        
        agent::create_agent(&creator1, helpers::test_metadata_uri(), helpers::none_domain());
        agent::create_agent(&creator2, helpers::test_metadata_uri(), helpers::none_domain());
        agent::create_agent(&creator3, helpers::test_metadata_uri(), helpers::none_domain());
        
        // All should succeed
    }
}

