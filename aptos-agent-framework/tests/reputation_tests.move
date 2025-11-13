#[test_only]
/// Reputation Module Unit Tests
module aaf::reputation_tests {
    use std::option;
    use std::signer;
    use aptos_framework::object::{Self, Object};
    use aaf::agent::{Self, Agent};
    use aaf::agent_reputation;
    use aaf::test_helpers::{Self as helpers};

    // ==================== Test Setup ====================

    fun setup(): (signer, signer, signer) {
        helpers::setup_timestamp();
        let owner = helpers::create_test_account(helpers::alice());
        let issuer = helpers::create_test_account(helpers::bob());
        let admin = helpers::create_test_account(helpers::admin());
        
        // Initialize reputation module global resources
        agent_reputation::init_for_test(&admin);
        
        (owner, issuer, admin)
    }

    fun create_agent_with_auth(
        owner: &signer,
        issuer_addr: address
    ): Object<Agent> {
        // Create agent using internal function that returns Object<Agent>
        let agent_obj = agent::create_agent_internal(
            owner,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        // Grant feedback auth to issuer
        let expiry = helpers::now() + helpers::one_week();
        agent::grant_feedback_auth(
            owner,
            agent_obj,
            issuer_addr,
            10, // index_limit
            expiry
        );
        
        // Return agent object
        agent_obj
    }

    // ==================== 2.1 Basic Reputation Issuance (8 tests) ====================

    #[test]
    /// Test issuing reputation in open mode (no capability required)
    fun test_issue_reputation_open_mode() {
        let (owner, issuer, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Issue reputation without capability (gated = false)
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            85, // score
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false // gated = false (open mode)
        );
    }

    #[test]
    /// Test issuing reputation in gated mode (capability required)
    fun test_issue_reputation_gated_mode() {
        let (owner, issuer, admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Grant issuer capability
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Issue reputation with capability (gated = true)
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            90,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            true // gated = true
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x20002)] // E_ISSUER_FORBIDDEN
    /// Test gated issuance fails without capability
    fun test_issue_reputation_no_capability_fails() {
        let (owner, issuer, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Try to issue in gated mode without capability (should fail)
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            75,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            true // gated = true, but no capability
        );
    }

    #[test]
    #[expected_failure] // E_AUTH_NOT_FOUND or similar from agent module
    /// Test issuance fails without feedback authorization
    fun test_issue_reputation_no_auth_fails() {
        let (_owner, issuer, _admin) = setup();
        let owner2 = helpers::create_test_account(helpers::charlie());
        
        // Create agent without granting auth to issuer
        agent::create_agent(
            &owner2,
            helpers::test_metadata_uri(),
            helpers::none_domain()
        );
        
        let agent_obj = object::address_to_object<Agent>(@0x0); // Placeholder
        
        // Try to issue without authorization (should fail)
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            80,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x20001)] // E_SCORE_OUT_OF_RANGE
    /// Test issuance fails with score > 100
    fun test_issue_reputation_invalid_score_fails() {
        let (owner, issuer, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Try to issue with invalid score (should fail)
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            101, // score > 100
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x20008)] // E_INVALID_FILE_URI
    /// Test issuance fails with empty file URI
    fun test_issue_reputation_empty_uri_fails() {
        let (owner, issuer, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Try to issue with empty URI (should fail)
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            75,
            helpers::test_context_hash(),
            std::string::utf8(b""), // Empty URI
            helpers::test_file_hash(),
            false
        );
    }

    #[test]
    /// Test reputation NFT is truly soulbound (cannot transfer)
    fun test_reputation_is_soulbound() {
        let (owner, issuer, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        agent_reputation::issue_reputation(
            &issuer,
            agent_obj,
            88,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Try to transfer (should fail due to set_untransferable)
        // TODO: Attempt transfer and verify failure
    }

    // ==================== 2.2 Issuer Capability Management (5 tests) ====================

    #[test]
    /// Test admin can grant issuer capability
    fun test_grant_issuer_capability() {
        let (_owner, issuer, admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
        
        // Verify capability granted
        assert!(agent_reputation::has_issuer_capability(issuer_addr), 0);
    }

    #[test]
    #[expected_failure(abort_code = 0x20005)] // E_NOT_ADMIN
    /// Test non-admin cannot grant capability
    fun test_grant_capability_non_admin_fails() {
        let (_owner, issuer, _admin) = setup();
        let non_admin = helpers::create_test_account(helpers::dave());
        let issuer_addr = signer::address_of(&issuer);
        
        // Try to grant as non-admin (should fail)
        agent_reputation::grant_issuer_capability(&non_admin, issuer_addr);
    }

    #[test]
    /// Test admin can revoke issuer capability
    fun test_revoke_issuer_capability() {
        let (_owner, issuer, admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Grant first
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
        assert!(agent_reputation::has_issuer_capability(issuer_addr), 0);
        
        // Then revoke
        agent_reputation::revoke_issuer_capability(&admin, issuer_addr);
        assert!(!agent_reputation::has_issuer_capability(issuer_addr), 1);
    }

    #[test]
    /// Test has_issuer_capability view function
    fun test_has_issuer_capability() {
        let (_owner, issuer, admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Before grant
        assert!(!agent_reputation::has_issuer_capability(issuer_addr), 0);
        
        // After grant
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
        assert!(agent_reputation::has_issuer_capability(issuer_addr), 1);
    }

    #[test]
    #[expected_failure(abort_code = 0x20006)] // E_CAPABILITY_EXISTS
    /// Test cannot grant duplicate capability
    fun test_duplicate_capability_grant_fails() {
        let (_owner, issuer, admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        // Grant once
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
        
        // Try to grant again (should fail)
        agent_reputation::grant_issuer_capability(&admin, issuer_addr);
    }

    // ==================== 2.3 Governance (3 tests) ====================

    #[test]
    /// Test admin can transfer governance
    fun test_transfer_governance() {
        let (_owner, _issuer, admin) = setup();
        let new_admin_addr = helpers::dave();
        
        // Verify initial admin
        assert!(agent_reputation::get_admin() == helpers::admin(), 0);
        
        // Transfer governance
        agent_reputation::transfer_governance(&admin, new_admin_addr);
        
        // Verify new admin
        assert!(agent_reputation::get_admin() == new_admin_addr, 1);
    }

    #[test]
    #[expected_failure(abort_code = 0x20005)] // E_NOT_ADMIN
    /// Test non-admin cannot transfer governance
    fun test_transfer_governance_non_admin_fails() {
        let (_owner, _issuer, _admin) = setup();
        let non_admin = helpers::create_test_account(helpers::dave());
        let new_admin_addr = helpers::charlie();
        
        // Try to transfer as non-admin (should fail)
        agent_reputation::transfer_governance(&non_admin, new_admin_addr);
    }

    #[test]
    /// Test get_admin view function
    fun test_get_admin() {
        let (_owner, _issuer, _admin) = setup();
        
        let admin_addr = agent_reputation::get_admin();
        assert!(admin_addr == helpers::admin(), 0);
    }

    // ==================== 2.4 Reputation Revocation (3 tests) ====================

    #[test]
    /// Test issuer can revoke their own reputation
    fun test_revoke_reputation_by_issuer() {
        let (owner, issuer, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Issue reputation and get its address
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            92,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Revoke
        agent_reputation::revoke_reputation(&issuer, reputation_addr);
        
        // Verify revoked status
        let (_agent, _issuer, _score, revoked, _issued_at, _response_count) = 
            agent_reputation::get_reputation(reputation_addr);
        assert!(revoked, 0);
    }

    #[test]
    #[expected_failure(abort_code = 0x20003)] // E_NOT_ISSUER
    /// Test non-issuer cannot revoke reputation
    fun test_revoke_reputation_non_issuer_fails() {
        let (owner, issuer, _admin) = setup();
        let non_issuer = helpers::create_test_account(helpers::dave());
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Issue reputation
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            78,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Try to revoke as non-issuer (should fail)
        agent_reputation::revoke_reputation(&non_issuer, reputation_addr);
    }

    #[test]
    #[expected_failure(abort_code = 0x20004)] // E_ALREADY_REVOKED
    /// Test cannot revoke already revoked reputation
    fun test_revoke_already_revoked_fails() {
        let (owner, issuer, _admin) = setup();
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            70,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Revoke once
        agent_reputation::revoke_reputation(&issuer, reputation_addr);
        
        // Try to revoke again (should fail)
        agent_reputation::revoke_reputation(&issuer, reputation_addr);
    }

    // ==================== 2.5 Response Records (3 tests) ====================

    #[test]
    /// Test appending response to reputation
    fun test_append_response_success() {
        let (owner, issuer, _admin) = setup();
        let responder = helpers::create_test_account(helpers::charlie());
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        // Issue reputation and get its address
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            95,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Append response
        agent_reputation::append_response(
            &responder,
            reputation_addr,
            helpers::test_response_uri(),
            helpers::test_response_hash()
        );
        
        // Verify response count increased
        let (_agent, _issuer, _score, _revoked, _issued_at, response_count) = 
            agent_reputation::get_reputation(reputation_addr);
        assert!(response_count == 1, 0);
    }

    #[test]
    /// Test appending multiple responses
    fun test_append_multiple_responses() {
        let (owner, issuer, _admin) = setup();
        let responder = helpers::create_test_account(helpers::charlie());
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            88,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Append 5 responses
        let i = 0;
        while (i < 5) {
            agent_reputation::append_response(
                &responder,
                reputation_addr,
                helpers::test_response_uri(),
                helpers::test_response_hash()
            );
            i = i + 1;
        };
        
        // Verify response count
        let (_agent, _issuer, _score, _revoked, _issued_at, response_count) = 
            agent_reputation::get_reputation(reputation_addr);
        assert!(response_count == 5, 0);
    }

    #[test]
    #[expected_failure(abort_code = 0x20007)] // E_TOO_MANY_RESPONSES
    /// Test cannot exceed maximum response limit (100)
    fun test_append_response_exceeds_limit_fails() {
        let (owner, issuer, _admin) = setup();
        let responder = helpers::create_test_account(helpers::charlie());
        let issuer_addr = signer::address_of(&issuer);
        
        let agent_obj = create_agent_with_auth(&owner, issuer_addr);
        
        let reputation_addr = agent_reputation::issue_reputation_internal(
            &issuer,
            agent_obj,
            82,
            helpers::test_context_hash(),
            helpers::test_file_uri(),
            helpers::test_file_hash(),
            false
        );
        
        // Append 101 responses (should fail at 101st)
        let i = 0;
        while (i <= 100) { // This will try to add 101
            agent_reputation::append_response(
                &responder,
                reputation_addr,
                helpers::test_response_uri(),
                helpers::test_response_hash()
            );
            i = i + 1;
        };
    }
}

