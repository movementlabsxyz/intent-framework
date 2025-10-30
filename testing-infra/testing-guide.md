# Localnet Testing Guide

This guide contains testing and validation commands for Docker-based localnets.

## Multi-Chain Testing

### Service Health Checks for Multiple Chains
```bash
# Chain 1 (ports 8080/8081)
curl -s http://127.0.0.1:8080/v1/ledger/info
curl -s http://127.0.0.1:8081/

# Chain 2 (ports 8082/8083)
curl -s http://127.0.0.1:8082/v1/ledger/info
curl -s http://127.0.0.1:8083/
```

### Multi-Chain Account Funding
```bash
# Fund account on Chain 1
curl -X POST "http://127.0.0.1:8081/mint?address=<ACCOUNT_ADDRESS>&amount=100000000"

# Fund account on Chain 2
curl -X POST "http://127.0.0.1:8083/mint?address=<ACCOUNT_ADDRESS>&amount=100000000"
```

### Multi-Chain Balance Verification
```bash
# Check balance on Chain 1
curl -s "http://127.0.0.1:8080/v1/accounts/<FA_STORE_ADDRESS>/resources" | jq '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance'

# Check balance on Chain 2
curl -s "http://127.0.0.1:8082/v1/accounts/<FA_STORE_ADDRESS>/resources" | jq '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance'
```

## Service Health Checks

### Node API Status
```bash
# Basic API health check
curl -s http://127.0.0.1:8080/v1/ledger/info

# Extract key chain information
curl -s http://127.0.0.1:8080/v1

# Check node role and status
curl -s http://127.0.0.1:8080/v1/ledger/info
```

### Faucet Service Status
```bash
# Check faucet health
curl -s http://127.0.0.1:8081/

# Should return "tap:ok" if healthy
```

## Account Management

### Manual Account Funding
```bash
# Fund an account via faucet API
curl -X POST "http://127.0.0.1:8081/mint?address=<ACCOUNT_ADDRESS>&amount=100000000"

# Example with specific address
SENDER=0x85eb5517a0e7fbd349ecd71794c940695f2a8c3a3f120a32aa57087c6997d81d
TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${SENDER}&amount=100000000" | jq -r '.[0]')
```

### Transaction Verification
```bash
# Check transaction status
curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${TX_HASH}" | jq '.success, .vm_status'

# Find FA store address from transaction events
curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${TX_HASH}" | jq '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store'
```

## Fungible Asset System (FA)

**Important**: Modern Aptos versions use the Fungible Asset (FA) system instead of the traditional CoinStore.

### Checking Balances
```bash
# Check actual on-chain balance via FA store (replace STORE_ADDRESS with actual address)
curl -s "http://127.0.0.1:8080/v1/accounts/<STORE_ADDRESS>/resources" | jq '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance'

# Complete example: Get FA store and check balance
FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store')
curl -s "http://127.0.0.1:8080/v1/accounts/${FA_STORE}/resources" | jq '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance'
```

### Key Differences from Traditional CoinStore
- **CoinStore**: `0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>` (outdated)
- **Fungible Asset**: `0x1::fungible_asset::FungibleStore` (current)
- **CLI Balance**: Shows simulated/cached values (usually accurate)
- **On-Chain Reality**: Balances stored in separate FA store objects
- **Account Resources**: May only show `0x1::account::Account`, not CoinStore

### Why This Matters
- Direct REST API queries for CoinStore will return empty `[]`
- Real balances are in fungible asset store objects
- Transaction events show `fungible_asset::Deposit/Withdraw` instead of `coin::DepositEvent`

## Complete Working Example

Here's a step-by-step example that creates accounts and sends transactions:

```bash
# 1. Clean start (remove any existing configs)
pkill -f "aptos node" || true
pkill -f faucet || true
rm -rf ~/.aptos/ .aptos/

# 2. Start local testnet (Docker)
# Docker: ./testing-infra/single-chain/setup-docker-chain.sh

# 3. Create Alice account (non-interactive)
printf "\n" | aptos init --profile alice --network local --assume-yes

# 4. Create Bob account (non-interactive)
printf "\n" | aptos init --profile bob --network local --assume-yes

# 5. Verify both accounts are funded
aptos account balance --profile alice
aptos account balance --profile bob

# 6. Send transaction from Alice to Bob (non-interactive)
# First, get Bob's address from the profile
BOB_ADDRESS=$(aptos config show-profiles | jq -r '.bob.account')
printf "yes\n" | aptos account transfer --profile alice --account ${BOB_ADDRESS} --amount 2000000 --max-gas 10000

# 7. Verify transaction results
aptos account balance --profile alice
aptos account balance --profile bob

# 8. Optional: Verify on-chain balances (FA system)
# Get the transaction hash from step 6 output, then:
TX_HASH="0x53858ac187dc7c92b51fc43d58c1135e42425aaad7a2aa6c4e4fd14ac0e3eaf1"
FA_STORE=$(curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${TX_HASH}" | jq -r '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store')
curl -s "http://127.0.0.1:8080/v1/accounts/${FA_STORE}/resources" | jq '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance'
```

## Troubleshooting

### CLI Funding Issues
If `aptos init` hangs during funding:
```bash
# Check if validator is running
ps aux | grep "aptos node"

# Check validator status
curl -s http://127.0.0.1:8080/v1 | grep -E '"chain_id"|"block_height"'

# Manual funding via faucet API (use address=, not auth_key=)
curl -X POST "http://127.0.0.1:8081/mint?address=<ACCOUNT_ADDRESS>&amount=100000000"
```

### Port Conflicts
If you get port conflicts:
```bash
# Check what's using the ports
lsof -i :8080
lsof -i :8081

# Kill existing processes
pkill -f "aptos node"
pkill -f faucet
```
