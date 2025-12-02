# Verifier-Based Negotiation Routing

## Overview

The Trusted Verifier service provides negotiation routing capabilities for off-chain communication between requesters and solvers for reserved intent creation. This eliminates the need for direct requester-solver communication and provides a centralized discovery and messaging service.

## Current State

**Current Negotiation Flow** (Verifier-Based):

- Requester creates draft intent (off-chain)
- Requester submits draft to verifier via `POST /draft-intent` (draft is open to any solver)
- Solvers poll verifier via `GET /draft-intents/pending` to discover drafts
- First solver to sign submits signature via `POST /draft-intent/:id/signature` (FCFS)
- Requester polls verifier via `GET /draft-intent/:id/signature` to retrieve signature
- Requester submits intent on-chain with solver's signature

**Solver Registration:**

- **On-chain**: Solvers register via `solver_registry::register_solver()` with public key and addresses (for signature verification)

**Benefits:**

- No direct requester-solver communication required
- Centralized negotiation tracking via verifier
- FCFS (First Come First Served) ensures fair competition

## Proposed Solution

The Trusted Verifier service will act as a negotiation message queue/hub:

1. **Message Queue (Polling-Based, FCFS)**: Requester submits draft (NO solver_address - open to any solver) → verifier stores draft → ALL solvers poll verifier for drafts → multiple solvers can sign → verifier accepts FIRST signature (FCFS) → requester polls verifier for signature (includes solver_address of first signer)
2. **Centralized Service**: Single endpoint instead of direct solver contact
3. **Monitoring**: Verifier logs negotiation attempts and success rates

**Note**: This is a **polling-based, FCFS (First Come First Served)** approach. Solvers regularly poll the verifier for new drafts. The verifier does NOT push/forward messages to solvers. This eliminates the need for solvers to run servers or expose public endpoints. **Drafts are open to any solver** - no solver_address specified when submitting. **First signature wins** - later signatures are rejected.

## Implementation Plan

### Phase 1: Draft Intent Submission & Message Queue

**New API Endpoints:**

- `POST /draft-intent` - Requester submits draft intent (open to any solver)
  - Request: `{ "requester_address": "0x...", "draft_data": {...} }`
  - Note: NO `solver_address` - draft is open to any registered solver
  - Response: `{ "success": true, "data": { "draft_id": "...", "status": "pending" } }`
  
- `GET /draft-intent/:id` - Get draft intent status
  - Response: `{ "success": true, "data": { "draft_id": "...", "status": "pending|signed|expired", ... } }`
  
- `GET /draft-intents/pending` - Solver polls for pending drafts (all solvers see all drafts)
  - No query params - returns ALL pending drafts
  - Response: `{ "success": true, "data": [{ "draft_id": "...", "requester_address": "0x...", "draft_data": {...} }] }`
  - Note: All solvers see all pending drafts - no filtering by solver_address

**Storage Requirements:**

- Message queue/storage for draft intents
- Draft metadata (id, requester, status, timestamp, expiry)
- First signature storage (solver_address, signature, timestamp) - only first signature accepted

### Phase 2: Signature Submission & Retrieval (FCFS)

**New API Endpoints:**

- `POST /draft-intent/:id/signature` - Solver submits signature
  - Request: `{ "solver_address": "0x...", "signature": "<hex>", "public_key": "<hex>" }`
  - Response (if first signature): `{ "success": true, "data": { "draft_id": "...", "status": "signed" } }`
  - Response (if already signed): `{ "success": false, "error": "Draft already signed by another solver", "data": null }` (409 Conflict)
  - **FCFS Logic**: Only the FIRST signature is accepted. Later signatures are rejected with 409 Conflict.
  
- `GET /draft-intent/:id/signature` - Requester polls for signature
  - Response (if signed): `{ "success": true, "data": { "signature": "<hex>", "solver_address": "0x...", "timestamp": ... } }`
  - Response (if pending): `{ "success": false, "error": "Draft not yet signed", "data": null }` (202 Accepted)
  - Returns the FIRST signature received (with solver_address of first signer)

**Validation:**

- Verify solver is registered on-chain (query via `mvm_client`)
- Verify signature format (Ed25519, hex-encoded)
- **FCFS Check**: If draft already has a signature, reject with 409 Conflict
- Update draft status to "signed" only if this is the first signature
- Store solver_address from signature (solver adds their address when signing)

### Phase 4: Authentication & Authorization

**Security Requirements:**

- Solver authentication: Verify solver owns the registered address
- Requester authentication: Optional, for tracking/rate limiting
- Signature verification: Verify solver signatures match registered public key

**Implementation:**

- JWT tokens or API keys for solver authentication
- Rate limiting per requester/solver
- Request signing for authenticated endpoints

### Phase 5: Monitoring & Logging

**New API Endpoints:**

- `GET /negotiations/stats` - Get negotiation statistics
  - Response: `{ "success": true, "data": { "total_drafts": 100, "signed": 85, "expired": 10, ... } }`
  
- `GET /negotiations/:draft_id/history` - Get negotiation history
  - Response: `{ "success": true, "data": [{ "event": "created", "timestamp": ... }, ...] }`

**Logging:**

- Log all draft submissions
- Log signature submissions
- Track success/failure rates
- Monitor solver response times

## Technical Implementation

### Storage Options

**Option A: In-Memory (Simple)**

- Use Rust HashMap/BTreeMap for storage
- Lost on restart (acceptable for MVP)
- Fast, no dependencies

**Option B: SQLite (Persistent)**

- Persistent storage across restarts
- Simple file-based database
- Good for production

**Option C: Redis (Scalable)**

- External dependency
- Better for distributed deployments
- More complex setup

**Recommendation**: Start with Option A (in-memory), migrate to Option B (SQLite) if persistence needed.

### API Design

**Base URL**: `http://<host>:<port>` (same as existing verifier API)

**Response Format** (consistent with existing API):

```json
{
  "success": true|false,
  "message": "string",
  "data": <payload|null>
}
```

**Error Handling**:

- 400 Bad Request: Invalid request format
- 401 Unauthorized: Authentication failed
- 404 Not Found: Draft/solver not found
- 409 Conflict: Draft already signed/expired
- 500 Internal Server Error: Server error

### Integration Points

**Requester Integration:**

1. Submit draft via `POST /draft-intent` (NO solver_address - open to any solver)
2. Poll `GET /draft-intent/:id/signature` for solver response
3. Receive signature with solver_address (from first solver that signed)
4. Use signature and solver_address to create reserved intent on-chain

**Solver Integration:**

1. Register ON-CHAIN via `solver_registry::register_solver()` (if not already registered)
2. **Poll** `GET /draft-intents/pending` regularly (e.g., every 5-30 seconds) for new drafts
   - All solvers see ALL pending drafts (no filtering)
3. Sign draft (add solver_address to draft to create IntentToSign) and submit via `POST /draft-intent/:id/signature`
4. If signature accepted (first): Success! Draft is now signed
5. If signature rejected (409 Conflict): Another solver signed first (FCFS)
6. Continue polling for new drafts

**Polling Approach**: Solvers actively poll the verifier. The verifier does NOT push/forward messages to solvers. This eliminates the need for solvers to run servers or expose public endpoints. **FCFS (First Come First Served)**: First solver to sign wins, later signatures rejected.

## Testing Strategy

1. **Unit Tests**: ✅ Test storage, routing logic, validation
   - ✅ Storage tests: `tests/storage_tests.rs` (comprehensive CRUD, FCFS, expiry, status transitions)
   - ✅ Signature validation tests: `tests/negotiation_validation_tests.rs` (format validation)
   - ✅ Solver registration tests: `tests/mvm_client_tests.rs` (`get_solver_public_key` tests)
2. **Integration Tests**: ⏸️ Test API endpoints end-to-end (deferred - handlers are thin wrappers)
3. **E2E Tests**: ⏸️ Test full negotiation flow (requester → verifier → solver → verifier → requester) (future)
4. **Load Tests**: ⏸️ Test concurrent draft submissions and polling (future)

## Migration Path

**Phase 1**: Deploy alongside existing verifier (no breaking changes)
**Phase 2**: Update documentation to use verifier routing (completed)
**Phase 3**: Authentication & Authorization (see Task 3 in `tasks.json`)

## Future Enhancements

- WebSocket support for real-time push notifications (alternative to polling)
- Multi-solver bidding (requesters can submit to multiple solvers)
- Reputation system for solvers
- Fee mechanism for verifier message queue service
- Draft intent expiry and cleanup

## Files to Modify/Create

1. **✅ Create**: `trusted-verifier/src/api/negotiation.rs` - Negotiation routing endpoints
2. **✅ Create**: `trusted-verifier/src/storage/` - Storage module for draft intents
3. **✅ Modify**: `trusted-verifier/src/api/mod.rs` - Add negotiation routes
4. **✅ Modify**: `trusted-verifier/src/api/generic.rs` - Integrate negotiation routes
5. **✅ Create**: `trusted-verifier/tests/storage_tests.rs` - Storage unit tests
6. **✅ Create**: `trusted-verifier/tests/negotiation_validation_tests.rs` - Signature validation tests
7. **✅ Update**: `trusted-verifier/tests/mvm_client_tests.rs` - Added `get_solver_public_key` tests
8. **⏸️ Update**: `docs/trusted-verifier/api.md` - Document new endpoints (pending)
9. **⏸️ Create**: `docs/trusted-verifier/negotiation-routing.md` - User guide (pending)
10. **✅ Update**: `.taskmaster/tasks/TESTNET_DEPLOYMENT_PLAN.md` - Note current state and future enhancement

## Dependencies

- No new external dependencies (use existing Rust stdlib)
- Optional: `sqlx` or `rusqlite` if using SQLite storage for draft intents
- Optional: `serde_json` (already in use)

## Success Criteria

- Requesters can submit drafts without specifying solver_address (open to any solver)
- Solvers can poll for drafts and submit signatures
- FCFS logic works correctly (first signature wins, later signatures rejected)
- Requesters receive signature with solver_address from first signer
- Full negotiation flow works end-to-end
- Verifier-based negotiation routing is the standard method for off-chain negotiation
