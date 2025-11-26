#!/bin/bash

# Balance Check Script for MVM E2E Tests
# Displays final balances for Hub (Chain 1) and Connected MVM (Chain 2)

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

source "$PROJECT_ROOT/testing-infra/util.sh"
source "$PROJECT_ROOT/testing-infra/util_mvm.sh"

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

