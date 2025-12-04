# Solver Tools

Tools for solvers to interact with the Intent Framework, including signature generation for reserved intents. Solvers fulfill intents by providing desired tokens or assets. For reserved intents, solvers must sign an `IntentToSign` structure off-chain.

## Quick Start

See the [component README](../../solver/README.md) for quick start commands.

## Overview

The solver provides both **command-line utilities** and a **continuous service**:

### Solver Service

A continuous service that automatically:

1. **Polls verifier** for pending draft intents
2. **Evaluates acceptance** based on configured token pairs and exchange rates
3. **Signs and submits** signatures for accepted drafts (FCFS - first solver to sign wins)
4. **Tracks signed intents** and monitors for their on-chain creation
5. **Fulfills inflow intents** by monitoring escrow deposits and providing tokens on hub chain
6. **Executes outflow transfers** by transferring tokens on connected chains and fulfilling hub intents

### Command-Line Utilities

1. **Generate Signatures**: Sign `IntentToSign` structures for reserved intents
2. **Build Transaction Templates**: Generate Move VM/EVM payload templates with embedded `intent_id` for outflow fulfillment

## Architecture

Solvers interact through verifier-based negotiation routing: Creator submits draft to verifier → solvers poll verifier for drafts → first solver to sign wins (FCFS) → creator retrieves signature from verifier.

See [Negotiation Routing Guide](../docs/trusted-verifier/negotiation-routing.md) for details.

Components:

- **Signing Service**: Continuous service that polls verifier and signs accepted drafts
- **Intent Tracker**: Monitors signed intents and tracks their lifecycle from draft to on-chain creation
- **Inflow Fulfillment Service**: Monitors escrow deposits on connected chains and fulfills inflow intents on hub chain
- **Outflow Fulfillment Service**: Executes transfers on connected chains and fulfills outflow intents on hub chain
- **Chain Clients**: Clients for interacting with hub chain (Movement) and connected chains (MVM/EVM)
- **Signature Generator**: Creates Ed25519 signatures for `IntentToSign` structures
- **Transaction Template Generator**: Produces Move/EVM templates with embedded `intent_id`
- **Key Management**: Reads solver private keys from Movement/Aptos configuration

## Project Structure

```text
solver/
├── src/
│   ├── bin/              # Binaries (solver service, sign_intent, connected_chain_tx_template)
│   ├── service/          # Service modules
│   │   ├── signing.rs    # Signing service loop (polls verifier, signs drafts)
│   │   ├── tracker.rs    # Intent tracker (monitors signed intents)
│   │   ├── inflow.rs     # Inflow fulfillment service (monitors escrows, fulfills intents)
│   │   └── outflow.rs    # Outflow fulfillment service (executes transfers, fulfills intents)
│   ├── chains/            # Chain clients
│   │   ├── hub.rs        # Hub chain client (Movement)
│   │   ├── connected_mvm.rs  # Connected MVM chain client
│   │   └── connected_evm.rs   # Connected EVM chain client
│   ├── acceptance.rs      # Token pair acceptance logic
│   ├── config.rs          # Configuration management
│   ├── crypto/            # Cryptographic operations (hashing, signing)
│   └── verifier_client.rs # HTTP client for verifier API
├── config/               # Configuration templates
└── Cargo.toml
```

## Solver Service

The solver service runs continuously, polling the verifier for pending drafts and automatically signing accepted intents.

### Configuration

Create a `solver.toml` configuration file based on the template:

```bash
cp solver/config/solver.template.toml solver.toml
# Edit solver.toml with your settings
```

See `solver/config/solver.template.toml` for the complete configuration template with all available options and examples.

### Running the Service

```bash
# Using config file
cargo run --bin solver -- --config solver.toml

# Using environment variable
SOLVER_CONFIG_PATH=solver.toml cargo run --bin solver

# Default location (solver.toml in current directory)
cargo run --bin solver
```

The service will:

1. Load configuration from the specified file or `SOLVER_CONFIG_PATH` environment variable
2. Initialize logging and connect to the verifier
3. Start multiple concurrent service loops:
   - **Signing loop**: Polls verifier for pending drafts, evaluates acceptance, signs and submits
   - **Tracking loop**: Monitors hub chain for intent creation events
   - **Inflow loop**: Monitors connected chains for escrow deposits and fulfills inflow intents
   - **Outflow loop**: Executes transfers on connected chains and fulfills outflow intents
4. Handle FCFS conflicts (if another solver already signed)
5. Automatically fulfill intents when conditions are met

### Acceptance Logic

The solver accepts drafts based on:

- **Token Pair Support**: The draft's token pair must be configured
- **Exchange Rate**: `offered_amount >= desired_amount * exchange_rate` (solver breaks even or profits)

All tokens are treated as fungible assets - no hardcoded USD/NATIVE distinctions.

## Inflow Fulfillment

The solver automatically fulfills **inflow intents** (tokens locked on connected chain, desired on hub):

1. **Monitor Escrows**: Polls connected chain for escrow deposits matching tracked inflow intents
2. **Fulfill Intent**: Calls hub chain `fulfill_inflow_intent` when escrow is detected
3. **Release Escrow**: Polls verifier for approval signature, then releases escrow on connected chain

### Supported Chains

- **Move VM Chains**: Uses `complete_escrow_from_fa` entry function
- **EVM Chains**: Uses Hardhat script `claim-escrow.js` (calls `IntentEscrow.claim()`)

**Note**: EVM escrow claiming currently uses Hardhat scripts. Future improvement: implement directly using Rust Ethereum libraries (`ethers-rs` or `alloy`) for better error handling and type safety.

## Outflow Fulfillment

The solver automatically fulfills **outflow intents** (tokens locked on hub, desired on connected chain):

1. **Execute Transfer**: Transfers tokens on connected chain to requester's address
2. **Get Verifier Approval**: Calls verifier `/validate-outflow-fulfillment` with transaction hash
3. **Fulfill Intent**: Calls hub chain `fulfill_outflow_intent` with verifier signature

### Supported Chains

- **Move VM Chains**: Uses `transfer_with_intent_id` entry function
- **EVM Chains**: Executes ERC20 transfer with `intent_id` encoded in calldata

**Note**: EVM transfer execution currently uses Hardhat scripts. Future improvement: implement directly using Rust Ethereum libraries (`ethers-rs` or `alloy`) for better integration and error handling.

## Intent Tracking

The solver tracks the lifecycle of intents:

1. **Signed**: Draftintent has been signed and submitted to verifier
2. **Created**: Intent has been created on-chain by requester
3. **Fulfilled**: Intent has been fulfilled by the solver

The tracker distinguishes between inflow and outflow intents for proper fulfillment routing.

## Reserved Intents

Reserved intents require off-chain negotiation:

1. Creator creates a draft intent (off-chain)
2. Solver signs the `IntentToSign` structure (off-chain)
3. Creator submits the intent on-chain with the solver's signature

This ensures only the authorized solver can fulfill the intent, providing commitment guarantees for cross-chain scenarios.

**Negotiation**: Creator submits draft to verifier, solvers poll for drafts (FCFS). See [Negotiation Routing Guide](../docs/trusted-verifier/negotiation-routing.md) for details.

Signature generation process:

1. Calls `utils::get_intent_hash()` to construct and hash the `IntentToSign` structure
2. Extracts the hash from the transaction event
3. Reads the solver's private key from Movement/Aptos config
4. Signs the hash with Ed25519
5. Outputs signature (hex with `0x` prefix) to stdout
6. Outputs public key (hex with `0x` prefix) to stderr with `PUBLIC_KEY:` prefix

**Note**: For accounts created with `movement init` or `aptos init` (new authentication key format), the public key must be passed explicitly to the Move contract. The script extracts the public key from stderr output.

### Usage Example

Generate a signature for an intent:

```bash
cargo run --bin sign_intent -- \
  --profile solver-chain1 \
  --chain-address 0x123 \
  --offered-metadata 0xabc \
  --offered-amount 1000000 \
  --offered-chain-id 1 \
  --desired-metadata 0xdef \
  --desired-amount 1000000 \
  --desired-chain-id 2 \
  --expiry-time 1234567890 \
  --issuer 0xrequester \
  --solver 0xsolver \
  --chain-num 1
```

For more details on the reserved intent flow, see [Protocol Documentation](../protocol.md).

## Connected Chain Outflow Fulfillment Transaction Templates

Outflow intents require solvers to execute a transfer on the connected chain with the hub `intent_id` encoded. The `connected_chain_tx_template` binary produces templates for Move VM and EVM transfers.

**Move VM:**

```bash
cargo run --bin connected_chain_tx_template -- \
  --chain mvm \
  --recipient <address> \
  --metadata <metadata_address> \
  --amount <amount> \
  --intent-id <intent_id>
```

**EVM:**

```bash
cargo run --bin connected_chain_tx_template -- \
  --chain evm \
  --recipient <address> \
  --amount <amount> \
  --intent-id <intent_id>
```

The binary prints parameters that must match the hub intent and the command/calldata to execute the transfer.

**Note:** For Move VM, `--metadata` must be a hex address (object address of Metadata), not a module path. The intent framework module must be deployed on the connected chain.

## Chain Clients

The solver includes chain clients for interacting with different blockchain types:

### Hub Chain Client (`chains/hub.rs`)

- **Query Intent Events**: `get_intent_events()` - Queries hub chain for intent creation and fulfillment events
- **Fulfill Inflow Intent**: `fulfill_inflow_intent()` - Calls `fulfill_inflow_intent` entry function
- **Fulfill Outflow Intent**: `fulfill_outflow_intent()` - Calls `fulfill_outflow_intent` entry function

### Connected MVM Client (`chains/connected_mvm.rs`)

- **Query Escrow Events**: `get_escrow_events()` - Queries connected MVM chain for escrow creation events
- **Transfer with Intent ID**: `transfer_with_intent_id()` - Executes token transfer with embedded `intent_id`
- **Complete Escrow**: `complete_escrow_from_fa()` - Releases escrow with verifier signature

### Connected EVM Client (`chains/connected_evm.rs`)

- **Query Escrow Events**: `get_escrow_events()` - Queries EVM chain for `EscrowInitialized` events via JSON-RPC
- **Claim Escrow**: `claim_escrow()` - Claims escrow using Hardhat script (calls `IntentEscrow.claim()`)
- **Transfer with Intent ID**: `transfer_with_intent_id()` - Placeholder for ERC20 transfer with embedded `intent_id` (requires Ethereum signing library)

**Note**: EVM operations currently use Hardhat scripts for transaction execution. Future improvement: implement directly using Rust Ethereum libraries (`ethers-rs` or `alloy`) for better integration and error handling.
