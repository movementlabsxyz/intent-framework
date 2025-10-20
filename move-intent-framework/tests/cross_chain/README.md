# Cross-chain Oracle Intent Integration Test

This directory contains orchestration scripts and docs to run a cross-chain test with two local Aptos nodes (Chain A and Chain B) and the oracle monitoring service.

## Prerequisites
- Rust toolchain
- Aptos CLI
- Movement `aptos-core` repository (branches: `l1-migration` and `start_single_node_network`)
- Optional: Restic v0.18+ if using Movement DB snapshots

## Setup Two Nodes
Initialize nodes from scratch (l1-migration).

### Option 1: From Scratch (l1-migration)
1. Clone and build:
   ```bash
   git clone https://github.com/movementlabsxyz/aptos-core.git
   cd aptos-core && git checkout l1-migration
   cargo build -p aptos-node --release
   ```
2. Prepare per-node directories (A/B) and identities under separate ROOTs.
3. Use `aptos genesis set-validator-configuration` for each node.
4. Create `validator_node.yaml` per node (different ports for B).
5. Start nodes:
   ```bash
   aptos-node -f /path/to/chainA/validator_node.yaml
   aptos-node -f /path/to/chainB/validator_node.yaml
   ```

 



## Verify Nodes
```bash
curl http://127.0.0.1:8080/v1
curl http://127.0.0.1:8081/v1
```
Expect growing `block_height` and logs with executing transactions.

## Test Flow (High-Level)
1. Deploy or ensure `aptos-intent` modules on both A and B.
2. Create intent on Chain A (record intent-id).
3. Perform vault action on Chain B to satisfy intent.
4. Run monitoring service; it observes B and submits oracle fulfillment on A.
5. Confirm intent transitions to Fulfilled, then Close it on A.

## Next
- Add a script-based runner (`test_cross_chain_oracle_intent.ts` or `.py`) and minimal monitoring service stub.

## Config
This folder contains a committed `config.json` with placeholders:

```json
{
  "chainA": { "restUrl": "http://127.0.0.1:8080", "privateKeyHex": "REPLACE_WITH_DEV_PRIVATE_KEY_HEX" },
  "chainB": { "restUrl": "http://127.0.0.1:8081", "privateKeyHex": "REPLACE_WITH_DEV_PRIVATE_KEY_HEX" },
  "intentModuleAddress": "REPLACE_WITH_MODULE_ADDRESS_ON_CHAIN_A",
  "vaultAddress": "REPLACE_WITH_VAULT_ADDRESS_ON_CHAIN_B",
  "pollingMs": 2000
}
```

Replace the placeholders locally with your validator endpoints and dev keys.

