#!/bin/bash

# Balance Check Script for EVM E2E Tests
# Displays final balances for Hub (Chain 1) and Connected EVM (Chain 3)

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"

# Setup project root
setup_project_root

# Get test tokens addresses
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1" 2>/dev/null) || true
source "$PROJECT_ROOT/.tmp/chain-info.env" 2>/dev/null || true
USDXYZ_ADDRESS="$USDXYZ_EVM_ADDRESS"

if [ -z "$TEST_TOKENS_CHAIN1" ]; then
    echo "⚠️  Warning: test-tokens-chain1 profile not found, skipping USDxyz balances"
    display_balances_hub
else
    display_balances_hub "0x$TEST_TOKENS_CHAIN1"
fi

if [ -z "$USDXYZ_ADDRESS" ]; then
    echo "⚠️  Warning: USDXYZ_EVM_ADDRESS not found, skipping USDxyz balances"
    display_balances_connected_evm
else
    display_balances_connected_evm "$USDXYZ_ADDRESS"
fi

