#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-intent"
cd "$PROJECT_ROOT"

log "======================================"
log "🎯 CROSS-CHAIN INTENT - SUBMISSION"
log "======================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""
log "This script submits cross-chain intents (Steps 1-3):"
log "  1. [HUB CHAIN] User creates intent requesting tokens"
log "  2. [CONNECTED CHAIN] User creates escrow with locked tokens"
log "  3. [HUB CHAIN] Solver fulfills intent on hub chain"
log ""
log "For verifier monitoring and approval (Steps 4-6), run:"
log "  ./testing-infra/e2e-tests-apt/run-cross-chain-verifier.sh"
log ""
log "The verifier will:"
log "  4. Monitor both chains for intents and escrows"
log "  5. Wait for hub intent to be fulfilled"
log "  6. Sign approval for escrow release on connected chain"
log ""

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
    ./testing-infra/e2e-tests-apt/setup-and-deploy.sh

    if [ $? -ne 0 ]; then
        log_and_echo "❌ Failed to setup chains and deploy contracts"
        exit 1
    fi

    log ""
    log "✅ Chains setup and contracts deployed successfully!"
    log ""
else
    log ""
    log "⚡ Using existing running networks (skipping setup)"
    log "   Use parameter '1' to run full setup: ./submit-cross-chain-intent.sh 1"
    log ""
fi

# Note: Verifier monitoring will be handled separately

# Get addresses
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

# Get Alice and Bob addresses
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
ALICE_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')

log ""
log "📋 Chain Information:"
log "   Hub Chain (Chain 1):     $CHAIN1_ADDRESS"
log "   Connected Chain (Chain 2): $CHAIN2_ADDRESS"
log "   Alice Chain 1 (hub):     $ALICE_CHAIN1_ADDRESS"
log "   Bob Chain 1 (hub):       $BOB_CHAIN1_ADDRESS"
log "   Alice Chain 2 (connected): $ALICE_CHAIN2_ADDRESS"

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
log "📝 STEP 1: [HUB CHAIN] Alice creates intent requesting tokens"
log "================================================="
log "   User creates intent on hub chain requesting tokens from solver"
log "   - Alice creates intent on Chain 1 (hub chain)"
log "   - Intent requests 100000000 tokens to be provided by solver"
log "   - Using intent_id: $INTENT_ID"

# Get APT metadata addresses for both chains using helper function
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

# Get APT metadata on Chain 2
log "     Getting APT metadata on Chain 2..."
aptos move run --profile alice-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::test_fa_helper::get_apt_metadata_address" \
    >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    sleep 2
    APT_METADATA_CHAIN2=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("APTMetadataAddressEvent")) | .data.metadata' | head -n 1)
    if [ -n "$APT_METADATA_CHAIN2" ] && [ "$APT_METADATA_CHAIN2" != "null" ]; then
        log "     ✅ Got APT metadata on Chain 2: $APT_METADATA_CHAIN2"
        SOURCE_FA_METADATA_CHAIN2="$APT_METADATA_CHAIN2"
    else
        log_and_echo "     ❌ Failed to extract APT metadata from Chain 2 transaction"
        exit 1
    fi
else
    log_and_echo "     ❌ Failed to get APT metadata on Chain 2"
    exit 1
fi

# Create cross-chain request intent on Chain 1 using fa_intent module
log "   - Creating cross-chain request intent on Chain 1..."
log "     Source FA metadata: $SOURCE_FA_METADATA_CHAIN1"
log "     Desired FA metadata: $DESIRED_FA_METADATA_CHAIN1"
aptos move run --profile alice-chain1 --assume-yes \
    --function-id "0x${CHAIN1_ADDRESS}::fa_intent_cross_chain::create_cross_chain_request_intent_entry" \
    --args "address:${SOURCE_FA_METADATA_CHAIN1}" "address:${DESIRED_FA_METADATA_CHAIN1}" "u64:100000000" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" >> "$LOG_FILE" 2>&1

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
log "📝 STEP 2: [CONNECTED CHAIN] Alice creates escrow intent with locked tokens"
log "================================================="
log "   User creates escrow on connected chain WITH tokens locked in it"
log "   - Alice locks 100000000 tokens in escrow on Chain 2 (connected chain)"
log "   - User provides hub chain intent_id when creating escrow"
log "   - Using intent_id from hub chain: $INTENT_ID"

# Submit escrow intent using Alice's account on Chain 2 (connected chain)
log "   - Creating escrow intent on Chain 2..."
log "     Source FA metadata: $SOURCE_FA_METADATA_CHAIN2"
aptos move run --profile alice-chain2 --assume-yes \
    --function-id "0x${CHAIN2_ADDRESS}::intent_as_escrow_entry::create_escrow_from_fa" \
    --args "address:${SOURCE_FA_METADATA_CHAIN2}" "u64:100000000" "hex:${ORACLE_PUBLIC_KEY}" "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "     ✅ Escrow intent created on Chain 2!"
    
    # Verify escrow was stored on-chain and check locked amount
    sleep 2
    log "     - Verifying escrow stored on-chain with locked tokens..."
    
    # Extract event data directly without piping through head
    ESCROW_ADDRESS=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_address' | head -n 1)
    ESCROW_INTENT_ID=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.intent_id' | head -n 1)
    LOCKED_AMOUNT=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.source_amount' | head -n 1)
    DESIRED_AMOUNT=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE_CHAIN2_ADDRESS}/transactions?limit=1" | \
        jq -r '.[0].events[] | select(.type | contains("OracleLimitOrderEvent")) | .data.desired_amount' | head -n 1)
    
    if [ -n "$ESCROW_ADDRESS" ] && [ "$ESCROW_ADDRESS" != "null" ]; then
        
        log "     ✅ Escrow stored at: $ESCROW_ADDRESS"
        log "     ✅ Intent ID link: $ESCROW_INTENT_ID (should match: $INTENT_ID)"
        log "     ✅ Locked amount: $LOCKED_AMOUNT tokens"
        log "     ✅ Desired amount: $DESIRED_AMOUNT tokens"
        
          # Verify intent_id matches (normalize hex strings for comparison)
          # Remove 0x prefix and convert to lowercase, then compare
          NORMALIZED_INTENT_ID=$(echo "$INTENT_ID" | tr '[:upper:]' '[:lower:]' | sed 's/^0x//' | sed 's/^0*//')
          NORMALIZED_ESCROW_INTENT_ID=$(echo "$ESCROW_INTENT_ID" | tr '[:upper:]' '[:lower:]' | sed 's/^0x//' | sed 's/^0*//')
          
          # If normalization results in empty string, restore at least one zero
          [ -z "$NORMALIZED_INTENT_ID" ] && NORMALIZED_INTENT_ID="0"
          [ -z "$NORMALIZED_ESCROW_INTENT_ID" ] && NORMALIZED_ESCROW_INTENT_ID="0"
          
          if [ "$NORMALIZED_INTENT_ID" = "$NORMALIZED_ESCROW_INTENT_ID" ]; then
              log "     ✅ Intent IDs match - correct cross-chain link!"
          else
              log_and_echo "     ❌ ERROR: Intent IDs don't match!"
              log_and_echo "        Expected: $INTENT_ID"
              log_and_echo "        Got: $ESCROW_INTENT_ID"
              exit 1
          fi
        
        # Verify locked amount matches expected
        if [ "$LOCKED_AMOUNT" = "100000000" ]; then
            log "     ✅ Escrow has correct locked amount (100000000 tokens)"
        else
            log "     ⚠️  Escrow has unexpected locked amount: $LOCKED_AMOUNT"
        fi
        
        log_and_echo "✅ Escrow created"
    else
        log_and_echo "     ❌ ERROR: Could not verify escrow from events"
        exit 1
    fi
else
    log_and_echo "     ❌ Escrow intent creation failed!"
    exit 1
fi

log ""
log "📝 STEP 3: [HUB CHAIN] Bob fulfills intent on hub chain"
log "================================================="
log "   Solver monitors escrow event on connected chain and fulfills intent on hub chain"
log "   - Solver sees escrow event on connected chain"
log "   - Bob sees intent with ID: $INTENT_ID"
log "   - Bob provides 100000000 tokens on hub chain to fulfill the intent"

# TODO: We need to get the actual intent object address from Step 1
# For now, we'll need to extract it from the transaction event
INTENT_OBJECT_ADDRESS="$HUB_INTENT_ADDRESS"

if [ -n "$INTENT_OBJECT_ADDRESS" ] && [ "$INTENT_OBJECT_ADDRESS" != "null" ]; then
    log "   - Fulfilling intent at: $INTENT_OBJECT_ADDRESS"
    
    # Bob fulfills the intent by providing tokens
    aptos move run --profile bob-chain1 --assume-yes \
        --function-id "0x${CHAIN1_ADDRESS}::fa_intent_cross_chain::fulfill_cross_chain_request_intent" \
        --args "address:$INTENT_OBJECT_ADDRESS" "u64:100000000" >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        log "     ✅ Bob successfully fulfilled the intent!"
        log_and_echo "✅ Intent fulfilled"
    else
        log_and_echo "     ❌ Intent fulfillment failed!"
        exit 1
    fi
else
    log_and_echo "     ⚠️  Could not get intent object address, skipping fulfillment"
    exit 1
fi

log ""
log "🎉 INTENT SUBMISSION COMPLETE!"
log "=============================="
log ""
log "✅ Steps 1-3 completed successfully:"
log "   1. Intent created on Chain 1 (hub chain)"
log "   2. Escrow created on Chain 2 (connected chain) with locked tokens"
log "   3. Intent fulfilled on Chain 1 by Bob"
log ""
log "📋 Intent Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$HUB_INTENT_ADDRESS" ] && [ "$HUB_INTENT_ADDRESS" != "null" ]; then
    log "   Chain 1 Hub Intent: $HUB_INTENT_ADDRESS"
fi
if [ -n "$ESCROW_ADDRESS" ] && [ "$ESCROW_ADDRESS" != "null" ]; then
    log "   Chain 2 Escrow: $ESCROW_ADDRESS"
fi
# Check final balances using common function
# TODO: BALANCE DISCREPANCY INVESTIGATION
# Bob's balance decrease doesn't match expected amount when fulfilling with 100M:
# - Event shows provided_amount: 100,000,000 (correct)
# - Bob's balance decreases by 99,888,740 (less than 100M)
# - This suggests either:
#   1. aptos account balance shows coin balance while transfers use FA (but balances seem linked for APT)
#   2. Initial balance check captured wrong timing/state
#   3. Gas fees being deducted from transfer amount (unusual)
# Needs investigation to understand coin vs FA balance relationship and why loss < transfer amount
display_balances

log ""
log "🔍 Next Steps:"
log "   To monitor and verify these events with the trusted verifier, run:"
log "   ./testing-infra/e2e-tests-apt/run-cross-chain-verifier.sh"
log ""
log "✨ Script completed - intents are submitted and waiting for verification!"

