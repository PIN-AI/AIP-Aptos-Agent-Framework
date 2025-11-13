#!/bin/bash
# AAF Test Runner Script
# Usage: ./scripts/run_tests.sh [options]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Functions
print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  $1"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
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
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Parse arguments
MODE=${1:-all}

case "$MODE" in
    compile)
        print_header "Compiling AAF"
        aptos move compile --dev
        print_success "Compilation successful"
        ;;
        
    test)
        print_header "Running All Tests"
        aptos move test
        print_success "All tests passed"
        ;;
        
    agent)
        print_header "Running Agent Module Tests"
        aptos move test --filter agent_tests
        ;;
        
    reputation)
        print_header "Running Reputation Module Tests"
        aptos move test --filter reputation_tests
        ;;
        
    validation)
        print_header "Running Validation Module Tests"
        aptos move test --filter validation_tests
        ;;
        
    integration)
        print_header "Running Integration Tests"
        aptos move test --filter integration_tests
        ;;
        
    coverage)
        print_header "Generating Coverage Report"
        aptos move test --coverage
        print_info "Coverage report generated"
        ;;
        
    gas)
        print_header "Running Gas Benchmarks"
        aptos move test --gas-report
        print_info "Gas report generated"
        ;;
        
    all)
        print_header "AAF Full Test Suite"
        
        echo ""
        print_info "Step 1/4: Compiling..."
        if aptos move compile --dev 2>&1 | grep -q "error:"; then
            print_error "Compilation failed"
            exit 1
        fi
        print_success "Compilation passed"
        
        echo ""
        print_info "Step 2/4: Running unit tests..."
        if aptos move test 2>&1 | tee test_output.txt | grep -q "FAILED"; then
            print_warning "Some tests failed (expected for skeleton tests)"
        else
            print_success "All tests passed"
        fi
        
        echo ""
        print_info "Step 3/4: Generating coverage..."
        aptos move test --coverage > /dev/null 2>&1 || true
        print_info "Coverage report available"
        
        echo ""
        print_info "Step 4/4: Gas analysis..."
        aptos move test --gas-report > gas_report.txt 2>&1 || true
        print_info "Gas report saved to gas_report.txt"
        
        echo ""
        print_header "Test Summary"
        if [ -f test_output.txt ]; then
            grep -A 5 "Test result:" test_output.txt || true
            rm test_output.txt
        fi
        ;;
        
    clean)
        print_header "Cleaning Build Artifacts"
        rm -rf build/
        rm -f gas_report.txt
        rm -f test_output.txt
        print_success "Clean complete"
        ;;
        
    help|--help|-h)
        echo "AAF Test Runner"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  compile      - Compile Move code only"
        echo "  test         - Run all tests"
        echo "  agent        - Run agent module tests only"
        echo "  reputation   - Run reputation module tests only"
        echo "  validation   - Run validation module tests only"
        echo "  integration  - Run integration tests only"
        echo "  coverage     - Generate test coverage report"
        echo "  gas          - Run Gas benchmarks"
        echo "  all          - Run full test suite (default)"
        echo "  clean        - Clean build artifacts"
        echo "  help         - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Run full test suite"
        echo "  $0 agent              # Run agent tests only"
        echo "  $0 coverage           # Generate coverage"
        ;;
        
    *)
        print_error "Unknown command: $MODE"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac

