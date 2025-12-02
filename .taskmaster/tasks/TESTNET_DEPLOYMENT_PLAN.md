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

## Phase 4: Deploy Verifier and Solver Services to AWS EC2

**Architecture Note**: The verifier and solver are off-chain services that run on EC2. The requester operates locally (client-side).

**Verifier Capabilities**:

- Monitors chains for intents, escrows, and fulfillments
- Validates cross-chain fulfillment conditions
- Provides approval signatures via REST API (`/approval`, `/approvals`)
- Provides negotiation routing for off-chain communication between requesters and solvers (see `.taskmaster/tasks/VERIFIER_NEGOTIATION_ROUTING.md`)

### 4.1 Launch EC2 Instance

**Instance Requirements:**

- **AMI**: Ubuntu 22.04 LTS or Amazon Linux 2023
- **Instance Type**: t3.small (2 vCPU, 2GB RAM) minimum (can run both verifier and solver)
- **Storage**: 20GB minimum
- **Security Group**:
  - SSH (22) from your IP
  - Custom TCP (3333) for verifier API (or configure reverse proxy/load balancer)
  - Custom TCP (3334) for solver API (if solver exposes API, adjust as needed)

**Launch Steps:**

1. Go to AWS EC2 Console → Launch Instance
2. Select Ubuntu 22.04 LTS AMI
3. Choose t3.small instance type
4. Configure security group:
   - SSH (22) from your IP
   - Custom TCP (3333) from 0.0.0.0/0 (or restrict to specific IPs)
5. Create/select SSH key pair
6. Launch instance

**Save EC2 connection details** to `.testnet-keys.env`:

```bash
EC2_HOST=<your-ec2-public-ip-or-hostname>
EC2_USER=ubuntu  # or 'ec2-user' for Amazon Linux
EC2_SSH_KEY_PATH=<path-to-your-ssh-private-key>
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

### 4.3 Build Verifier and Solver on EC2

Since you're building on macOS, build directly on the EC2 instance:

#### Option A: Build on EC2 (Recommended)

```bash
# SSH into EC2
ssh -i $EC2_SSH_KEY_PATH $EC2_USER@$EC2_HOST

# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Clone repository (or copy files)
# Option 1: Clone from GitHub
git clone <your-repo-url>
cd intent-framework

# Option 2: Copy files from local machine
# (From your local machine)
cd /path/to/intent-framework
tar czf trusted-verifier.tar.gz trusted-verifier/
scp -i $EC2_SSH_KEY_PATH trusted-verifier.tar.gz $EC2_USER@$EC2_HOST:~/
# (Back on EC2)
tar xzf trusted-verifier.tar.gz

# Build verifier release binary
cd trusted-verifier
cargo build --release

# Build solver binaries
cd ../solver
cargo build --release
```

#### Option B: Cross-Compile from macOS

If you prefer to build locally and copy the binary:

```bash
# Install cross-compilation target
rustup target add x86_64-unknown-linux-gnu

# Install cross-compilation toolchain (macOS)
brew install SergioBenitez/osxct/x86_64-unknown-linux-gnu

# Build for Linux
cd trusted-verifier
cargo build --release --target x86_64-unknown-linux-gnu

# Copy binary to EC2
scp -i $EC2_SSH_KEY_PATH target/x86_64-unknown-linux-gnu/release/trusted-verifier \
  $EC2_USER@$EC2_HOST:/tmp/
```

### 4.4 Set Up Systemd Services

#### 4.4.1 Verifier Service

On EC2, create verifier systemd service file:

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

# Copy binary and config (from trusted-verifier directory)
sudo cp trusted-verifier/target/release/trusted-verifier /opt/verifier/
sudo cp trusted-verifier/config/verifier_testnet.toml /opt/verifier/config/
sudo chmod +x /opt/verifier/trusted-verifier
sudo chmod 600 /opt/verifier/config/verifier_testnet.toml
sudo chown -R verifier:verifier /opt/verifier

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable verifier
sudo systemctl start verifier
```

#### 4.4.2 Solver Service

On EC2, create solver systemd service file:

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
ExecStart=/opt/solver/solver-service
Environment="RUST_LOG=info"
Environment="MOVEMENT_SOLVER_PRIVATE_KEY=<MOVEMENT_SOLVER_PRIVATE_KEY>"
Environment="BASE_SOLVER_PRIVATE_KEY=<BASE_SOLVER_PRIVATE_KEY>"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Note**: If solver is CLI-only (no service), you may need to create a wrapper script or cron job. Adjust `ExecStart` accordingly.

**Set up solver user and directory:**

```bash
# Create solver user
sudo useradd -r -s /bin/false solver

# Create directory structure
sudo mkdir -p /opt/solver/bin
sudo chown -R solver:solver /opt/solver

# Copy solver binaries (from solver directory)
sudo cp solver/target/release/sign_intent /opt/solver/bin/
sudo cp solver/target/release/connected_chain_tx_template /opt/solver/bin/
# If solver has a service binary, copy it:
# sudo cp solver/target/release/solver-service /opt/solver/

# Set permissions
sudo chmod +x /opt/solver/bin/*
sudo chown -R solver:solver /opt/solver

# Enable and start service (if solver-service exists)
# sudo systemctl daemon-reload
# sudo systemctl enable solver
# sudo systemctl start solver
```

### 4.5 Verify Deployment

**Check service status:**

```bash
# Verifier service
sudo systemctl status verifier

# Solver service (if running as service)
sudo systemctl status solver
```

**View logs:**

```bash
# Verifier logs
sudo journalctl -u verifier -f

# Solver logs (if running as service)
sudo journalctl -u solver -f
```

**Test verifier health endpoints:**

```bash
# From EC2
curl http://localhost:3333/health
curl http://localhost:3333/public-key

# From your local machine
curl http://$EC2_HOST:3333/health
curl http://$EC2_HOST:3333/public-key
```

**Expected responses:**

- `/health`: Should return `{"status":"ok"}`
- `/public-key`: Should return the verifier's public key

**Test solver tools (if CLI-based):**

```bash
# Test solver signature generation
sudo -u solver /opt/solver/bin/sign_intent --help

# Test transaction template generation
sudo -u solver /opt/solver/bin/connected_chain_tx_template --help
```

### 4.6 Quick Start (Automated Deployment)

Use the deployment scripts (if available):

```bash
# Deploy verifier
./testing-infra/testnet/deploy-verifier-ec2.sh

# Deploy solver
./testing-infra/testnet/deploy-solver-ec2.sh
```

The scripts will:

1. Build binaries on EC2 (or copy pre-built)
2. Copy configuration files
3. Set up systemd services
4. Start and enable services
5. Verify health endpoints

---

## Phase 5: Post-Deployment Verification

### 5.1 Checklist

- [ ] Move modules deployed and callable on Movement Bardock
- [ ] IntentEscrow deployed on Base Sepolia
- [ ] Verifier service running and healthy on EC2
- [ ] Solver service running and healthy on EC2
- [ ] Verifier monitoring both chains
- [ ] Solver can monitor and fulfill intents
- [ ] End-to-end intent flow tested

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
