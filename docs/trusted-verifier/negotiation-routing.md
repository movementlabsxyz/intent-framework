# Negotiation Routing Guide

This guide explains how to use the verifier's negotiation routing capabilities for off-chain communication between requesters and solvers.

## Overview

The negotiation routing system enables:

- **Requesters** to submit draft intents without needing direct contact with solvers
- **Solvers** to discover and sign drafts through a centralized message queue
- **FCFS (First Come First Served)** logic where the first solver to sign wins

**Architecture**: Polling-based system where solvers poll the verifier for drafts. The verifier does NOT push/forward messages to solvers.

## Prerequisites

### Solver Prerequisites

- Must be registered on-chain via `solver_registry::register_solver()` with public key and addresses
- Must have Ed25519 keypair for signing drafts
- Must poll the verifier regularly (e.g., every 5-30 seconds)

### Requester Prerequisites

- Must have a Move VM address (for `requester_address`)
- Must prepare draft data matching the `IntentDraft` structure from Move

## Requester Workflow

### 1. Submit Draft Intent

Submit a draft intent to the verifier. The draft is open to any solver (no `solver_address` required).

```bash
curl -X POST http://127.0.0.1:3333/draft-intent \
  -H "Content-Type: application/json" \
  -d '{
    "requester_address": "0x123...",
    "draft_data": {
      "offered_metadata": "0x1::test::Token",
      "offered_amount": 1000,
      "desired_metadata": "0x1::test::Token2",
      "desired_amount": 2000
    },
    "expiry_time": 2000000
  }'
```

**Response**: Returns `draft_id` (UUID) and status `"pending"`

### 2. Poll for Signature

Poll the verifier regularly to check if a solver has signed your draft.

```bash
# Poll every 5 seconds
while true; do
  RESPONSE=$(curl -s http://127.0.0.1:3333/draft-intent/$DRAFT_ID/signature)
  if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
    SIGNATURE=$(echo "$RESPONSE" | jq -r '.data.signature')
    SOLVER_ADDRESS=$(echo "$RESPONSE" | jq -r '.data.solver_address')
    echo "Signature received from $SOLVER_ADDRESS: $SIGNATURE"
    break
  fi
  sleep 5
done
```

**Response codes**:

- `200 OK`: Draft is signed (signature available)
- `202 Accepted`: Draft is pending (not yet signed)
- `404 Not Found`: Draft doesn't exist

### 3. Use Signature On-Chain

Once you receive the signature, use it along with `solver_address` to create a reserved intent on-chain.

```bash
# Convert hex signature to bytes if needed
movement move run \
  --function-id "0x<module>::intent::create_reserved_intent" \
  --args "address:<solver_address>" "hex:<signature>" ...
```

## Solver Workflow

### 1. Register On-Chain (if not already registered)

Register your solver on-chain with public key and addresses:

```bash
movement move run \
  --function-id "0x<module>::solver_registry::register_solver" \
  --args "vector<u8>:<public_key_bytes>" "address:<evm_address>" "address:<mvm_address>"
```

### 2. Poll for Pending Drafts

Poll the verifier regularly to discover new drafts. All solvers see all pending drafts.

```bash
# Poll every 10 seconds
while true; do
  DRAFTS=$(curl -s http://127.0.0.1:3333/draft-intents/pending | jq -r '.data[]')
  for DRAFT in $DRAFTS; do
    DRAFT_ID=$(echo "$DRAFT" | jq -r '.draft_id')
    # Process draft...
  done
  sleep 10
done
```

### 3. Sign Draft

Sign the draft and submit your signature. **FCFS Logic**: First signature wins, later signatures are rejected with 409 Conflict.

```bash
# Sign draft (add solver_address to create IntentToSign)
SIGNATURE=$(sign_draft "$DRAFT_DATA" "$SOLVER_ADDRESS" "$PRIVATE_KEY")

curl -X POST http://127.0.0.1:3333/draft-intent/$DRAFT_ID/signature \
  -H "Content-Type: application/json" \
  -d "{
    \"solver_address\": \"$SOLVER_ADDRESS\",
    \"signature\": \"$SIGNATURE\",
    \"public_key\": \"$PUBLIC_KEY\"
  }"
```

**Response codes**:

- `200 OK`: Signature accepted (you were first!)
- `409 Conflict`: Draft already signed by another solver (you were too late)
- `400 Bad Request`: Invalid signature format or solver not registered

### 4. Continue Polling

Continue polling for new drafts. If your signature was rejected (409), try the next draft.

## FCFS (First Come First Served) Logic

- **First signature wins**: The first solver to submit a valid signature gets the draft
- **Later signatures rejected**: Subsequent signatures are rejected with 409 Conflict
- **No solver selection**: Requesters don't specify which solver should sign
- **Open competition**: All registered solvers can compete for any draft

## Signature Format

- **Type**: Ed25519
- **Length**: 64 bytes (128 hex characters)
- **Format**: Hex string (with or without `0x` prefix)
- **Validation**: Verifier checks signature format and verifies solver is registered on-chain

## Error Handling

### Common Errors

**400 Bad Request**:

- Invalid signature format (wrong length, invalid hex)
- Solver not registered on-chain

**404 Not Found**:

- Draft doesn't exist
- Draft ID is invalid

**409 Conflict**:

- Draft already signed by another solver (FCFS)

**500 Internal Server Error**:

- Verifier failed to connect to hub chain
- Internal server error

## Best Practices

### Requester Best Practices

- Set reasonable `expiry_time` (Unix timestamp)
- Poll regularly but not too frequently (every 5-10 seconds)
- Handle 202 Accepted responses gracefully (draft not yet signed)
- Store `draft_id` for tracking

### Solver Best Practices

- Poll regularly (every 5-30 seconds) to discover new drafts quickly
- Sign drafts as fast as possible (FCFS competition)
- Handle 409 Conflict gracefully (draft already taken)
- Verify draft data before signing
- Monitor your signature acceptance rate

## Example: Full Flow

### Requester Side

```bash
# 1. Submit draft
DRAFT_RESPONSE=$(curl -s -X POST http://127.0.0.1:3333/draft-intent \
  -H "Content-Type: application/json" \
  -d '{"requester_address": "0x123...", "draft_data": {...}, "expiry_time": 2000000}')
DRAFT_ID=$(echo "$DRAFT_RESPONSE" | jq -r '.data.draft_id')

# 2. Poll for signature
while true; do
  SIG_RESPONSE=$(curl -s http://127.0.0.1:3333/draft-intent/$DRAFT_ID/signature)
  if echo "$SIG_RESPONSE" | jq -e '.success == true' > /dev/null; then
    SIGNATURE=$(echo "$SIG_RESPONSE" | jq -r '.data.signature')
    SOLVER=$(echo "$SIG_RESPONSE" | jq -r '.data.solver_address')
    echo "Got signature from $SOLVER"
    break
  fi
  sleep 5
done

# 3. Use signature on-chain
movement move run --function-id "..." --args "address:$SOLVER" "hex:$SIGNATURE" ...
```

### Solver Side

```bash
# 1. Poll for drafts
while true; do
  DRAFTS=$(curl -s http://127.0.0.1:3333/draft-intents/pending | jq -r '.data[]')
  
  for DRAFT in $DRAFTS; do
    DRAFT_ID=$(echo "$DRAFT" | jq -r '.draft_id')
    DRAFT_DATA=$(echo "$DRAFT" | jq -r '.draft_data')
    
    # 2. Sign draft
    SIGNATURE=$(sign_draft "$DRAFT_DATA" "$SOLVER_ADDRESS" "$PRIVATE_KEY")
    
    # 3. Submit signature
    RESPONSE=$(curl -s -X POST http://127.0.0.1:3333/draft-intent/$DRAFT_ID/signature \
      -H "Content-Type: application/json" \
      -d "{\"solver_address\": \"$SOLVER_ADDRESS\", \"signature\": \"$SIGNATURE\", \"public_key\": \"$PUBLIC_KEY\"}")
    
    if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
      echo "Successfully signed draft $DRAFT_ID"
    elif echo "$RESPONSE" | jq -e '.error | contains("already signed")' > /dev/null; then
      echo "Draft $DRAFT_ID already taken"
    fi
  done
  
  sleep 10
done
```

## Limitations

- **In-memory storage**: Drafts are lost on verifier restart (acceptable for MVP)
- **No persistence**: No database backing (future enhancement)
- **Polling overhead**: Solvers must poll regularly (future: WebSocket support)
- **No authentication**: Currently no rate limiting or authentication (future enhancement)

## Future Enhancements

- WebSocket support for real-time push notifications
- Persistent storage (SQLite/Redis)
- Authentication and rate limiting
- Negotiation statistics and monitoring
- Draft intent expiry and cleanup automation
