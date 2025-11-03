#!/bin/bash

# Source common utilities
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../common.sh"

# Setup project root and logging
setup_project_root
setup_logging "release-evm-escrow"
cd "$PROJECT_ROOT"

log "🔓 EVM ESCROW RELEASE"
log "====================="
log_and_echo "📝 All output logged to: $LOG_FILE"

# Check if verifier is running
if ! curl -s http://127.0.0.1:3333/health >/dev/null 2>&1; then
    log_and_echo "❌ Verifier is not running. Please start it first:"
    log_and_echo "   ./testing-infra/e2e-tests/complete-system/run-cross-chain-verifier.sh"
    exit 1
fi

# Get EVM vault address
cd evm-intent-framework
VAULT_ADDRESS=$(grep -i "IntentVault deployed to" "$PROJECT_ROOT/tmp/intent-framework-logs/deploy-vault"*.log 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '\n')
cd ..

if [ -z "$VAULT_ADDRESS" ]; then
    log_and_echo "❌ Could not find vault address"
    exit 1
fi

log "   Vault address: $VAULT_ADDRESS"

# Track released escrows to avoid duplicate attempts
RELEASED_ESCROWS=""

# Function to check for new approvals and release escrows
check_and_release_escrows() {
    APPROVALS_RESPONSE=$(curl -s "http://127.0.0.1:3333/approvals")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    APPROVALS_SUCCESS=$(echo "$APPROVALS_RESPONSE" | jq -r '.success' 2>/dev/null)
    if [ "$APPROVALS_SUCCESS" != "true" ]; then
        return 1
    fi
    
    # Extract approvals array
    APPROVALS_COUNT=$(echo "$APPROVALS_RESPONSE" | jq -r '.data | length' 2>/dev/null || echo "0")
    
    if [ "$APPROVALS_COUNT" = "0" ]; then
        return 0
    fi
    
    # Process each approval
    for i in $(seq 0 $((APPROVALS_COUNT - 1))); do
        ESCROW_ID=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].escrow_id" 2>/dev/null)
        INTENT_ID=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].intent_id" 2>/dev/null)
        APPROVAL_VALUE=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].approval_value" 2>/dev/null)
        SIGNATURE_BASE64=$(echo "$APPROVALS_RESPONSE" | jq -r ".data[$i].signature" 2>/dev/null)
        
        if [ -z "$ESCROW_ID" ] || [ "$ESCROW_ID" = "null" ] || [ "$APPROVAL_VALUE" != "1" ]; then
            continue
        fi
        
        # Skip if already released
        if [[ "$RELEASED_ESCROWS" == *"$ESCROW_ID"* ]]; then
            continue
        fi
        
        log ""
        log "   📦 New approval found for escrow: $ESCROW_ID"
        log "   🔓 Releasing escrow on EVM chain..."
        
        # Convert intent_id to EVM format (remove 0x, pad to 64 chars)
        INTENT_ID_HEX=$(echo "$INTENT_ID" | sed 's/^0x//')
        INTENT_ID_HEX=$(printf "%064s" "$INTENT_ID_HEX" | tr ' ' '0')
        INTENT_ID_EVM="0x$INTENT_ID_HEX"
        
        # Convert signature from base64 to hex for EVM
        # The verifier provides ECDSA signature as base64-encoded bytes (65 bytes: r || s || v)
        SIGNATURE_HEX=$(echo "$SIGNATURE_BASE64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')
        
        if [ -z "$SIGNATURE_HEX" ]; then
            log "   ❌ Failed to decode signature"
            continue
        fi
        
        # Signature should be 130 hex chars (65 bytes * 2)
        if [ ${#SIGNATURE_HEX} -ne 130 ]; then
            log "   ❌ Invalid signature length: expected 130 hex chars, got ${#SIGNATURE_HEX}"
            continue
        fi
        
        # Submit escrow release transaction on EVM
        cd evm-intent-framework
        
        log "   - Calling IntentVault.claim() on EVM..."
        CLAIM_OUTPUT=$(nix develop -c bash -c "npx hardhat run - <<'EOF'
const hre = require('hardhat');
(async () => {
  const signers = await hre.ethers.getSigners();
  const vault = await hre.ethers.getContractAt('IntentVault', '$VAULT_ADDRESS');
  const intentId = BigInt('$INTENT_ID_EVM');
  const approvalValue = 1;
  const signature = '0x$SIGNATURE_HEX';
  
  try {
    const tx = await vault.connect(signers[1]).claim(intentId, approvalValue, signature);
    const receipt = await tx.wait();
    console.log('Claim transaction hash:', receipt.hash);
    console.log('Escrow released successfully!');
  } catch (error) {
    console.error('Error claiming escrow:', error.message);
    process.exit(1);
  }
})();
EOF" 2>&1 | tee -a "$LOG_FILE")
        
        TX_EXIT_CODE=$?
        cd ..
        
        if [ $TX_EXIT_CODE -eq 0 ]; then
            log "   ✅ Escrow released successfully on EVM chain!"
            RELEASED_ESCROWS="${RELEASED_ESCROWS}${RELEASED_ESCROWS:+ }${ESCROW_ID}"
        else
            log "   ❌ Failed to release escrow on EVM chain"
            log "      See log file for details: $LOG_FILE"
        fi
    done
}

log ""
log "⏳ Polling verifier for approvals..."
log "   Verifier API: http://127.0.0.1:3333/approvals"
log ""

# Poll for approvals a few times before script exits
log "   - Checking for approvals (will check 10 times with 3 second intervals)..."
for i in {1..10}; do
    sleep 3
    check_and_release_escrows
done

log ""
log "✅ Escrow release monitoring complete!"
log ""
log "📝 Useful commands:"
log "   View approvals:  curl -s http://127.0.0.1:3333/approvals | jq"
log "   View events:    curl -s http://127.0.0.1:3333/events | jq"
log "   Health check:   curl -s http://127.0.0.1:3333/health"

