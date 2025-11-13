#!/usr/bin/env tsx
/**
 * AAF Issue Reputation Script
 * Issue reputation NFT to an agent
 *
 * Usage:
 *   tsx issue_reputation.ts --agent <AGENT_ADDR> --score <0-100> --file-uri <URI> [--gated]
 *   tsx issue_reputation.ts --agent 0x123... --score 95 --file-uri "ipfs://QmHash" --context "Task completed successfully"
 *   NETWORK=testnet tsx issue_reputation.ts --agent 0x123... --score 80 --file-uri "https://example.com/feedback.json" --gated
 */

import { initAAF, header, success, error, info, warning, colors, waitForTransaction, extractObjectAddress } from "./utils.js";
import crypto from "crypto";

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Generate keccak256 hash from string (matches Move's aptos_hash::keccak256)
 */
function keccak256Hash(input: string): Uint8Array {
  // Use SHA3-256 (keccak256) - Node.js crypto supports it
  const hash = crypto.createHash('sha3-256');
  hash.update(input);
  return new Uint8Array(hash.digest());
}

/**
 * Convert Uint8Array to hex string with 0x prefix
 */
function toHexString(bytes: Uint8Array): string {
  return '0x' + Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Parse hex string to Uint8Array
 */
function fromHexString(hex: string): Uint8Array {
  const cleanHex = hex.replace(/^0x/, '');
  const bytes = new Uint8Array(cleanHex.length / 2);
  for (let i = 0; i < cleanHex.length; i += 2) {
    bytes[i / 2] = parseInt(cleanHex.substr(i, 2), 16);
  }
  return bytes;
}

// ============================================================================
// Parse Arguments
// ============================================================================

function parseArgs() {
  const args = process.argv.slice(2);
  const params: {
    agent?: string;
    score?: number;
    context?: string;
    contextHash?: string;
    fileUri?: string;
    fileHash?: string;
    gated?: boolean;
    network?: string;
    profile?: string;
  } = {};

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--agent":
        params.agent = args[++i];
        break;
      case "--score":
        params.score = parseInt(args[++i]);
        break;
      case "--context":
        params.context = args[++i];
        break;
      case "--context-hash":
        params.contextHash = args[++i];
        break;
      case "--file-uri":
        params.fileUri = args[++i];
        break;
      case "--file-hash":
        params.fileHash = args[++i];
        break;
      case "--gated":
        params.gated = true;
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
AAF Issue Reputation Script

Usage:
  tsx issue_reputation.ts [options]

Options:
  --agent ADDR          Agent object address (required)
  --score NUM           Reputation score 0-100 (required)
  --file-uri URI        Off-chain feedback file URI (required)
  --context TEXT        Task context (auto-hashed, optional)
  --context-hash HEX    Context hash (0x..., optional, overrides --context)
  --file-hash HEX       File content hash (0x..., optional, auto-hashed from URI if not provided)
  --gated               Require feedback authorization (default: false)
  --network NET         Network (devnet/testnet/mainnet, default: devnet)
  --profile NAME        Aptos profile (default: default)
  --help, -h            Show this help

Note:
- If --gated is set, you must have feedback authorization from agent owner
- Either provide --context (auto-hashed) or --context-hash directly
- If --file-hash is not provided, it will be auto-generated from --file-uri

Environment Variables:
  NETWORK               Network to use
  APTOS_PROFILE         Aptos profile to use
  APTOS_PRIVATE_KEY     Private key (overrides profile)

Examples:
  tsx issue_reputation.ts --agent 0x123... --score 95 --file-uri "ipfs://QmHash" --context "Task completed"
  tsx issue_reputation.ts --agent 0x123... --score 80 --file-uri "https://example.com/feedback.json" --gated
  NETWORK=testnet tsx issue_reputation.ts --agent 0x123... --score 100 --file-uri "ipfs://QmABC" --context-hash 0xabc...
        `);
        process.exit(0);
    }
  }

  // Use environment variables as fallback
  params.network = params.network || process.env.NETWORK || "devnet";
  params.profile = params.profile || process.env.APTOS_PROFILE || "default";
  params.gated = params.gated || false;

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
    info("Usage: tsx issue_reputation.ts --agent <AGENT_ADDR> --score <0-100> --file-uri <URI>");
    process.exit(1);
  }

  if (params.score === undefined) {
    error("Missing required parameter: --score");
    info("Usage: tsx issue_reputation.ts --agent <AGENT_ADDR> --score <0-100> --file-uri <URI>");
    process.exit(1);
  }

  if (params.score < 0 || params.score > 100) {
    error("Score must be between 0 and 100");
    process.exit(1);
  }

  if (!params.fileUri) {
    error("Missing required parameter: --file-uri");
    info("Usage: tsx issue_reputation.ts --agent <AGENT_ADDR> --score <0-100> --file-uri <URI>");
    process.exit(1);
  }

  // Calculate context hash
  let contextHash: Uint8Array;
  if (params.contextHash) {
    contextHash = fromHexString(params.contextHash);
  } else if (params.context) {
    contextHash = keccak256Hash(params.context);
    info(`Context hash (auto-generated): ${toHexString(contextHash)}`);
  } else {
    // Use empty hash if no context provided
    contextHash = new Uint8Array(32);
    warning("No context provided, using zero hash");
  }

  // Calculate file hash
  let fileHash: Uint8Array;
  if (params.fileHash) {
    fileHash = fromHexString(params.fileHash);
  } else {
    fileHash = keccak256Hash(params.fileUri);
    info(`File hash (auto-generated): ${toHexString(fileHash)}`);
  }

  // Initialize AAF
  const { aptos, account, moduleAddress } = initAAF(params.network!, params.profile!);

  // ============================================================================
  // Display Parameters
  // ============================================================================
  header("Reputation Parameters");

  console.log(`${colors.cyan}Agent:${colors.reset}         ${colors.yellow}${params.agent}${colors.reset}`);
  console.log(`${colors.cyan}Score:${colors.reset}         ${colors.yellow}${params.score}${colors.reset}/100`);
  console.log(`${colors.cyan}File URI:${colors.reset}      ${colors.yellow}${params.fileUri}${colors.reset}`);
  console.log(`${colors.cyan}File Hash:${colors.reset}     ${colors.yellow}${toHexString(fileHash)}${colors.reset}`);
  if (params.context) {
    console.log(`${colors.cyan}Context:${colors.reset}       ${colors.yellow}${params.context}${colors.reset}`);
  }
  console.log(`${colors.cyan}Context Hash:${colors.reset}  ${colors.yellow}${toHexString(contextHash)}${colors.reset}`);
  console.log(`${colors.cyan}Gated:${colors.reset}         ${colors.yellow}${params.gated}${colors.reset}`);

  // ============================================================================
  // Build Transaction
  // ============================================================================
  header("Issuing Reputation");

  info(`Calling ${moduleAddress}::agent_reputation::issue_reputation`);

  try {
    info("Building transaction...");

    // Step 1: Build transaction
    const transaction = await aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${moduleAddress}::agent_reputation::issue_reputation`,
        functionArguments: [
          params.agent,
          params.score,
          Array.from(contextHash),
          params.fileUri,
          Array.from(fileHash),
          params.gated
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

    success("Reputation issued successfully!");

    // Extract reputation NFT address from events
    const events = (executedTx as any).events || [];
    const reputationAddress = extractObjectAddress(events, "ReputationIssued");

    // ============================================================================
    // Display Results
    // ============================================================================
    header("Reputation Issued");

    console.log(`${colors.green}✅ Reputation NFT issued successfully!${colors.reset}`);
    console.log("");
    console.log(`${colors.cyan}Reputation Details:${colors.reset}`);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log(`  Issuer:         ${colors.yellow}${account.accountAddress.toString()}${colors.reset}`);
    console.log(`  Agent:          ${colors.yellow}${params.agent}${colors.reset}`);
    console.log(`  Score:          ${colors.yellow}${params.score}${colors.reset}/100`);
    console.log(`  File URI:       ${colors.yellow}${params.fileUri}${colors.reset}`);
    if (reputationAddress) {
      console.log(`  NFT Object:     ${colors.yellow}${reputationAddress}${colors.reset}`);
    }
    console.log(`  Transaction:    ${colors.yellow}${committedTx.hash}${colors.reset}`);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("");

    console.log(`${colors.cyan}Next Steps:${colors.reset}`);
    console.log(`  1. Agent owner can respond: tsx append_response.ts --reputation ${reputationAddress || "REP_ADDR"}`);
    console.log(`  2. Query reputation: tsx query_reputation.ts --reputation ${reputationAddress || "REP_ADDR"}`);
    console.log("");

    console.log(`${colors.cyan}Explorer URL:${colors.reset}`);
    console.log(`  https://explorer.aptoslabs.com/txn/${committedTx.hash}?network=${params.network}`);
    console.log("");

    success("Reputation issuance complete! 🎉");

    // Return reputation address for bash script to capture
    if (reputationAddress) {
      console.log(`\nREPUTATION_ADDRESS=${reputationAddress}`);
    }

  } catch (err: any) {
    error("Failed to issue reputation");
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
