# Trusted Verifier – Usage Guide

This guide covers how to run the verifier locally with the dual‑chain setup, the event linkage the verifier relies on, and operational debugging tips.

## Configuration

File: `trusted-verifier/config/verifier.toml` (relative to project root)

- **hub_chain**: `rpc_url`, `chain_id`, `intent_module_address`, `known_accounts` (required)
- **connected_chain_apt**: `rpc_url`, `chain_id`, `intent_module_address`, `escrow_module_address`, `known_accounts` (optional, for Aptos escrow monitoring)
- **connected_chain_evm**: `rpc_url`, `chain_id`, `escrow_contract_address`, `verifier_address` (optional, for EVM escrow monitoring)
- **verifier**: `private_key` (base64, 32‑byte), `public_key` (base64, 32‑byte), polling/timeout
- **api**: `host`, `port`

The verifier automatically monitors all configured chains concurrently:

- Hub chain monitoring is always enabled
- Aptos connected chain monitoring starts if `[connected_chain_apt]` is configured
- EVM connected chain monitoring starts if `[connected_chain_evm]` is configured

Keys

- Use `cargo run --bin generate_keys` to print base64 keys
- Copy into `verifier.toml` (both keys must correspond)

## Running

Run the full E2E test flow:

```
./testing-infra/e2e-tests-apt/run-tests.sh
```

This script sets up chains, deploys contracts, submits intents, runs integration tests, starts the verifier, and releases escrow.

## Event linkage

- **Hub chain**
  - `LimitOrderEvent` — intent creation (issuer, amounts, metadata, expiry, revocable, solver, offered_chain_id, desired_chain_id)
  - `LimitOrderFulfillmentEvent` — fulfillment (intent_id, solver, provided amount/metadata)
- **Connected Aptos chain**
  - `OracleLimitOrderEvent` (escrow) — escrow deposit with verifier public key and desired amounts
- **Connected EVM chain**
  - `EscrowInitialized` — escrow creation (intentId, maker, token, reservedSolver)
- **Linking**
  - Shared `intent_id` across chains links hub intents to escrows on connected chains
  - Verifier validates `chain_id` matches between intent `offered_chain_id` and escrow `chain_id`
  - Each `EscrowEvent` includes a `chain_type` field (Move, Evm, Solana) set by the verifier based on which monitor discovered the event. This is trusted because it comes from the verifier's configuration, not from untrusted event data.

## Cross‑Chain Flow

1) Hub: Alice creates regular (non‑oracle) intent
2) Connected: Alice creates escrow (non‑revocable), includes verifier public key, links `intent_id`
3) Hub: Bob fulfills the intent
4) Verifier: observes fulfillment + escrow, generates approval (signature over BCS(u64=1))
5) Script: submits `complete_escrow_from_fa` on connected chain with approval

## Balances and Debugging

- The integration script prints initial and final balances for Alice/Bob on both chains
- For APT, CLI coin balance is not the FA store balance; scripts focus on consistent before/after checks
- Useful commands:
  - `curl -s http://127.0.0.1:3333/health`
  - `curl -s http://127.0.0.1:3333/public-key`
  - `curl -s http://127.0.0.1:3333/events | jq`
  - `curl -s http://127.0.0.1:3333/approvals | jq`
