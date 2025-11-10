#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../util.sh"
source "$SCRIPT_DIR/../chain-connected-evm/utils.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-escrow"
cd "$PROJECT_ROOT"


# Load INTENT_ID from info file if not provided
if ! load_intent_info "INTENT_ID"; then
    exit 1
fi

# Get EVM escrow contract address from deployment logs
cd evm-intent-framework
ESCROW_ADDRESS=$(grep -i "IntentEscrow deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-contract"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
if [ -z "$ESCROW_ADDRESS" ]; then
    # Try to get from hardhat config or last deployment
    ESCROW_ADDRESS=$(nix develop -c bash -c "npx hardhat run scripts/deploy.js --network localhost --dry-run 2>&1 | grep 'IntentEscrow deployed to' | awk '{print \$NF}'" 2>/dev/null | tail -1 | tr -d '\n')
fi
cd ..

if [ -z "$ESCROW_ADDRESS" ]; then
    log_and_echo "❌ ERROR: Could not find escrow contract address. Please ensure IntentEscrow is deployed."
    log_and_echo "   Run: ./testing-infra/chain-connected-evm/deploy-contract.sh"
    exit 1
fi

log ""
log "📋 Chain Information:"
log "   EVM Chain (Chain 3):    $ESCROW_ADDRESS"
log "   Intent ID:              $INTENT_ID"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

log ""
log "🔑 Configuration:"
log "   Expiry time: $EXPIRY_TIME"
log "   Intent ID (for escrow): $INTENT_ID"
log "   Exchange rate: 1000 ETH = 1 APT"

# Check and display initial balances using common function
log ""
display_balances

log ""
log "   Creating escrow on EVM chain..."
log "   - Alice locks 1000 ETH in escrow on Chain 3 (EVM)"
log "   - User provides hub chain intent_id when creating escrow"
log "   - Using intent_id from hub chain: $INTENT_ID"
log "   - Exchange rate: 1000 ETH = 1 APT"

cd evm-intent-framework

# Convert intent_id from Aptos format to EVM uint256
INTENT_ID_EVM=$(convert_intent_id_to_evm "$INTENT_ID")
log "     Intent ID (EVM): $INTENT_ID_EVM"

# Create escrow for this intent with ETH (address(0)) and deposit funds atomically
log "   - Creating escrow for intent (ETH escrow) with funds..."
# Reserved solver: Bob - funds will go to Bob when escrow is claimed
BOB_ADDRESS=$(get_hardhat_account_address "2")
ETH_AMOUNT_WEI="1000000000000000000000"  # 1000 ETH = 1000 * 10^18 wei
CREATE_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && ESCROW_ADDRESS='$ESCROW_ADDRESS' INTENT_ID_EVM='$INTENT_ID_EVM' ETH_AMOUNT_WEI='$ETH_AMOUNT_WEI' RESERVED_SOLVER='$BOB_ADDRESS' npx hardhat run scripts/create-escrow-eth.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
CREATE_EXIT_CODE=$?

# Check if creation was successful
if [ $CREATE_EXIT_CODE -ne 0 ]; then
    log_and_echo "     ❌ ERROR: Escrow creation failed!"
    log_and_echo "   Creation output: $CREATE_OUTPUT"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

# Verify creation succeeded by checking for success message
if ! echo "$CREATE_OUTPUT" | grep -qi "Escrow created for intent"; then
    log_and_echo "     ❌ ERROR: Escrow creation did not complete successfully"
    log_and_echo "   Creation output: $CREATE_OUTPUT"
    log_and_echo "   Expected to see 'Escrow created for intent (ETH)' in output"
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
log "   1. Escrow created on Chain 3 (EVM) with locked ETH"
log ""
log "📋 Escrow Details:"
log "   Intent ID: $INTENT_ID"
log "   Escrow Address: $ESCROW_ADDRESS"
log "   Locked Amount: 1000 ETH"

# Check final balances using common function
display_balances


