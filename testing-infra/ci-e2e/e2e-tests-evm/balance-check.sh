#!/bin/bash

# Balance Check Script for EVM E2E Tests
# Displays and validates final balances for Hub (Chain 1, USDhub) and Connected EVM (Chain 3, USDcon)
# Usage: balance-check.sh <solver_chain_hub> <requester_chain_hub> <solver_chain_connected> <requester_chain_connected>
#   - Pass -1 for any parameter to skip that check
#   - Values are in 10e-6.USDhub / 10e-6.USDcon units (e.g., 2000000 = 2 USDhub or 2 USDcon)

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root
setup_project_root

# Parse expected balance parameters
SOLVER_CHAIN_HUB_EXPECTED="${1:-}"
REQUESTER_CHAIN_HUB_EXPECTED="${2:-}"
SOLVER_CHAIN_CONNECTED_EXPECTED="${3:-}"
REQUESTER_CHAIN_CONNECTED_EXPECTED="${4:-}"

# Get test tokens addresses
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1" 2>/dev/null) || true
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true
USDCON_TOKEN_ADDRESS="$USDCON_EVM_ADDRESS"

# Display balances
if [ -z "$TEST_TOKENS_CHAIN1" ]; then
    echo "⚠️  Warning: test-tokens-chain1 profile not found, skipping USDhub balances"
    display_balances_hub
else
    display_balances_hub "0x$TEST_TOKENS_CHAIN1"
fi

if [ -z "$USDCON_TOKEN_ADDRESS" ]; then
    echo "⚠️  Warning: USDCON_EVM_ADDRESS not found, skipping USDcon balances"
    display_balances_connected_evm
else
    display_balances_connected_evm "$USDCON_TOKEN_ADDRESS"
fi

# Validate solver balance on Chain 1 (Hub)
if [ -n "$SOLVER_CHAIN_HUB_EXPECTED" ] && [ "$SOLVER_CHAIN_HUB_EXPECTED" != "-1" ] && [ -n "$TEST_TOKENS_CHAIN1" ]; then
    SOLVER_CHAIN_HUB_ADDRESS=$(get_profile_address "solver-chain1" 2>/dev/null || echo "")
    if [ -n "$SOLVER_CHAIN_HUB_ADDRESS" ]; then
        SOLVER_CHAIN_HUB_ACTUAL=$(get_usdxyz_balance "solver-chain1" "1" "0x$TEST_TOKENS_CHAIN1" 2>/dev/null || echo "0")
        
        if [ "$SOLVER_CHAIN_HUB_ACTUAL" != "$SOLVER_CHAIN_HUB_EXPECTED" ]; then
            log_and_echo "❌ ERROR: Solver balance mismatch on Chain 1 (Hub)!"
            log_and_echo "   Actual:   $SOLVER_CHAIN_HUB_ACTUAL 10e-6.USDhub"
            log_and_echo "   Expected: $SOLVER_CHAIN_HUB_EXPECTED 10e-6.USDhub"
            display_service_logs "Solver balance mismatch on Chain 1 (Hub)"
            exit 1
        fi
        log_and_echo "✅ Solver balance validated on Chain 1 (Hub): $SOLVER_CHAIN_HUB_ACTUAL 10e-6.USDhub"
    fi
fi

# Validate requester balance on Chain 1 (Hub)
if [ -n "$REQUESTER_CHAIN_HUB_EXPECTED" ] && [ "$REQUESTER_CHAIN_HUB_EXPECTED" != "-1" ] && [ -n "$TEST_TOKENS_CHAIN1" ]; then
    REQUESTER_CHAIN_HUB_ADDRESS=$(get_profile_address "requester-chain1" 2>/dev/null || echo "")
    if [ -n "$REQUESTER_CHAIN_HUB_ADDRESS" ]; then
        REQUESTER_CHAIN_HUB_ACTUAL=$(get_usdxyz_balance "requester-chain1" "1" "0x$TEST_TOKENS_CHAIN1" 2>/dev/null || echo "0")
        
        if [ "$REQUESTER_CHAIN_HUB_ACTUAL" != "$REQUESTER_CHAIN_HUB_EXPECTED" ]; then
            log_and_echo "❌ ERROR: Requester balance mismatch on Chain 1 (Hub)!"
            log_and_echo "   Actual:   $REQUESTER_CHAIN_HUB_ACTUAL 10e-6.USDhub"
            log_and_echo "   Expected: $REQUESTER_CHAIN_HUB_EXPECTED 10e-6.USDhub"
            display_service_logs "Requester balance mismatch on Chain 1 (Hub)"
            exit 1
        fi
        log_and_echo "✅ Requester balance validated on Chain 1 (Hub): $REQUESTER_CHAIN_HUB_ACTUAL 10e-6.USDhub"
    fi
fi

# Validate solver balance on Chain 3 (Connected EVM)
if [ -n "$SOLVER_CHAIN_CONNECTED_EXPECTED" ] && [ "$SOLVER_CHAIN_CONNECTED_EXPECTED" != "-1" ] && [ -n "$USDCON_TOKEN_ADDRESS" ]; then
    SOLVER_EVM_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1)
    
    if [ -n "$SOLVER_EVM_ADDRESS" ]; then
        SOLVER_CHAIN_CONNECTED_ACTUAL=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDCON_TOKEN_ADDRESS' ACCOUNT='$SOLVER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1 | grep -E '^[0-9]+$' | tail -1)
        
        if [ "$SOLVER_CHAIN_CONNECTED_ACTUAL" != "$SOLVER_CHAIN_CONNECTED_EXPECTED" ]; then
            log_and_echo "❌ ERROR: Solver balance mismatch on Chain 3 (Connected EVM)!"
            log_and_echo "   Actual:   $SOLVER_CHAIN_CONNECTED_ACTUAL 10e-6.USDcon"
            log_and_echo "   Expected: $SOLVER_CHAIN_CONNECTED_EXPECTED 10e-6.USDcon"
            display_service_logs "Solver balance mismatch on Chain 3 (Connected EVM)"
            exit 1
        fi
        log_and_echo "✅ Solver balance validated on Chain 3 (Connected EVM): $SOLVER_CHAIN_CONNECTED_ACTUAL 10e-6.USDcon"
    fi
fi

# Validate requester balance on Chain 3 (Connected EVM)
if [ -n "$REQUESTER_CHAIN_CONNECTED_EXPECTED" ] && [ "$REQUESTER_CHAIN_CONNECTED_EXPECTED" != "-1" ] && [ -n "$USDCON_TOKEN_ADDRESS" ]; then
    REQUESTER_EVM_ADDRESS=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-address.js --network localhost" 2>&1 | grep -E '^0x[a-fA-F0-9]{40}$' | head -1)
    
    if [ -n "$REQUESTER_EVM_ADDRESS" ]; then
        REQUESTER_CHAIN_CONNECTED_ACTUAL=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && TOKEN_ADDRESS='$USDCON_TOKEN_ADDRESS' ACCOUNT='$REQUESTER_EVM_ADDRESS' npx hardhat run scripts/get-token-balance.js --network localhost" 2>&1 | grep -E '^[0-9]+$' | tail -1)
        
        if [ "$REQUESTER_CHAIN_CONNECTED_ACTUAL" != "$REQUESTER_CHAIN_CONNECTED_EXPECTED" ]; then
            log_and_echo "❌ ERROR: Requester balance mismatch on Chain 3 (Connected EVM)!"
            log_and_echo "   Actual:   $REQUESTER_CHAIN_CONNECTED_ACTUAL 10e-6.USDcon"
            log_and_echo "   Expected: $REQUESTER_CHAIN_CONNECTED_EXPECTED 10e-6.USDcon"
            display_service_logs "Requester balance mismatch on Chain 3 (Connected EVM)"
            exit 1
        fi
        log_and_echo "✅ Requester balance validated on Chain 3 (Connected EVM): $REQUESTER_CHAIN_CONNECTED_ACTUAL 10e-6.USDcon"
    fi
fi

# Explicit success exit (prevents set -e issues from log_and_echo return code)
exit 0
