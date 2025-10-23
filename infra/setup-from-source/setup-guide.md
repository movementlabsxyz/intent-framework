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

### Testing and Validation

For comprehensive testing commands, troubleshooting steps, and validation procedures that work with both Docker and manual setups, see the [shared testing guide](../testing-guide.md).

This includes:
- Service health checks
- Account funding and management
- Transaction verification
- Fungible Asset System documentation
- Complete working examples
- Troubleshooting commands

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

