# Cross-chain Oracle Intent Integration Test

This directory contains orchestration scripts and docs to run a cross-chain test with two local Aptos nodes (Chain A and Chain B) and the oracle monitoring service.

## Prerequisites
- Rust toolchain
- Aptos CLI

## Environment Setup
Use the Docker-based localnets from `testing-infra` to run Hub and Connected chains.

```bash
# Single chain
./testing-infra/single-chain/setup-docker-chain.sh

# Multi-chain (two independent localnets)
./testing-infra/multi-chain/setup-dual-chains.sh

# Stop both chains
./testing-infra/multi-chain/stop-dual-chains.sh
```


## Verify Nodes
```bash
# Check Chain A (default ports)
curl http://127.0.0.1:8080/v1

# Check Chain B (Docker default ports)
curl http://127.0.0.1:8082/v1
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
1. Deploy `aptos-intent` modules on both Hub Chain (A) and Connected Chain (B).
2. [Hub Chain] Create regular (non-oracle) intent requesting tokens.
3. [Connected Chain] Create escrow with tokens locked (with verifier public key), linking to hub intent via intent_id.
4. Start verifier service to monitor both chains and validate conditions.
5. [Hub Chain] Solver fulfills the intent on Hub Chain (no verifier signature needed).
6. Verifier observes hub fulfillment and generates approval signature for escrow release.
7. [Connected Chain] Escrow can be released with verifier approval signature.

## Next
- Add a script-based runner (`test_cross_chain_oracle_intent.ts` or `.py`) and minimal monitoring service stub.

## Config
This folder contains a committed `config.json` with placeholders:

```json
{
  "chainA": { "restUrl": "http://127.0.0.1:8080", "privateKeyHex": "REPLACE_WITH_DEV_PRIVATE_KEY_HEX" },
  "chainB": { "restUrl": "http://127.0.0.1:8082", "privateKeyHex": "REPLACE_WITH_DEV_PRIVATE_KEY_HEX" },
  "intentModuleAddress": "REPLACE_WITH_MODULE_ADDRESS_ON_CHAIN_A",
  "vaultAddress": "REPLACE_WITH_VAULT_ADDRESS_ON_CHAIN_B",
  "pollingMs": 2000
}
```

Replace the placeholders locally with your validator endpoints and dev keys.

## Note
Currently using main Aptos repository; Movement fork integration planned for later.

