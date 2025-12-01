#!/bin/bash

# Balance Check Script for MVM E2E Tests
# Displays final balances for Hub (Chain 1) and Connected MVM (Chain 2)

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"

# Setup project root
setup_project_root

# Get test tokens addresses
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1" 2>/dev/null) || true
TEST_TOKENS_CHAIN2=$(get_profile_address "test-tokens-chain2" 2>/dev/null) || true

if [ -z "$TEST_TOKENS_CHAIN1" ]; then
    echo "⚠️  Warning: test-tokens-chain1 profile not found, skipping USDxyz balances"
    display_balances_hub
else
    display_balances_hub "0x$TEST_TOKENS_CHAIN1"
fi

if [ -z "$TEST_TOKENS_CHAIN2" ]; then
    echo "⚠️  Warning: test-tokens-chain2 profile not found, skipping USDxyz balances"
    display_balances_connected_mvm
else
    display_balances_connected_mvm "0x$TEST_TOKENS_CHAIN2"
fi

