# Verifier-Based Negotiation Routing

## Overview

Add negotiation routing capabilities to the Trusted Verifier service to facilitate off-chain communication between requesters and solvers for reserved intent creation. This eliminates the need for direct requester-solver communication and provides a centralized discovery and messaging service.

## Current State

**Current Negotiation Flow:**
- Requester creates draft intent (off-chain)
- Requester contacts solver directly (off-chain, manual/HTTP/messaging)
- Solver signs draft and returns signature (off-chain, direct response)
- Requester submits intent on-chain with solver's signature

**Limitations:**
- Requester must know how to contact solver
- No solver discovery mechanism
- No centralized negotiation tracking
- Direct communication required

## Proposed Solution

The Trusted Verifier service will act as a negotiation routing hub:

1. **Solver Discovery**: Solvers register with verifier; requesters query available solvers
2. **Message Routing**: Requester submits draft → verifier routes to solver → solver responds → verifier routes back
3. **Centralized Service**: Single endpoint instead of direct solver contact
4. **Monitoring**: Verifier logs negotiation attempts and success rates

## Implementation Plan

### Phase 1: Solver Registration & Discovery

**New API Endpoints:**

- `POST /solvers/register` - Register solver with verifier
  - Request: `{ "solver_address": "0x...", "public_key": "<base64>", "endpoints": {...} }`
  - Response: `{ "success": true, "solver_id": "..." }`
  
- `GET /solvers` - List available solvers
  - Response: `{ "success": true, "data": [{ "solver_address": "0x...", "status": "active", ... }] }`
  
- `GET /solvers/:address` - Get solver details
  - Response: `{ "success": true, "data": { "solver_address": "0x...", "public_key": "...", ... } }`

**Storage Requirements:**
- In-memory or persistent storage for solver registry
- Solver metadata (address, public key, status, registration timestamp)

### Phase 2: Draft Intent Submission & Routing

**New API Endpoints:**

- `POST /draft-intent` - Requester submits draft intent
  - Request: `{ "requester_address": "0x...", "draft_data": {...}, "solver_address": "0x..." }`
  - Response: `{ "success": true, "data": { "draft_id": "...", "status": "pending" } }`
  
- `GET /draft-intent/:id` - Get draft intent status
  - Response: `{ "success": true, "data": { "draft_id": "...", "status": "pending|signed|expired", ... } }`
  
- `GET /draft-intents/pending` - Solver polls for pending drafts (filtered by solver_address)
  - Query params: `?solver_address=0x...`
  - Response: `{ "success": true, "data": [{ "draft_id": "...", "requester_address": "0x...", "draft_data": {...} }] }`

**Storage Requirements:**
- Message queue/storage for draft intents
- Draft metadata (id, requester, solver, status, timestamp, expiry)

### Phase 3: Signature Submission & Routing

**New API Endpoints:**

- `POST /draft-intent/:id/signature` - Solver submits signature
  - Request: `{ "solver_address": "0x...", "signature": "<hex>", "public_key": "<hex>" }`
  - Response: `{ "success": true, "data": { "draft_id": "...", "status": "signed" } }`
  
- `GET /draft-intent/:id/signature` - Requester polls for signature
  - Response: `{ "success": true, "data": { "signature": "<hex>", "solver_address": "0x...", "timestamp": ... } }`

**Validation:**
- Verify solver address matches draft's target solver
- Verify signature format (Ed25519, hex-encoded)
- Update draft status to "signed"

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
1. Query `/solvers` to discover available solvers
2. Submit draft via `POST /draft-intent`
3. Poll `GET /draft-intent/:id/signature` for solver response
4. Use signature to create reserved intent on-chain

**Solver Integration:**
1. Register via `POST /solvers/register`
2. Poll `GET /draft-intents/pending` for new drafts
3. Sign draft and submit via `POST /draft-intent/:id/signature`
4. Continue monitoring for new drafts

## Testing Strategy

1. **Unit Tests**: Test storage, routing logic, validation
2. **Integration Tests**: Test API endpoints end-to-end
3. **E2E Tests**: Test full negotiation flow (requester → verifier → solver → verifier → requester)
4. **Load Tests**: Test concurrent draft submissions and polling

## Migration Path

**Phase 1**: Deploy alongside existing verifier (no breaking changes)
**Phase 2**: Update documentation to recommend verifier routing
**Phase 3**: Deprecate direct negotiation (optional, keep for backward compatibility)

## Future Enhancements

- WebSocket support for real-time notifications (instead of polling)
- Multi-solver bidding (requesters can submit to multiple solvers)
- Reputation system for solvers
- Fee mechanism for verifier routing service
- Draft intent expiry and cleanup

## Files to Modify/Create

1. **Create**: `trusted-verifier/src/api/negotiation.rs` - Negotiation routing endpoints
2. **Create**: `trusted-verifier/src/storage/` - Storage module for drafts and solvers
3. **Modify**: `trusted-verifier/src/api/mod.rs` - Add negotiation routes
4. **Modify**: `trusted-verifier/src/api/generic.rs` - Integrate negotiation routes
5. **Update**: `docs/trusted-verifier/api.md` - Document new endpoints
6. **Create**: `docs/trusted-verifier/negotiation-routing.md` - User guide
7. **Update**: `.taskmaster/tasks/TESTNET_DEPLOYMENT_PLAN.md` - Note current state and future enhancement

## Dependencies

- No new external dependencies (use existing Rust stdlib)
- Optional: `sqlx` or `rusqlite` if using SQLite storage
- Optional: `serde_json` (already in use)

## Success Criteria

- Requesters can discover solvers via API
- Requesters can submit drafts without direct solver contact
- Solvers can poll for drafts and submit signatures
- Full negotiation flow works end-to-end
- Backward compatible with existing direct negotiation flow

