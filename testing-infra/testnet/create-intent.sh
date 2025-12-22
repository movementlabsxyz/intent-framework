#!/bin/bash

# Create Intent on Movement Testnet (Requester Script)
#
# This script allows a requester to create an intent on Movement Bardock Testnet.
# It uses verifier-based negotiation routing:
#   1. Submit draft intent to verifier
#   2. Wait for solver to sign (solver service polls automatically)
#   3. Retrieve signature from verifier
#   4. Create intent on-chain with solver signature
#
# Prerequisites:
#   - Verifier running locally (or remotely)
#   - Solver service running (to sign drafts)
#   - Movement CLI installed
#   - .testnet-keys.env with MOVEMENT_REQUESTER_PRIVATE_KEY
#   - trusted-verifier/config/verifier_testnet.toml configured
#
# Usage:
#   ./create-intent.sh inflow <amount>   # Create inflow intent (USDC Base → USDC Movement)
#   ./create-intent.sh outflow <amount>  # Create outflow intent (USDC Movement → USDC Base)
#   Amount is in smallest units (6 decimals): 100000 = 0.1 USDC, 1000000 = 1 USDC
#   Amount is REQUIRED

set -e

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Parse arguments - positional: flow_type amount
FLOW_TYPE="${1}"
AMOUNT="${2}"

# Validate flow type
if [ "$FLOW_TYPE" != "inflow" ] && [ "$FLOW_TYPE" != "outflow" ]; then
    echo "❌ ERROR: Flow type must be 'inflow' or 'outflow'"
    echo ""
    echo "Usage:"
    echo "   ./create-intent.sh inflow <amount>   # USDC Base → USDC Movement"
    echo "   ./create-intent.sh outflow <amount>  # USDC Movement → USDC Base"
    echo ""
    echo "   Amount is REQUIRED and must be in smallest units (6 decimals):"
    echo "   - 100000 = 0.1 USDC"
    echo "   - 1000000 = 1 USDC"
    echo ""
    echo "Examples:"
    echo "   ./create-intent.sh inflow 100000    # 0.1 USDC"
    echo "   ./create-intent.sh inflow 1000000    # 1 USDC"
    echo "   ./create-intent.sh outflow 2000000   # 2 USDC"
    exit 1
fi

# Validate amount is provided
if [ -z "$AMOUNT" ]; then
    echo "❌ ERROR: Amount is required"
    echo ""
    echo "Usage:"
    echo "   ./create-intent.sh $FLOW_TYPE <amount>"
    echo ""
    echo "   Amount must be in smallest units (6 decimals):"
    echo "   - 100000 = 0.1 USDC"
    echo "   - 1000000 = 1 USDC"
    echo ""
    echo "Examples:"
    echo "   ./create-intent.sh $FLOW_TYPE 100000    # 0.1 USDC"
    echo "   ./create-intent.sh $FLOW_TYPE 1000000    # 1 USDC"
    exit 1
fi

# Validate amount is numeric
if ! [[ "$AMOUNT" =~ ^[0-9]+$ ]]; then
    echo "❌ ERROR: Amount must be a positive integer"
    echo "   Provided: $AMOUNT"
    echo ""
    echo "Usage:"
    echo "   ./create-intent.sh $FLOW_TYPE <amount>"
    echo ""
    echo "   Amount must be in smallest units (6 decimals):"
    echo "   - 100000 = 0.1 USDC"
    echo "   - 1000000 = 1 USDC"
    exit 1
fi

echo "🔍 Creating $FLOW_TYPE Intent on Movement Testnet"
echo "=================================================="
echo ""

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get ERC20 token balance on Base Sepolia
# Usage: get_base_usdc_balance <address> <token_addr> <rpc_url>
get_base_usdc_balance() {
    local address="$1"
    local token_addr="$2"
    local rpc_url="$3"
    
    # ERC20 balanceOf(address) selector = 0x70a08231
    local address_padded=$(echo "$address" | tr '[:upper:]' '[:lower:]' | sed 's/0x//' | awk '{printf "%064s", $0}' | tr ' ' '0')
    local data="0x70a08231${address_padded}"
    
    local result=$(curl -s -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$token_addr\",\"data\":\"$data\"},\"latest\"],\"id\":1}" \
        2>/dev/null | jq -r '.result // "0x0"')
    
    # Convert hex to decimal
    echo $((result))
}

# Get USDC.e balance on Movement (Fungible Asset)
# Usage: get_movement_usdc_balance <address> <metadata_addr> <rpc_url>
get_movement_usdc_balance() {
    local address="$1"
    local metadata="$2"
    local rpc_url="$3"
    
    local result=$(curl -s -X POST "${rpc_url}/view" \
        -H "Content-Type: application/json" \
        -d "{
            \"function\": \"0x1::primary_fungible_store::balance\",
            \"type_arguments\": [\"0x1::fungible_asset::Metadata\"],
            \"arguments\": [\"$address\", \"$metadata\"]
        }" 2>/dev/null | jq -r '.[0] // "0"')
    
    echo "${result:-0}"
}

# Format balance with USDC display
# Usage: format_usdc <raw_amount>
format_usdc() {
    local raw="$1"
    local usdc=$(echo "scale=6; $raw / 1000000" | bc 2>/dev/null || echo "?")
    echo "$raw ($usdc USDC)"
}

# Load .testnet-keys.env
TESTNET_KEYS_FILE="$PROJECT_ROOT/.testnet-keys.env"

if [ ! -f "$TESTNET_KEYS_FILE" ]; then
    echo "❌ ERROR: .testnet-keys.env not found at $TESTNET_KEYS_FILE"
    exit 1
fi

source "$TESTNET_KEYS_FILE"

# Check required variables
if [ -z "$MOVEMENT_REQUESTER_PRIVATE_KEY" ] || [ -z "$MOVEMENT_REQUESTER_ADDRESS" ]; then
    echo "❌ ERROR: MOVEMENT_REQUESTER_PRIVATE_KEY and MOVEMENT_REQUESTER_ADDRESS must be set in .testnet-keys.env"
    exit 1
fi

# Load assets configuration
ASSETS_CONFIG_FILE="$PROJECT_ROOT/testing-infra/testnet/config/testnet-assets.toml"

if [ ! -f "$ASSETS_CONFIG_FILE" ]; then
    echo "❌ ERROR: testnet-assets.toml not found at $ASSETS_CONFIG_FILE"
    exit 1
fi

# Load verifier config
VERIFIER_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testnet.toml"

if [ ! -f "$VERIFIER_CONFIG" ]; then
    echo "❌ ERROR: verifier_testnet.toml not found at $VERIFIER_CONFIG"
    exit 1
fi

# Extract config values
INTENT_MODULE_ADDRESS=$(grep -A5 "\[hub_chain\]" "$VERIFIER_CONFIG" | grep "intent_module_addr" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
VERIFIER_URL="http://localhost:3333"  # Default to local verifier

# Check if verifier is reachable
echo "   Checking verifier health..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$VERIFIER_URL/health" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ ERROR: Verifier not responding at $VERIFIER_URL (HTTP $HTTP_CODE)"
    echo ""
    echo "   Make sure verifier is running:"
    echo "   ./testing-infra/testnet/run-verifier-local.sh"
    exit 1
fi

echo "   ✅ Verifier is healthy"
echo ""

# Get verifier public key (needed for outflow intents)
VERIFIER_PUBLIC_KEY_B64="$VERIFIER_PUBLIC_KEY"
if [ -z "$VERIFIER_PUBLIC_KEY_B64" ]; then
    echo "❌ ERROR: VERIFIER_PUBLIC_KEY not set in .testnet-keys.env"
    exit 1
fi

VERIFIER_PUBLIC_KEY_HEX=$(echo "$VERIFIER_PUBLIC_KEY_B64" | base64 -d 2>/dev/null | xxd -p -c 1000 | tr -d '\n')
VERIFIER_PUBLIC_KEY="0x${VERIFIER_PUBLIC_KEY_HEX}"

# Setup Movement CLI profile for requester
REQUESTER_PROFILE="requester-movement-testnet"

echo "   Setting up Movement CLI profile '$REQUESTER_PROFILE'..."
if ! movement config show-profiles --profile "$REQUESTER_PROFILE" &>/dev/null; then
    movement init --profile "$REQUESTER_PROFILE" \
        --network custom \
        --rest-url https://testnet.movementnetwork.xyz/v1 \
        --private-key "$MOVEMENT_REQUESTER_PRIVATE_KEY" \
        --skip-faucet \
        --assume-yes
    echo "   ✅ Profile created"
else
    echo "   ✅ Profile already exists"
fi
echo ""

# Read USDC addresses and chain IDs from testnet-assets.toml
USDC_MOVEMENT_METADATA=$(grep -A 10 "^\[movement_bardock_testnet\]" "$ASSETS_CONFIG_FILE" | grep "^usdc = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
if [ -z "$USDC_MOVEMENT_METADATA" ]; then
    echo "❌ ERROR: Movement USDC address not found in testnet-assets.toml"
    exit 1
fi

USDC_BASE_METADATA=$(grep -A 10 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^usdc = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
if [ -z "$USDC_BASE_METADATA" ]; then
    echo "❌ ERROR: Base Sepolia USDC address not found in testnet-assets.toml"
    exit 1
fi

HUB_CHAIN_ID=$(grep -A 5 "^\[movement_bardock_testnet\]" "$ASSETS_CONFIG_FILE" | grep "^chain_id = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -z "$HUB_CHAIN_ID" ]; then
    echo "❌ ERROR: Movement chain ID not found in testnet-assets.toml"
    exit 1
fi

CONNECTED_CHAIN_ID=$(grep -A 5 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^chain_id = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -z "$CONNECTED_CHAIN_ID" ]; then
    echo "❌ ERROR: Base Sepolia chain ID not found in testnet-assets.toml"
    exit 1
fi

echo "   USDC.e metadata: $USDC_MOVEMENT_METADATA"
echo "   USDC Base:       $USDC_BASE_METADATA"
echo "   Hub Chain ID:   $HUB_CHAIN_ID"
echo "   Connected Chain ID: $CONNECTED_CHAIN_ID"
echo ""

# Generate intent ID
INTENT_ID="0x$(openssl rand -hex 32)"
EXPIRY_TIME=$(date -u +%s)
EXPIRY_TIME=$((EXPIRY_TIME + 60))  # 1 minute from now (for testing)

echo "📋 Intent Configuration:"
echo "   Flow Type:        $FLOW_TYPE"
echo "   Intent ID:        $INTENT_ID"
echo "   Amount:           $AMOUNT (1 USDC = 1000000)"
# Format expiry time (portable for both macOS and Linux)
if date --version >/dev/null 2>&1; then
    # GNU date (Linux)
    EXPIRY_FORMATTED=$(date -u -d "@$EXPIRY_TIME" +"%Y-%m-%d %H:%M:%S UTC")
else
    # BSD date (macOS)
    EXPIRY_FORMATTED=$(date -u -r "$EXPIRY_TIME" +"%Y-%m-%d %H:%M:%S UTC")
fi
echo "   Expiry Time:      $EXPIRY_TIME ($EXPIRY_FORMATTED)"
echo ""

# Determine offered/desired metadata based on flow type
if [ "$FLOW_TYPE" = "inflow" ]; then
    # Inflow: Offered on Base (connected), Desired on Movement (hub)
    OFFERED_METADATA="$USDC_BASE_METADATA"
    OFFERED_CHAIN_ID=$CONNECTED_CHAIN_ID
    DESIRED_METADATA="$USDC_MOVEMENT_METADATA"
    DESIRED_CHAIN_ID=$HUB_CHAIN_ID
    echo "   Offered:          USDC on Base Sepolia ($OFFERED_METADATA)"
    echo "   Desired:           USDC.e on Movement ($DESIRED_METADATA)"
else
    # Outflow: Offered on Movement (hub), Desired on Base (connected)
    OFFERED_METADATA="$USDC_MOVEMENT_METADATA"
    OFFERED_CHAIN_ID=$HUB_CHAIN_ID
    DESIRED_METADATA="$USDC_BASE_METADATA"
    DESIRED_CHAIN_ID=$CONNECTED_CHAIN_ID
    echo "   Offered:          USDC.e on Movement ($OFFERED_METADATA)"
    echo "   Desired:           USDC on Base Sepolia ($DESIRED_METADATA)"
fi
echo ""

# Get solver address from config
SOLVER_ADDRESS=$(grep -A5 "\[solver\]" "$PROJECT_ROOT/solver/config/solver_testnet.toml" 2>/dev/null | grep "address" | head -1 | sed 's/.*= *"\(.*\)".*/\1/' || echo "")

if [ -z "$SOLVER_ADDRESS" ]; then
    # Fallback: get from .testnet-keys.env
    SOLVER_ADDRESS="$MOVEMENT_SOLVER_ADDRESS"
fi

if [ -z "$SOLVER_ADDRESS" ]; then
    echo "❌ ERROR: Could not determine solver address"
    echo "   Set MOVEMENT_SOLVER_ADDRESS in .testnet-keys.env or solver_testnet.toml"
    exit 1
fi

echo "   Solver Address:    $SOLVER_ADDRESS"
echo ""

# Record initial balances on both chains to track the full transfer
INITIAL_BASE_BALANCE=""
INITIAL_MOVEMENT_BALANCE=""
HUB_RPC="https://testnet.movementnetwork.xyz/v1"
BASE_SEPOLIA_RPC_URL=$(grep -A 5 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^rpc_url = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")

echo "📊 Initial Balances:"

# Get Movement USDC.e balance
INITIAL_MOVEMENT_BALANCE=$(get_movement_usdc_balance "$MOVEMENT_REQUESTER_ADDRESS" "$USDC_MOVEMENT_METADATA" "$HUB_RPC")
echo "   Movement (USDC.e):    $(format_usdc "$INITIAL_MOVEMENT_BALANCE")"

# Get Base Sepolia USDC balance
if [ -n "$BASE_SEPOLIA_RPC_URL" ] && [ -n "$BASE_REQUESTER_ADDRESS" ]; then
    INITIAL_BASE_BALANCE=$(get_base_usdc_balance "$BASE_REQUESTER_ADDRESS" "$USDC_BASE_METADATA" "$BASE_SEPOLIA_RPC_URL")
    echo "   Base Sepolia (USDC):  $(format_usdc "$INITIAL_BASE_BALANCE")"
fi
echo ""

# Step 1: Submit draft intent to verifier
echo "🔄 Step 1: Submitting draft intent to verifier..."

# Build draft data JSON
DRAFT_DATA=$(jq -n \
    --arg om "$OFFERED_METADATA" \
    --arg oa "$AMOUNT" \
    --arg oci "$OFFERED_CHAIN_ID" \
    --arg dm "$DESIRED_METADATA" \
    --arg da "$AMOUNT" \
    --arg dci "$DESIRED_CHAIN_ID" \
    --arg et "$EXPIRY_TIME" \
    --arg ii "$INTENT_ID" \
    --arg is "$MOVEMENT_REQUESTER_ADDRESS" \
    --arg ca "$INTENT_MODULE_ADDRESS" \
    --arg ft "$FLOW_TYPE" \
    '{
        offered_metadata: $om,
        offered_amount: $oa,
        offered_chain_id: $oci,
        desired_metadata: $dm,
        desired_amount: $da,
        desired_chain_id: $dci,
        expiry_time: ($et | tonumber),
        intent_id: $ii,
        issuer: $is,
        chain_addr: $ca,
        flow_type: $ft
    }')

# Submit draft
DRAFT_RESPONSE=$(curl -s -X POST "$VERIFIER_URL/draftintent" \
    -H "Content-Type: application/json" \
    -d "{
        \"requester_addr\": \"$MOVEMENT_REQUESTER_ADDRESS\",
        \"draft_data\": $DRAFT_DATA,
        \"expiry_time\": $EXPIRY_TIME
    }")

DRAFT_ID=$(echo "$DRAFT_RESPONSE" | jq -r '.data.draft_id // empty')

if [ -z "$DRAFT_ID" ] || [ "$DRAFT_ID" = "null" ]; then
    echo "❌ ERROR: Failed to submit draft intent"
    echo "   Response: $DRAFT_RESPONSE"
    exit 1
fi

echo "   ✅ Draft submitted (ID: $DRAFT_ID)"
echo ""

# Step 2: Wait for solver to sign
echo "🔄 Step 2: Waiting for solver to sign draft..."
echo "   (Solver service polls verifier automatically)"
echo "   This may take a few seconds..."

MAX_ATTEMPTS=30
ATTEMPT=0
SIGNATURE_DATA=""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
    
    RESPONSE=$(curl -s "$VERIFIER_URL/draftintent/$DRAFT_ID/signature" 2>/dev/null || echo "")
    
    if [ -n "$RESPONSE" ]; then
        SIGNATURE=$(echo "$RESPONSE" | jq -r '.data.signature // empty')
        if [ -n "$SIGNATURE" ] && [ "$SIGNATURE" != "null" ]; then
            SIGNATURE_DATA="$RESPONSE"
            break
        fi
    fi
    
    echo "   Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for signature..."
done

if [ -z "$SIGNATURE_DATA" ]; then
    echo "❌ ERROR: Timeout waiting for solver signature"
    echo "   Make sure solver service is running:"
    echo "   ./testing-infra/testnet/run-solver-local.sh"
    exit 1
fi

RETRIEVED_SIGNATURE=$(echo "$SIGNATURE_DATA" | jq -r '.data.signature')
RETRIEVED_SOLVER=$(echo "$SIGNATURE_DATA" | jq -r '.data.solver_addr')

echo "   ✅ Signature received from solver: $RETRIEVED_SOLVER"
echo ""

# Step 3: Create intent on-chain
echo "🔄 Step 3: Creating intent on-chain..."

SOLVER_SIGNATURE_HEX="${RETRIEVED_SIGNATURE#0x}"
VERIFIER_PUBLIC_KEY_HEX_CLEAN="${VERIFIER_PUBLIC_KEY#0x}"

# Prepare private key (add 0x prefix if needed)
REQUESTER_PRIVATE_KEY_HEX="${MOVEMENT_REQUESTER_PRIVATE_KEY}"
if [[ ! "$REQUESTER_PRIVATE_KEY_HEX" == 0x* ]]; then
    REQUESTER_PRIVATE_KEY_HEX="0x${REQUESTER_PRIVATE_KEY_HEX}"
fi

HUB_RPC_URL="https://testnet.movementnetwork.xyz/v1"

if [ "$FLOW_TYPE" = "inflow" ]; then
    # Inflow intent
    movement move run --private-key "$REQUESTER_PRIVATE_KEY_HEX" --url "$HUB_RPC_URL" --assume-yes \
        --function-id "${INTENT_MODULE_ADDRESS}::fa_intent_inflow::create_inflow_intent_entry" \
        --args "address:${OFFERED_METADATA}" "u64:${AMOUNT}" "u64:${OFFERED_CHAIN_ID}" \
               "address:${DESIRED_METADATA}" "u64:${AMOUNT}" "u64:${DESIRED_CHAIN_ID}" \
               "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" \
               "address:${RETRIEVED_SOLVER}" "hex:${SOLVER_SIGNATURE_HEX}"
else
    # Outflow intent (requires requester address on connected chain)
    if [ -z "$BASE_REQUESTER_ADDRESS" ]; then
        echo "❌ ERROR: BASE_REQUESTER_ADDRESS not set in .testnet-keys.env"
        echo "   Outflow intents require the requester's address on the connected chain"
        exit 1
    fi
    
    movement move run --private-key "$REQUESTER_PRIVATE_KEY_HEX" --url "$HUB_RPC_URL" --assume-yes \
        --function-id "${INTENT_MODULE_ADDRESS}::fa_intent_outflow::create_outflow_intent_entry" \
        --args "address:${OFFERED_METADATA}" "u64:${AMOUNT}" "u64:${OFFERED_CHAIN_ID}" \
               "address:${DESIRED_METADATA}" "u64:${AMOUNT}" "u64:${DESIRED_CHAIN_ID}" \
               "u64:${EXPIRY_TIME}" "address:${INTENT_ID}" \
               "address:${BASE_REQUESTER_ADDRESS}" \
               "hex:${VERIFIER_PUBLIC_KEY_HEX_CLEAN}" \
               "address:${RETRIEVED_SOLVER}" "hex:${SOLVER_SIGNATURE_HEX}"
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Intent created on Movement!"
    echo ""
    echo "📋 Intent Details:"
    echo "   Intent ID:        $INTENT_ID"
    echo "   Draft ID:         $DRAFT_ID"
    echo "   Flow Type:        $FLOW_TYPE"
    echo "   Solver:           $RETRIEVED_SOLVER"
    echo ""
    
    if [ "$FLOW_TYPE" = "inflow" ]; then
        # Step 4: Create escrow on Base Sepolia for inflow intents
        echo "🔄 Step 4: Creating escrow on Base Sepolia..."
        
        # Check required variables for escrow creation
        if [ -z "$BASE_REQUESTER_PRIVATE_KEY" ]; then
            echo "⚠️  WARNING: BASE_REQUESTER_PRIVATE_KEY not set in .testnet-keys.env"
            echo "   Cannot automatically create escrow. Manual steps required:"
            echo ""
            echo "💡 Next steps (manual):"
            echo "   1. Create escrow on Base Sepolia with intent ID: $INTENT_ID"
            echo "   2. Solver will fulfill intent when escrow is deposited"
            exit 0
        fi
        
        if [ -z "$BASE_SOLVER_ADDRESS" ]; then
            echo "⚠️  WARNING: BASE_SOLVER_ADDRESS not set in .testnet-keys.env"
            echo "   Cannot automatically create escrow. Manual steps required:"
            echo ""
            echo "💡 Next steps (manual):"
            echo "   1. Create escrow on Base Sepolia with intent ID: $INTENT_ID"
            echo "   2. Solver will fulfill intent when escrow is deposited"
            exit 0
        fi
        
        # Get escrow contract address from verifier config
        ESCROW_CONTRACT_ADDRESS=$(grep -A5 "\[connected_chain_evm\]" "$VERIFIER_CONFIG" | grep "escrow_contract_addr" | head -1 | sed 's/.*= *"\(.*\)".*/\1/')
        
        if [ -z "$ESCROW_CONTRACT_ADDRESS" ]; then
            echo "⚠️  WARNING: escrow_contract_addr not found in verifier_testnet.toml"
            echo "   Cannot automatically create escrow. Manual steps required:"
            echo ""
            echo "💡 Next steps (manual):"
            echo "   1. Create escrow on Base Sepolia with intent ID: $INTENT_ID"
            echo "   2. Solver will fulfill intent when escrow is deposited"
            exit 0
        fi
        
        # Get Base Sepolia RPC URL from assets config
        BASE_SEPOLIA_RPC_URL=$(grep -A 5 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^rpc_url = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
        
        if [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
            echo "⚠️  WARNING: Base Sepolia RPC URL not found in testnet-assets.toml"
            echo "   Cannot automatically create escrow."
            exit 1
        fi
        
        echo "   Escrow Contract: $ESCROW_CONTRACT_ADDRESS"
        echo "   Token (USDC):    $USDC_BASE_METADATA"
        echo "   Amount:          $AMOUNT"
        echo "   Solver:          $BASE_SOLVER_ADDRESS"
        echo ""
        
        # Run the create-escrow script
        cd "$PROJECT_ROOT/evm-intent-framework"
        
        # Install dependencies if needed
        if [ ! -d "node_modules" ]; then
            echo "   Installing npm dependencies..."
            npm install --silent
        fi
        
        ESCROW_CONTRACT_ADDRESS="$ESCROW_CONTRACT_ADDRESS" \
        INTENT_ID="$INTENT_ID" \
        TOKEN_ADDRESS="$USDC_BASE_METADATA" \
        AMOUNT="$AMOUNT" \
        SOLVER_ADDRESS="$BASE_SOLVER_ADDRESS" \
        REQUESTER_PRIVATE_KEY="$BASE_REQUESTER_PRIVATE_KEY" \
        RPC_URL="$BASE_SEPOLIA_RPC_URL" \
        npx hardhat run scripts/create-escrow.js --network baseSepolia
        
        ESCROW_EXIT_CODE=$?
        
        cd "$PROJECT_ROOT"
        
        if [ $ESCROW_EXIT_CODE -eq 0 ]; then
            echo ""
            echo "🎉 Inflow intent complete!"
            echo ""
            echo "💡 Next steps:"
            echo "   1. Solver will detect the escrow deposit"
            echo "   2. Solver will fulfill intent on Movement (send USDC.e to requester)"
            echo "   3. Solver will claim USDC from escrow on Base Sepolia"
        else
            echo ""
            echo "⚠️  Escrow creation failed. Intent was created on Movement."
            echo ""
            echo "💡 Manual steps required:"
            echo "   1. Create escrow on Base Sepolia with intent ID: $INTENT_ID"
            echo "   2. Solver will fulfill intent when escrow is deposited"
        fi
    else
        echo "🎉 Outflow intent created!"
        echo ""
        
        # Wait for fulfillment on Base Sepolia
        if [ -n "$INITIAL_BASE_BALANCE" ] && [ -n "$BASE_SEPOLIA_RPC_URL" ] && [ -n "$BASE_REQUESTER_ADDRESS" ]; then
            echo "⏳ Waiting for solver to fulfill on Base Sepolia..."
            echo "   (timeout: 90 seconds)"
            echo ""
            
            MAX_WAIT=90
            POLL_INTERVAL=5
            WAITED=0
            FULFILLED=false
            
            while [ $WAITED -lt $MAX_WAIT ]; do
                CURRENT_BASE_BALANCE=$(get_base_usdc_balance "$BASE_REQUESTER_ADDRESS" "$USDC_BASE_METADATA" "$BASE_SEPOLIA_RPC_URL")
                
                if [ "$CURRENT_BASE_BALANCE" -gt "$INITIAL_BASE_BALANCE" ]; then
                    FULFILLED=true
                    echo "✅ Fulfillment received on Base Sepolia!"
                    echo ""
                    break
                fi
                
                printf "   Waiting... (%ds/%ds)\r" $WAITED $MAX_WAIT
                sleep $POLL_INTERVAL
                WAITED=$((WAITED + POLL_INTERVAL))
            done
            
            if [ "$FULFILLED" = "true" ]; then
                # Get final balances on both chains
                FINAL_MOVEMENT_BALANCE=$(get_movement_usdc_balance "$MOVEMENT_REQUESTER_ADDRESS" "$USDC_MOVEMENT_METADATA" "$HUB_RPC")
                FINAL_BASE_BALANCE=$CURRENT_BASE_BALANCE
                
                # Calculate changes
                MOVEMENT_CHANGE=$((FINAL_MOVEMENT_BALANCE - INITIAL_MOVEMENT_BALANCE))
                BASE_CHANGE=$((FINAL_BASE_BALANCE - INITIAL_BASE_BALANCE))
                
                echo "📊 Final Balances (Outflow: Movement → Base Sepolia):"
                echo ""
                echo "   Movement (USDC.e):"
                echo "     Before:  $(format_usdc "$INITIAL_MOVEMENT_BALANCE")"
                echo "     After:   $(format_usdc "$FINAL_MOVEMENT_BALANCE")"
                echo "     Change:  $MOVEMENT_CHANGE ($(echo "scale=6; $MOVEMENT_CHANGE / 1000000" | bc 2>/dev/null || echo "?") USDC)"
                echo ""
                echo "   Base Sepolia (USDC):"
                echo "     Before:  $(format_usdc "$INITIAL_BASE_BALANCE")"
                echo "     After:   $(format_usdc "$FINAL_BASE_BALANCE")"
                echo "     Change:  +$BASE_CHANGE (+$(echo "scale=6; $BASE_CHANGE / 1000000" | bc 2>/dev/null || echo "?") USDC)"
            else
                echo ""
                echo "⏰ Timeout waiting for fulfillment."
                echo "   The solver may still be processing. Check logs."
            fi
        else
            echo "💡 Next steps:"
            echo "   1. Tokens are locked on Movement chain"
            echo "   2. Solver will transfer tokens on Base Sepolia"
            echo "   3. Verifier will approve fulfillment"
            echo "   4. Solver will claim locked tokens on Movement"
        fi
    fi
else
    echo ""
    echo "❌ ERROR: Failed to create intent on-chain"
    exit 1
fi

