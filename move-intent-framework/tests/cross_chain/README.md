# Cross-chain Oracle Intent Integration Test

This directory contains orchestration scripts and docs to run a cross-chain test with two local Aptos nodes (Chain A and Chain B) and the oracle monitoring service.

## Prerequisites
- Rust toolchain
- Aptos CLI
- Aptos `aptos-core` repository (main branch)
- Optional: Restic v0.18+ if using Movement DB snapshots

Run this once to ensure `aptos-core` is available:
```bash
bash move-intent-framework/tests/cross_chain/setup_aptos_core.sh
```

## Setup Two Nodes
Use the modern Aptos CLI approach to set up both Chain A and Chain B.

### Automated Setup (Recommended)
1. **Chain A (Port 8080)**:
   ```bash
   # Terminal 1
   aptos node run-localnet --with-faucet --force-restart --assume-yes
   ```

2. **Chain B (Port 8081)**:
   ```bash
   # Terminal 2 - Use different ports
   aptos node run-localnet --with-faucet --force-restart --assume-yes --faucet-port 8082
   ```

### Legacy Manual Setup (Alternative)
Use the automated single validator script for more control:
1. **Chain A (Port 8080)**:
   ```bash
   ./infra/single-validator/run_local_validator.sh
   ```

2. **Chain B (Port 8081)**:
   ```bash
   # Modify the script to use different ports, or run manually:
   # Copy infra/single-validator/work/validator_node.yaml to chainB/
   # Edit ports: 8080->8081, 6180->6182, etc.
   # Run: aptos-node -f chainB/validator_node.yaml
   ```

 



## Verify Nodes
```bash
# Check Chain A (default ports)
curl http://127.0.0.1:8080/v1

# Check Chain B (if using different ports)
curl http://127.0.0.1:8081/v1
```

**Expected Response:**
```json
{
  "chain_id": 4,
  "epoch": "2", 
  "ledger_version": "25",
  "oldest_ledger_version": "0",
  "ledger_timestamp": "1761052515406711",
  "node_role": "validator",
  "oldest_block_height": "0",
  "block_height": "11",
  "git_hash": ""
}
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

## Note
Currently using main Aptos repository; Movement fork integration planned for later.

