#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "submit-escrow"
cd "$PROJECT_ROOT"

log "======================================"
log "🎯 ESCROW CREATION - CONNECTED CHAIN"
log "======================================"
log_and_echo "📝 All output logged to: $LOG_FILE"
log ""
log "This script creates escrow on connected chain:"
log "  [CONNECTED CHAIN] User creates escrow with locked tokens"
log ""
log "Note: Hub chain intent should be created first using:"
log "      ./testing-infra/e2e-tests-apt/submit-hub-intent.sh"
log ""
log "Usage: ./testing-infra/e2e-tests-apt/submit-escrow.sh"
log "   (INTENT_ID will be loaded from tmp/intent-info.env if not provided)"

# Load INTENT_ID from info file if not provided
if [ -z "$INTENT_ID" ]; then
    INTENT_INFO_FILE="${PROJECT_ROOT}/tmp/intent-info.env"
    if [ -f "$INTENT_INFO_FILE" ]; then
        source "$INTENT_INFO_FILE"
        log "   ✅ Loaded INTENT_ID from $INTENT_INFO_FILE"
    else
        log_and_echo "❌ ERROR: INTENT_ID not provided and intent-info.env not found"
        log_and_echo "   Run submit-hub-intent.sh first, or provide INTENT_ID=<id>"
        exit 1
    fi
fi

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

log ""
log "🔑 Configuration:"
log "   Oracle public key: $ORACLE_PUBLIC_KEY"
log "   Expiry time: $EXPIRY_TIME"
log "   Intent ID: $INTENT_ID"

# Check and display initial balances using common function
log ""
display_balances

log ""
log "📝 STEP 1: [CONNECTED CHAIN] Alice creates escrow intent with locked tokens"
log "================================================="
log "   User creates escrow on connected chain WITH tokens locked in it"
log "   - Alice locks 100000000 tokens in escrow on Chain 2 (connected chain)"
log "   - User provides hub chain intent_id when creating escrow"
log "   - Using intent_id from hub chain: $INTENT_ID"

# Get APT metadata on Chain 2
log "   - Getting APT metadata on Chain 2..."
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
log "🎉 ESCROW CREATION COMPLETE!"
log "============================"
log ""
log "✅ Step completed successfully:"
log "   1. Escrow created on Chain 2 (connected chain) with locked tokens"
log ""
log "📋 Escrow Details:"
log "   Intent ID: $INTENT_ID"
if [ -n "$ESCROW_ADDRESS" ] && [ "$ESCROW_ADDRESS" != "null" ]; then
    log "   Chain 2 Escrow: $ESCROW_ADDRESS"
fi

# Check final balances using common function
display_balances

log ""
log "🔍 Next Steps:"
log "   To create and fulfill the hub chain intent, run:"
log "   ./testing-infra/e2e-tests-apt/submit-hub-intent.sh"
log ""
log "   Or to monitor and verify with the trusted verifier, run:"
log "   ./testing-infra/e2e-tests-apt/release-escrow.sh"
log ""
log "✨ Script completed - escrow is created and waiting for verification!"

