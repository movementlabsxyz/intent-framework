# Trusted Verifier – Usage Guide

This guide covers how to run the verifier locally with the dual‑chain setup, the event linkage the verifier relies on, and operational debugging tips.

## Configuration

File: [`trusted-verifier/config/verifier.toml`](../../trusted-verifier/config/verifier.toml)

- hub_chain / connected_chain: `rpc_url`, `chain_id`, module addresses, `known_accounts`
- verifier: `private_key` (base64, 32‑byte), `public_key` (base64, 32‑byte), polling/timeout
- api: `host`, `port`

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

- Hub chain
  - `LimitOrderEvent` — intent creation (issuer, amounts, metadata, expiry, revocable)
  - `LimitOrderFulfillmentEvent` — fulfillment (intent_id, solver, provided amount/metadata)
- Connected chain
  - `OracleLimitOrderEvent` (escrow) — escrow deposit with verifier public key and desired amounts
- Linking
  - Shared `intent_id` across chains

## Cross‑Chain Flow

1) Hub: Alice creates regular (non‑oracle) intent
2) Connected: Alice creates escrow (non‑revocable), includes verifier public key, links `intent_id`
3) Hub: Bob fulfills the intent
4) Verifier: observes fulfillment + escrow, generates approval (signature over BCS(u64=1))
5) Script: submits `complete_escrow_from_fa` on connected chain with approval

Notes
- Fulfillment correctness is enforced by Move; the verifier does not re‑validate fulfillment details
- The verifier confirms linkage and non‑revocability before approval

## Balances and Debugging

- The integration script prints initial and final balances for Alice/Bob on both chains
- For APT, CLI coin balance is not the FA store balance; scripts focus on consistent before/after checks
- Useful commands:
  - `curl -s http://127.0.0.1:3333/health`
  - `curl -s http://127.0.0.1:3333/public-key`
  - `curl -s http://127.0.0.1:3333/events | jq`
  - `curl -s http://127.0.0.1:3333/approvals | jq`

