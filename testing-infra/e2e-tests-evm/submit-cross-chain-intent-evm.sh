#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-intent-evm"
cd "$PROJECT_ROOT"

log "======================================"
log "🎯 MIXED-CHAIN INTENT - SUBMISSION"
log "======================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""
log "This script submits mixed-chain intents (Steps 1-3):"
log "  1. [HUB CHAIN] User creates intent requesting tokens"
log "  2. [EVM CHAIN] User creates escrow with locked tokens"
log "  3. [HUB CHAIN] Solver fulfills intent on hub chain"
log ""
log "For verifier monitoring and approval (Steps 4-6), run:"
log "  ./testing-infra/e2e-tests-evm/release-evm-escrow.sh"
log ""
log "The verifier will:"
log "  4. Monitor Chain 1 (Aptos hub) for intents and fulfillments"
log "  5. Wait for hub intent to be fulfilled"
log "  6. Sign approval for escrow release on EVM chain"

# Validate parameter
if [ -z "$1" ] || ([ "$1" != "0" ] && [ "$1" != "1" ]); then
    log_and_echo "❌ Error: Invalid parameter!"
    log_and_echo ""
    log_and_echo "Usage: $0 <parameter>"
    log_and_echo "  Parameter 0: Use existing running networks (skip setup)"
    log_and_echo "  Parameter 1: Run full setup and deploy contracts"
    log_and_echo ""
    log_and_echo "Examples:"
    log_and_echo "  $0 0    # Use existing networks"
    log_and_echo "  $0 1    # Run full setup"
    exit 1
fi

# Generate a random intent_id that will be used for both hub and escrow
INTENT_ID="0x$(openssl rand -hex 32)"

# Check if we should run setup or use existing networks
if [ "$1" = "1" ]; then
    log ""
    log "🚀 Step 0.1: Setting up chains and deploying contracts..."
    log "========================================================"
    
    # Setup EVM chain first
    log "📦 Setting up EVM chain (Chain 3)..."
    ./testing-infra/e2e-tests-evm/setup-and-deploy-evm.sh

    if [ $? -ne 0 ]; then
        log_and_echo "❌ Failed to setup EVM chain"
        exit 1
    fi
    
    log ""
    log "📦 Setting up Aptos chains (Chain 1)..."
    ./testing-infra/e2e-tests-apt/setup-and-deploy.sh

    if [ $? -ne 0 ]; then
        log_and_echo "❌ Failed to setup Aptos chains"
        exit 1
    fi

    log ""
    log "✅ Chains setup and contracts deployed successfully!"
    log ""
else
    log ""
    log "⚡ Using existing running networks (skipping setup)"
    log "   Ensure both Aptos chains and EVM chain are running"
    log "   Use parameter '1' to run full setup: ./submit-cross-chain-intent-evm.sh 1"
    log ""
fi

# Get addresses
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')

# Get Alice and Bob addresses
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')

# Get EVM vault address from deployment logs or config
cd evm-intent-framework
VAULT_ADDRESS=$(grep -i "IntentVault deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-vault"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
if [ -z "$VAULT_ADDRESS" ]; then
    # Try to get from hardhat config or last deployment
    VAULT_ADDRESS=$(nix develop -c bash -c "npx hardhat run scripts/deploy.js --network localhost --dry-run 2>&1 | grep 'IntentVault deployed to' | awk '{print \$NF}'" 2>/dev/null | tail -1 | tr -d '\n')
fi
cd ..

if [ -z "$VAULT_ADDRESS" ]; then
    log_and_echo "⚠️  Warning: Could not find vault address. Please ensure IntentVault is deployed."
    log_and_echo "   Run: ./testing-infra/e2e-tests-evm/deploy-vault.sh"
    VAULT_ADDRESS="0x0000000000000000000000000000000000000000"  # Placeholder
fi

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   EVM Chain (Chain 3):    $VAULT_ADDRESS"
log "   Alice Chain 1 (hub):     $ALICE_CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"

# Load oracle public key from verifier config (base64 encoded, needs to be converted to hex)
# Use verifier_testing.toml for tests - required, panic if not found
VERIFIER_TESTING_CONFIG="${PROJECT_ROOT}/trusted-verifier/config/verifier_testing.toml"

if [ ! -f "$VERIFIER_TESTING_CONFIG" ]; then
    log_and_echo "❌ ERROR: verifier_testing.toml not found at $VERIFIER_TESTING_CONFIG"
    log_and_echo "   Tests require trusted-verifier/config/verifier_testing.toml to exist"
    exit 1
fi

# Export config path for Rust code to use (if called)
export VERIFIER_CONFIG_PATH="$VERIFIER_TESTING_CONFIG"

VERIFIER_PUBLIC_KEY_B64=$(grep "^public_key" "$VERIFIER_TESTING_CONFIG" | cut -d'"' -f2)

if [ -z "$VERIFIER_PUBLIC_KEY_B64" ]; then
    log_and_echo "❌ ERROR: Could not find public_key in verifier_testing.toml"
    log_and_echo "   The verifier public key is required for escrow creation."
    log_and_echo "   Please ensure verifier_testing.toml has a valid public_key field."
    exit 1
fi

# Convert base64 public key to hex (32 bytes)
ORACLE_PUBLIC_KEY_HEX=$(echo "$VERIFIER_PUBLIC_KEY_B64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')

if [ -z "$ORACLE_PUBLIC_KEY_HEX" ] || [ ${#ORACLE_PUBLIC_KEY_HEX} -ne 64 ]; then
    log_and_echo "❌ ERROR: Invalid public key format in verifier_testing.toml"
    log_and_echo "   Expected: base64-encoded 32-byte Ed25519 public key"
    log_and_echo "   Got: $VERIFIER_PUBLIC_KEY_B64"
    log_and_echo "   Please ensure the public_key in verifier_testing.toml is valid base64 and decodes to 32 bytes (64 hex chars)."
    exit 1
fi

ORACLE_PUBLIC_KEY="0x${ORACLE_PUBLIC_KEY_HEX}"
log "   ✅ Loaded verifier public key from config (32 bytes)"

EXPIRY_TIME=$(date -d "+1 hour" +%s)

# Generate a random intent_id upfront (for cross-chain linking)
INTENT_ID="0x$(openssl rand -hex 32)"

log ""
log "🔑 Configuration:"
log "   Oracle public key: $ORACLE_PUBLIC_KEY"
log "   Expiry time: $EXPIRY_TIME"
log "   Intent ID (for hub & escrow): $INTENT_ID"

# Check and display initial balances using common function
log ""
display_balances

log ""
log "📝 STEP 1: [HUB CHAIN] Alice creates intent requesting APT"
log "================================================="
log "   User creates intent on hub chain requesting APT from solver"
log "   - Alice creates intent on Chain 1 (hub chain)"
log "   - Intent requests 1 APT to be provided by solver (1000 ETH for 1 APT)"
log "   - Using intent_id: $INTENT_ID"

# Get APT metadata addresses for Chain 1 using helper function
log "   - Getting APT metadata addresses..."

# Get APT metadata on Chain 1
log "     Getting APT metadata on Chain 1..."
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::test_fa_helper::get_apt_metadata_address" \
    >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    sleep 2
    APT_METADATA_CHAIN1=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("APTMetadataAddressEvent")) | .data.metadata' | head -n 1)
    if [ -n "$APT_METADATA_CHAIN1" ] && [ "$APT_METADATA_CHAIN1" != "null" ]; then
        log "     ✅ Got APT metadata on Chain 1: $APT_METADATA_CHAIN1"
        SOURCE_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"
        DESIRED_FA_METADATA_CHAIN1="$APT_METADATA_CHAIN1"
    else
        log_and_echo "     ❌ Failed to extract APT metadata from Chain 1 transaction"
        exit 1
    fi
else
    log_and_echo "     ❌ Failed to get APT metadata on Chain 1"
    exit 1
fi

# Create cross-chain request intent on Chain 1 using fa_intent module
# 1 APT = 100000000 Octas (Aptos has 8 decimals)
APT_AMOUNT_OCTAS="100000000"
log "   - Creating cross-chain request intent on Chain 1..."
log "     Source FA metadata: $SOURCE_FA_METADATA_CHAIN1"
log "     Desired FA metadata: $DESIRED_FA_METADATA_CHAIN1"
log "     Amount: 1 APT ($APT_AMOUNT_OCTAS Octas)"
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_cross_chain::create_cross_chain_request_intent_entry" \
    --args "address:${SOURCE_FA_METADATA_CHAIN1}" "address:${DESIRED_FA_METADATA_CHAIN1}" "u64:${APT_AMOUNT_OCTAS}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Intent created on Chain 1!"
    
    # Verify intent was stored on-chain by checking Alice's latest transaction
    sleep 2
    log "     - Verifying intent stored on-chain..."
    HUB_INTENT_ADDRESS=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_CHAIN1_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("LimitOrderEvent")) | .data.intent_address' | head -n 1)
    
    if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
        log "     ✅ Hub intent stored at: $HUB_INTENT_ADDRESS"
        log_and_echo "✅ Intent created"
    else
        log_and_echo "     ❌ ERROR: Could not verify hub intent address"
        exit 1
    fi
else
    log_and_echo "     ❌ Intent creation failed on Chain 1!"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

log ""
log "📝 STEP 2: [EVM CHAIN] Alice creates escrow with locked ETH"
log "================================================="
log "   User creates escrow on EVM chain WITH ETH locked in it"
log "   - Alice locks 1000 ETH in escrow on Chain 3 (EVM)"
log "   - User provides hub chain intent_id when creating escrow"
log "   - Using intent_id from hub chain: $INTENT_ID"
log "   - Exchange rate: 1000 ETH = 1 APT"

cd evm-intent-framework

# Convert intent_id from Aptos format to EVM uint256
# Intent ID is already in hex format (0x...), just need to remove 0x and pad to 64 chars
INTENT_ID_HEX=$(echo "$INTENT_ID" | sed 's/^0x//')
# Ensure it's 64 characters (32 bytes)
INTENT_ID_HEX=$(printf "%064s" "$INTENT_ID_HEX" | tr ' ' '0')
INTENT_ID_EVM="0x$INTENT_ID_HEX"

log "     Intent ID (EVM): $INTENT_ID_EVM"

# Initialize vault for this intent with ETH (address(0))
log "   - Initializing vault for intent (ETH vault)..."
EXPIRY_TIME_EVM=$(date -d "+1 hour" +%s)
INIT_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && VAULT_ADDRESS='$VAULT_ADDRESS' INTENT_ID_EVM='$INTENT_ID_EVM' EXPIRY_TIME_EVM='$EXPIRY_TIME_EVM' npx hardhat run scripts/initialize-vault-eth.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
INIT_EXIT_CODE=$?

# Check if initialization was successful
if [ $INIT_EXIT_CODE -ne 0 ]; then
    log_and_echo "     ❌ ERROR: Vault initialization failed!"
    log_and_echo "   Initialization output: $INIT_OUTPUT"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

# Verify initialization succeeded by checking for success message
if ! echo "$INIT_OUTPUT" | grep -qi "Vault initialized for intent"; then
    log_and_echo "     ❌ ERROR: Vault initialization did not complete successfully"
    log_and_echo "   Initialization output: $INIT_OUTPUT"
    log_and_echo "   Expected to see 'Vault initialized for intent (ETH)' in output"
    exit 1
fi

# Deposit 1000 ETH into vault
log "   - Depositing 1000 ETH into vault..."
ETH_AMOUNT_WEI="1000000000000000000000"  # 1000 ETH = 1000 * 10^18 wei
DEPOSIT_OUTPUT=$(nix develop "$PROJECT_ROOT" -c bash -c "cd '$PROJECT_ROOT/evm-intent-framework' && VAULT_ADDRESS='$VAULT_ADDRESS' INTENT_ID_EVM='$INTENT_ID_EVM' ETH_AMOUNT_WEI='$ETH_AMOUNT_WEI' npx hardhat run scripts/deposit-eth.js --network localhost" 2>&1 | tee -a "$LOG_FILE")
DEPOSIT_EXIT_CODE=$?

# Check if deposit was successful
if [ $DEPOSIT_EXIT_CODE -ne 0 ]; then
    log_and_echo "     ❌ ERROR: ETH deposit failed!"
    log_and_echo "   Deposit output: $DEPOSIT_OUTPUT"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

# Verify deposit succeeded by checking for success message
if ! echo "$DEPOSIT_OUTPUT" | grep -qi "Deposited.*wei.*ETH.*vault"; then
    log_and_echo "     ❌ ERROR: ETH deposit did not complete successfully"
    log_and_echo "   Deposit output: $DEPOSIT_OUTPUT"
    log_and_echo "   Expected to see 'Deposited ... wei (ETH) into vault' in output"
    exit 1
fi

log "     ✅ Escrow created on Chain 3 (EVM)!"
log_and_echo "✅ Escrow created"

cd ..

log ""
log "📝 STEP 3: [HUB CHAIN] Bob fulfills intent on hub chain"
log "================================================="
log "   Solver monitors escrow event on EVM chain and fulfills intent on hub chain"
log "   - Bob sees intent with ID: $INTENT_ID"
log "   - Bob provides 1 APT ($APT_AMOUNT_OCTAS Octas) on hub chain to fulfill the intent"

# Get the intent object address from Step 1
if [ -z "$HUB_INTENT_ADDRESS" ] || [ "$HUB_INTENT_ADDRESS" = "null" ]; then
    log_and_echo "     ❌ ERROR: Could not find hub intent address"
    exit 1
fi

log "   - Intent object address: $HUB_INTENT_ADDRESS"
log "   - Fulfilling intent..."

# Bob fulfills the intent by providing 1 APT
aptos move run --profile bob-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_cross_chain::fulfill_cross_chain_request_intent" \
    --args "address:$HUB_INTENT_ADDRESS" "u64:${APT_AMOUNT_OCTAS}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Bob successfully fulfilled the intent!"
    log_and_echo "✅ Intent fulfilled"
else
    log_and_echo "     ❌ Intent fulfillment failed!"
    log_and_echo "   See log file for details: $LOG_FILE"
    exit 1
fi

log ""
log "======================================"
log "✅ CROSS-CHAIN INTENT SUBMISSION COMPLETE!"
log "======================================"
log ""
log "Next steps:"
log "  1. Run verifier to monitor and approve: ./testing-infra/e2e-tests-evm/release-evm-escrow.sh"
log ""
log "Summary:"
log "   ✅ Intent created on Chain 1 (Aptos hub): Requesting 1 APT"
log "   ✅ Escrow created on Chain 3 (EVM): 1000 ETH locked"
log "   ✅ Intent fulfilled on Chain 1 (Aptos hub): Bob provided 1 APT"
log "   ⏳ Waiting for verifier approval to release 1000 ETH escrow on Chain 3"

