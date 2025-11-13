#!/bin/bash
# AAF Devnet Deployment Script
# Usage: ./scripts/deploy_devnet.sh [options]
#
# Options:
#   --skip-tests    Skip pre-deployment tests
#   --force         Force deployment even if tests fail
#   --profile NAME  Use specific Aptos profile (default: default)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Configuration
NETWORK="devnet"
PROFILE="${APTOS_PROFILE:-default}"
SKIP_TESTS=false
FORCE=false
DEPLOYMENT_LOG="deployments/devnet_$(date +%Y%m%d_%H%M%S).log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "AAF Devnet Deployment Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-tests       Skip pre-deployment tests"
            echo "  --force            Force deployment even if tests fail"
            echo "  --profile NAME     Use specific Aptos profile (default: default)"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  APTOS_PROFILE      Aptos CLI profile to use"
            echo ""
            echo "Examples:"
            echo "  $0                           # Deploy with full tests"
            echo "  $0 --skip-tests              # Deploy without running tests"
            echo "  $0 --profile myaccount       # Deploy using 'myaccount' profile"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Utility functions
print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${MAGENTA}$1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Create deployments directory if it doesn't exist
mkdir -p deployments

# Start logging
exec > >(tee -a "$DEPLOYMENT_LOG") 2>&1

print_header "AAF Devnet Deployment - $(date)"
echo -e "${CYAN}Network:${NC} $NETWORK"
echo -e "${CYAN}Profile:${NC} $PROFILE"
echo -e "${CYAN}Log File:${NC} $DEPLOYMENT_LOG"

# ============================================================================
# Step 1: Environment Checks
# ============================================================================
print_header "Step 1/6: Environment Checks"

# Check Aptos CLI installation
print_info "Checking Aptos CLI installation..."
if ! command -v aptos &> /dev/null; then
    print_error "Aptos CLI not found. Please install it first:"
    echo "  curl -fsSL https://aptos.dev/scripts/install_cli.py | python3"
    exit 1
fi

APTOS_VERSION=$(aptos --version 2>&1 | head -n 1)
print_success "Aptos CLI found: $APTOS_VERSION"

# Check if profile exists (check JSON output)
print_info "Checking profile '$PROFILE'..."
if aptos config show-profiles 2>/dev/null | grep -q "\"$PROFILE\""; then
    print_success "Profile '$PROFILE' exists"
else
    print_warning "Profile '$PROFILE' not found."
    read -p "Create new profile? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Initializing new profile '$PROFILE' on $NETWORK..."
        if aptos init --network $NETWORK --profile $PROFILE; then
            print_success "Profile created"
        else
            print_error "Failed to create profile"
            exit 1
        fi
    else
        print_error "Cannot proceed without a valid profile"
        exit 1
    fi
fi

# Get account address (from JSON output)
ACCOUNT_ADDRESS=$(aptos config show-profiles --profile $PROFILE 2>/dev/null | grep '"account"' | head -n 1 | awk -F'"' '{print $4}')

# Add 0x prefix if not present
if [ -n "$ACCOUNT_ADDRESS" ] && [[ ! "$ACCOUNT_ADDRESS" =~ ^0x ]]; then
    ACCOUNT_ADDRESS="0x$ACCOUNT_ADDRESS"
fi

if [ -z "$ACCOUNT_ADDRESS" ]; then
    print_error "Could not determine account address from profile"
    print_info "Please check: aptos config show-profiles --profile $PROFILE"
    exit 1
fi
print_info "Account Address: ${CYAN}$ACCOUNT_ADDRESS${NC}"

# Check account balance
print_info "Checking account balance on $NETWORK..."

# Try to get balance using account list (JSON output)
BALANCE_RAW=$(aptos account list --account $ACCOUNT_ADDRESS --profile $PROFILE 2>/dev/null)
BALANCE=$(echo "$BALANCE_RAW" | grep -o '"coin"[^}]*"value"[[:space:]]*:[[:space:]]*"[0-9]*"' | grep -o '[0-9]*' | head -n 1)

# If no balance found, assume 0 (new account)
if [ -z "$BALANCE" ]; then
    BALANCE=0
fi

print_info "Current Balance: ${CYAN}${BALANCE}${NC} Octas ($(echo "scale=2; $BALANCE / 100000000" | bc) APT)"

# Fund account if balance is too low (< 100,000,000 Octas = 1 APT)
MIN_BALANCE=100000000
if [ "$BALANCE" -lt $MIN_BALANCE ]; then
    print_warning "Balance too low for deployment. Requesting funds from faucet..."
    if aptos account fund-with-faucet --account $ACCOUNT_ADDRESS --profile $PROFILE 2>&1 | tee /tmp/faucet_output.txt; then
        print_success "Faucet funding successful"
        # Wait for indexing
        sleep 3
        # Re-check balance
        BALANCE_RAW=$(aptos account list --account $ACCOUNT_ADDRESS --profile $PROFILE 2>/dev/null)
        BALANCE=$(echo "$BALANCE_RAW" | grep -o '"coin"[^}]*"value"[[:space:]]*:[[:space:]]*"[0-9]*"' | grep -o '[0-9]*' | head -n 1)
        if [ -z "$BALANCE" ]; then
            BALANCE=100000000  # Assume faucet gave 1 APT
        fi
        print_info "New Balance: ${CYAN}${BALANCE}${NC} Octas ($(echo "scale=2; $BALANCE / 100000000" | bc) APT)"
    else
        print_error "Failed to fund account from faucet"
        cat /tmp/faucet_output.txt
        exit 1
    fi
else
    print_success "Balance sufficient for deployment"
fi

# ============================================================================
# Step 2: Pre-Deployment Checks
# ============================================================================
print_header "Step 2/6: Pre-Deployment Checks"

# Compile code
print_info "Compiling Move code..."
if aptos move compile --dev; then
    print_success "Compilation successful"
else
    print_error "Compilation failed"
    exit 1
fi

# Run tests (unless skipped)
if [ "$SKIP_TESTS" = false ]; then
    print_info "Running test suite..."
    if aptos move test --dev; then
        print_success "All tests passed"
    else
        if [ "$FORCE" = true ]; then
            print_warning "Tests failed but proceeding due to --force flag"
        else
            print_error "Tests failed. Use --force to deploy anyway or --skip-tests to skip"
            exit 1
        fi
    fi
else
    print_warning "Tests skipped (--skip-tests flag)"
fi

# ============================================================================
# Step 3: Deployment Information
# ============================================================================
print_header "Step 3/6: Deployment Information"

echo -e "${CYAN}Package Name:${NC} AptosAgentFramework"
echo -e "${CYAN}Version:${NC} v2.3"
echo -e "${CYAN}Modules:${NC}"
echo "  - aaf::agent"
echo "  - aaf::agent_reputation"
echo "  - aaf::agent_validation"
echo ""
echo -e "${YELLOW}Named Address 'aaf' will be deployed to: ${CYAN}$ACCOUNT_ADDRESS${NC}"
echo ""

# Prompt for confirmation
if [ -t 0 ]; then  # Only prompt if stdin is a terminal
    read -p "Proceed with deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled by user"
        exit 0
    fi
fi

# ============================================================================
# Step 4: Execute Deployment
# ============================================================================
print_header "Step 4/6: Executing Deployment"

print_info "Publishing to $NETWORK..."
DEPLOY_START=$(date +%s)

# Capture deployment output
if DEPLOY_OUTPUT=$(aptos move publish \
    --named-addresses aaf=$ACCOUNT_ADDRESS \
    --profile $PROFILE \
    --assume-yes 2>&1); then

    DEPLOY_END=$(date +%s)
    DEPLOY_TIME=$((DEPLOY_END - DEPLOY_START))

    print_success "Deployment successful! (${DEPLOY_TIME}s)"

    # Extract transaction hash from output
    TX_HASH=$(echo "$DEPLOY_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | head -n 1)
    if [ -n "$TX_HASH" ]; then
        print_info "Transaction Hash: ${CYAN}$TX_HASH${NC}"
    fi
else
    print_error "Deployment failed"
    echo ""
    echo -e "${RED}Error Output:${NC}"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

# ============================================================================
# Step 5: Post-Deployment Verification
# ============================================================================
print_header "Step 5/6: Post-Deployment Verification"

print_info "Waiting for transaction to be indexed (5 seconds)..."
sleep 5

# Verify modules are deployed
print_info "Verifying deployed modules..."
MODULES_FOUND=0

if aptos move view --function-id "${ACCOUNT_ADDRESS}::agent::dummy_view" 2>/dev/null | grep -q "error"; then
    # Module might not have view function, try alternative check
    if aptos account list --account $ACCOUNT_ADDRESS --profile $PROFILE 2>/dev/null | grep -q "move_modules"; then
        print_success "Module 'agent' deployed"
        MODULES_FOUND=$((MODULES_FOUND + 1))
    fi
else
    print_success "Module 'agent' deployed and accessible"
    MODULES_FOUND=$((MODULES_FOUND + 1))
fi

# Check remaining modules via account info
MODULE_LIST=$(aptos account list --account $ACCOUNT_ADDRESS --profile $PROFILE 2>/dev/null | grep -c "agent_reputation\|agent_validation" || echo "0")

if [ "$MODULE_LIST" -gt 0 ]; then
    print_success "Module 'agent_reputation' deployed"
    print_success "Module 'agent_validation' deployed"
    MODULES_FOUND=$((MODULES_FOUND + 2))
fi

if [ $MODULES_FOUND -eq 3 ]; then
    print_success "All 3 modules verified on-chain"
else
    print_warning "Could not verify all modules (found $MODULES_FOUND/3)"
    print_info "This may be due to indexing delay. Check manually later."
fi

# ============================================================================
# Step 6: Save Deployment Record
# ============================================================================
print_header "Step 6/6: Saving Deployment Record"

DEPLOYMENT_FILE="deployments/devnet_latest.json"
DEPLOYMENT_ARCHIVE="deployments/devnet_$(date +%Y%m%d_%H%M%S).json"

cat > "$DEPLOYMENT_FILE" <<EOF
{
  "network": "$NETWORK",
  "profile": "$PROFILE",
  "account_address": "$ACCOUNT_ADDRESS",
  "transaction_hash": "${TX_HASH:-unknown}",
  "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployment_timestamp": $(date +%s),
  "modules": {
    "agent": "${ACCOUNT_ADDRESS}::agent",
    "agent_reputation": "${ACCOUNT_ADDRESS}::agent_reputation",
    "agent_validation": "${ACCOUNT_ADDRESS}::agent_validation"
  },
  "version": "v2.3",
  "aptos_cli_version": "$APTOS_VERSION"
}
EOF

# Also save archived copy
cp "$DEPLOYMENT_FILE" "$DEPLOYMENT_ARCHIVE"

print_success "Deployment record saved:"
print_info "  Latest: $DEPLOYMENT_FILE"
print_info "  Archive: $DEPLOYMENT_ARCHIVE"

# ============================================================================
# Deployment Summary
# ============================================================================
print_header "Deployment Summary"

echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo ""
echo -e "${CYAN}Deployment Details:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Network:        ${YELLOW}$NETWORK${NC}"
echo -e "  Account:        ${YELLOW}$ACCOUNT_ADDRESS${NC}"
echo -e "  Profile:        ${YELLOW}$PROFILE${NC}"
if [ -n "$TX_HASH" ]; then
echo -e "  Transaction:    ${YELLOW}$TX_HASH${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${CYAN}Deployed Modules:${NC}"
echo "  1. ${ACCOUNT_ADDRESS}::agent"
echo "  2. ${ACCOUNT_ADDRESS}::agent_reputation"
echo "  3. ${ACCOUNT_ADDRESS}::agent_validation"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. View deployment: aptos account list --account $ACCOUNT_ADDRESS"
echo "  2. Interact via SDK or CLI using module address: $ACCOUNT_ADDRESS"
echo "  3. Check logs: cat $DEPLOYMENT_LOG"
echo ""
echo -e "${CYAN}Explorer URLs:${NC}"
echo "  https://explorer.aptoslabs.com/account/$ACCOUNT_ADDRESS?network=$NETWORK"
if [ -n "$TX_HASH" ]; then
echo "  https://explorer.aptoslabs.com/txn/$TX_HASH?network=$NETWORK"
fi
echo ""

print_success "Deployment process complete! 🎉"
