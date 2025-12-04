# Intent Framework Testnet Deployment Plan

Deployment plan for Movement Bardock Testnet (Hub) + Base Sepolia (Connected Chain).

**Intent Flow**: USDC/pyUSD (Movement) → USDC/pyUSD (Base Sepolia)

---

## Overview

| Component | Network | Deployment Target |
| --------- | ------- | ----------------- |
| Move Intent Framework | Movement Bardock Testnet | Hub Chain |
| EVM IntentEscrow | Base Sepolia | Connected Chain |
| Trusted Verifier | AWS EC2 | Off-chain Service |
| Solver Service | AWS EC2 | Off-chain Service |
| Requester | Local | Client-side (operated locally) |

---

## Network Configuration

### Movement Bardock Testnet (Hub Chain)

> **Reference**: [Movement Network Endpoints](https://docs.movementnetwork.xyz/devs/networkEndpoints)

| Property | Value |
| -------- | ----- |
| Network Name | Movement Bardock Testnet |
| RPC URL | `https://testnet.movementnetwork.xyz/v1` |
| Faucet UI | `https://faucet.movementnetwork.xyz/` |
| Faucet API | `https://faucet.testnet.movementnetwork.xyz/` |
| Chain ID | `250` |
| Explorer | `https://explorer.movementnetwork.xyz/?network=bardock+testnet` |

### Base Sepolia Testnet (Connected Chain)

| Property | Value |
| -------- | ----- |
| Network Name | Base Sepolia |
| RPC URL | `https://sepolia.base.org` |
| Chain ID | `84532` |
| Explorer | `https://sepolia.basescan.org` |
| Faucet | `https://www.alchemy.com/faucets/base-sepolia` |

---

## Prerequisites

### 1. Environment Setup

```bash
# Copy the environment template
cp env.testnet.example .env.testnet

# Edit with your values (see Phase 1 for key generation)
```

### 2. Accounts & Keys ✅

- [x] **Movement Account**: Create/fund deployer wallet on Movement Bardock
- [x] **Base Account**: Create/fund deployer wallet on Base Sepolia
- [x] **Verifier Keys**: Generate Ed25519 keypair for verifier service
- [x] **Verifier ETH Address**: Derive ECDSA address for EVM signature verification

### 3. Testnet Funds ✅

- [x] Movement Testnet MOVE (for gas)
- [x] Movement Testnet USDC/pyUSD (for intent creation)
- [x] Base Sepolia ETH (for gas)
- [x] Base Sepolia USDC/pyUSD (for escrow flow)

### 4. Development Tools

```bash
# Enter nix development shell (provides Movement CLI, Node.js, Rust)
nix develop

# Or install manually:
# - Movement CLI (for Movement testnet deployment)
# - Node.js 18+ (for Hardhat/EVM deployment)
# - Rust (for Trusted Verifier)
```

---

## Completed Phases ✅

**Phase 1: Generate Keys & Configure** ✅

- All keys generated and saved to `.testnet-keys.env`
- Movement accounts (deployer, requester, solver) created via Nightly Wallet
- Base accounts (deployer, requester, solver) created via MetaMask
- Verifier Ed25519 keypair generated
- Verifier Ethereum address derived
- All accounts funded with testnet tokens

**Phase 2: Deploy Move Intent Framework** ✅

- Movement modules deployed to Movement Bardock Testnet
- Module address saved to `.testnet-keys.env` as `MOVEMENT_INTENT_MODULE_ADDRESS`

**Phase 3: Deploy EVM IntentEscrow** ✅

- IntentEscrow contract deployed to Base Sepolia
- Contract address saved to `.testnet-keys.env` as `BASE_ESCROW_CONTRACT_ADDRESS`

**Reference**: All keys and deployed addresses are stored in `.testnet-keys.env` (gitignored).

---

## Phase 3.5: Local Testing (Before EC2 Deployment)

Before deploying to EC2, test the services locally to ensure configuration is correct.

### 3.5.1 Configure Local Test Files

Fill in your testnet config files with actual values from `.testnet-keys.env`:

```bash
# Verifier config
trusted-verifier/config/verifier_testnet.toml

# Solver config (use localhost:3333 for verifier_url)
solver/config/solver_testnet.toml
```

### 3.5.2 Run Verifier Locally

```bash
# Terminal 1: Start verifier
./testing-infra/testnet/run-verifier-local.sh

# Or with release build (faster):
./testing-infra/testnet/run-verifier-local.sh --release
```

**Expected output:**
- "Starting Trusted Verifier Service"
- "Configuration loaded successfully"
- "Starting background event monitoring"
- API available at http://localhost:3333

**Verify:**
```bash
curl http://localhost:3333/health
# Expected: {"status":"ok"}
```

### 3.5.3 Run Solver Locally

```bash
# Terminal 2: Start solver (after verifier is running)
./testing-infra/testnet/run-solver-local.sh

# Or with release build (faster):
./testing-infra/testnet/run-solver-local.sh --release
```

**Expected output:**
- "Starting Solver Service"
- "Configuration loaded successfully"
- "Verifier URL: http://localhost:3333"
- "Signing service initialized"
- "Inflow service initialized"
- "Outflow service initialized"

### 3.5.4 What to Check

- [ ] Verifier starts without errors
- [ ] Verifier can connect to Movement Bardock RPC
- [ ] Verifier can connect to Base Sepolia RPC
- [ ] Solver starts without errors
- [ ] Solver can connect to verifier
- [ ] No authentication/key errors in logs

### 3.5.5 Update Config for EC2

After local testing succeeds, update `solver_testnet.toml` for EC2 deployment:

```toml
# Change from localhost to EC2 verifier IP
verifier_url = "http://<EC2_VERIFIER_HOST>:3333"
```

---

## Phase 4: Deploy Verifier and Solver Services to AWS EC2

**Architecture Note**: The verifier and solver are off-chain services that run on EC2. The requester operates locally (client-side).

**Verifier Capabilities**:

- Monitors chains for intents, escrows, and fulfillments
- Validates cross-chain fulfillment conditions
- Provides approval signatures via REST API (`/approval`, `/approvals`)
- Provides negotiation routing for off-chain communication between requesters and solvers (see `.taskmaster/tasks/VERIFIER_NEGOTIATION_ROUTING.md`)

**Solver Capabilities**:

- Polls verifier for pending draft intents (FCFS - first to sign wins)
- Evaluates acceptance based on configured token pairs and exchange rates
- Signs and submits signatures for accepted drafts
- Tracks signed intents and monitors for their on-chain creation
- Fulfills inflow intents by monitoring escrow deposits on connected chains
- Executes outflow transfers on connected chains and fulfills hub intents

### 4.1 Launch EC2 Instances

**Architecture**: Two separate EC2 instances for isolation and independent management.

```
┌─────────────────────┐         ┌─────────────────────┐
│   Verifier EC2      │         │    Solver EC2       │
│                     │         │                     │
│  ┌───────────────┐  │  HTTP   │  ┌───────────────┐  │
│  │   Verifier    │◄─┼─────────┼──│    Solver     │  │
│  │  (port 3333)  │  │         │  │  (background) │  │
│  └───────────────┘  │         │  └───────────────┘  │
│         ▲           │         │                     │
└─────────┼───────────┘         └─────────────────────┘
          │
   External requests
```

#### 4.1.1 Verifier Instance

**Requirements:**

- **AMI**: Ubuntu 22.04 LTS
- **Instance Type**: t3.micro (1 vCPU, 1GB RAM) - sufficient for verifier
- **Storage**: 20GB
- **Security Group** (verifier-sg):
  - SSH (22) from your IP
  - Custom TCP (3333) from 0.0.0.0/0 (verifier API - restrict in production)

#### 4.1.2 Solver Instance

**Requirements:**

- **AMI**: Ubuntu 22.04 LTS
- **Instance Type**: t3.micro (1 vCPU, 1GB RAM) - sufficient for solver
- **Storage**: 20GB
- **Security Group** (solver-sg):
  - SSH (22) from your IP
  - (No inbound ports needed - solver only makes outbound connections)

**Launch Steps:**

1. Go to AWS EC2 Console → Launch Instance
2. Launch **Verifier instance** first:
   - Select Ubuntu 22.04 LTS AMI
   - Choose t3.micro instance type
   - Create security group with SSH (22) + TCP (3333)
   - Create/select SSH key pair
   - Launch and note the public IP
3. Launch **Solver instance**:
   - Select Ubuntu 22.04 LTS AMI
   - Choose t3.micro instance type
   - Create security group with SSH (22) only
   - Use same SSH key pair
   - Launch and note the public IP

**Save EC2 connection details** to `.testnet-keys.env`:

```bash
# Verifier EC2
EC2_VERIFIER_HOST=<verifier-ec2-public-ip>
EC2_VERIFIER_USER=ubuntu

# Solver EC2
EC2_SOLVER_HOST=<solver-ec2-public-ip>
EC2_SOLVER_USER=ubuntu

# Shared SSH key (or use separate keys)
EC2_SSH_KEY_PATH=<path-to-your-ssh-private-key>
```

**Important**: The solver config must use the verifier's public IP:

```toml
# In solver_testnet.toml
[service]
verifier_url = "http://<EC2_VERIFIER_HOST>:3333"
```

### 4.2 Prepare Verifier Configuration File

Create `trusted-verifier/config/verifier_testnet.toml` using values from `.testnet-keys.env`:

```bash
cd trusted-verifier
cp config/verifier.template.toml config/verifier_testnet.toml
```

Edit `config/verifier_testnet.toml`:

```toml
# Hub Chain Configuration
[hub_chain]
name = "Movement Bardock Testnet"
rpc_url = "https://testnet.movementnetwork.xyz/v1"
chain_id = 250
intent_module_address = "<MOVEMENT_INTENT_MODULE_ADDRESS>"  # From .testnet-keys.env
known_accounts = ["<MOVEMENT_REQUESTER_ADDRESS>", "<MOVEMENT_SOLVER_ADDRESS>"]

# Connected EVM Chain Configuration
[connected_chain_evm]
name = "Base Sepolia"
rpc_url = "https://sepolia.base.org"
chain_id = 84532
escrow_contract_address = "<BASE_ESCROW_CONTRACT_ADDRESS>"  # From .testnet-keys.env
verifier_address = "<VERIFIER_ETH_ADDRESS>"  # From .testnet-keys.env

# Verifier Configuration
[verifier]
private_key = "<VERIFIER_PRIVATE_KEY>"  # From .testnet-keys.env
public_key = "<VERIFIER_PUBLIC_KEY>"    # From .testnet-keys.env
polling_interval_ms = 5000
validation_timeout_ms = 60000

# API Server Configuration
[api]
host = "0.0.0.0"  # Listen on all interfaces
port = 3333
cors_origins = ["*"]  # Adjust for production
```

### 4.2.1 Prepare Solver Configuration File

Create `solver/config/solver_testnet.toml` using values from `.testnet-keys.env`:

```bash
cd solver
cp config/solver_testnet.toml config/solver_testnet.toml
# Or copy from template:
# cp config/solver.template.toml config/solver_testnet.toml
```

Edit `config/solver_testnet.toml`:

```toml
# Service Configuration
[service]
verifier_url = "http://<EC2_VERIFIER_HOST>:3333"  # Verifier EC2 public IP
polling_interval_ms = 5000                         # Polling interval for checking pending drafts

# Hub Chain Configuration - Movement Bardock Testnet
[hub_chain]
name = "Movement Bardock Testnet"
rpc_url = "https://testnet.movementnetwork.xyz/v1"
chain_id = 250
module_address = "<MOVEMENT_INTENT_MODULE_ADDRESS>"  # From .testnet-keys.env
profile = "solver-movement-testnet"                   # Movement CLI profile for solver

# Connected Chain Configuration - Base Sepolia
[connected_chain]
type = "evm"
name = "Base Sepolia"
rpc_url = "https://sepolia.base.org"
chain_id = 84532
escrow_contract_address = "<BASE_ESCROW_CONTRACT_ADDRESS>"  # From .testnet-keys.env
private_key_env = "BASE_SOLVER_PRIVATE_KEY"                 # Env var with EVM private key

# Acceptance Criteria - Token pairs and exchange rates
[acceptance]
# Format: "offered_chain_id:offered_token:desired_chain_id:desired_token" = exchange_rate
# Uncomment and update with actual token addresses:
# "84532:0x036CbD53842c5426634e7929541eC2318f3dCF7e:250:<MOVEMENT_USDC_ADDRESS>" = 1.0
# "250:<MOVEMENT_USDC_ADDRESS>:84532:0x036CbD53842c5426634e7929541eC2318f3dCF7e" = 1.0

# Solver Configuration
[solver]
profile = "solver-movement-testnet"      # Movement CLI profile for solver
address = "<MOVEMENT_SOLVER_ADDRESS>"    # From .testnet-keys.env
```

**Note**: The solver requires a Movement CLI profile for signing transactions on the hub chain. Set up the profile on EC2:

```bash
movement init --profile solver-movement-testnet \
  --network custom \
  --rest-url https://testnet.movementnetwork.xyz/v1 \
  --private-key "$MOVEMENT_SOLVER_PRIVATE_KEY" \
  --skip-faucet \
  --assume-yes
```

### 4.3 Build Services on EC2

Since you're building on macOS, build directly on each EC2 instance.

#### 4.3.1 Build Verifier on Verifier EC2

```bash
# SSH into Verifier EC2
ssh -i $EC2_SSH_KEY_PATH $EC2_VERIFIER_USER@$EC2_VERIFIER_HOST

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Clone repository
git clone https://github.com/movementlabsxyz/intent-framework.git
cd intent-framework

# Build verifier release binary
cd trusted-verifier
cargo build --release

# Binary location: target/release/trusted-verifier
```

#### 4.3.2 Build Solver on Solver EC2

```bash
# SSH into Solver EC2
ssh -i $EC2_SSH_KEY_PATH $EC2_SOLVER_USER@$EC2_SOLVER_HOST

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Clone repository
git clone https://github.com/movementlabsxyz/intent-framework.git
cd intent-framework

# Build solver release binary
cd solver
cargo build --release

# Binary location: target/release/solver
```

#### Alternative: Cross-Compile from macOS

If you prefer to build locally and copy binaries:

```bash
# Install cross-compilation target
rustup target add x86_64-unknown-linux-gnu

# Install cross-compilation toolchain (macOS)
brew install SergioBenitez/osxct/x86_64-unknown-linux-gnu

# Build verifier for Linux
cd trusted-verifier
cargo build --release --target x86_64-unknown-linux-gnu
scp -i $EC2_SSH_KEY_PATH target/x86_64-unknown-linux-gnu/release/trusted-verifier \
  $EC2_VERIFIER_USER@$EC2_VERIFIER_HOST:/tmp/

# Build solver for Linux
cd ../solver
cargo build --release --target x86_64-unknown-linux-gnu
scp -i $EC2_SSH_KEY_PATH target/x86_64-unknown-linux-gnu/release/solver \
  $EC2_SOLVER_USER@$EC2_SOLVER_HOST:/tmp/
```

### 4.4 Set Up Systemd Services

#### 4.4.1 Verifier Service (on Verifier EC2)

SSH into **Verifier EC2** and create the systemd service file:

```bash
sudo nano /etc/systemd/system/verifier.service
```

**Verifier service file content:**

```ini
[Unit]
Description=Intent Framework Trusted Verifier Service
After=network.target

[Service]
Type=simple
User=verifier
WorkingDirectory=/opt/verifier
ExecStart=/opt/verifier/trusted-verifier
Environment="VERIFIER_CONFIG_PATH=/opt/verifier/config/verifier_testnet.toml"
Environment="RUST_LOG=info"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Set up verifier user and directory:**

```bash
# Create verifier user
sudo useradd -r -s /bin/false verifier

# Create directory structure
sudo mkdir -p /opt/verifier/config
sudo chown -R verifier:verifier /opt/verifier

# Copy binary (from intent-framework directory)
sudo cp ~/intent-framework/trusted-verifier/target/release/trusted-verifier /opt/verifier/
sudo chmod +x /opt/verifier/trusted-verifier

# Create config file with your values (copy from local or create manually)
sudo nano /opt/verifier/config/verifier_testnet.toml
sudo chmod 600 /opt/verifier/config/verifier_testnet.toml

sudo chown -R verifier:verifier /opt/verifier

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable verifier
sudo systemctl start verifier
```

#### 4.4.2 Solver Service (on Solver EC2)

SSH into **Solver EC2** and create the systemd service file:

```bash
sudo nano /etc/systemd/system/solver.service
```

**Solver service file content:**

```ini
[Unit]
Description=Intent Framework Solver Service
After=network.target

[Service]
Type=simple
User=solver
WorkingDirectory=/opt/solver
ExecStart=/opt/solver/solver --config /opt/solver/config/solver_testnet.toml
Environment="RUST_LOG=info"
Environment="BASE_SOLVER_PRIVATE_KEY=<BASE_SOLVER_PRIVATE_KEY>"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Note**: The solver service:
- Runs continuously, polling the verifier for pending drafts
- Automatically signs and fulfills intents based on acceptance criteria
- Connects to verifier via HTTP (ensure verifier is running first)
- Does not expose an API (background service only)

**Set up solver user and directory:**

```bash
# Create solver user
sudo useradd -r -s /bin/false solver

# Create directory structure
sudo mkdir -p /opt/solver/config
sudo mkdir -p /opt/solver/bin
sudo chown -R solver:solver /opt/solver

# Copy solver binary and config (from intent-framework directory)
sudo cp ~/intent-framework/solver/target/release/solver /opt/solver/
sudo chmod +x /opt/solver/solver

# Create config file with your values (copy from local or create manually)
# IMPORTANT: Update verifier_url to point to Verifier EC2's public IP
sudo nano /opt/solver/config/solver_testnet.toml
sudo chmod 600 /opt/solver/config/solver_testnet.toml

# Copy utility binaries (optional, for manual operations)
sudo cp ~/intent-framework/solver/target/release/sign_intent /opt/solver/bin/
sudo cp ~/intent-framework/solver/target/release/connected_chain_tx_template /opt/solver/bin/
sudo chmod +x /opt/solver/bin/*

sudo chown -R solver:solver /opt/solver

# Install Movement CLI (required for signing on hub chain)
# See: https://docs.movementnetwork.xyz/devs/movementcli
curl -fsSL https://raw.githubusercontent.com/movementlabsxyz/aptos-core/main/scripts/cli/install_cli.py | python3

# Set up Movement CLI profile for solver (required for signing)
sudo -u solver movement init --profile solver-movement-testnet \
  --network custom \
  --rest-url https://testnet.movementnetwork.xyz/v1 \
  --private-key "$MOVEMENT_SOLVER_PRIVATE_KEY" \
  --skip-faucet \
  --assume-yes

# Enable and start service (after verifier is running!)
sudo systemctl daemon-reload
sudo systemctl enable solver
sudo systemctl start solver
```

### 4.5 Verify Deployment

#### 4.5.1 Verify Verifier (on Verifier EC2)

```bash
# SSH into Verifier EC2
ssh -i $EC2_SSH_KEY_PATH $EC2_VERIFIER_USER@$EC2_VERIFIER_HOST

# Check service status
sudo systemctl status verifier

# View logs
sudo journalctl -u verifier -f
```

**Test verifier health endpoints:**

```bash
# From Verifier EC2
curl http://localhost:3333/health
curl http://localhost:3333/public-key

# From your local machine
curl http://$EC2_VERIFIER_HOST:3333/health
curl http://$EC2_VERIFIER_HOST:3333/public-key
```

**Expected responses:**

- `/health`: Should return `{"status":"ok"}`
- `/public-key`: Should return the verifier's public key

#### 4.5.2 Verify Solver (on Solver EC2)

```bash
# SSH into Solver EC2
ssh -i $EC2_SSH_KEY_PATH $EC2_SOLVER_USER@$EC2_SOLVER_HOST

# Check service status
sudo systemctl status solver

# View logs
sudo journalctl -u solver -f
```

**Check solver logs for startup messages:**

```bash
sudo journalctl -u solver --no-pager | head -50

# Expected log messages:
# - "Starting Solver Service"
# - "Configuration loaded successfully"
# - "Verifier URL: http://<EC2_VERIFIER_HOST>:3333"
# - "Signing service initialized"
# - "Inflow service initialized"
# - "Outflow service initialized"
# - "Starting all services..."
```

**Test connectivity to verifier (from Solver EC2):**

```bash
# Solver should be able to reach verifier
curl http://$EC2_VERIFIER_HOST:3333/health
```

**Test solver utility binaries (optional):**

```bash
# Test solver signature generation
sudo -u solver /opt/solver/bin/sign_intent --help

# Test transaction template generation
sudo -u solver /opt/solver/bin/connected_chain_tx_template --help
```

### 4.6 Deployment Scripts

#### Local Testing Scripts

Test locally before deploying to EC2:

```bash
# Terminal 1: Run verifier locally
./testing-infra/testnet/run-verifier-local.sh

# Terminal 2: Run solver locally (after verifier is up)
./testing-infra/testnet/run-solver-local.sh
```

#### EC2 Deployment Scripts

After local testing succeeds, deploy to EC2:

```bash
# Step 1: Update solver config with EC2 verifier IP
# Edit solver/config/solver_testnet.toml:
# verifier_url = "http://<EC2_VERIFIER_HOST>:3333"

# Step 2: Deploy verifier first
./testing-infra/testnet/deploy-verifier-ec2.sh

# Step 3: Deploy solver (after verifier is healthy)
./testing-infra/testnet/deploy-solver-ec2.sh
```

**What the EC2 scripts do:**

1. SSH into the respective EC2 instance
2. Install Rust and dependencies
3. Clone repo and build release binaries
4. Copy configuration files from your local machine
5. Set up systemd services
6. Configure Movement CLI profile (solver only)
7. Start and enable services
8. Verify health endpoints

**Deployment order:**
1. Deploy verifier first (solver depends on it)
2. Verify verifier is healthy: `curl http://<EC2_VERIFIER_HOST>:3333/health`
3. Deploy solver after verifier is healthy

---

## Phase 5: Post-Deployment Verification

### 5.1 Checklist

**On-Chain Contracts:**
- [x] Move modules deployed and callable on Movement Bardock
- [x] IntentEscrow deployed on Base Sepolia

**Off-Chain Services:**
- [ ] Verifier service running and healthy on EC2
- [ ] Solver service running and healthy on EC2
- [ ] Verifier monitoring both chains (check logs for event polling)
- [ ] Solver connected to verifier (check logs for "Verifier URL")

**End-to-End Testing:**
- [ ] Solver can accept and sign draft intents
- [ ] Intent can be created on Movement with solver signature
- [ ] Escrow can be created on Base Sepolia
- [ ] Solver can fulfill intent and claim escrow
- [ ] Full cross-chain flow tested

### 5.2 Test Intent Flow (USDC/pyUSD → USDC/pyUSD)

**Note on Negotiation**: For reserved intents, requester and solver negotiate off-chain using verifier-based negotiation routing:

1. **Off-chain Negotiation** (Verifier-Based):
   - Requester creates draft intent (off-chain)
   - Requester submits draft to verifier via `POST /draft-intent` (draft is open to any solver)
   - Solvers poll verifier via `GET /draft-intents/pending` to discover drafts
   - First solver to sign submits signature via `POST /draft-intent/:id/signature` (FCFS)
   - Requester polls verifier via `GET /draft-intent/:id/signature` to retrieve signature
   - Requester submits intent on-chain with solver's signature

   See `.taskmaster/tasks/VERIFIER_NEGOTIATION_ROUTING.md` for details.

2. **Requester creates Intent on Movement** - offers USDC/pyUSD, wants USDC/pyUSD on Base (with solver signature)
3. **Requester creates Escrow on Base Sepolia** - deposits USDC/pyUSD for solver
4. **Solver fulfills Intent on Movement** - sends USDC/pyUSD to requester
5. **Verifier generates approval** - confirms fulfillment
6. **Solver claims Escrow on Base Sepolia** - receives USDC/pyUSD

---

## CI/CD: GitHub Actions Workflow

Create `.github/workflows/deploy-testnet.yml` for automated deployments:

```yaml
name: Deploy to Testnet

on:
  workflow_dispatch:
    inputs:
      deploy_movement:
        description: 'Deploy to Movement Bardock'
        type: boolean
        default: true
      deploy_base:
        description: 'Deploy to Base Sepolia'
        type: boolean
        default: true

env:
  MOVEMENT_RPC_URL: https://testnet.movementnetwork.xyz/v1
  BASE_SEPOLIA_RPC_URL: https://sepolia.base.org

jobs:
  deploy-movement:
    if: ${{ inputs.deploy_movement }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Nix
        uses: cachix/install-nix-action@v24
        with:
          nix_path: nixpkgs=channel:nixos-unstable
      
      - name: Deploy Move Modules
        run: |
          nix develop -c bash -c "
            cd move-intent-framework
            movement init --profile testnet --network custom \
              --rest-url $MOVEMENT_RPC_URL \
              --private-key \${{ secrets.MOVEMENT_PRIVATE_KEY }}
            
            ADDR=\$(movement config show-profiles --profile testnet | jq -r '.Result.testnet.account')
            
            movement move publish \
              --profile testnet \
              --named-addresses mvmt_intent=0x\$ADDR \
              --skip-fetch-latest-git-deps \
              --assume-yes
          "
    outputs:
      module_address: ${{ steps.deploy.outputs.address }}

  deploy-base:
    if: ${{ inputs.deploy_base }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: evm-intent-framework/package-lock.json
      
      - name: Install Dependencies
        working-directory: evm-intent-framework
        run: npm ci
      
      - name: Deploy IntentEscrow
        working-directory: evm-intent-framework
        env:
          DEPLOYER_PRIVATE_KEY: ${{ secrets.BASE_DEPLOYER_PRIVATE_KEY }}
          VERIFIER_ADDRESS: ${{ secrets.VERIFIER_ETH_ADDRESS }}
        run: |
          npx hardhat run scripts/deploy.js --network baseSepolia
      
      - name: Verify Contract
        if: ${{ secrets.BASESCAN_API_KEY != '' }}
        working-directory: evm-intent-framework
        env:
          BASESCAN_API_KEY: ${{ secrets.BASESCAN_API_KEY }}
        run: |
          npx hardhat verify --network baseSepolia $CONTRACT_ADDRESS $VERIFIER_ADDRESS
```

---

## GitHub Secrets Required

| Secret | Description |
| ------ | ----------- |
| `MOVEMENT_PRIVATE_KEY` | Private key for Movement deployer account |
| `BASE_DEPLOYER_PRIVATE_KEY` | Private key for Base Sepolia deployer |
| `VERIFIER_ETH_ADDRESS` | Ethereum address derived from verifier keys |
| `VERIFIER_PRIVATE_KEY` | Ed25519 private key (base64) for verifier |
| `VERIFIER_PUBLIC_KEY` | Ed25519 public key (base64) for verifier |
| `BASESCAN_API_KEY` | (Optional) For contract verification |

---

## Deployed Addresses (Fill After Deployment)

| Component | Network | Address |
| --------- | ------- | ------- |
| Intent Framework | Movement Bardock | `0x...` |
| IntentEscrow | Base Sepolia | `0x...` |
| Verifier API | Cloud | `https://...` |

---

## Rollback Procedure

### Movement

Move modules cannot be deleted after deployment. Deploy new version with updated address if needed.

### Base Sepolia

Contract is immutable. Deploy new instance and update verifier config.

### Verifier

Update config file and restart service.

---

## Monitoring & Alerts

### Verifier Health Endpoints

```bash
# Health check
GET /health

# Public key (for verification)
GET /public-key

# Observed events
GET /events

# Generated approvals
GET /approvals
```

### Recommended Monitoring

- [ ] Verifier service uptime
- [ ] RPC endpoint availability (Movement + Base)
- [ ] Event processing latency
- [ ] Approval generation success rate

---

## Security Considerations

1. **Never commit private keys** - Use GitHub Secrets or environment variables
2. **Verifier keys are critical** - Store securely, backup offline
3. **Rate limiting** - Consider API rate limits for production
4. **Key rotation** - Plan for verifier key rotation procedure
5. **Testnet vs Mainnet** - Separate accounts and configurations

---

## Next Steps

1. [x] Fund testnet accounts
2. [x] Generate and secure verifier keys
3. [x] Deploy Move modules to Movement Bardock
4. [x] Deploy IntentEscrow to Base Sepolia
5. [ ] Configure and deploy Verifier and Solver services to EC2
6. [ ] Run end-to-end test
7. [ ] Set up monitoring
8. [x] Document deployed addresses
