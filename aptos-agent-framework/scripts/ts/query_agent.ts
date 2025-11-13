#!/usr/bin/env tsx
/**
 * AAF Query Agent Script
 * Query agent information from blockchain
 *
 * Usage:
 *   tsx query_agent.ts --agent <AGENT_ADDR>
 *   tsx query_agent.ts --agent 0x123... --check-auth <CLIENT_ADDR>
 *   NETWORK=testnet tsx query_agent.ts --agent 0x123...
 */

import { initAAF, header, success, error, info, warning, colors, viewFunction } from "./utils.js";

// ============================================================================
// Parse Arguments
// ============================================================================

function parseArgs() {
  const args = process.argv.slice(2);
  const params: {
    agent?: string;
    checkAuth?: string;
    network?: string;
    profile?: string;
  } = {};

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--agent":
        params.agent = args[++i];
        break;
      case "--check-auth":
        params.checkAuth = args[++i];
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
AAF Query Agent Script

Usage:
  tsx query_agent.ts [options]

Options:
  --agent ADDR          Agent object address (required)
  --check-auth ADDR     Check if address has valid feedback authorization (optional)
  --network NET         Network (devnet/testnet/mainnet, default: devnet)
  --profile NAME        Aptos profile (default: default)
  --help, -h            Show this help

Environment Variables:
  NETWORK               Network to use
  APTOS_PROFILE         Aptos profile to use

Examples:
  tsx query_agent.ts --agent 0x123...
  tsx query_agent.ts --agent 0x123... --check-auth 0x456...
  NETWORK=testnet tsx query_agent.ts --agent 0x123...
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
    info("Usage: tsx query_agent.ts --agent <AGENT_ADDR>");
    process.exit(1);
  }

  // Initialize AAF
  const { aptos, account, moduleAddress } = initAAF(params.network!, params.profile!);

  // ============================================================================
  // Query Agent Info
  // ============================================================================
  header("Querying Agent Information");

  info(`Agent Address: ${params.agent}`);

  try {
    // Call get_agent_info view function
    info("Calling view function: get_agent_info");
    const agentInfo = await viewFunction(
      aptos,
      moduleAddress,
      "agent",
      "get_agent_info",
      [params.agent]
    );

    if (!agentInfo || agentInfo.length < 3) {
      error("Failed to get agent information");
      warning("Agent may not exist at this address");
      process.exit(1);
    }

    const [owner, metadataUri, domain] = agentInfo;

    // ============================================================================
    // Display Agent Info
    // ============================================================================
    header("Agent Information");

    console.log(`${colors.cyan}Agent Details:${colors.reset}`);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log(`  ${colors.cyan}Agent Address:${colors.reset}  ${colors.yellow}${params.agent}${colors.reset}`);
    console.log(`  ${colors.cyan}Owner:${colors.reset}          ${colors.yellow}${owner}${colors.reset}`);
    console.log(`  ${colors.cyan}Metadata URI:${colors.reset}   ${colors.yellow}${metadataUri}${colors.reset}`);

    // Handle Option<String> domain
    if (domain && domain.vec && domain.vec.length > 0) {
      console.log(`  ${colors.cyan}Domain:${colors.reset}         ${colors.yellow}${domain.vec[0]}${colors.reset}`);
    } else {
      console.log(`  ${colors.cyan}Domain:${colors.reset}         ${colors.yellow}None${colors.reset}`);
    }
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("");

    // ============================================================================
    // Check Feedback Authorization (Optional)
    // ============================================================================
    if (params.checkAuth) {
      header("Checking Feedback Authorization");

      info(`Checking authorization for: ${params.checkAuth}`);

      try {
        info("Calling view function: has_valid_feedback_auth");
        const hasAuth = await viewFunction(
          aptos,
          moduleAddress,
          "agent",
          "has_valid_feedback_auth",
          [params.agent, params.checkAuth]
        );

        console.log(`${colors.cyan}Authorization Status:${colors.reset}`);
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        console.log(`  ${colors.cyan}Client:${colors.reset}         ${colors.yellow}${params.checkAuth}${colors.reset}`);

        if (hasAuth && hasAuth[0] === true) {
          console.log(`  ${colors.cyan}Authorized:${colors.reset}     ${colors.green}✅ Yes${colors.reset}`);
          console.log("");
          success("Client has valid feedback authorization!");
        } else {
          console.log(`  ${colors.cyan}Authorized:${colors.reset}     ${colors.red}❌ No${colors.reset}`);
          console.log("");
          warning("Client does not have valid feedback authorization");
          console.log(`${colors.cyan}To grant authorization:${colors.reset}`);
          console.log(`  tsx grant_feedback_auth.ts --agent ${params.agent} --client ${params.checkAuth} --limit 10 --days 30`);
        }
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        console.log("");
      } catch (err: any) {
        error("Failed to check authorization");
        console.error(err);
      }
    }

    // ============================================================================
    // Display Next Steps
    // ============================================================================
    console.log(`${colors.cyan}Available Actions:${colors.reset}`);
    console.log(`  1. Grant feedback auth:     tsx grant_feedback_auth.ts --agent ${params.agent} --client <ADDR> --limit <NUM> --days <DAYS>`);
    console.log(`  2. Issue reputation:        tsx issue_reputation.ts --agent ${params.agent} --score <0-100> --file-uri <URI>`);
    console.log(`  3. Update agent:            tsx update_agent.ts --agent ${params.agent} --metadata-uri <URI>`);
    console.log("");

    console.log(`${colors.cyan}Explorer URL:${colors.reset}`);
    console.log(`  https://explorer.aptoslabs.com/account/${params.agent}?network=${params.network}`);
    console.log("");

    success("Query complete! 🎉");

  } catch (err: any) {
    error("Failed to query agent information");
    console.error(err);

    if (err.message && err.message.includes("Resource not found")) {
      warning("Agent does not exist at this address");
      info("Make sure you're using the correct agent address and network");
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
