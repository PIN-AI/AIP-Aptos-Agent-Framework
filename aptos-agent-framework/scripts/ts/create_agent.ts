#!/usr/bin/env tsx
/**
 * AAF Create Agent Script
 * Creates a new agent on the Aptos blockchain
 *
 * Usage:
 *   tsx create_agent.ts --metadata-uri "https://example.com/agent.json"
 *   tsx create_agent.ts --metadata-uri "ipfs://QmHash" --domain "ai.trading"
 *   NETWORK=testnet tsx create_agent.ts --metadata-uri "..."
 */

import { initAAF, header, success, error, info, warning, colors, waitForTransaction, extractObjectAddress } from "./utils.js";

// ============================================================================
// Parse Arguments
// ============================================================================

function parseArgs() {
  const args = process.argv.slice(2);
  const params: {
    metadataUri?: string;
    domain?: string;
    network?: string;
    profile?: string;
  } = {};

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--metadata-uri":
        params.metadataUri = args[++i];
        break;
      case "--domain":
        params.domain = args[++i];
        break;
      case "--network":
        params.network = args[++i];
        break;
      case "--profile":
        params.profile = args[++i];
        break;
      case "--help":
      case "-h":
        console.log(`
AAF Create Agent Script

Usage:
  tsx create_agent.ts [options]

Options:
  --metadata-uri URI    Agent metadata URI (required)
  --domain DOMAIN       Agent domain (optional)
  --network NET         Network (devnet/testnet/mainnet, default: devnet)
  --profile NAME        Aptos profile (default: default)
  --help, -h            Show this help

Environment Variables:
  NETWORK               Network to use
  APTOS_PROFILE         Aptos profile to use
  APTOS_PRIVATE_KEY     Private key (overrides profile)

Examples:
  tsx create_agent.ts --metadata-uri "https://example.com/agent.json"
  tsx create_agent.ts --metadata-uri "ipfs://QmHash" --domain "ai.trading"
  NETWORK=testnet tsx create_agent.ts --metadata-uri "..."
        `);
        process.exit(0);
    }
  }

  // Use environment variables as fallback
  params.network = params.network || process.env.NETWORK || "devnet";
  params.profile = params.profile || process.env.APTOS_PROFILE || "default";

  return params;
}

// ============================================================================
// Main Function
// ============================================================================

async function main() {
  const params = parseArgs();

  // Validate required parameters
  if (!params.metadataUri) {
    error("Missing required parameter: --metadata-uri");
    info("Usage: tsx create_agent.ts --metadata-uri 'https://example.com/agent.json'");
    process.exit(1);
  }

  // Initialize AAF
  const { aptos, account, moduleAddress } = initAAF(params.network!, params.profile!);

  // ============================================================================
  // Display Parameters
  // ============================================================================
  header("Agent Parameters");

  console.log(`${colors.cyan}Metadata URI:${colors.reset} ${colors.yellow}${params.metadataUri}${colors.reset}`);
  if (params.domain) {
    console.log(`${colors.cyan}Domain:${colors.reset}       ${colors.yellow}${params.domain}${colors.reset}`);
  } else {
    console.log(`${colors.cyan}Domain:${colors.reset}       ${colors.yellow}None${colors.reset}`);
  }

  // ============================================================================
  // Build Transaction
  // ============================================================================
  header("Creating Agent");

  info(`Calling ${moduleAddress}::agent::create_agent`);

  try {
    info("Building transaction...");

    // Choose function based on domain parameter
    // Use CLI-friendly functions that avoid Option types
    const functionName = params.domain
      ? "create_agent_with_domain"
      : "create_agent_simple";

    const functionArgs = params.domain
      ? [params.metadataUri, params.domain]
      : [params.metadataUri];

    info(`Using function: ${functionName}`);
    info(`Arguments: ${JSON.stringify(functionArgs)}`);

    // Step 1: Build transaction
    const transaction = await aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${moduleAddress}::agent::${functionName}`,
        functionArguments: functionArgs,
      },
    });

    success("Transaction built");

    // Step 2: Sign transaction
    const senderAuthenticator = aptos.transaction.sign({
      signer: account,
      transaction,
    });

    success("Transaction signed");

    // Step 3: Submit transaction
    const committedTx = await aptos.transaction.submit.simple({
      transaction,
      senderAuthenticator,
    });

    success("Transaction submitted!");
    info(`Transaction Hash: ${colors.cyan}${committedTx.hash}${colors.reset}`);

    // Wait for transaction
    const executedTx = await waitForTransaction(aptos, committedTx.hash);

    if (!executedTx.success) {
      error("Transaction failed!");
      console.log(JSON.stringify(executedTx, null, 2));
      process.exit(1);
    }

    success("Agent created successfully!");

    // Extract agent address from events
    const events = (executedTx as any).events || [];
    const agentAddress = extractObjectAddress(events, "AgentRegistered");

    // ============================================================================
    // Display Results
    // ============================================================================
    header("Agent Created");

    console.log(`${colors.green}✅ Agent created successfully!${colors.reset}`);
    console.log("");
    console.log(`${colors.cyan}Agent Details:${colors.reset}`);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log(`  Creator:        ${colors.yellow}${account.accountAddress.toString()}${colors.reset}`);
    console.log(`  Metadata URI:   ${colors.yellow}${params.metadataUri}${colors.reset}`);
    if (params.domain) {
      console.log(`  Domain:         ${colors.yellow}${params.domain}${colors.reset}`);
    }
    if (agentAddress) {
      console.log(`  Agent Object:   ${colors.yellow}${agentAddress}${colors.reset}`);
    }
    console.log(`  Transaction:    ${colors.yellow}${committedTx.hash}${colors.reset}`);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("");

    console.log(`${colors.cyan}Next Steps:${colors.reset}`);
    console.log(`  1. Grant feedback auth: tsx grant_feedback_auth.ts --agent ${agentAddress || "AGENT_ADDR"}`);
    console.log(`  2. Issue reputation: tsx issue_reputation.ts --agent ${agentAddress || "AGENT_ADDR"}`);
    console.log("");

    console.log(`${colors.cyan}Explorer URL:${colors.reset}`);
    console.log(`  https://explorer.aptoslabs.com/txn/${committedTx.hash}?network=${params.network}`);
    console.log("");

    success("Agent creation complete! 🎉");

    // Return agent address for bash script to capture
    if (agentAddress) {
      console.log(`\nAGENT_ADDRESS=${agentAddress}`);
    }

  } catch (err: any) {
    error("Failed to create agent");
    console.error(err);
    if (err.transaction) {
      console.log("\nTransaction Details:");
      console.log(JSON.stringify(err.transaction, null, 2));
    }
    process.exit(1);
  }
}

// Run
main().catch((err) => {
  error("Unhandled error");
  console.error(err);
  process.exit(1);
});
