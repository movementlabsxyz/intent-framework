#!/usr/bin/env bash
# Generate test summary table for all components
# Usage: ./scripts/test-summary.sh

set -e

VERIFIER_TEST_OUTPUT=$(RUST_LOG=off nix develop -c bash -c "cd trusted-verifier && cargo test --quiet 2>&1")
VERIFIER_PASSED=$(echo "$VERIFIER_TEST_OUTPUT" | grep -oE "[0-9]+ passed" | awk '{sum += $1} END {print sum}')
VERIFIER_FAILED=$(echo "$VERIFIER_TEST_OUTPUT" | grep -oE "[0-9]+ failed" | awk '{sum += $1} END {print sum+0}')

SOLVER_TEST_OUTPUT=$(RUST_LOG=off nix develop -c bash -c "cd solver && cargo test --quiet 2>&1")
SOLVER_PASSED=$(echo "$SOLVER_TEST_OUTPUT" | grep -oE "[0-9]+ passed" | awk '{sum += $1} END {print sum}')
SOLVER_FAILED=$(echo "$SOLVER_TEST_OUTPUT" | grep -oE "[0-9]+ failed" | awk '{sum += $1} END {print sum+0}')

MOVE_PASSED=$(nix develop -c bash -c "cd move-intent-framework && movement move test --dev --named-addresses mvmt_intent=0x123" 2>&1 | grep -oE "passed: [0-9]+" | awk '{print $2}' | head -1)
MOVE_FAILED=$(nix develop -c bash -c "cd move-intent-framework && movement move test --dev --named-addresses mvmt_intent=0x123" 2>&1 | grep -oE "failed: [0-9]+" | awk '{print $2}' | head -1)

EVM_PASSED=$(nix develop -c bash -c "cd evm-intent-framework && npm test" 2>&1 | grep -oE "[0-9]+ passing" | awk '{print $1}')
EVM_FAILED=$(nix develop -c bash -c "cd evm-intent-framework && npm test" 2>&1 | grep -oE "[0-9]+ failing" | awk '{print $1+0}' || echo "0")
EVM_FAILED=${EVM_FAILED:-0}

echo "=== Test Summary Table ==="
echo ""
echo "| Tests | Passed | Failed |"
echo "|-------|--------|--------|"
echo "| Verifier (Rust) | $VERIFIER_PASSED | $VERIFIER_FAILED |"
echo "| Solver (Rust) | $SOLVER_PASSED | $SOLVER_FAILED |"
echo "| Move | $MOVE_PASSED | $MOVE_FAILED |"
echo "| EVM | $EVM_PASSED | $EVM_FAILED |"
echo ""

