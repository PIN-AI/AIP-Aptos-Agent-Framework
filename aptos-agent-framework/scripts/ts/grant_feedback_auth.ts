#!/usr/bin/env tsx
/**
 * AAF Grant Feedback Authorization Script
 * Agent owner grants feedback authorization to a client
 *
 * Usage:
 *   tsx grant_feedback_auth.ts --agent <AGENT_ADDR> --client <CLIENT_ADDR> --limit <NUM> --days <DAYS>
 *   tsx grant_feedback_auth.ts --agent 0x123... --client 0x456... --limit 10 --days 30
 *   NETWORK=testnet tsx grant_feedback_auth.ts --agent 0x123... --client 0x456... --limit 5 --hours 24
 */

import { initAAF, header, success, error, info, warning, colors, waitForTransaction } from "./utils.js";

// ============================================================================
// Parse Arguments
// ============================================================================

function parseArgs() {
  const args = process.argv.slice(2);
  const params: {
    agent?: string;
    client?: string;
    indexLimit?: number;
    expiry?: number;
    days?: number;
    hours?: number;
    network?: string;
    profile?: string;
  } = {};

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--agent":
        params.agent = args[++i];
        break;
      case "--client":
        params.client = args[++i];
        break;
      case "--limit":
        params.indexLimit = parseInt(args[++i]);
        break;
      case "--expiry":
        params.expiry = parseInt(args[++i]);
        break;
      case "--days":
        params.days = parseInt(args[++i]);
        break;
      case "--hours":
        params.hours = parseInt(args[++i]);
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
AAF Grant Feedback Authorization Script

Usage:
  tsx grant_feedback_auth.ts [options]

Options:
  --agent ADDR          Agent object address (required)
  --client ADDR         Client address to authorize (required)
  --limit NUM           Maximum feedback index limit (required)
  --expiry TIMESTAMP    Authorization expiry timestamp (optional)
  --days NUM            Authorization duration in days (optional, default: 30)
  --hours NUM           Authorization duration in hours (optional)
  --network NET         Network (devnet/testnet/mainnet, default: devnet)
  --profile NAME        Aptos profile (default: default)
  --help, -h            Show this help

Note: You must be the agent owner to grant authorization.
Either provide --expiry directly or use --days/--hours to calculate it.

Environment Variables:
  NETWORK               Network to use
  APTOS_PROFILE         Aptos profile to use
  APTOS_PRIVATE_KEY     Private key (overrides profile)

Examples:
  tsx grant_feedback_auth.ts --agent 0x123... --client 0x456... --limit 10 --days 30
  tsx grant_feedback_auth.ts --agent 0x123... --client 0x456... --limit 5 --hours 24
  NETWORK=testnet tsx grant_feedback_auth.ts --agent 0x123... --client 0x456... --limit 100 --days 90
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
  if (!params.agent) {
    error("Missing required parameter: --agent");
    info("Usage: tsx grant_feedback_auth.ts --agent <AGENT_ADDR> --client <CLIENT_ADDR> --limit <NUM> --days <DAYS>");
    process.exit(1);
  }

  if (!params.client) {
    error("Missing required parameter: --client");
    info("Usage: tsx grant_feedback_auth.ts --agent <AGENT_ADDR> --client <CLIENT_ADDR> --limit <NUM> --days <DAYS>");
    process.exit(1);
  }

  if (params.indexLimit === undefined) {
    error("Missing required parameter: --limit");
    info("Usage: tsx grant_feedback_auth.ts --agent <AGENT_ADDR> --client <CLIENT_ADDR> --limit <NUM> --days <DAYS>");
    process.exit(1);
  }

  // Initialize AAF
  const { aptos, account, moduleAddress } = initAAF(params.network!, params.profile!);

  // Calculate expiry timestamp
  let expiryTimestamp: number;

  if (params.expiry) {
    expiryTimestamp = params.expiry;
  } else {
    // Get current timestamp from blockchain
    const ledgerInfo = await aptos.getLedgerInfo();
    const currentTimestamp = Math.floor(parseInt(ledgerInfo.ledger_timestamp) / 1_000_000); // Convert microseconds to seconds

    // Default to 30 days if not specified
    const durationSeconds = params.hours
      ? params.hours * 3600
      : (params.days || 30) * 86400;

    expiryTimestamp = currentTimestamp + durationSeconds;
  }

  // ============================================================================
  // Display Parameters
  // ============================================================================
  header("Feedback Authorization Parameters");

  console.log(`${colors.cyan}Agent:${colors.reset}       ${colors.yellow}${params.agent}${colors.reset}`);
  console.log(`${colors.cyan}Client:${colors.reset}      ${colors.yellow}${params.client}${colors.reset}`);
  console.log(`${colors.cyan}Index Limit:${colors.reset} ${colors.yellow}${params.indexLimit}${colors.reset}`);
  console.log(`${colors.cyan}Expiry:${colors.reset}      ${colors.yellow}${expiryTimestamp}${colors.reset} (${new Date(expiryTimestamp * 1000).toISOString()})`);

  // ============================================================================
  // Build Transaction
  // ============================================================================
  header("Granting Feedback Authorization");

  info(`Calling ${moduleAddress}::agent::grant_feedback_auth`);

  try {
    info("Building transaction...");

    // Step 1: Build transaction
    const transaction = await aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${moduleAddress}::agent::grant_feedback_auth`,
        functionArguments: [
          params.agent,
          params.client,
          params.indexLimit,
          expiryTimestamp
        ],
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

    success("Feedback authorization granted successfully!");

    // ============================================================================
    // Display Results
    // ============================================================================
    header("Authorization Granted");

    console.log(`${colors.green}✅ Feedback authorization granted successfully!${colors.reset}`);
    console.log("");
    console.log(`${colors.cyan}Authorization Details:${colors.reset}`);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log(`  Agent:          ${colors.yellow}${params.agent}${colors.reset}`);
    console.log(`  Authorized:     ${colors.yellow}${params.client}${colors.reset}`);
    console.log(`  Quota:          ${colors.yellow}${params.indexLimit}${colors.reset} feedbacks`);
    console.log(`  Expiry:         ${colors.yellow}${new Date(expiryTimestamp * 1000).toISOString()}${colors.reset}`);
    console.log(`  Transaction:    ${colors.yellow}${committedTx.hash}${colors.reset}`);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("");

    console.log(`${colors.cyan}Next Steps:${colors.reset}`);
    console.log(`  1. Client can now issue reputation: tsx issue_reputation.ts --agent ${params.agent}`);
    console.log("");

    console.log(`${colors.cyan}Explorer URL:${colors.reset}`);
    console.log(`  https://explorer.aptoslabs.com/txn/${committedTx.hash}?network=${params.network}`);
    console.log("");

    success("Feedback authorization complete! 🎉");

  } catch (err: any) {
    error("Failed to grant feedback authorization");
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
