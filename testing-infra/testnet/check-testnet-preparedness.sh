#!/bin/bash

# Check Testnet Preparedness Script
# Checks balances and deployed contracts for testnet readiness
# 
# Checks:
#   1. Account balances (MOVE, ETH, USDC/USDC.e)
#   2. Deployed contracts (Movement Intent Module, Base Escrow)
#
# Supports:
#   - Movement Bardock Testnet (MOVE, USDC.e)
#   - Base Sepolia (ETH, USDC)
#   - Ethereum Sepolia (ETH, USDC)
# 
# Assets Config: testing-infra/testnet/config/testnet-assets.toml
# Service Configs: trusted-verifier/config/verifier_testnet.toml, solver/config/solver_testnet.toml (gitignored)
# Keys: .testnet-keys.env

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
export PROJECT_ROOT

# Source utilities (for error handling only, not logging)
source "$PROJECT_ROOT/testing-infra/ci-e2e/util.sh" 2>/dev/null || true

echo "🔍 Checking Testnet Preparedness"
echo "================================="
echo ""

# Load .testnet-keys.env
TESTNET_KEYS_FILE="$PROJECT_ROOT/.testnet-keys.env"

if [ ! -f "$TESTNET_KEYS_FILE" ]; then
    echo "❌ ERROR: .testnet-keys.env not found at $TESTNET_KEYS_FILE"
    echo "   Create it from env.testnet.example first"
    exit 1
fi

# Source the keys file
source "$TESTNET_KEYS_FILE"

# Load assets configuration
ASSETS_CONFIG_FILE="$PROJECT_ROOT/testing-infra/testnet/config/testnet-assets.toml"

if [ ! -f "$ASSETS_CONFIG_FILE" ]; then
    echo "❌ ERROR: testnet-assets.toml not found at $ASSETS_CONFIG_FILE"
    echo "   Asset addresses must be configured in testing-infra/testnet/config/testnet-assets.toml"
    exit 1
fi

# Parse TOML config (simple grep-based parser)
# Extract Base Sepolia USDC address and decimals
BASE_USDC_ADDRESS=$(grep -A 20 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^usdc = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
BASE_USDC_DECIMALS=$(grep -A 20 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^usdc_decimals = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -z "$BASE_USDC_ADDRESS" ]; then
    echo "⚠️  WARNING: Base Sepolia USDC address not found in testnet-assets.toml"
    echo "   Base Sepolia USDC balance checks will be skipped"
elif [ -z "$BASE_USDC_DECIMALS" ]; then
    echo "❌ ERROR: Base Sepolia USDC decimals not found in testnet-assets.toml"
    echo "   Add usdc_decimals = 6 to [base_sepolia] section"
    exit 1
fi

# Extract Ethereum Sepolia USDC address and decimals
SEPOLIA_USDC_ADDRESS=$(grep -A 20 "^\[ethereum_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^usdc = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
SEPOLIA_USDC_DECIMALS=$(grep -A 20 "^\[ethereum_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^usdc_decimals = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -z "$SEPOLIA_USDC_ADDRESS" ]; then
    echo "⚠️  WARNING: Ethereum Sepolia USDC address not found in testnet-assets.toml"
    echo "   Ethereum Sepolia USDC balance checks will be skipped"
elif [ -z "$SEPOLIA_USDC_DECIMALS" ]; then
    echo "❌ ERROR: Ethereum Sepolia USDC decimals not found in testnet-assets.toml"
    echo "   Add usdc_decimals = 6 to [ethereum_sepolia] section"
    exit 1
fi

# Extract Movement USDC address and decimals
MOVEMENT_USDC_ADDRESS=$(grep -A 20 "^\[movement_bardock_testnet\]" "$ASSETS_CONFIG_FILE" | grep "^usdc = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
MOVEMENT_USDC_DECIMALS=$(grep -A 20 "^\[movement_bardock_testnet\]" "$ASSETS_CONFIG_FILE" | grep "^usdc_decimals = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -n "$MOVEMENT_USDC_ADDRESS" ] && [ -z "$MOVEMENT_USDC_DECIMALS" ]; then
    echo "❌ ERROR: Movement USDC.e address configured but decimals not found in testnet-assets.toml"
    echo "   Add usdc_decimals = 6 to [movement_bardock_testnet] section"
    exit 1
fi

# Extract native token decimals
MOVEMENT_NATIVE_DECIMALS=$(grep -A 10 "^\[movement_bardock_testnet\]" "$ASSETS_CONFIG_FILE" | grep "^native_token_decimals = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -z "$MOVEMENT_NATIVE_DECIMALS" ]; then
    echo "❌ ERROR: Movement native token decimals not found in testnet-assets.toml"
    echo "   Add native_token_decimals = 8 to [movement_bardock_testnet] section"
    exit 1
fi

BASE_NATIVE_DECIMALS=$(grep -A 10 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^native_token_decimals = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -z "$BASE_NATIVE_DECIMALS" ]; then
    echo "❌ ERROR: Base Sepolia native token decimals not found in testnet-assets.toml"
    echo "   Add native_token_decimals = 18 to [base_sepolia] section"
    exit 1
fi

SEPOLIA_NATIVE_DECIMALS=$(grep -A 10 "^\[ethereum_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^native_token_decimals = " | sed 's/.*= \([0-9]*\).*/\1/' || echo "")
if [ -z "$SEPOLIA_NATIVE_DECIMALS" ]; then
    echo "❌ ERROR: Ethereum Sepolia native token decimals not found in testnet-assets.toml"
    echo "   Add native_token_decimals = 18 to [ethereum_sepolia] section"
    exit 1
fi

# Extract RPC URLs
MOVEMENT_RPC_URL=$(grep -A 5 "^\[movement_bardock_testnet\]" "$ASSETS_CONFIG_FILE" | grep "^rpc_url = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
if [ -z "$MOVEMENT_RPC_URL" ]; then
    echo "⚠️  WARNING: Movement RPC URL not found in testnet-assets.toml"
    echo "   Movement balance checks will fail"
fi

BASE_RPC_URL=$(grep -A 5 "^\[base_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^rpc_url = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
if [ -z "$BASE_RPC_URL" ]; then
    echo "⚠️  WARNING: Base Sepolia RPC URL not found in testnet-assets.toml"
    echo "   Base Sepolia balance checks will fail"
fi

# Substitute API key in Base Sepolia RPC URL if placeholder is present
if [[ "$BASE_RPC_URL" == *"ALCHEMY_API_KEY"* ]]; then
    if [ -n "$ALCHEMY_BASE_SEPOLIA_API_KEY" ]; then
        BASE_RPC_URL="${BASE_RPC_URL/ALCHEMY_API_KEY/$ALCHEMY_BASE_SEPOLIA_API_KEY}"
    else
        echo "⚠️  WARNING: ALCHEMY_BASE_SEPOLIA_API_KEY not set in .testnet-keys.env"
        echo "   Base Sepolia balance checks will fail"
    fi
fi

SEPOLIA_RPC_URL=$(grep -A 5 "^\[ethereum_sepolia\]" "$ASSETS_CONFIG_FILE" | grep "^rpc_url = " | sed 's/.*= "\(.*\)".*/\1/' | tr -d '"' || echo "")
if [ -z "$SEPOLIA_RPC_URL" ]; then
    echo "⚠️  WARNING: Ethereum Sepolia RPC URL not found in testnet-assets.toml"
    echo "   Ethereum Sepolia balance checks will fail"
fi

# Substitute API key in Sepolia RPC URL if placeholder is present
if [[ "$SEPOLIA_RPC_URL" == *"ALCHEMY_API_KEY"* ]]; then
    if [ -n "$ALCHEMY_ETH_SEPOLIA_API_KEY" ]; then
        SEPOLIA_RPC_URL="${SEPOLIA_RPC_URL/ALCHEMY_API_KEY/$ALCHEMY_ETH_SEPOLIA_API_KEY}"
    else
        echo "⚠️  WARNING: ALCHEMY_ETH_SEPOLIA_API_KEY not set in .testnet-keys.env"
        echo "   Ethereum Sepolia balance checks will fail"
    fi
fi

# Function to get Movement balance (MOVE tokens)
# Uses the view function API to get balance (works with both CoinStore and FA systems)
get_movement_balance() {
    local address="$1"
    # Ensure address has 0x prefix
    if [[ ! "$address" =~ ^0x ]]; then
        address="0x${address}"
    fi
    
    # Query balance via view function API (with 10 second timeout)
    local balance=$(curl -s --max-time 10 -X POST "${MOVEMENT_RPC_URL}/view" \
        -H "Content-Type: application/json" \
        -d "{\"function\":\"0x1::coin::balance\",\"type_arguments\":[\"0x1::aptos_coin::AptosCoin\"],\"arguments\":[\"$address\"]}" \
        | jq -r '.[0] // "0"' 2>/dev/null)
    
    if [ -z "$balance" ] || [ "$balance" = "null" ]; then
        echo "0"
    else
        echo "$balance"
    fi
}

# Function to get Movement USDC balance (Fungible Asset)
get_movement_usdc_balance() {
    local address="$1"
    # Ensure address has 0x prefix
    if [[ ! "$address" =~ ^0x ]]; then
        address="0x${address}"
    fi
    
    # If USDC address is not configured, return 0
    if [ -z "$MOVEMENT_USDC_ADDRESS" ] || [ "$MOVEMENT_USDC_ADDRESS" = "" ]; then
        echo "0"
        return
    fi
    
    # Query USDC.e balance via view function API (Fungible Asset)
    # USDC.e is deployed as a Fungible Asset, use primary_fungible_store::balance
    local balance=$(curl -s --max-time 10 -X POST "${MOVEMENT_RPC_URL}/view" \
        -H "Content-Type: application/json" \
        -d "{\"function\":\"0x1::primary_fungible_store::balance\",\"type_arguments\":[\"0x1::fungible_asset::Metadata\"],\"arguments\":[\"$address\",\"${MOVEMENT_USDC_ADDRESS}\"]}" \
        | jq -r '.[0] // "0"' 2>/dev/null)
    
    if [ -z "$balance" ] || [ "$balance" = "null" ]; then
        echo "0"
    else
        echo "$balance"
    fi
}

# Function to get EVM ETH balance (works for any EVM chain)
get_evm_eth_balance() {
    local address="$1"
    local rpc_url="$2"
    
    # Ensure address has 0x prefix
    if [[ ! "$address" =~ ^0x ]]; then
        address="0x${address}"
    fi
    
    # Query balance via JSON-RPC (with 10 second timeout)
    local balance_hex=$(curl -s --max-time 10 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$address\",\"latest\"],\"id\":1}" \
        | jq -r '.result // "0x0"' 2>/dev/null)
    
    if [ -z "$balance_hex" ] || [ "$balance_hex" = "null" ] || [ "$balance_hex" = "0x0" ]; then
        echo "0"
    else
        # Convert hex to decimal (remove 0x, uppercase, use bc for large numbers)
        local hex_no_prefix="${balance_hex#0x}"
        local hex_upper=$(echo "$hex_no_prefix" | tr '[:lower:]' '[:upper:]')
        echo "obase=10; ibase=16; $hex_upper" | bc 2>/dev/null || echo "0"
    fi
}

# Function to get ERC20 token balance (works for any EVM chain)
get_evm_token_balance() {
    local address="$1"
    local token_address="$2"
    local rpc_url="$3"
    
    # Ensure addresses have 0x prefix
    if [[ ! "$address" =~ ^0x ]]; then
        address="0x${address}"
    fi
    if [[ ! "$token_address" =~ ^0x ]]; then
        token_address="0x${token_address}"
    fi
    
    # ERC20 balanceOf(address) - function selector: 0x70a08231
    # Pad address to 64 hex characters (32 bytes) with leading zeros
    local addr_no_prefix="${address#0x}"
    local addr_padded=$(printf "%064s" "$addr_no_prefix" | sed 's/ /0/g')
    local data="0x70a08231$addr_padded"
    
    local balance_hex=$(curl -s --max-time 10 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$token_address\",\"data\":\"$data\"},\"latest\"],\"id\":1}" \
        | jq -r '.result // "0x0"' 2>/dev/null)
    
    if [ -z "$balance_hex" ] || [ "$balance_hex" = "null" ] || [ "$balance_hex" = "0x0" ]; then
        echo "0"
    else
        # Convert hex to decimal (remove 0x, uppercase, use bc for large numbers)
        local hex_no_prefix="${balance_hex#0x}"
        local hex_upper=$(echo "$hex_no_prefix" | tr '[:lower:]' '[:upper:]')
        echo "obase=10; ibase=16; $hex_upper" | bc 2>/dev/null || echo "0"
    fi
}

# Wrapper functions for backwards compatibility
get_base_eth_balance() {
    get_evm_eth_balance "$1" "$BASE_RPC_URL"
}

get_base_token_balance() {
    get_evm_token_balance "$1" "$2" "$BASE_RPC_URL"
}

# Format balance for display
format_balance() {
    local balance="$1"
    local decimals="$2"
    local symbol="${3:-}"
    
    # Convert from smallest unit to human-readable
    # Decimals must be provided (read from testnet-assets.toml config)
    local divisor
    case "$decimals" in
        18) divisor="1000000000000000000" ;;
        8)  divisor="100000000" ;;
        6)  divisor="1000000" ;;
        *)  divisor="1" ;;
    esac
    
    local formatted=$(echo "scale=6; $balance / $divisor" | bc 2>/dev/null || echo "0")
    
    if [ -n "$symbol" ]; then
        printf "%.6f %s" "$formatted" "$symbol"
    else
        case "$decimals" in
            18) printf "%.6f ETH" "$formatted" ;;
            8)  printf "%.6f MOVE" "$formatted" ;;
            6)  printf "%.6f USDC" "$formatted" ;;
            *)  printf "%s" "$balance" ;;
        esac
    fi
}

# Check Movement balances
echo "📊 Movement Bardock Testnet"
echo "----------------------------"
echo "   RPC: $MOVEMENT_RPC_URL"

if [ -z "$MOVEMENT_DEPLOYER_ADDRESS" ]; then
    echo "⚠️  MOVEMENT_DEPLOYER_ADDRESS not set in .testnet-keys.env"
else
    balance=$(get_movement_balance "$MOVEMENT_DEPLOYER_ADDRESS")
    formatted=$(format_balance "$balance" "$MOVEMENT_NATIVE_DECIMALS")
    usdc_balance=$(get_movement_usdc_balance "$MOVEMENT_DEPLOYER_ADDRESS")
    echo "   Deployer  ($MOVEMENT_DEPLOYER_ADDRESS)"
    if [ -n "$MOVEMENT_USDC_ADDRESS" ]; then
        usdc_formatted=$(format_balance "$usdc_balance" "$MOVEMENT_USDC_DECIMALS" "USDC.e")
        echo "             $formatted, $usdc_formatted"
    else
        echo "             $formatted (USDC.e n/a)"
    fi
fi

if [ -z "$MOVEMENT_REQUESTER_ADDRESS" ]; then
    echo "⚠️  MOVEMENT_REQUESTER_ADDRESS not set in .testnet-keys.env"
else
    balance=$(get_movement_balance "$MOVEMENT_REQUESTER_ADDRESS")
    formatted=$(format_balance "$balance" "$MOVEMENT_NATIVE_DECIMALS")
    usdc_balance=$(get_movement_usdc_balance "$MOVEMENT_REQUESTER_ADDRESS")
    echo "   Requester ($MOVEMENT_REQUESTER_ADDRESS)"
    if [ -n "$MOVEMENT_USDC_ADDRESS" ]; then
        usdc_formatted=$(format_balance "$usdc_balance" "$MOVEMENT_USDC_DECIMALS" "USDC.e")
        echo "             $formatted, $usdc_formatted"
    else
        echo "             $formatted (USDC.e n/a)"
    fi
fi

if [ -z "$MOVEMENT_SOLVER_ADDRESS" ]; then
    echo "⚠️  MOVEMENT_SOLVER_ADDRESS not set in .testnet-keys.env"
else
    balance=$(get_movement_balance "$MOVEMENT_SOLVER_ADDRESS")
    formatted=$(format_balance "$balance" "$MOVEMENT_NATIVE_DECIMALS")
    usdc_balance=$(get_movement_usdc_balance "$MOVEMENT_SOLVER_ADDRESS")
    echo "   Solver    ($MOVEMENT_SOLVER_ADDRESS)"
    if [ -n "$MOVEMENT_USDC_ADDRESS" ]; then
        usdc_formatted=$(format_balance "$usdc_balance" "$MOVEMENT_USDC_DECIMALS" "USDC.e")
        echo "             $formatted, $usdc_formatted"
    else
        echo "             $formatted (USDC.e n/a)"
    fi
fi

echo ""

# Check Base Sepolia balances
echo "📊 Base Sepolia"
echo "---------------"
echo "   RPC: $BASE_RPC_URL"

if [ -z "$BASE_DEPLOYER_ADDRESS" ]; then
    echo "⚠️  BASE_DEPLOYER_ADDRESS not set in .testnet-keys.env"
else
    eth_balance=$(get_base_eth_balance "$BASE_DEPLOYER_ADDRESS")
    eth_formatted=$(format_balance "$eth_balance" "$BASE_NATIVE_DECIMALS")
    echo "   Deployer  ($BASE_DEPLOYER_ADDRESS)"
    if [ -n "$BASE_USDC_ADDRESS" ]; then
        usdc_balance=$(get_base_token_balance "$BASE_DEPLOYER_ADDRESS" "$BASE_USDC_ADDRESS")
        usdc_formatted=$(format_balance "$usdc_balance" "$BASE_USDC_DECIMALS" "USDC")
        echo "             $eth_formatted, $usdc_formatted"
    else
        echo "             $eth_formatted (USDC n/a)"
    fi
fi

if [ -z "$BASE_REQUESTER_ADDRESS" ]; then
    echo "⚠️  BASE_REQUESTER_ADDRESS not set in .testnet-keys.env"
else
    eth_balance=$(get_base_eth_balance "$BASE_REQUESTER_ADDRESS")
    eth_formatted=$(format_balance "$eth_balance" "$BASE_NATIVE_DECIMALS")
    echo "   Requester ($BASE_REQUESTER_ADDRESS)"
    if [ -n "$BASE_USDC_ADDRESS" ]; then
        usdc_balance=$(get_base_token_balance "$BASE_REQUESTER_ADDRESS" "$BASE_USDC_ADDRESS")
        usdc_formatted=$(format_balance "$usdc_balance" "$BASE_USDC_DECIMALS" "USDC")
        echo "             $eth_formatted, $usdc_formatted"
    else
        echo "             $eth_formatted (USDC n/a)"
    fi
fi

if [ -z "$BASE_SOLVER_ADDRESS" ]; then
    echo "⚠️  BASE_SOLVER_ADDRESS not set in .testnet-keys.env"
else
    eth_balance=$(get_base_eth_balance "$BASE_SOLVER_ADDRESS")
    eth_formatted=$(format_balance "$eth_balance" "$BASE_NATIVE_DECIMALS")
    echo "   Solver    ($BASE_SOLVER_ADDRESS)"
    if [ -n "$BASE_USDC_ADDRESS" ]; then
        usdc_balance=$(get_base_token_balance "$BASE_SOLVER_ADDRESS" "$BASE_USDC_ADDRESS")
        usdc_formatted=$(format_balance "$usdc_balance" "$BASE_USDC_DECIMALS" "USDC")
        echo "             $eth_formatted, $usdc_formatted"
    else
        echo "             $eth_formatted (USDC n/a)"
    fi
fi

echo ""

# Check Ethereum Sepolia balances (using same addresses as Base - EVM addresses work across chains)
echo "📊 Ethereum Sepolia"
echo "-------------------"
echo "   RPC: $SEPOLIA_RPC_URL"
echo "   (Using same addresses as Base Sepolia)"

if [ -z "$BASE_DEPLOYER_ADDRESS" ]; then
    echo "⚠️  BASE_DEPLOYER_ADDRESS not set in .testnet-keys.env"
else
    eth_balance=$(get_evm_eth_balance "$BASE_DEPLOYER_ADDRESS" "$SEPOLIA_RPC_URL")
    eth_formatted=$(format_balance "$eth_balance" "$SEPOLIA_NATIVE_DECIMALS")
    echo "   Deployer  ($BASE_DEPLOYER_ADDRESS)"
    if [ -n "$SEPOLIA_USDC_ADDRESS" ]; then
        usdc_balance=$(get_evm_token_balance "$BASE_DEPLOYER_ADDRESS" "$SEPOLIA_USDC_ADDRESS" "$SEPOLIA_RPC_URL")
        usdc_formatted=$(format_balance "$usdc_balance" "$SEPOLIA_USDC_DECIMALS" "USDC")
        echo "             $eth_formatted, $usdc_formatted"
    else
        echo "             $eth_formatted (USDC n/a)"
    fi
fi

if [ -z "$BASE_REQUESTER_ADDRESS" ]; then
    echo "⚠️  BASE_REQUESTER_ADDRESS not set in .testnet-keys.env"
else
    eth_balance=$(get_evm_eth_balance "$BASE_REQUESTER_ADDRESS" "$SEPOLIA_RPC_URL")
    eth_formatted=$(format_balance "$eth_balance" "$SEPOLIA_NATIVE_DECIMALS")
    echo "   Requester ($BASE_REQUESTER_ADDRESS)"
    if [ -n "$SEPOLIA_USDC_ADDRESS" ]; then
        usdc_balance=$(get_evm_token_balance "$BASE_REQUESTER_ADDRESS" "$SEPOLIA_USDC_ADDRESS" "$SEPOLIA_RPC_URL")
        usdc_formatted=$(format_balance "$usdc_balance" "$SEPOLIA_USDC_DECIMALS" "USDC")
        echo "             $eth_formatted, $usdc_formatted"
    else
        echo "             $eth_formatted (USDC n/a)"
    fi
fi

if [ -z "$BASE_SOLVER_ADDRESS" ]; then
    echo "⚠️  BASE_SOLVER_ADDRESS not set in .testnet-keys.env"
else
    eth_balance=$(get_evm_eth_balance "$BASE_SOLVER_ADDRESS" "$SEPOLIA_RPC_URL")
    eth_formatted=$(format_balance "$eth_balance" "$SEPOLIA_NATIVE_DECIMALS")
    echo "   Solver    ($BASE_SOLVER_ADDRESS)"
    if [ -n "$SEPOLIA_USDC_ADDRESS" ]; then
        usdc_balance=$(get_evm_token_balance "$BASE_SOLVER_ADDRESS" "$SEPOLIA_USDC_ADDRESS" "$SEPOLIA_RPC_URL")
        usdc_formatted=$(format_balance "$usdc_balance" "$SEPOLIA_USDC_DECIMALS" "USDC")
        echo "             $eth_formatted, $usdc_formatted"
    else
        echo "             $eth_formatted (USDC n/a)"
    fi
fi

echo ""

# =============================================================================
# CONTRACT DEPLOYMENT STATUS
# =============================================================================

echo "📦 Deployed Contracts"
echo "---------------------"

# Check Movement Intent Module
check_movement_module() {
    local module_address="$1"
    
    # Ensure address has 0x prefix
    if [[ ! "$module_address" =~ ^0x ]]; then
        module_address="0x${module_address}"
    fi
    
    # Query account modules to check if intent module exists
    local response=$(curl -s --max-time 10 "${MOVEMENT_RPC_URL}/accounts/${module_address}/modules" 2>/dev/null)
    
    if echo "$response" | jq -e '.[].abi.name' 2>/dev/null | grep -q "intent"; then
        echo "✅"
    else
        echo "❌"
    fi
}

# Check Base Escrow Contract (EVM)
check_evm_contract() {
    local contract_address="$1"
    local rpc_url="$2"
    
    # Ensure address has 0x prefix
    if [[ ! "$contract_address" =~ ^0x ]]; then
        contract_address="0x${contract_address}"
    fi
    
    # Query contract code
    local code=$(curl -s --max-time 10 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$contract_address\",\"latest\"],\"id\":1}" \
        | jq -r '.result // "0x"' 2>/dev/null)
    
    if [ -n "$code" ] && [ "$code" != "0x" ] && [ "$code" != "null" ]; then
        echo "✅"
    else
        echo "❌"
    fi
}

# Movement Intent Module
# Read from verifier_testnet.toml (gitignored config file)
VERIFIER_CONFIG="$PROJECT_ROOT/trusted-verifier/config/verifier_testnet.toml"
if [ -f "$VERIFIER_CONFIG" ]; then
    MOVEMENT_INTENT_MODULE_ADDRESS=$(grep -A5 "\[hub_chain\]" "$VERIFIER_CONFIG" | grep "intent_module_address" | sed 's/.*= *"\(.*\)".*/\1/' | tr -d '"' || echo "")
fi

if [ -z "$MOVEMENT_INTENT_MODULE_ADDRESS" ] || [ "$MOVEMENT_INTENT_MODULE_ADDRESS" = "" ]; then
    echo "   Movement Intent Module: ⏳ Not configured (check verifier_testnet.toml)"
else
    status=$(check_movement_module "$MOVEMENT_INTENT_MODULE_ADDRESS")
    echo "   Movement Intent Module ($MOVEMENT_INTENT_MODULE_ADDRESS)"
    echo "             Status: $status Deployed"
fi

# Base Escrow Contract
# Read from verifier_testnet.toml (gitignored config file)
if [ -f "$VERIFIER_CONFIG" ]; then
    BASE_ESCROW_CONTRACT_ADDRESS=$(grep -A5 "\[connected_chain_evm\]" "$VERIFIER_CONFIG" | grep "escrow_contract_address" | sed 's/.*= *"\(.*\)".*/\1/' | tr -d '"' || echo "")
fi

if [ -z "$BASE_ESCROW_CONTRACT_ADDRESS" ] || [ "$BASE_ESCROW_CONTRACT_ADDRESS" = "" ]; then
    echo "   Base Escrow Contract:   ⏳ Not configured (check verifier_testnet.toml)"
else
    status=$(check_evm_contract "$BASE_ESCROW_CONTRACT_ADDRESS" "$BASE_RPC_URL")
    echo "   Base Escrow Contract ($BASE_ESCROW_CONTRACT_ADDRESS)"
    echo "             Status: $status Deployed"
fi

echo ""

# =============================================================================
# SUMMARY
# =============================================================================

echo "📋 Summary"
echo "----------"

# Count readiness
ready_count=0
total_count=6

# Check balances
if [ -n "$MOVEMENT_DEPLOYER_ADDRESS" ]; then
    balance=$(get_movement_balance "$MOVEMENT_DEPLOYER_ADDRESS")
    if [ "$balance" != "0" ] && [ -n "$balance" ]; then
        ((ready_count++))
    fi
fi

if [ -n "$BASE_DEPLOYER_ADDRESS" ]; then
    balance=$(get_base_eth_balance "$BASE_DEPLOYER_ADDRESS")
    if [ "$balance" != "0" ] && [ -n "$balance" ]; then
        ((ready_count++))
    fi
fi

# Check requester/solver have funds
if [ -n "$MOVEMENT_REQUESTER_ADDRESS" ]; then
    balance=$(get_movement_balance "$MOVEMENT_REQUESTER_ADDRESS")
    if [ "$balance" != "0" ] && [ -n "$balance" ]; then
        ((ready_count++))
    fi
fi

if [ -n "$BASE_REQUESTER_ADDRESS" ]; then
    balance=$(get_base_eth_balance "$BASE_REQUESTER_ADDRESS")
    if [ "$balance" != "0" ] && [ -n "$balance" ]; then
        ((ready_count++))
    fi
fi

# Check contracts deployed
if [ -n "$MOVEMENT_INTENT_MODULE_ADDRESS" ] && [ "$MOVEMENT_INTENT_MODULE_ADDRESS" != "" ]; then
    ((ready_count++))
fi

if [ -n "$BASE_ESCROW_CONTRACT_ADDRESS" ] && [ "$BASE_ESCROW_CONTRACT_ADDRESS" != "" ]; then
    ((ready_count++))
fi

echo "   Readiness: $ready_count/$total_count checks passed"

if [ -z "$MOVEMENT_USDC_ADDRESS" ] || [ "$MOVEMENT_USDC_ADDRESS" = "" ]; then
    echo ""
    echo "💡 Note: Movement USDC.e address not configured in testnet-assets.toml"
fi

echo ""
echo "   Assets Config: $ASSETS_CONFIG_FILE"
echo "   Service Configs: verifier_testnet.toml, solver_testnet.toml (gitignored)"
echo "   Keys:   $TESTNET_KEYS_FILE"
echo ""
echo "✅ Preparedness check complete!"

