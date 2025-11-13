/**
 * AAF TypeScript SDK Utilities
 * Common functions for interacting with deployed AAF modules
 */

import { Aptos, AptosConfig, Network, Account, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import { readFileSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import dotenv from "dotenv";

// Get script directory for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SCRIPTS_DIR = resolve(__dirname, "..");
const PROJECT_DIR = resolve(SCRIPTS_DIR, "..");

// Load .env file - try both locations
const envPaths = [
  resolve(SCRIPTS_DIR, ".env"),
  resolve(process.cwd(), ".env"),
];

for (const envPath of envPaths) {
  if (existsSync(envPath)) {
    dotenv.config({ path: envPath });
    break;
  }
}

// ============================================================================
// Types
// ============================================================================

export interface DeploymentInfo {
  network: string;
  profile: string;
  account_address: string;
  transaction_hash: string;
  deployment_time: string;
  deployment_timestamp: number;
  modules: {
    agent: string;
    agent_reputation: string;
    agent_validation: string;
  };
  version: string;
  aptos_cli_version: string;
}

export interface AAFConfig {
  aptos: Aptos;
  account: Account;
  moduleAddress: string;
  deployment: DeploymentInfo;
}

// ============================================================================
// Color Output
// ============================================================================

export const colors = {
  reset: "\x1b[0m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
  magenta: "\x1b[35m",
};

export function success(msg: string): void {
  console.log(`${colors.green}✅ ${msg}${colors.reset}`);
}

export function error(msg: string): void {
  console.log(`${colors.red}❌ ${msg}${colors.reset}`);
}

export function info(msg: string): void {
  console.log(`${colors.cyan}ℹ️  ${msg}${colors.reset}`);
}

export function warning(msg: string): void {
  console.log(`${colors.yellow}⚠️  ${msg}${colors.reset}`);
}

export function header(msg: string): void {
  console.log("");
  console.log(`${colors.blue}╔══════════════════════════════════════════════════════════════╗${colors.reset}`);
  console.log(`${colors.blue}║${colors.reset}  ${colors.magenta}${msg}${colors.reset}`);
  console.log(`${colors.blue}╚══════════════════════════════════════════════════════════════╝${colors.reset}`);
}

// ============================================================================
// Configuration Loading
// ============================================================================

/**
 * Load deployment info from JSON file
 */
export function loadDeployment(network: string = "devnet"): DeploymentInfo {
  const deploymentFile = resolve(PROJECT_DIR, `deployments/${network}_latest.json`);

  if (!existsSync(deploymentFile)) {
    error(`Deployment file not found: ${deploymentFile}`);
    error(`Please deploy to ${network} first using: ./scripts/deploy_${network}.sh`);
    process.exit(1);
  }

  const deployment = JSON.parse(readFileSync(deploymentFile, "utf-8")) as DeploymentInfo;
  return deployment;
}

/**
 * Load account from private key
 * Reads from env var APTOS_PRIVATE_KEY or .aptos/config.yaml
 */
export function loadAccount(profile: string = "default"): Account {
  // Try environment variable first
  if (process.env.APTOS_PRIVATE_KEY) {
    let privateKeyHex = process.env.APTOS_PRIVATE_KEY.trim();

    // Handle JSON format (e.g., from `aptos config show-private-key`)
    if (privateKeyHex.startsWith('{')) {
      try {
        const jsonData = JSON.parse(privateKeyHex);
        // Try multiple possible JSON structures
        privateKeyHex =
          jsonData.Result?.private_key ||
          jsonData.Result?.PrivateKey ||
          jsonData.Result || // Sometimes it's just "Result": "ed25519-priv-0x..."
          jsonData.private_key ||
          jsonData.PrivateKey ||
          null;

        if (!privateKeyHex) {
          error("Could not find private key in JSON structure");
          error("JSON structure: " + JSON.stringify(jsonData, null, 2));
          error("Please set APTOS_PRIVATE_KEY in .env file:");
          error("  APTOS_PRIVATE_KEY=0x...");
          process.exit(1);
        }
      } catch (e) {
        error("Failed to parse APTOS_PRIVATE_KEY as JSON");
        throw e;
      }
    }

    // Remove ed25519-priv- prefix if present
    privateKeyHex = privateKeyHex.replace(/^ed25519-priv-/, "");

    // Remove 0x prefix if present
    privateKeyHex = privateKeyHex.replace(/^0x/, "");

    try {
      const privateKey = new Ed25519PrivateKey(privateKeyHex);
      return Account.fromPrivateKey({ privateKey });
    } catch (e: any) {
      error(`Failed to load private key: ${e.message}`);
      error(`Private key format should be: ed25519-priv-0x... or 0x...`);
      error(`Current value: ${privateKeyHex.substring(0, 20)}...`);
      process.exit(1);
    }
  }

  // If no env var, show helpful error message
  error("No private key found!");
  error("");
  error("Option 1: Create .env file in scripts/ directory:");
  error(`  cd ${SCRIPTS_DIR}`);
  error("  cp .env.example .env");
  error("  # Edit .env and add your private key");
  error("");
  error("Option 2: Set environment variable:");
  error("  export APTOS_PRIVATE_KEY=ed25519-priv-0x...");
  error("");
  error("Get your private key:");
  error("  cd .. && aptos config show-private-key --profile default");
  process.exit(1);

  // Try reading from .aptos/config.yaml
  const configPath = resolve(process.env.HOME || "~", ".aptos/config.yaml");

  if (!existsSync(configPath)) {
    error("No private key found!");
    error("Set APTOS_PRIVATE_KEY environment variable or configure Aptos CLI");
    info("Example: export APTOS_PRIVATE_KEY=0x...");
    process.exit(1);
  }

  // Parse YAML config file (simple parsing for private_key field)
  const configContent = readFileSync(configPath, "utf-8");
  const profileSection = configContent.split(`${profile}:`)[1];

  if (!profileSection) {
    error(`Profile '${profile}' not found in ${configPath}`);
    process.exit(1);
  }

  const privateKeyMatch = profileSection.match(/private_key:\s*["']?([0-9a-fx]+)["']?/i);

  if (!privateKeyMatch) {
    error(`Private key not found for profile '${profile}'`);
    info("You can export it: export APTOS_PRIVATE_KEY=$(aptos config show-private-key --profile default)");
    process.exit(1);
  }

  const privateKeyHex = privateKeyMatch[1].replace(/^0x/, "");
  const privateKey = new Ed25519PrivateKey(privateKeyHex);

  return Account.fromPrivateKey({ privateKey });
}

/**
 * Initialize AAF configuration
 */
export function initAAF(network: string = "devnet", profile: string = "default"): AAFConfig {
  header(`AAF SDK Initialization - ${new Date().toISOString()}`);

  info(`Network: ${network}`);
  info(`Profile: ${profile}`);

  // Load deployment info
  const deployment = loadDeployment(network);
  success(`Loaded deployment info (version ${deployment.version})`);

  // Initialize Aptos client
  const networkEnum = network === "mainnet" ? Network.MAINNET
                    : network === "testnet" ? Network.TESTNET
                    : Network.DEVNET;

  const config = new AptosConfig({ network: networkEnum });
  const aptos = new Aptos(config);
  success(`Connected to ${network}`);

  // Load account
  const account = loadAccount(profile);
  info(`Account: ${account.accountAddress.toString()}`);

  const moduleAddress = deployment.account_address;
  info(`Module Address: ${moduleAddress}`);

  return {
    aptos,
    account,
    moduleAddress,
    deployment,
  };
}

// ============================================================================
// Transaction Helpers
// ============================================================================

/**
 * Wait for transaction and return result
 */
export async function waitForTransaction(aptos: Aptos, txHash: string) {
  info(`Waiting for transaction: ${txHash}`);
  const result = await aptos.waitForTransaction({ transactionHash: txHash });
  return result;
}

/**
 * Extract object address from transaction events
 */
export function extractObjectAddress(events: any[], eventType: string): string | null {
  const event = events.find((e) => e.type.includes(eventType));
  if (!event) return null;

  // Try common field names
  const data = event.data;
  return data.agent || data.nft || data.object || data.address || null;
}

// ============================================================================
// View Functions
// ============================================================================

/**
 * Call a view function
 */
export async function viewFunction(
  aptos: Aptos,
  moduleAddress: string,
  moduleName: string,
  functionName: string,
  args: any[] = []
): Promise<any> {
  const result = await aptos.view({
    payload: {
      function: `${moduleAddress}::${moduleName}::${functionName}`,
      typeArguments: [],
      functionArguments: args,
    },
  });
  return result;
}
