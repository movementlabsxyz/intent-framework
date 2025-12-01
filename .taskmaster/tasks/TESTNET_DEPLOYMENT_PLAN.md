# Intent Framework Testnet Deployment Plan

Deployment plan for Movement Bardock Testnet (Hub) + Base Sepolia (Connected Chain).

**Intent Flow**: USDC/pyUSD (Movement) → USDC/pyUSD (Base Sepolia)

---

## Overview

| Component | Network | Deployment Target |
|-----------|---------|-------------------|
| Move Intent Framework | Movement Bardock Testnet | Hub Chain |
| EVM IntentEscrow | Base Sepolia | Connected Chain |
| Trusted Verifier | Cloud/VPS | Off-chain Service |

---

## Network Configuration

### Movement Bardock Testnet (Hub Chain)

> **Reference**: [Movement Network Endpoints](https://docs.movementnetwork.xyz/devs/networkEndpoints)

| Property | Value |
|----------|-------|
| Network Name | Movement Bardock Testnet |
| RPC URL | `https://testnet.movementnetwork.xyz/v1` |
| Faucet UI | `https://faucet.movementnetwork.xyz/` |
| Faucet API | `https://faucet.testnet.movementnetwork.xyz/` |
| Chain ID | `250` |
| Explorer | `https://explorer.movementnetwork.xyz/?network=bardock+testnet` |

### Base Sepolia Testnet (Connected Chain)

| Property | Value |
|----------|-------|
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

### 2. Accounts & Keys

- [ ] **Movement Account**: Create/fund deployer wallet on Movement Bardock
- [ ] **Base Account**: Create/fund deployer wallet on Base Sepolia
- [ ] **Verifier Keys**: Generate Ed25519 keypair for verifier service
- [ ] **Verifier ETH Address**: Derive ECDSA address for EVM signature verification

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

## Phase 1: Generate Keys & Configure

### 1.0 Setup Environment File ✅

```bash
cp env.testnet.example .env.testnet
```

All generated keys below should be saved to `.testnet-keys.env`.

### 1.1 Generate Movement Keys (Nightly Wallet Compatible) ✅

Create three accounts in Nightly Wallet: deployer, requester, and solver.

**Setup Nightly Wallet:**

1. Install [Nightly Wallet](https://nightly.app/) browser extension
2. Add Movement Bardock network (Settings → Networks → Add Custom):
   - Name: `Movement Bardock Testnet`
   - RPC: `https://testnet.movementnetwork.xyz/v1`

**Create accounts:**

1. Create first wallet (Deployer) - note the address shown
2. Create second wallet (Requester) - note the address shown
3. Create third wallet (Solver) - note the address shown

**Export private keys:**

For each account: Account → Export Private Key → copy the hex string

**Save to `.testnet-keys.env`:**

- `MOVEMENT_DEPLOYER_PRIVATE_KEY` / `MOVEMENT_DEPLOYER_ADDRESS`
- `MOVEMENT_REQUESTER_PRIVATE_KEY` / `MOVEMENT_REQUESTER_ADDRESS`
- `MOVEMENT_SOLVER_PRIVATE_KEY` / `MOVEMENT_SOLVER_ADDRESS`

### 1.2 Generate Base Keys (MetaMask Compatible) ✅

Create three accounts in MetaMask: deployer, requester, and solver.

**Setup MetaMask:**

1. Install [MetaMask](https://metamask.io/) browser extension
2. Add Base Sepolia network (Settings → Networks → Add Network):
   - Network Name: `Base Sepolia`
   - RPC URL: `https://sepolia.base.org`
   - Chain ID: `84532`
   - Currency Symbol: `ETH`
   - Explorer: `https://sepolia.basescan.org`

**Create accounts:**

1. Create first account (Deployer) - note the address shown
2. Create second account (Requester) - note the address shown
3. Create third account (Solver) - note the address shown

**Export private keys:**

For each account: Account menu → Account details → Show private key → copy

**Save to `.testnet-keys.env`:**

- `BASE_DEPLOYER_PRIVATE_KEY` / `BASE_DEPLOYER_ADDRESS`
- `BASE_REQUESTER_PRIVATE_KEY` / `BASE_REQUESTER_ADDRESS`
- `BASE_SOLVER_PRIVATE_KEY` / `BASE_SOLVER_ADDRESS`

### 1.3 Generate Verifier Keypair ✅

Requires nix development shell for correct Rust version:

```bash
# From project root
nix develop -c bash -c "cd trusted-verifier && cargo run --bin generate_keys"
```

Save to `.testnet-keys.env`:

- `private_key` (base64) → `VERIFIER_PRIVATE_KEY`
- `public_key` (base64) → `VERIFIER_PUBLIC_KEY`

### 1.4 Get Verifier Ethereum Address ✅

Derives the Ethereum address from the verifier's ECDSA key (used for EVM signature verification):

```bash
# From project root
nix develop -c bash -c "cd trusted-verifier && cargo run --bin get_verifier_eth_address"
```

Save to `.testnet-keys.env` → `VERIFIER_ETH_ADDRESS`

### 1.5 Fund All Accounts ✅

The intent flow is **USDC/pyUSD (Movement) → USDC/pyUSD (Base)**, so we need:

- MOVE tokens for gas on Movement
- USDC/pyUSD on Movement for the requester to create intents
- ETH for gas on Base Sepolia
- USDC/pyUSD on Base for the escrow flow

**Movement Testnet:**

1. **MOVE (for gas)**: Go to <https://faucet.movementnetwork.xyz/>
   - Fund all 3 accounts: Deployer, Requester, Solver

2. **USDC/pyUSD**: Get testnet stablecoins on Movement
   - <https://faucet.circle.com/> (select Movement/Aptos Testnet if available) - for USDC
   - <https://faucet.paxos.com/> - for pyUSD (Paxos USD)
   - Or bridge from another testnet

**Base Sepolia:**

1. **ETH (for gas)**: Go to <https://www.alchemy.com/faucets/base-sepolia>
   - Fund all 3 accounts: Deployer, Requester, Solver
   - Need ~0.1 ETH each

2. **USDC/pyUSD**: Get testnet stablecoins on Base Sepolia
   - <https://faucet.circle.com/> (select Base Sepolia) - for USDC
   - <https://faucet.paxos.com/> - for pyUSD (Paxos USD)
   - Fund Requester and Solver accounts

### 1.6 Create Testnet Configuration

Create `trusted-verifier/config/verifier_testnet.toml` using values from `.env.testnet`:

```toml
# Testnet Configuration: Movement Bardock + Base Sepolia

[hub_chain]
name = "Movement Bardock Testnet"
rpc_url = "https://testnet.movementnetwork.xyz/v1"
chain_id = 250
intent_module_address = "<MOVEMENT_INTENT_MODULE_ADDRESS>"  # Fill after deployment
escrow_module_address = ""
known_accounts = ["<MOVEMENT_REQUESTER_ADDRESS>", "<MOVEMENT_SOLVER_ADDRESS>"]

[connected_chain_evm]
name = "Base Sepolia"
rpc_url = "https://sepolia.base.org"
chain_id = 84532
escrow_contract_address = "<BASE_ESCROW_CONTRACT_ADDRESS>"  # Fill after deployment
verifier_address = "<VERIFIER_ETH_ADDRESS>"

[verifier]
private_key = "<VERIFIER_PRIVATE_KEY>"
public_key = "<VERIFIER_PUBLIC_KEY>"
polling_interval_ms = 5000
validation_timeout_ms = 60000

[api]
host = "0.0.0.0"
port = 3333
cors_origins = ["*"]
```

---

## Phase 2: Deploy Move Intent Framework (Movement)

### Quick Start (Automated)

Use the deployment script:

```bash
./testing-infra/testnet/deploy-movement-testnet.sh
```

The script will:
1. Read keys from `.testnet-keys.env`
2. Configure Movement CLI profile
3. Compile Move modules
4. Deploy to Movement Bardock Testnet
5. Verify deployment
6. Display the deployed address to save

**Save the displayed address** to `.testnet-keys.env` as `MOVEMENT_INTENT_MODULE_ADDRESS`.

### Manual Deployment (Alternative)

If you prefer to deploy manually:

#### 2.1 Configure Movement CLI for Movement Testnet

```bash
# Initialize profile for Movement Bardock
movement init --profile movement-testnet --network custom \
  --rest-url https://testnet.movementnetwork.xyz/v1 \
  --faucet-url https://faucet.movementnetwork.xyz/

# Fund account if needed (or use the faucet UI)
movement account fund-with-faucet --profile movement-testnet --amount 100000000
```

#### 2.2 Get Deployer Address

```bash
export DEPLOYER_ADDRESS=$(movement config show-profiles --profile movement-testnet | jq -r '.Result["movement-testnet"].account')
echo "Deployer address: 0x$DEPLOYER_ADDRESS"
```

#### 2.3 Deploy Move Modules

```bash
cd move-intent-framework

# Compile first
movement move compile \
  --named-addresses mvmt_intent=0x$DEPLOYER_ADDRESS \
  --skip-fetch-latest-git-deps

# Deploy
movement move publish \
  --profile movement-testnet \
  --named-addresses mvmt_intent=0x$DEPLOYER_ADDRESS \
  --skip-fetch-latest-git-deps \
  --assume-yes
```

#### 2.4 Verify Deployment

```bash
# Check modules are deployed
movement move view \
  --profile movement-testnet \
  --function-id 0x$DEPLOYER_ADDRESS::intent::get_intent_count \
  --args address:0x$DEPLOYER_ADDRESS
```

**Save**: `INTENT_MODULE_ADDRESS=0x$DEPLOYER_ADDRESS`

---

## Phase 3: Deploy EVM IntentEscrow (Base Sepolia)

### Quick Start (Automated)

Use the deployment script:

```bash
./testing-infra/testnet/deploy-base-testnet.sh
```

The script will:
1. Read keys from `.testnet-keys.env`
2. Create Hardhat `.env` file
3. Install dependencies if needed
4. Deploy IntentEscrow to Base Sepolia
5. Optionally verify contract on Basescan (if API key is set)
6. Display the deployed address to save

**Save the displayed address** to `.testnet-keys.env` as `BASE_ESCROW_CONTRACT_ADDRESS`.

### Manual Deployment (Alternative)

If you prefer to deploy manually:

#### 3.1 Configure Hardhat for Base Sepolia

Ensure `evm-intent-framework/hardhat.config.js` includes Base Sepolia network:

```javascript
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    hardhat: { chainId: 31337 },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
      chainId: 84532,
      accounts: process.env.DEPLOYER_PRIVATE_KEY 
        ? [process.env.DEPLOYER_PRIVATE_KEY] 
        : [],
    },
  },
  etherscan: {
    apiKey: {
      baseSepolia: process.env.BASESCAN_API_KEY || "",
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
    ],
  },
};
```

#### 3.2 Create Environment File

Create `evm-intent-framework/.env`:

```bash
DEPLOYER_PRIVATE_KEY=<your-private-key>
VERIFIER_ADDRESS=<verifier-eth-address>
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=<optional-for-verification>
```

#### 3.3 Deploy Contract

```bash
cd evm-intent-framework
npm install

# Deploy to Base Sepolia
npx hardhat run scripts/deploy.js --network baseSepolia
```

#### 3.4 Verify Contract (Optional)

```bash
npx hardhat verify --network baseSepolia <CONTRACT_ADDRESS> <VERIFIER_ADDRESS>
```

**Save**: `ESCROW_CONTRACT_ADDRESS=<deployed-address>`

---

## Phase 4: Deploy Trusted Verifier

### 4.1 Build Verifier

```bash
cd trusted-verifier
cargo build --release
```

### 4.2 Update Configuration

Edit `config/verifier_testnet.toml` with deployed addresses:

- `hub_chain.intent_module_address` → Movement deployed address
- `connected_chain_evm.escrow_contract_address` → Base Sepolia deployed address

### 4.3 Run Verifier Service

```bash
VERIFIER_CONFIG_PATH=config/verifier_testnet.toml \
  ./target/release/trusted-verifier
```

### 4.4 Verify Service Health

```bash
curl -s http://localhost:3333/health
curl -s http://localhost:3333/public-key
```

---

## Phase 5: Post-Deployment Verification

### 5.1 Checklist

- [ ] Move modules deployed and callable on Movement Bardock
- [ ] IntentEscrow deployed on Base Sepolia
- [ ] Verifier service running and healthy
- [ ] Verifier monitoring both chains
- [ ] End-to-end intent flow tested

### 5.2 Test Intent Flow (USDC/pyUSD → USDC/pyUSD)

1. **Requester creates Intent on Movement** - offers USDC/pyUSD, wants USDC/pyUSD on Base
2. **Requester creates Escrow on Base Sepolia** - deposits USDC/pyUSD for solver
3. **Solver fulfills Intent on Movement** - sends USDC/pyUSD to requester
4. **Verifier generates approval** - confirms fulfillment
5. **Solver claims Escrow on Base Sepolia** - receives USDC/pyUSD

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
|--------|-------------|
| `MOVEMENT_PRIVATE_KEY` | Private key for Movement deployer account |
| `BASE_DEPLOYER_PRIVATE_KEY` | Private key for Base Sepolia deployer |
| `VERIFIER_ETH_ADDRESS` | Ethereum address derived from verifier keys |
| `VERIFIER_PRIVATE_KEY` | Ed25519 private key (base64) for verifier |
| `VERIFIER_PUBLIC_KEY` | Ed25519 public key (base64) for verifier |
| `BASESCAN_API_KEY` | (Optional) For contract verification |

---

## Deployed Addresses (Fill After Deployment)

| Component | Network | Address |
|-----------|---------|---------|
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
2. [ ] Generate and secure verifier keys
3. [ ] Deploy Move modules to Movement Bardock
4. [ ] Deploy IntentEscrow to Base Sepolia
5. [ ] Configure and deploy Trusted Verifier
6. [ ] Run end-to-end test
7. [ ] Set up monitoring
8. [ ] Document deployed addresses
