#[test_only]
/// Test Helper Module - Provides common utilities for AAF testing
module aaf::test_helpers {
    use std::string::{Self, String};
    use std::option;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;

    // ==================== Test Account Management ====================

    /// Create a test account at the given address
    public fun create_test_account(addr: address): signer {
        account::create_account_for_test(addr)
    }

    /// Create multiple test accounts
    public fun create_test_accounts(addrs: vector<address>): vector<signer> {
        let signers = vector::empty<signer>();
        let i = 0;
        let len = vector::length(&addrs);
        while (i < len) {
            let addr = *vector::borrow(&addrs, i);
            vector::push_back(&mut signers, create_test_account(addr));
            i = i + 1;
        };
        signers
    }

    // ==================== Timestamp Management ====================

    /// Initialize timestamp for testing (must call at start of each test)
    public fun setup_timestamp() {
        let framework = account::create_account_for_test(@0x1);
        timestamp::set_time_has_started_for_testing(&framework);
    }

    /// Fast forward time by specified seconds
    public fun fast_forward(seconds: u64) {
        timestamp::update_global_time_for_test_secs(
            timestamp::now_seconds() + seconds
        );
    }

    /// Get current test timestamp
    public fun now(): u64 {
        timestamp::now_seconds()
    }

    // ==================== Test Data Generators ====================

    /// Generate standard test metadata URI
    public fun test_metadata_uri(): String {
        string::utf8(b"https://example.com/agent-card.json")
    }

    /// Generate test metadata URI with index
    public fun test_metadata_uri_indexed(index: u64): String {
        let base = b"https://example.com/agent-";
        vector::append(&mut base, num_to_bytes(index));
        vector::append(&mut base, b".json");
        string::utf8(base)
    }

    /// Generate test domain
    public fun test_domain(): String {
        string::utf8(b"example.com")
    }

    /// Generate test domain with index
    public fun test_domain_indexed(index: u64): String {
        let base = b"agent";
        vector::append(&mut base, num_to_bytes(index));
        vector::append(&mut base, b".example.com");
        string::utf8(base)
    }

    /// Generate test file URI for reputation
    public fun test_file_uri(): String {
        string::utf8(b"https://storage.example.com/feedback-123.json")
    }

    /// Generate test file hash
    public fun test_file_hash(): vector<u8> {
        x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    }

    /// Generate test context hash
    public fun test_context_hash(): vector<u8> {
        x"fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321"
    }

    /// Generate test data hash for validation
    public fun test_data_hash(): vector<u8> {
        x"abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
    }

    /// Generate test response URI
    public fun test_response_uri(): String {
        string::utf8(b"https://response.example.com/resp-456.json")
    }

    /// Generate test response hash
    public fun test_response_hash(): vector<u8> {
        x"0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba"
    }

    // ==================== Time Constants ====================

    public fun one_hour(): u64 { 3600 }
    public fun one_day(): u64 { 86400 }
    public fun one_week(): u64 { 604800 }
    public fun one_month(): u64 { 2592000 }

    // ==================== Test Addresses ====================

    public fun alice(): address { @0xA11CE }
    public fun bob(): address { @0xB0B }
    public fun charlie(): address { @0xC4A211E }
    public fun dave(): address { @0xDADE }
    public fun admin(): address { @0xCAFE }

    // ==================== Helper Functions ====================

    /// Convert u64 to bytes (simple implementation for testing)
    fun num_to_bytes(num: u64): vector<u8> {
        if (num == 0) return b"0";
        
        let bytes = vector::empty<u8>();
        let temp = num;
        
        while (temp > 0) {
            let digit = ((temp % 10) as u8) + 48; // ASCII '0' = 48
            vector::push_back(&mut bytes, digit);
            temp = temp / 10;
        };
        
        // Reverse the vector
        vector::reverse(&mut bytes);
        bytes
    }

    /// Create an Option<String> for domain
    public fun some_domain(): option::Option<String> {
        option::some(test_domain())
    }

    /// Create an empty Option<String>
    public fun none_domain(): option::Option<String> {
        option::none<String>()
    }
}

