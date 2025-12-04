#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../util_mvm.sh"
source "$SCRIPT_DIR/../util_evm.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "inflow-submit-escrow"
cd "$PROJECT_ROOT"


# Load INTENT_ID from info file if not provided
if ! load_intent_info "INTENT_ID"; then
    exit 1
fi

# Get EVM escrow contract address from deployment logs
cd evm-intent-framework
ESCROW_ADDRESS=$(grep -i "IntentEscrow deployed to" "$PROJECT_ROOT/.tmp/intent-framework-logs/deploy-contract"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
if [ -z "$ESCROW_ADDRESS" ]; then
    # Try to get from hardhat config or last deployment
    ESCROW_ADDRESS=$(nix develop -c bash -c "npx hardhat run scripts/deploy.js --network localhost --dry-run 2>&1 | grep 'IntentEscrow deployed to' | awk '{print \$NF}'" 2>/dev/null | tail -1 | tr -d '\n')
fi
cd ..

if [ -z "$ESCROW_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not find escrow contract address. Please ensure IntentEscrow is deployed."
    log_and_echo "   Run: ./testing-infra/ci-e2e/chain-connected-evm/deploy-contract.sh"
    exit 1
fi

log ""
log "📋 Chain Information:"
log "   EVM Chain (Chain 3):    $ESCROW_ADDRESS"
log "   Intent ID:              $INTENT_ID"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

# Get USDxyz token address from chain-info.env
if [ -f "$PROJECT_ROOT/.tmp/chain-info.env" ]; then
    source "$PROJECT_ROOT/.tmp/chain-info.env"
    USDXYZ_ADDRESS="$USDXYZ_EVM_ADDRESS"
fi
if [ -z "$USDXYZ_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not find USDxyz token address. Please ensure USDxyz is deployed."
    exit 1
fi

# Get test tokens address for balance display
TEST_TOKENS_CHAIN1=$(get_profile_address "test-tokens-chain1")

log ""
log "🔑 Configuration:"
log "   Expiry time: $EXPIRY_TIME"
log "   Intent ID (for escrow): $INTENT_ID"
log "   USDxyz token address: $USDXYZ_ADDRESS"
log "   Escrow amount: 1 USDxyz (matches intent offered_amount)"

# Check and display initial balances using common function
log ""
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""

log ""
log "   Creating escrow on EVM chain..."
log "   - Requester locks 1 USDxyz in escrow on Chain 3 (EVM)"
log "   - Requester provides hub chain intent_id when creating escrow"
log "   - Using intent_id from hub chain: $INTENT_ID"
log "   - Amount matches intent offered_amount"

cd evm-intent-framework

# Convert intent_id from Move VM format to EVM uint256
INTENT_ID_EVM=$(convert_intent_id_to_evm "$INTENT_ID")
log "     Intent ID (EVM): $INTENT_ID_EVM"

# Create escrow for this intent with USDxyz ERC20 token
log "   - Creating escrow for intent (USDxyz ERC20 escrow) with funds..."
# Reserved solver: Solver - funds will go to Solver when escrow is claimed
SOLVER_ADDRESS=$(get_hardhat_account_address "2")
# Escrow amount must match the intent's offered_amount (1 USDxyz)
USDXYZ_AMOUNT="1000000"  # 1 USDxyz = 1_000_000 (6 decimals)
CREATE_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ESCROW_ADDRESS='$ESCROW_ADDRESS' TOKEN_ADDRESS='$USDXYZ_ADDRESS' INTENT_ID_EVM='$INTENT_ID_EVM' AMOUNT='$USDXYZ_AMOUNT' RESERVED_SOLVER='$SOLVER_ADDRESS' npx hardhat run scripts/create-escrow-erc20.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
CREATE_EXIT_CODE=$?

# Check if creation was successful
if [ $CREATE_EXIT_CODE -ne 0 ]; then
    log_and_echo "     ❌ ERROR: Escrow creation failed!"
    log_and_echo "   Creation output: $CREATE_OUTPUT"
    log_and_echo "   Log file contents:"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    cat "$LOG_FILE"
    log_and_echo "   + + + + + + + + + + + + + + + + + + + +"
    exit 1
fi

# Verify creation succeeded by checking for success message
if ! echo "$CREATE_OUTPUT" | grep -qi "Escrow created for intent"; then
    log_and_echo "     ❌ ERROR: Escrow creation did not complete successfully"
    log_and_echo "   Creation output: $CREATE_OUTPUT"
    log_and_echo "   Expected to see 'Escrow created for intent (ERC20)' in output"
    exit 1
fi

log "     ✅ Escrow created on Chain 3 (EVM)!"
log_and_echo "✅ Escrow created"

cd ..

log ""
log "🎉 ESCROW CREATION COMPLETE!"
log "============================"
log ""
log "✅ Step completed successfully:"
log "   1. Escrow created on Chain 3 (EVM) with locked USDxyz"
log ""
log "📋 Escrow Details:"
log "   Intent ID: $INTENT_ID"
log "   Escrow Address: $ESCROW_ADDRESS"
log "   Locked Amount: 1 USDxyz (matches intent offered_amount)"

# Check final balances using common function
display_balances_hub "0x$TEST_TOKENS_CHAIN1"
display_balances_connected_evm "$USDXYZ_ADDRESS"
log_and_echo ""


