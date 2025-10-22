# Single Validator Quickstart

This guide runs a local validator using Aptos `aptos-core` (main branch) with two setup options.

## Prerequisites

- Rust toolchain
- Aptos CLI

### System Dependencies

Install required system packages:

```bash
# Install system dependencies
sudo apt install -y $(cat infra/setup-from-source/requirements.txt)
```

Required packages:
- `binutils` - GNU linker tools
- `lld` - LLVM linker  
- `libudev-dev` - Hardware device library (for HID API)
- `pkg-config` - Package configuration tool

## Running the Local Testnet

The simplest way to run a local validator with automatic account funding:

```bash
# Start local testnet with faucet (includes automatic setup)
aptos node run-localnet --with-faucet --force-restart --assume-yes
```

**⚠️ Important Port Limitation:**
The `aptos node run-localnet` command does **not** support custom port configuration. It hardcodes:
- REST API to port 8080
- Faucet to port 8081

To run multiple chains in parallel with custom ports (e.g., Chain A on 8010/8011, Chain B on 8020/8021), you must use manual validator setup instead of `run-localnet`.

## Manual Validator Setup (Multi-Chain)

For running multiple chains in parallel with custom ports, use the manual setup approach:

### Quick Start
```bash
# Setup Chain A (ports 8010/8011)
./infra/setup-chain-a.sh

# Test Chain A
./infra/test-chain-a.sh
```

### Manual Setup Process
1. **Generate config files** (one-time):
   ```bash
   aptos node run-localnet --with-faucet --force-restart --assume-yes --test-dir ./infra/.aptos/chain-a
   # Stop immediately after config generation (Ctrl+C)
   ```

2. **Modify ports** in `./infra/.aptos/chain-a/0/node.yaml`:
   ```yaml
   api:
     address: "0.0.0.0:8010"  # Change from 8080
   admin_service:
     address: "0.0.0.0:9112"  # Change from 9102
   metrics:
     address: "0.0.0.0:9111"  # Change from 9101
   ```

3. **Start validator**:
   ```bash
   RUST_LOG=warn infra/external/aptos-core/target/release/aptos-node -f ./infra/.aptos/chain-a/0/node.yaml
   ```

4. **Start faucet**:
   ```bash
   infra/external/aptos-core/target/release/aptos-faucet-service run-simple \
     --node-url http://127.0.0.1:8010 \
     --listen-port 8011 \
     --key-file-path ./infra/.aptos/chain-a/mint.key \
     --chain-id 4
   ```

### Benefits of Manual Setup
- **Custom ports**: Full control over REST API and faucet ports
- **Multiple chains**: Run Chain A (8010/8011) and Chain B (8020/8021) in parallel
- **Fresh starts**: Scripts ensure clean state on each run
- **Automated testing**: Built-in account creation, funding, and transfer tests

### Automated Scripts
The manual setup includes automated scripts for reliability:

**`infra/setup-chain-a.sh`** - Complete Chain A setup:
- Cleans up existing processes and data
- Generates fresh config files
- Modifies ports to 8010/8011
- Starts validator and faucet
- Creates and funds test accounts (alice, bob)
- Verifies initial balances

**`infra/test-chain-a.sh`** - Dedicated testing:
- Checks if Chain A is running
- Creates fresh test accounts
- Tests token transfers between accounts
- Verifies final balances
- Fails if any test fails

**Usage:**
```bash
# Setup Chain A
./infra/setup-chain-a.sh

# Test Chain A (can run multiple times)
./infra/test-chain-a.sh
```

**Benefits:**

- Automatically generates all configuration files
- Includes faucet service for automatic account funding
- `aptos init` works out of the box
- Designed for testing and development
- No manual configuration needed

The output will show:
- REST API endpoint: `http://0.0.0.0:8080`
- Faucet endpoint: `http://0.0.0.0:8081`
- Chain ID and waypoint

## CLI Initialization

With the faucet-enabled testnet, CLI initialization works automatically:

```bash
# Initialize CLI with local network (non-interactive)
printf "\n" | aptos init --profile alice --network local --assume-yes

# This will:
# 1. Generate a new private key automatically
# 2. Create the account on-chain
# 3. Fund the account with 100M Octas via faucet
# 4. Set up the profile for future use
```

**For interactive use:**
```bash
aptos init --profile alice --network local --assume-yes
# When prompted, press Enter to generate a new key
```

## Sending Transactions

Once accounts are created and funded, you can send transactions:

```bash
# Send transaction (non-interactive)
printf "yes\n" | aptos account transfer --profile alice --account <BOB_ADDRESS> --amount 1000000 --max-gas 10000

# For interactive use:
aptos account transfer --profile alice --account <BOB_ADDRESS> --amount 1000000 --max-gas 10000
# When prompted, type "yes" to confirm
```

**Important:**
- Use `--max-gas 10000` to ensure sufficient gas
- Use `printf "yes\n"` for non-interactive confirmation
- Check balances before and after to verify success

## Manual Verification

```bash
# Check validator is running and get status
curl http://127.0.0.1:8080/v1
# Should return JSON with chain_id, block_height, node_role, etc.

# Check if process is running
ps aux | grep aptos-node

# Check what ports are listening
netstat -an | grep LISTEN | grep 8080
```

## Files Created
The local testnet automatically creates configuration files in `~/.aptos/testnet/`:
- `validator.log` - Node logs
- `mint.key` - Aptos root key for funding
- Various configuration and data files

## Stopping the Validator
```bash
# Find and kill the process
pkill -f "aptos node"
# or find PID and kill manually
ps aux | grep "aptos node"
kill <PID>
```

## Complete Cleanup
To completely reset everything (useful for testing):

```bash
# 1. Kill all Aptos processes
pkill -f "aptos node" || true
pkill -f faucet || true

# 2. Remove CLI profiles (created by aptos init)
rm -rf .aptos/

# 3. Remove global Aptos config (created by testnet)
rm -rf ~/.aptos/

# 4. Verify clean state
aptos config show-profiles
# Should show: "Unable to find config... have you run aptos init?"

ps aux | grep aptos
# Should only show language server (if any)
```

**What gets removed:**
- **`.aptos/`** (local): CLI profiles (alice, bob, etc.) created by `aptos init`
- **`~/.aptos/`** (global): Testnet data, logs, and global config created by `aptos node run-localnet`

**Use this when:**
- Starting fresh for testing
- Troubleshooting persistent issues
- Switching between different testnet setups

## Troubleshooting

### Validator Not Starting
If the validator doesn't start properly:
```bash
# Kill any stray processes
pkill -f aptos-node || true
pkill -f faucet || true

# Start fresh
aptos node run-localnet --with-faucet --force-restart --assume-yes
```

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

### Fungible Asset System (FA)
**Important**: Modern Aptos versions use the Fungible Asset (FA) system instead of the traditional CoinStore. The `aptos account balance` command shows simulated/cached balances, but actual balances are stored in separate fungible asset store objects.

```bash
# Fund an account
SENDER=0x85eb5517a0e7fbd349ecd71794c940695f2a8c3a3f120a32aa57087c6997d81d
TX_HASH=$(curl -s -X POST "http://127.0.0.1:8081/mint?address=${SENDER}&amount=100000000" | jq -r '.[0]')

# Check transaction status
curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${TX_HASH}" | jq '.success, .vm_status'

# Find FA store address from transaction events
curl -s "http://127.0.0.1:8080/v1/transactions/by_hash/${TX_HASH}" | jq '.events[] | select(.type=="0x1::fungible_asset::Deposit").data.store'

# Check actual on-chain balance via FA store (replace STORE_ADDRESS with actual address)
curl -s "http://127.0.0.1:8080/v1/accounts/<STORE_ADDRESS>/resources" | jq '.[] | select(.type=="0x1::fungible_asset::FungibleStore").data.balance'
```

**Key Differences from Traditional CoinStore:**
- **CoinStore**: `0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>` (outdated)
- **Fungible Asset**: `0x1::fungible_asset::FungibleStore` (current)
- **CLI Balance**: Shows simulated/cached values (usually accurate)
- **On-Chain Reality**: Balances stored in separate FA store objects
- **Account Resources**: May only show `0x1::account::Account`, not CoinStore

**Why This Matters:**
- Direct REST API queries for CoinStore will return empty `[]`
- Real balances are in fungible asset store objects
- Transaction events show `fungible_asset::Deposit/Withdraw` instead of `coin::DepositEvent`

### Complete Working Example
Here's a step-by-step example that creates accounts and sends transactions:

```bash
# 1. Clean start (remove any existing configs)
pkill -f "aptos node" || true
pkill -f faucet || true
rm -rf ~/.aptos/ .aptos/

# 2. Start local testnet
aptos node run-localnet --with-faucet --force-restart --assume-yes

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

**Expected Results:**
- Alice: ~97,950,100 Octas (100M - 2M transfer - gas fees)
- Bob: 102,000,000 Octas (100M + 2M transfer)
- Transaction hash returned for verification

**Key Points:**
- Use `printf "\n"` to handle interactive prompts for account creation
- Use `printf "yes\n"` to handle transaction confirmation prompts
- Use `--max-gas 10000` to ensure sufficient gas for transactions
- Both accounts are automatically funded with 100M Octas via faucet
- **Note**: Balances shown by CLI are simulated/cached; actual balances use fungible asset system

### Process Names
- **Validator process**: `aptos node run-localnet` (not `aptos-node`)
- **Faucet**: Runs as part of the main process (not separate)

## Pin and Verify aptos-core (Enforced on Build)
- Ensure Aptos `aptos-core` is present (plain clone):
  ```bash
  bash move-intent-framework/tests/cross_chain/setup_aptos_core.sh
  ```
- Builds/tests run a verification hook via `move-intent-framework/Move.toml` that checks `infra/external/aptos-core` HEAD against the lock file `infra/external/aptos-core.lock`.
  - If they differ, the build exits non-zero with a clear message.
- To update the pinned commit intentionally:
  ```bash
  git -C infra/external/aptos-core rev-parse HEAD > infra/external/aptos-core.lock
  ```
  Commit the updated lock file.

