---
aip: unconfirmed
title: Aptos Agent Framework
author: PIN-AI Team
discussions-to:
Status: Draft
last-call-end-date:
type: Standard (Framework, Application)
created: 11/10/2025
updated: 11/13/2025
requires: aip-10, aip-11
---

# Aptos Agent Framework

## Summary

This AIP proposes the Aptos Agent Framework (AAF), a native on-chain framework for creating, managing, and interacting with autonomous agents on Aptos. AAF leverages the unique capabilities of the Move Object Model and Digital Assets to provide a composable, trustless foundation for a decentralized agent economy. The framework defines three core layers:

1. **Identity Layer**: Each agent is a native Move `Object` with a globally unique address, enabling agents to own assets and interact as first-class blockchain citizens.
2. **Reputation Layer**: Feedback is tokenized as composable Digital Assets (NFTs) using a "Core Immutable, State Mutable" design—core reputation data (score, issuer, context) is permanent, while state (revocation, responses) can be updated with full transparency.
3. **Validation Layer**: A flexible request/response interface for third-party validation, with globally unique request IDs and optional TTL enforcement.

AAF is designed for the emerging AI agent economy, supporting protocols like MCP and A2A, while providing crypto-economic trust mechanisms native to blockchain.

### Out of scope

*   **Agent Intelligence:** The framework does not define the off-chain logic or AI models that power the agents. It only provides the on-chain primitives for identity, reputation, and validation.
*   **Specific Agent Implementations:** This AIP specifies the framework, not the implementation of any particular type of agent (e.g., a trading agent, a content generation agent).
*   **Complex Validation Schemes:** The initial validation layer will focus on a simple staking and slashing model. More complex validation mechanisms (e.g., requiring multiple validators, optimistic validation) are left for future proposals.

## High-level Overview

The Aptos Agent Framework (AAF) is designed to make autonomous agents first-class citizens of the Aptos ecosystem, with native blockchain identity, composable reputation, and flexible validation mechanisms.

### Why AAF is uniquely suited to Aptos

Unlike account-based or registry-based approaches common in other ecosystems, AAF fully embraces the **Move Object Model** to provide superior composability and ownership semantics:

1.  **Identity Layer**: Every agent is a native Move `Object` with:
    - Globally unique, permanent on-chain address
    - Ability to own assets (including its own reputation NFTs)
    - Direct event emission for rich on-chain activity tracking
    - Built-in authorization system for feedback control

2.  **Reputation Layer**: Reputation is not just a number—it's **tokenized as composable Digital Assets**:
    - Each reputation is an independent NFT with "Core Immutable, State Mutable" design
    - Core data (score, issuer, context) is immutable to ensure trust
    - State data (revoked, responses) is mutable for lifecycle management
    - Other protocols can directly query and compose with reputation NFTs
    - Soulbound (non-transferable) by default to prevent reputation trading

3.  **Validation Layer**: A flexible, event-driven validation system:
    - Globally unique request IDs (hash of agent + validator + data + timestamp)
    - Pending and completed validation tracking with TTL enforcement
    - Pluggable validator architecture (staking pools, TEE oracles, zkML verifiers in future phases)

### Integration with Agent Communication Protocols

AAF provides the **trust and identity layer** for agent communication protocols:
- **MCP (Model Context Protocol)**: Agents can advertise MCP endpoints in their AgentCard
- **A2A (Agent-to-Agent)**: Native support for A2A skills and task ontology in reputation metadata
- **Custom Protocols**: Flexible endpoint system supports any communication standard

This layered approach creates a robust foundation for AI-powered DAOs, decentralized task marketplaces, and autonomous on-chain services.

### Design Decisions

- Start outside `0x1` and upstream later: AAF starts as community modules to iterate faster; a minimal, stable interface and events may later be proposed into `0x1`.
- No on-chain registry initially: Identity discovery relies on Agent Objects (AIP-10) + off-chain AgentCard (well-known URI) and on-chain events. An optional minimal `agent_registry` (domain → agent address) may be added in future iterations as an optional index.
- Reputation issuance control: Reputation is tokenized as soulbound Digital Assets. Two issuance modes: open "feedback" (permissionless) and credential "attestations" (gated by issuer capability). This AIP specifies issuer capability whitelisting; economic gating via staking may be added in future proposals.
- Validation design: This AIP provides event-driven request/response with minimal pending-request state and TTL enforcement. Economic security mechanisms (staking pools, slashing, arbitration) are deferred to future proposals.
- Authentication integration: Leverage AIP-104 (Account Abstraction) and AIP-113 (Derivable AA for domain-scoped authentication) for agent authentication; AIP-121 serves as a reference for cross-chain implementation patterns. Use AIP-39 for gas sponsorship in cross-agent flows.

## Impact

*   **dApp Developers:** Can build applications that leverage a standardized pool of on-chain agents for various tasks, without needing to build their own agent management systems.
*   **Agent Operators:** Can deploy agents that are instantly compatible with the entire AAF ecosystem, gaining access to a wider market.
*   **Users:** Can interact with agents with a higher degree of trust, thanks to transparent on-chain reputation and economic security.
*   **Dependencies:** This AIP requires and builds upon:
    *   **AIP-10 (Move Objects):** For the core identity primitive.
    *   **AIP-11 (Digital Assets):** For the tokenized reputation system.

## Alternative Solutions

1.  **Account-Based Agent Model**: Using standard Aptos accounts to represent agents was considered. In this model, each agent would be a regular account with associated metadata stored in resources. This was rejected because:
    - Lacks composability: reputation cannot be directly referenced as independent assets
    - No clear ownership model for reputation data
    - Limited extensibility compared to Object-based design
    - Misses the benefits of AIP-10/11 (Objects and Digital Assets)

2.  **Centralized Registry Contract**: A single registry contract mapping agent IDs to metadata was considered (common pattern in other blockchain ecosystems). This was rejected because:
    - Creates a bottleneck: all agent operations must go through the registry
    - Limits composability: agents cannot be treated as independent entities
    - Does not leverage Aptos's Object Model advantages
    - Harder to extend with custom agent-specific logic

3.  **Off-Chain Registry with On-Chain Anchors**: Using an off-chain system (e.g., centralized database or IPFS) for agent identity and reputation, with only cryptographic anchors on-chain. This was rejected because:
    - Sacrifices decentralization and trustlessness
    - Reduces transparency (off-chain data can be censored or manipulated)
    - Loses composability with other on-chain protocols
    - Reintroduces centralized trust assumptions

4.  **Pure Event-Based System**: Storing all data in events without on-chain state. This was rejected because:
    - No on-chain composability (smart contracts cannot read events)
    - Requires complex off-chain indexing for any queries
    - No on-chain enforcement of authorization or TTL logic

**Why Object-Based Design is Superior**: The proposed Object-based model aligns perfectly with Aptos's architecture, making agents true, native participants in the on-chain economy. Objects provide:
- Native ownership and transferability
- Direct event emission
- Resource co-location (gas efficiency via resource groups)
- Extensibility through capability-based access control
- Composability with other Object-based protocols

## Specification and Implementation Details

AAF will be implemented first as community modules. A minimal stable interface may be proposed to `0x1` later.

### 1. Identity Module (`agent`)

This module defines the `Agent` object with feedback authorization capability.

```move
module agent {
    use aptos_framework::object::{Self, Object};
    use aptos_framework::table::{Self, Table};
    use aptos_framework::timestamp;
    use std::option;
    use std::string::String;

    // Declare friend module
    friend aaf::agent_reputation;

    /// Authorization for a client to issue reputation feedback.
    /// Note: client address is the Table key, not stored in the struct
    struct FeedbackAuth has store {
        index_limit: u64,     // Maximum feedback index allowed (for rate limiting)
        expiry: u64,          // Timestamp when authorization expires
        last_index: u64,      // Last used feedback index
    }

    /// The core Agent object.
    struct Agent has key {
        metadata_uri: String,
        owner: address,
        domain: option::Option<String>,
        feedback_auths: Table<address, FeedbackAuth>,  // client_address => FeedbackAuth
    }

    // ===== Events =====
    #[event]
    struct AgentRegistered has drop, store {
        agent: address,
        owner: address,
        metadata_uri_hash: vector<u8>,  // Hash for indexing
        domain: option::Option<String>,
        timestamp: u64,
    }

    #[event]
    struct AgentUpdated has drop, store {
        agent: address,
        metadata_uri_hash: option::Option<vector<u8>>,  // Hash if updated
        domain: option::Option<String>,
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

    // ===== Public Entry Functions =====

    /// Creates a new Agent object with metadata URI and optional domain.
    /// Returns Object<Agent> via internal function, entry function discards return.
    public entry fun create_agent(
        creator: &signer,
        metadata_uri: String,
        domain: option::Option<String>
    );

    public entry fun create_agent_simple(
        creator: &signer,
        metadata_uri: String
    );

    public entry fun create_agent_with_domain(
        creator: &signer,
        metadata_uri: String,
        domain: String
    );

    /// Agent owner grants feedback authorization to a client with rate limiting.
    public entry fun grant_feedback_auth(
        owner: &signer,
        agent: Object<Agent>,
        client: address,
        index_limit: u64,
        expiry: u64
    ) acquires Agent;

    /// Agent owner revokes feedback authorization from a client.
    public entry fun revoke_feedback_auth(
        owner: &signer,
        agent: Object<Agent>,
        client: address
    ) acquires Agent;

    /// Update agent metadata URI and/or domain.
    public entry fun update_agent(
        owner: &signer,
        agent: Object<Agent>,
        new_metadata_uri: option::Option<String>,
        new_domain: option::Option<String>
    ) acquires Agent;

    /// Transfer agent ownership to a new address.
    public entry fun transfer_owner(
        owner: &signer,
        agent: Object<Agent>,
        new_owner: address
    ) acquires Agent;

    // ===== Friend Functions =====

    /// Verifies feedback authorization and consumes one quota slot.
    /// Returns the feedback index for this issuance.
    public(friend) fun verify_and_consume_feedback_auth(
        agent: Object<Agent>,
        client: address
    ): u64 acquires Agent;

    // ===== Error Codes =====
    const E_NOT_OWNER: u64 = 0x10001;
    const E_AUTH_NOT_FOUND: u64 = 0x10002;
    const E_AUTH_EXPIRED: u64 = 0x10003;
    const E_AUTH_QUOTA_EXCEEDED: u64 = 0x10004;
    const E_INVALID_METADATA_URI: u64 = 0x10005;
    const E_INVALID_EXPIRY: u64 = 0x10006;
}
```

### 2. Reputation Module (`agent_reputation`)

This module implements reputation as composable Digital Assets with "Core Immutable, State Mutable" design.

**Design Philosophy**: Reputation NFTs have immutable core data (score, issuer, context) to ensure integrity, while supporting mutable state (revocation, response tracking) for lifecycle management. Response records are stored as independent objects to prevent Gas DoS attacks.

```move
module agent_reputation {
    use aptos_framework::object::{Self, Object};
    use aptos_framework::agent::Agent;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use std::string::String;

    /// Maximum number of responses per reputation (prevent DoS)
    const MAX_RESPONSES: u64 = 100;

    /// Response record (stored as independent object)
    struct ResponseRecord has key {
        reputation: address,       // Associated reputation NFT
        responder: address,
        response_uri: String,
        response_hash: vector<u8>,
        timestamp: u64,
        index: u64,                // Response index (nth response)
    }

    /// Reputation NFT: Core data immutable, state data mutable.
    struct ReputationNFT has key {
        // ===== IMMUTABLE CORE (set at creation) =====
        agent: address,
        issuer: address,
        score: u8,                  // 0-100
        context_hash: vector<u8>,   // Hash of task/interaction context
        file_uri: String,           // Off-chain detailed feedback
        file_hash: vector<u8>,      // Hash of file_uri content
        issued_at: u64,
        feedback_index: u64,        // Monotonic index for this issuer->agent

        // ===== MUTABLE STATE =====
        revoked: bool,
        response_count: u64,        // Response counter (responses stored separately)
    }

    /// Issuer capability store (using Table for efficient storage)
    struct IssuerCapabilityStore has key {
        issuers: Table<address, bool>,
    }

    /// Governance configuration (avoid hardcoded admin)
    struct GovernanceConfig has key {
        admin: address,
    }

    // ===== Events =====
    #[event]
    struct ReputationIssued has drop, store {
        reputation_obj: address,
        agent: address,
        issuer: address,
        score: u8,
        context_hash: vector<u8>,  // Hash for indexing
        file_hash: vector<u8>,     // Hash for verification
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
        response_obj: address,     // Independent response object
        agent: address,
        responder: address,
        response_hash: vector<u8>,  // Hash for verification
        index: u64,
        timestamp: u64,
    }

    #[event]
    struct GovernanceTransferred has drop, store {
        old_admin: address,
        new_admin: address,
        timestamp: u64,
    }

    // ===== Public Entry Functions =====

    /// Issues a soulbound reputation NFT to an agent.
    /// Requires agent's prior feedback authorization.
    /// If gated=true, requires IssuerCapability.
    public entry fun issue_reputation(
        issuer: &signer,
        agent: Object<Agent>,
        score: u8,
        context_hash: vector<u8>,
        file_uri: String,
        file_hash: vector<u8>,
        gated: bool
    ) acquires IssuerCapabilityStore;

    /// Issuer marks their previously issued reputation as revoked.
    public entry fun revoke_reputation(
        issuer: &signer,
        reputation: Object<ReputationNFT>
    ) acquires ReputationNFT;

    /// Appends a response record to a reputation NFT.
    /// Creates independent ResponseRecord object (max 100 per reputation).
    public entry fun append_response(
        responder: &signer,
        reputation: Object<ReputationNFT>,
        response_uri: String,
        response_hash: vector<u8>
    ) acquires ReputationNFT;

    /// Grants issuer capability to an address (admin-controlled).
    public entry fun grant_issuer_capability(
        admin: &signer,
        issuer: address
    ) acquires GovernanceConfig, IssuerCapabilityStore;

    /// Transfers governance to a new admin.
    public entry fun transfer_governance(
        admin: &signer,
        new_admin: address
    ) acquires GovernanceConfig;

    // ===== View Functions =====

    /// Returns (agent, issuer, score, revoked, issued_at).
    #[view]
    public fun get_reputation(
        reputation: Object<ReputationNFT>
    ): (address, address, u8, bool, u64) acquires ReputationNFT;

    /// Returns the number of responses appended to this reputation.
    #[view]
    public fun get_response_count(
        reputation: Object<ReputationNFT>
    ): u64 acquires ReputationNFT;

    // ===== Error Codes =====
    const E_SCORE_OUT_OF_RANGE: u64 = 0x20001;
    const E_ISSUER_FORBIDDEN: u64 = 0x20002;
    const E_NOT_ISSUER: u64 = 0x20003;
    const E_ALREADY_REVOKED: u64 = 0x20004;
    const E_NOT_ADMIN: u64 = 0x20005;
    const E_INVALID_FILE_URI: u64 = 0x20006;
    const E_MAX_RESPONSES_REACHED: u64 = 0x20007;
    const E_REVOKED: u64 = 0x20008;
}
```

### 3. Validation Module (`agent_validation`)

This module provides a request/response interface for validation with globally unique request IDs.

```move
module agent_validation {
    use aptos_framework::object::{Self, Object};
    use aptos_framework::table::{Self, Table};
    use aptos_framework::agent::Agent;
    use std::vector;

    /// Pending request information.
    struct RequestInfo has store, drop {
        agent: address,
        validator: address,
        data_hash: vector<u8>,
        created_at: u64,
        ttl_secs: u64,
    }

    /// Completed validation record.
    struct ValidationRecord has store, drop {
        agent: address,
        validator: address,
        data_hash: vector<u8>,
        response: u8,           // 0-100 score
        response_uri: String,
        response_hash: vector<u8>,
        responded_at: u64,
    }

    /// Global storage for pending and completed validations.
    struct ValidationRegistry has key {
        pending: Table<vector<u8>, RequestInfo>,
        completed: Table<vector<u8>, ValidationRecord>,
    }

    // ===== Events =====
    #[event]
    struct ValidationRequested has drop, store {
        request_id: vector<u8>,
        agent: address,
        validator: address,
        data_hash: vector<u8>,  // Hash for indexing
        created_at: u64,
        ttl_secs: u64,
    }

    #[event]
    struct ValidationResponded has drop, store {
        request_id: vector<u8>,
        agent: address,
        validator: address,
        response: u8,
        response_hash: vector<u8>,  // Hash for verification
        responded_at: u64,
    }

    // ===== Module Initialization =====

    /// Initializes the validation registry (called once at module deployment).
    fun init_module(deployer: &signer);

    // ===== Public Entry Functions =====

    /// Requests validation for an agent's work.
    /// Computes globally unique request_id = hash(agent || validator || data_hash || timestamp).
    public entry fun request_validation(
        requester: &signer,
        agent_addr: address,
        validator: address,
        data_hash: vector<u8>,
        ttl_secs: u64
    ) acquires ValidationRegistry;

    /// Validator responds to a pending request with a score and evidence.
    /// Verifies TTL and moves the request from pending to completed.
    public entry fun respond_validation(
        responder: &signer,
        request_id: vector<u8>,
        response: u8,
        response_uri: String,
        response_hash: vector<u8>
    ) acquires ValidationRegistry;

    // ===== View Functions =====

    /// Returns (agent, validator, response, responded_at) for a completed validation.
    #[view]
    public fun get_validation_status(
        request_id: vector<u8>
    ): (address, address, u8, u64) acquires ValidationRegistry;

    /// Checks if a request is still pending.
    #[view]
    public fun is_pending(request_id: vector<u8>): bool acquires ValidationRegistry;

    // ===== Helper Functions =====

    /// Computes globally unique request_id from agent, validator, data_hash, and timestamp.
    fun compute_request_id(
        agent: address,
        validator: address,
        data_hash: &vector<u8>,
        timestamp: u64
    ): vector<u8>;

    // ===== Error Codes =====
    const E_REQUEST_EXISTS: u64 = 0x30001;
    const E_RESPONSE_OUT_OF_RANGE: u64 = 0x30002;
    const E_REQUEST_NOT_FOUND: u64 = 0x30003;
    const E_NOT_VALIDATOR: u64 = 0x30004;
    const E_REQUEST_EXPIRED: u64 = 0x30005;
    const E_VALIDATION_NOT_FOUND: u64 = 0x30006;
    const E_INVALID_TTL: u64 = 0x30007;
}
```

**Notes**:
- This specification intentionally excludes staking/slashing mechanisms. `ValidationRequested/Responded` events provide a stable interface for external protocols to integrate economic security layers.
- The `ValidationRegistry` can be deployed at a well-known address for easier indexing.

### 4. AgentCard Metadata Schema

The `metadata_uri` field in `Agent` MUST resolve to a JSON file following this standard schema for interoperability:

```jsonc
{
  // ===== REQUIRED FIELDS =====
  "type": "https://aptoslabs.com/standards/aaf#agentcard-v1",
  "name": "Agent Name",
  "description": "Natural language description of the agent, capabilities, and pricing",

  // ===== OPTIONAL FIELDS =====
  "image": "https://example.com/agent-avatar.png",

  // Communication endpoints: supports MCP, A2A, and custom protocols
  "endpoints": [
    {
      "name": "MCP",
      "endpoint": "https://agent.example.com/mcp",
      "version": "2025-06-18",
      "capabilities": {}  // MCP capabilities object (optional)
    },
    {
      "name": "A2A",
      "endpoint": "https://agent.example.com/.well-known/agent-card.json",
      "version": "0.3.0"
    },
    {
      "name": "Custom-Protocol",
      "endpoint": "wss://agent.example.com/ws",
      "version": "1.0"
    }
  ],

  // Agent wallet addresses (can be on any chain)
  "wallets": [
    {
      "chain": "aptos",
      "address": "0x1234...abcd"
    },
    {
      "chain": "ethereum",
      "address": "0x5678...efgh"
    }
  ],

  // Cross-chain agent registrations
  "registrations": [
    {
      "chain": "aptos",
      "network": "mainnet",
      "agent_address": "0xabcd...1234"
    }
  ],

  // Supported trust mechanisms
  "supportedTrust": [
    "reputation",           // Reputation NFTs via agent_reputation module
    "validation",           // Validation via agent_validation module
    "crypto-economic",      // Staking/slashing (P1+)
    "tee-attestation"       // TEE-based trust (P2+)
  ],

  // Agent capabilities and skills (application-defined)
  "capabilities": {
    "tasks": ["trading", "data-analysis", "content-generation"],
    "languages": ["en", "fr"],
    "max_concurrent_tasks": 10
  }
}
```

**Discovery Convention**: Agents SHOULD host their AgentCard at:
- HTTPS: `https://{domain}/.well-known/agentcard.json` (if `domain` field is set)
- IPFS: `ipfs://{cid}` (content-addressable, recommended for immutability)
- Shelby: `shelby://{resource_id}` (Aptos native hot storage, when available on mainnet)

HTTPS endpoints provide immediate accessibility, while content-addressable storage (IPFS, Shelby) ensures data permanence and tamper-resistance.

**Indexing**: Off-chain indexers SHOULD monitor `AgentRegistered` events and fetch AgentCards for search/discovery services.

### 5. Authentication and Gas Sponsorship

- Authentication: adopt AIP-104 for base Account Abstraction and AIP-113 for Derivable AA (domain-scoped authenticators) for agents, with human-readable message formats referencing an entry function and network name. AIP-121 provides a reference pattern for cross-chain authentication.
- Gas Sponsorship: adopt AIP-39 to allow a separate gas payer (e.g., service operator) in client-server agent workflows without blocking on sender nonce.

## Risks and Drawbacks

*   **Reputation Gaming:** Malicious actors could try to boost their reputation by creating fake tasks and positive reviews (Sybil attacks). This must be mitigated at the application layer, for example by tying reputation issuance to economically significant tasks.
*   **Slashing Complexity:** The logic for determining when to slash an agent can be complex and may require a trusted oracle or a decentralized court system, which adds complexity.
*   **Gas Costs:** Storing all reputation on-chain as NFTs could be expensive. Applications may need to be selective about what warrants an on-chain reputation entry.

## Security Considerations

The primary security risk is the slashing mechanism. The `slash` function must be strictly controlled to prevent malicious actors from unfairly penalizing honest agents. Access to this function should be limited, for example, to specific governance-approved contracts or multi-sig authorities. All modules will require extensive unit testing and formal verification where possible.

## Future Potential

### Enhanced Discovery and Indexing
- **On-chain Agent Registry**: An optional `agent_registry` module mapping domains to agent addresses, enabling efficient on-chain discovery without relying solely on event indexing.

### Advanced Validation and Economic Security
- **Validation Pools with Staking/Slashing**: A minimal `ValidationPool` framework (conceptually similar to AIP-6's delegation pool) enabling validators to stake tokens, with conditional slashing for dishonest validation responses.
- **Pluggable Validation Backends**: Support for TEE attestations (e.g., Intel SGX proofs), zkML verifiers for AI model execution validation, and committee-based validation for high-value tasks.
- **Optimistic Validation**: Challenge-response mechanisms where validation results are assumed correct unless disputed within a time window.

### Reputation Enhancements
- **Reputation Aggregation Standards**: Standardized on-chain and off-chain methods for computing aggregate reputation scores across multiple issuers, with domain-specific weighting.
- **Sybil-Resistant Reputation**: Economic bonding requirements or proof-of-work for feedback issuance to mitigate spam and fake reviews.
- **Cross-Chain Reputation Bridging**: Mechanisms to import reputation signals from other blockchains (e.g., Ethereum attestations via bridges).

### Governance and Upgradeability
- **DAO-Governed Issuer Capabilities**: Replace admin-controlled issuer capability grants with on-chain governance (proposal + voting) for credential attestation authorities.
- **Modular Authentication**: Support for custom authentication modules beyond AIP-104/113, allowing agents to define bespoke access control policies.

### Ecosystem Integration
- **AI DAOs**: AAF as the backbone for DAOs where agents are voting members, autonomously executing proposals and managing treasury.
- **Decentralized Compute/Task Markets**: Standardized marketplaces where users submit tasks to agents, with reputation-based agent selection and escrow-based payments.
- **Agent-to-Agent Economy**: Agents hiring sub-agents for task decomposition, creating autonomous on-chain supply chains with reputation-based trust.
- **Composable Reputation as Collateral**: Using reputation NFTs as collateral in DeFi protocols or as prerequisites for high-value task participation.
## Testing 

- Unit tests
  - `agent`: register/update/transfer events emitted; ownership checks.
  - `agent_reputation`: mint soulbound NFT; enforce non-transferability; issuer capability gating for credentials.
  - `agent_validation`: happy-path request/respond; TTL expiry; mismatched agent/validator rejections; response range bounds.
- E2E tests
  - Reputation issuance to Agent Object and indexer detection via events.
  - Validation request/response roundtrip and off-chain resolver fetching by `data_hash`.
  - Sponsored Tx flow: sender signs, gas payer adds signature, execution context matches sender.
- Negative tests
  - Attempt to transfer soulbound reputation; gated minting without capability; expired validation response.

Results are expected as part of a reference PoC repository accompanying this AIP; devnet demonstrations will be recorded.

## Timeline

### Current Status

**Devnet Implementation Complete **

AAF is now live on Aptos Devnet with full functionality:

- **Contract Deployment**: [View on Explorer](https://explorer.aptoslabs.com/txn/0x717bcb2d19eee1ceefad3ce67e291b843ecfdb18fc18c40fccfc37678df3f8f0?network=devnet)
- **GitHub Repository**: https://github.com/PIN-AI/AIP-Aptos-Agent-Framework

**Live Demonstrations**:
All core features have been tested on-chain with verifiable transactions:

- [Agent Creation](https://explorer.aptoslabs.com/txn/0x1d167fd96d25b0ad71d3f87f88295dae8f0600ea2569c1d5e3974c96c4d384c1?network=devnet)
- [Feedback Authorization](https://explorer.aptoslabs.com/txn/0x8c92f1a5591dd7c5b34b0c41b8dacfda62088583c1046e07c6d9281c1718bae4?network=devnet)
- [Reputation Issuance](https://explorer.aptoslabs.com/txn/0xc56a13a44c8eea4173f439351a6c3d2e5b33c85d2f9289a40a3f0c4abcbe38d8?network=devnet)

### Suggested implementation timeline
- **Initial Release (COMPLETED)**: Core AAF modules (identity, reputation, validation), unit/E2E tests, devnet demo, SDK helpers for event structs.
- **Community Review (CURRENT)**: Gathering feedback from the Aptos community, security review, and integration testing with real-world use cases.
- **Future Enhancements**: Optional on-chain registry, validation pools with staking, production-hardened DAA examples.

### Suggested developer platform support timeline
- **Initial SDK Support (COMPLETED)**: TypeScript SDK interaction tools with full feature coverage, CLI-friendly interfaces avoiding complex types.
- **Future Enhancements**: SDK types for events and helper encoders/decoders; indexer event handlers and reputation aggregation examples; staking/slashing indexer parsers, registry query APIs.

### Suggested deployment timeline
- **Devnet**: Core modules deployed, all tests passed, live demonstrations available.
- **Testnet**: Following community feedback, security review, and stability testing.
- **Mainnet**: After security audit, demonstrated adoption interest, and testnet validation.

## Open Questions (Optional)

- Should `agent_registry` be standardized in future iterations or remain ecosystem-specific to encourage competition in discovery services?
- Minimum data schema for reputation NFTs to balance expressiveness and indexer cost? (score scale, context hashing)
- Common message format and scope limitations for DAA authenticators to provide consistent UX across wallets?
