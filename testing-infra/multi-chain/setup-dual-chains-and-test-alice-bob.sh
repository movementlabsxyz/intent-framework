#!/bin/bash

# Setup Dual Chains and Test Alice/Bob Accounts
# This script:
# 1. Sets up dual Docker Aptos localnets
# 2. Creates and funds Alice and Bob accounts on both chains
# 3. Tests transfers between Alice and Bob on both chains
# Run this from the host machine (not inside Docker)

set -e

# Get project root (this script is typically run from project root)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Setup logging - redirect all output (echo and commands) to log file
LOG_DIR="$PROJECT_ROOT/tmp/intent-framework-logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/setup-dual-chains_${TIMESTAMP}.log"

# Helper function to print important messages to terminal (also logs them)
log_and_echo() {
    echo "$@"
    echo "$@" >> "$LOG_FILE"
}

# Helper function to write only to log file (not terminal)
log() {
    echo "$@" >> "$LOG_FILE"
}

# Expected funding amount in octas
# Note: aptos init funds accounts with 100000000, then we fund again with 100000000 = 200000000 total
EXPECTED_FUNDING_AMOUNT=200000000

log "🧪 Alice and Bob Account Testing - DUAL CHAINS"
log "=============================================="
log_and_echo "📝 All output logged to: $LOG_FILE"

log ""
log "% - - - - - - - - - - - SETUP - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Stop any existing Docker containers
log "🧹 Stopping any existing Docker containers..."
docker-compose -f testing-infra/multi-chain/docker-compose-chain1.yml down 2>/dev/null || true
docker-compose -f testing-infra/multi-chain/docker-compose-chain2.yml down 2>/dev/null || true

# Start fresh Docker localnets (both chains)
log "🚀 Starting fresh Docker Aptos localnets (dual chains)..."
./testing-infra/multi-chain/setup-dual-chains.sh

# Wait for services to be fully ready
log "⏳ Waiting for services to be fully ready..."
sleep 15

# Verify Chain 1 is running
log "🔍 Verifying Chain 1 is running..."
if ! curl -s http://127.0.0.1:8080/v1 > /dev/null; then
    log_and_echo "❌ Error: Chain 1 failed to start on port 8080"
    exit 1
fi
log "✅ Chain 1 is running"

# Verify Chain 2 is running
log "🔍 Verifying Chain 2 is running..."
if ! curl -s http://127.0.0.1:8082/v1 > /dev/null; then
    log_and_echo "❌ Error: Chain 2 failed to start on port 8082"
    exit 1
fi
log "✅ Chain 2 is running"

# Verify faucets are running
log "🔍 Verifying faucets are running..."
FAUCET1_RESPONSE=$(curl -s http://127.0.0.1:8081/ 2>/dev/null || echo "")
FAUCET2_RESPONSE=$(curl -s http://127.0.0.1:8083/ 2>/dev/null || echo "")

if [ "$FAUCET1_RESPONSE" = "tap:ok" ]; then
    log "✅ Chain 1 faucet is running"
else
    log_and_echo "❌ Error: Chain 1 faucet failed to start on port 8081"
    exit 1
fi

if [ "$FAUCET2_RESPONSE" = "tap:ok" ]; then
    log "✅ Chain 2 faucet is running"
else
    log_and_echo "❌ Error: Chain 2 faucet failed to start on port 8083"
    exit 1
fi

log_and_echo "✅ Docker chains setup"

# Show chain status (logged only, not displayed to terminal)
log ""
log "📊 Chain Status:"
CHAIN1_INFO=$(curl -s http://127.0.0.1:8080/v1 2>/dev/null)
CHAIN1_ID=$(echo "$CHAIN1_INFO" | jq -r '.chain_id // "unknown"' 2>/dev/null)
CHAIN1_HEIGHT=$(echo "$CHAIN1_INFO" | jq -r '.block_height // "unknown"' 2>/dev/null)
CHAIN1_ROLE=$(echo "$CHAIN1_INFO" | jq -r '.node_role // "unknown"' 2>/dev/null)
log "   Chain 1: ID=$CHAIN1_ID, Height=$CHAIN1_HEIGHT, Role=$CHAIN1_ROLE"

CHAIN2_INFO=$(curl -s http://127.0.0.1:8082/v1 2>/dev/null)
CHAIN2_ID=$(echo "$CHAIN2_INFO" | jq -r '.chain_id // "unknown"' 2>/dev/null)
CHAIN2_HEIGHT=$(echo "$CHAIN2_INFO" | jq -r '.block_height // "unknown"' 2>/dev/null)
CHAIN2_ROLE=$(echo "$CHAIN2_INFO" | jq -r '.node_role // "unknown"' 2>/dev/null)
log "   Chain 2: ID=$CHAIN2_ID, Height=$CHAIN2_HEIGHT, Role=$CHAIN2_ROLE"

# Clean up any existing profiles
log ""
log "🧹 Cleaning up existing CLI profiles..."
aptos config delete-profile --profile alice-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile bob-chain1 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile alice-chain2 >> "$LOG_FILE" 2>&1 || true
aptos config delete-profile --profile bob-chain2 >> "$LOG_FILE" 2>&1 || true

# Create test accounts for Chain 1
log ""
log "👥 Creating test accounts for Chain 1..."

# Create alice account for Chain 1
log "Creating alice-chain1 account for Chain 1..."
if printf "\n" | aptos init --profile alice-chain1 --network local --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Alice-chain1 account created successfully on Chain 1"
else
    log_and_echo "❌ Failed to create Alice-chain1 account on Chain 1"
    exit 1
fi

# Create bob account for Chain 1
log "Creating bob-chain1 account for Chain 1..."
if printf "\n" | aptos init --profile bob-chain1 --network local --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Bob-chain1 account created successfully on Chain 1"
else
    log_and_echo "❌ Failed to create Bob-chain1 account on Chain 1"
    exit 1
fi

# Create test accounts for Chain 2
log ""
log "👥 Creating test accounts for Chain 2..."

# Create alice account for Chain 2
log "Creating alice-chain2 account for Chain 2..."
if printf "\n" | aptos init --profile alice-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Alice-chain2 account created successfully on Chain 2"
else
    log_and_echo "❌ Failed to create Alice-chain2 account on Chain 2"
    exit 1
fi

# Create bob account for Chain 2
log "Creating bob-chain2 account for Chain 2..."
if printf "\n" | aptos init --profile bob-chain2 --network custom --rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes >> "$LOG_FILE" 2>&1; then
    log "✅ Bob-chain2 account created successfully on Chain 2"
else
    log_and_echo "❌ Failed to create Bob-chain2 account on Chain 2"
    exit 1
fi

log ""
log "% - - - - - - - - - - - FUNDING - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Fund Alice account on Chain 1
log "Funding Alice-chain1 account on Chain 1..."
ALICE_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
ALICE_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${ALICE_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$ALICE_TX_HASH" != "null" ] && [ -n "$ALICE_TX_HASH" ]; then
    log "✅ Alice-chain1 account funded successfully on Chain 1 (tx: $ALICE_TX_HASH)"
    
    # Wait for funding to be processed
    log "⏳ Waiting for Alice funding to be processed on Chain 1..."
    sleep 10
    
    # Get Alice's FA store address from transaction events
    ALICE_FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${ALICE_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$ALICE_FA_STORE" != "null" ] && [ -n "$ALICE_FA_STORE" ]; then
        ALICE_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${ALICE_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        
        if [ -z "$ALICE_BALANCE" ] || [ "$ALICE_BALANCE" = "null" ]; then
            log_and_echo "❌ ERROR: Failed to get Alice Chain 1 balance"
            exit 1
        fi
        
        if [ "$ALICE_BALANCE" != "$EXPECTED_FUNDING_AMOUNT" ]; then
            log_and_echo "❌ ERROR: Alice Chain 1 balance mismatch"
            log_and_echo "   Expected: $EXPECTED_FUNDING_AMOUNT Octas"
            log_and_echo "   Got: $ALICE_BALANCE Octas"
            exit 1
        fi
        
        log "✅ Alice Chain 1 balance verified: $ALICE_BALANCE Octas"
    else
        log_and_echo "❌ ERROR: Could not verify Alice Chain 1 balance via FA store"
        exit 1
    fi
else
    log_and_echo "❌ Failed to fund Alice account on Chain 1"
    exit 1
fi

# Fund Bob account on Chain 1
log "Funding Bob-chain1 account on Chain 1..."
BOB_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
BOB_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${BOB_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$BOB_TX_HASH" != "null" ] && [ -n "$BOB_TX_HASH" ]; then
    log "✅ Bob account funded successfully on Chain 1 (tx: $BOB_TX_HASH)"
    
    # Wait for funding to be processed
    log "⏳ Waiting for Bob funding to be processed on Chain 1..."
    sleep 10
    
    # Get Bob's FA store address from transaction events
    BOB_FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${BOB_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$BOB_FA_STORE" != "null" ] && [ -n "$BOB_FA_STORE" ]; then
        BOB_BALANCE=$(curl -s "http://127.0.0.1:8080/v1/accounts/${BOB_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        
        if [ -z "$BOB_BALANCE" ] || [ "$BOB_BALANCE" = "null" ]; then
            log_and_echo "❌ ERROR: Failed to get Bob Chain 1 balance"
            exit 1
        fi
        
        if [ "$BOB_BALANCE" != "$EXPECTED_FUNDING_AMOUNT" ]; then
            log_and_echo "❌ ERROR: Bob Chain 1 balance mismatch"
            log_and_echo "   Expected: $EXPECTED_FUNDING_AMOUNT Octas"
            log_and_echo "   Got: $BOB_BALANCE Octas"
            exit 1
        fi
        
        log "✅ Bob Chain 1 balance verified: $BOB_BALANCE Octas"
    else
        log_and_echo "❌ ERROR: Could not verify Bob Chain 1 balance via FA store"
        exit 1
    fi
else
    log_and_echo "❌ Failed to fund Bob account on Chain 1"
    exit 1
fi

# Fund Alice account on Chain 2
log "Funding Alice account on Chain 2..."
ALICE2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')
ALICE2_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8083/mint?address=${ALICE2_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$ALICE2_TX_HASH" != "null" ] && [ -n "$ALICE2_TX_HASH" ]; then
    log "✅ Alice account funded successfully on Chain 2 (tx: $ALICE2_TX_HASH)"
    
    # Wait for funding to be processed
    log "⏳ Waiting for Alice funding to be processed on Chain 2..."
    sleep 10
    
    # Get Alice's FA store address from transaction events
    ALICE2_FA_STORE=$(curl -s "http://127.0.0.1:8082/v1/transactions/by_hash/${ALICE2_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$ALICE2_FA_STORE" != "null" ] && [ -n "$ALICE2_FA_STORE" ]; then
        ALICE2_BALANCE=$(curl -s "http://127.0.0.1:8082/v1/accounts/${ALICE2_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        
        if [ -z "$ALICE2_BALANCE" ] || [ "$ALICE2_BALANCE" = "null" ]; then
            log_and_echo "❌ ERROR: Failed to get Alice Chain 2 balance"
            exit 1
        fi
        
        if [ "$ALICE2_BALANCE" != "$EXPECTED_FUNDING_AMOUNT" ]; then
            log_and_echo "❌ ERROR: Alice Chain 2 balance mismatch"
            log_and_echo "   Expected: $EXPECTED_FUNDING_AMOUNT Octas"
            log_and_echo "   Got: $ALICE2_BALANCE Octas"
            exit 1
        fi
        
        log "✅ Alice Chain 2 balance verified: $ALICE2_BALANCE Octas"
    else
        log_and_echo "❌ ERROR: Could not verify Alice Chain 2 balance via FA store"
        exit 1
    fi
else
    log_and_echo "❌ Failed to fund Alice account on Chain 2"
    exit 1
fi

# Fund Bob account on Chain 2
log "Funding Bob account on Chain 2..."
BOB2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain2"].account')
BOB2_TX_HASH=$(curl -s -X POST "http://127.0.0.1:8083/mint?address=${BOB2_ADDRESS}&amount=100000000" | jq -r '.[0]')

if [ "$BOB2_TX_HASH" != "null" ] && [ -n "$BOB2_TX_HASH" ]; then
    log "✅ Bob account funded successfully on Chain 2 (tx: $BOB2_TX_HASH)"
    
    # Wait for funding to be processed
    log "⏳ Waiting for Bob funding to be processed on Chain 2..."
    sleep 10
    
    # Get Bob's FA store address from transaction events
    BOB2_FA_STORE=$(curl -s "http://127.0.0.1:8082/v1/transactions/by_hash/${BOB2_TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store' | tail -1)
    
    if [ "$BOB2_FA_STORE" != "null" ] && [ -n "$BOB2_FA_STORE" ]; then
        BOB2_BALANCE=$(curl -s "http://127.0.0.1:8082/v1/accounts/${BOB2_FA_STORE}/resources" | jq -r '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance')
        
        if [ -z "$BOB2_BALANCE" ] || [ "$BOB2_BALANCE" = "null" ]; then
            log_and_echo "❌ ERROR: Failed to get Bob Chain 2 balance"
            exit 1
        fi
        
        if [ "$BOB2_BALANCE" != "$EXPECTED_FUNDING_AMOUNT" ]; then
            log_and_echo "❌ ERROR: Bob Chain 2 balance mismatch"
            log_and_echo "   Expected: $EXPECTED_FUNDING_AMOUNT Octas"
            log_and_echo "   Got: $BOB2_BALANCE Octas"
            exit 1
        fi
        
        log "✅ Bob Chain 2 balance verified: $BOB2_BALANCE Octas"
    else
        log_and_echo "❌ ERROR: Could not verify Bob Chain 2 balance via FA store"
        exit 1
    fi
else
    log_and_echo "❌ Failed to fund Bob account on Chain 2"
    exit 1
fi

log_and_echo "✅ Accounts funded"

log_and_echo ""
log_and_echo "   💰 Initial Balances:"
log_and_echo "   ====================="
log_and_echo "   Chain 1 (Hub):"
log_and_echo "      Alice: $ALICE_BALANCE Octas"
log_and_echo "      Bob:   $BOB_BALANCE Octas"
log_and_echo "   Chain 2 (Connected):"
log_and_echo "      Alice: $ALICE2_BALANCE Octas"
log_and_echo "      Bob:   $BOB2_BALANCE Octas"
log_and_echo ""

log ""
log "% - - - - - - - - - - - SUMMARY - - - - - - - - - - - -"
log "% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

log ""
log "🎉 DUAL-CHAIN ALICE AND BOB SETUP COMPLETE!"
log "============================================"
log ""
log "📋 Account Information:"
log "Chain 1 (port 8080):"
log "   Alice: $ALICE_ADDRESS"
log "   Bob:   $BOB_ADDRESS"
log ""
log "Chain 2 (port 8082):"
log "   Alice: $ALICE2_ADDRESS"
log "   Bob:   $BOB2_ADDRESS"
log ""
log "🔗 Chain Endpoints:"
log "   Chain 1 REST API: http://127.0.0.1:8080/v1"
log "   Chain 1 Faucet:   http://127.0.0.1:8081"
log "   Chain 2 REST API: http://127.0.0.1:8082/v1"
log "   Chain 2 Faucet:   http://127.0.0.1:8083"
log ""
log "📡 API Examples:"
log "   Check Chain 1 status:    curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height'"
log "   Check Chain 2 status:    curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height'"
log "   Get Alice Chain 1:       curl -s http://127.0.0.1:8080/v1/accounts/$ALICE_ADDRESS"
log "   Get Alice Chain 2:       curl -s http://127.0.0.1:8082/v1/accounts/$ALICE2_ADDRESS"
log "   Fund Chain 1 account:    curl -X POST \"http://127.0.0.1:8081/mint?address=<ADDRESS>&amount=100000000\""
log "   Fund Chain 2 account:    curl -X POST \"http://127.0.0.1:8083/mint?address=<ADDRESS>&amount=100000000\""
log ""
log "📋 Useful Commands:"
log "   Stop chains:     ./testing-infra/multi-chain/stop-dual-chains.sh"
log "   View profiles:   aptos config show-profiles"
log "   Test Chain 1:    aptos account balance --profile alice"
log "   Test Chain 2:    aptos account balance --profile alice-chain2"
log ""
log "✨ Ready for cross-chain testing!"
