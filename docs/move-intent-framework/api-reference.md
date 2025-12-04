# API Reference

This document provides a comprehensive reference for the Intent Framework's public APIs.

## Core Intent API

### Creating an Intent

```move
public fun create_intent<Source: store, Args: store + drop, Witness: drop>(
    offered_resource: Source,
    argument: Args,
    expiry_time: u64,
    issuer: address,
    _witness: Witness,
): Object<Intent<Source, Args>>
```

**Parameters:**

- `offered_resource`: The resource being offered in the trade
- `argument`: Trade-specific arguments (e.g., wanted asset type and amount)
- `expiry_time`: Unix timestamp when the intent expires
- `issuer`: Address of the intent creator
- `_witness`: Type witness for compile-time verification

**Returns:** An object containing the trade intent

### Starting a Trading Session

```move
public fun start_intent_session<Source: store, Args: store + drop>(
    intent: Object<Intent<Source, Args>>,
): (Source, Session<Args>)
```

**Parameters:**

- `intent`: The trade intent object

**Returns:** A tuple containing the offered resource and a trading session

### Completing an Intent

```move
public fun finish_intent_session<Witness: drop, Args: store + drop>(
    session: Session<Args>,
    _witness: Witness,
)
```

**Parameters:**

- `session`: The active trading session
- `_witness`: Verification witness proving trade conditions were met

## Fungible Asset Intent API

### Creating a Fungible Asset Intent

```move
public fun create_fa_to_fa_intent_entry(
    offered_metadata: Object<Metadata>,
    offered_amount: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    expiry_time: u64,
    solver_address: address,
    solver_signature: vector<u8>,
): Object<Intent<FungibleAsset, FungibleAssetLimitOrder>>
```

**Parameters:**

- `offered_metadata`: Metadata of the asset being offered
- `offered_amount`: Amount of the asset being offered
- `desired_metadata`: Metadata of the desired asset
- `desired_amount`: Amount of the desired asset
- `expiry_time`: Unix timestamp when the intent expires
- `solver_address`: Address of the authorized solver (0x0 for unreserved)
- `solver_signature`: Solver's signature (empty vector for unreserved)

**Returns:** A fungible asset trade intent object

### Creating an Inflow Request Intent

```move
public fun create_inflow_intent(
    account: &signer,
    offered_metadata: Object<Metadata>,
    offered_amount: u64,
    offered_chain_id: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    desired_chain_id: u64,
    expiry_time: u64,
    intent_id: address,
    solver: address,
    solver_signature: vector<u8>,
): Object<Intent<FungibleStoreManager, FungibleAssetLimitOrder>>
```

**Returns:** The created intent object

**Parameters:**

- `account`: Signer creating the intent
- `offered_metadata`: Metadata of the token type being offered (locked on another chain)
- `offered_amount`: Amount of tokens that will be locked in escrow on the connected chain
- `offered_chain_id`: Chain ID where the escrow will be created (where tokens are offered)
- `desired_metadata`: Metadata of the desired token type
- `desired_amount`: Amount of desired tokens
- `desired_chain_id`: Chain ID where this intent is created (where tokens are desired)
- `expiry_time`: Unix timestamp when intent expires
- `intent_id`: Intent ID for cross-chain linking
- `solver`: Address of the solver authorized to fulfill this intent (must be registered in solver registry)
- `solver_signature`: Ed25519 signature from the solver authorizing this intent

**Note**: This intent has 0 tokens locked on the hub chain because tokens are in escrow elsewhere. The `offered_amount` specifies how much will be locked in escrow on the connected chain. Cross-chain intents MUST be reserved to ensure solver commitment across chains. The solver's public key is looked up from the on-chain solver registry, so the solver must be registered before calling this function.

**Aborts:**

- `ESOLVER_NOT_REGISTERED`: Solver is not registered in the solver registry
- `EINVALID_SIGNATURE`: Signature verification failed

**Entry Function:** For transaction calls, use `create_inflow_intent_entry` which has the same parameters but doesn't return a value (entry functions cannot return values in Move).

### Creating an Outflow Request Intent

```move
public fun create_outflow_intent(
    requester_signer: &signer,
    offered_metadata: Object<Metadata>,
    offered_amount: u64,
    offered_chain_id: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    desired_chain_id: u64,
    expiry_time: u64,
    intent_id: address,
    requester_address_connected_chain: address,
    verifier_public_key: vector<u8>,
    solver: address,
    solver_signature: vector<u8>,
): Object<Intent<FungibleStoreManager, OracleGuardedLimitOrder>>
```

**Returns:** The created intent object

**Parameters:**

- `requester_signer`: Signer of the requester creating the intent
- `offered_metadata`: Metadata of the token type being offered (locked on hub chain)
- `offered_amount`: Amount of tokens to withdraw and lock on hub chain
- `offered_chain_id`: Chain ID of the hub chain (where tokens are locked)
- `desired_metadata`: Metadata of the desired token type
- `desired_amount`: Amount of desired tokens
- `desired_chain_id`: Chain ID where tokens are desired (connected chain)
- `expiry_time`: Unix timestamp when intent expires
- `intent_id`: Intent ID for cross-chain linking
- `requester_address_connected_chain`: Address on connected chain where solver should send tokens
- `verifier_public_key`: Public key of the verifier that will approve the connected chain transaction (32 bytes)
- `solver`: Address of the solver authorized to fulfill this intent (must be registered in solver registry)
- `solver_signature`: Ed25519 signature from the solver authorizing this intent

**Note**: This intent locks actual tokens on the hub chain. The solver must transfer tokens on the connected chain first, then the verifier approves that transaction. The solver receives the locked tokens from the hub as reward. This function uses `OracleGuardedLimitOrder` and requires verifier signature for fulfillment.

**Aborts:**

- `ESOLVER_NOT_REGISTERED`: Solver is not registered in the solver registry
- `EINVALID_SIGNATURE`: Signature verification failed
- `EINVALID_REQUESTER_ADDRESS`: `requester_address_connected_chain` is zero address (0x0)

**Entry Function:** For transaction calls, use `create_outflow_intent_entry` which has the same parameters but doesn't return a value (entry functions cannot return values in Move).

### Fulfilling an Inflow Request Intent

```move
public entry fun fulfill_inflow_intent(
    solver: &signer,
    intent: Object<Intent<FungibleStoreManager, FungibleAssetLimitOrder>>,
    payment_amount: u64,
)
```

**Parameters:**

- `solver`: Signer fulfilling the intent
- `intent`: Object reference to the inflow intent to fulfill
- `payment_amount`: Amount of tokens to provide

**Note**: This function is used to fulfill inflow intents where tokens are locked on the connected chain (in escrow) and desired on the hub. The solver provides the desired tokens to the requester on the hub chain. No verifier signature is required for inflow intents.

### Fulfilling an Outflow Request Intent

```move
public entry fun fulfill_outflow_intent(
    solver: &signer,
    intent: Object<Intent<FungibleStoreManager, OracleGuardedLimitOrder>>,
    verifier_signature_bytes: vector<u8>,
)
```

**Parameters:**

- `solver`: Signer fulfilling the intent
- `intent`: Object reference to the outflow intent to fulfill
- `verifier_signature_bytes`: Verifier's Ed25519 signature as bytes (signs the intent_id, proves connected chain transfer)

**Note**: This function is used to fulfill outflow intents where tokens are locked on the hub chain and desired on the connected chain. The solver must first transfer tokens on the connected chain, then the verifier approves that transaction. The solver receives the locked tokens from the hub as reward. Verifier signature is required - it proves the solver transferred tokens on the connected chain.

### Starting a Fungible Asset Session

```move
public fun start_fa_offering_session(
    intent: Object<Intent<FungibleAsset, FungibleAssetLimitOrder>>,
): (FungibleAsset, Session<FungibleAssetLimitOrder>)
```

**Parameters:**

- `intent`: The fungible asset trade intent

**Returns:** The offered fungible asset and trading session

### Completing a Fungible Asset Intent

```move
public fun finish_fa_receiving_session(
    session: Session<FungibleAssetLimitOrder>,
    payment: FungibleAsset,
): FungibleAsset
```

**Parameters:**

- `session`: The active trading session
- `payment`: The fungible asset being provided as payment

**Returns:** The fungible asset received in exchange

## Intent Reservation API

### Creating a Draft Intent

```move
public fun create_draft_intent(
    offered_metadata: Object<Metadata>,
    offered_amount: u64,
    offered_chain_id: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    desired_chain_id: u64,
    expiry_time: u64,
    requester: address,
): Draftintent
```

**Parameters:**

- `offered_metadata`: Metadata of the asset being offered
- `offered_amount`: Amount of the asset being offered
- `offered_chain_id`: Chain ID where offered tokens are located
- `desired_metadata`: Metadata of the desired asset
- `desired_amount`: Amount of the desired asset
- `desired_chain_id`: Chain ID where desired tokens are located
- `expiry_time`: Unix timestamp when the intent expires
- `requester`: Address of the intent creator

**Returns:** A draft intent for off-chain sharing

### Adding Solver to Draft

```move
public fun add_solver_to_draft_intent(
    draft: Draftintent,
    solver_address: address,
): IntentToSign
```

**Parameters:**

- `draft`: The draft intent
- `solver_address`: Address of the solver

**Returns:** Intent data ready for signing

### Verifying and Creating Reservation

```move
public fun verify_and_create_reservation(
    intent_to_sign: IntentToSign,
    solver_signature: vector<u8>,
): Option<IntentReserved>
```

**Parameters:**

- `intent_to_sign`: The intent data that was signed
- `solver_signature`: The solver's signature

**Returns:** An optional reservation if verification succeeds

**Note**: This function extracts the public key from the solver's authentication key on-chain. It only works for accounts with the old authentication key format (33 bytes with 0x00 prefix). For cross-chain intents or accounts created with `movement init` or `aptos init` (new format, 32 bytes), solvers must be registered in the solver registry and use `verify_and_create_reservation_from_registry` instead.

**Aborts:**

- `EINVALID_AUTH_KEY_FORMAT`: Authentication key format is invalid
- `EPUBLIC_KEY_VALIDATION_FAILED`: Public key validation failed
- `EINVALID_SIGNATURE`: Signature verification failed

### Verifying and Creating Reservation from Registry

```move
public fun verify_and_create_reservation_from_registry(
    intent_to_sign: IntentToSign,
    solver_signature: vector<u8>,
): Option<IntentReserved>
```

**Parameters:**

- `intent_to_sign`: The intent data that was signed
- `solver_signature`: The solver's signature

**Returns:** An optional reservation if verification succeeds

**Note**: This function looks up the solver's public key from the on-chain solver registry. The solver must be registered in the registry before calling this function. This is the recommended approach for cross-chain intents and accounts created with `movement init` or `aptos init` (new format, 32 bytes) where the public key cannot be extracted from the authentication key.

**Aborts:**

- `ESOLVER_NOT_REGISTERED`: Solver is not registered in the solver registry
- `EINVALID_SIGNATURE`: Signature verification failed

## Oracle Intent API

### Creating Oracle-Guarded Intents

```move
public fun create_oracle_guarded_intent_entry(
    offered_metadata: Object<Metadata>,
    offered_amount: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    expiry_time: u64,
    oracle_requirement: OracleSignatureRequirement,
): Object<Intent<FungibleAsset, OracleGuardedLimitOrder>>
```

**Parameters:**

- `offered_metadata`: Metadata of the asset being offered
- `offered_amount`: Amount of the asset being offered
- `desired_metadata`: Metadata of the desired asset
- `desired_amount`: Amount of the desired asset
- `expiry_time`: Unix timestamp when the intent expires
- `oracle_requirement`: Oracle signature requirements

**Returns:** An oracle-guarded trade intent object

### Creating Oracle Signature Requirements

```move
public fun new_oracle_signature_requirement(
    min_reported_value: u64,
    public_key: ed25519::UnvalidatedPublicKey,
): OracleSignatureRequirement
```

**Parameters:**

- `min_reported_value`: Minimum value the oracle must report
- `public_key`: Authorized oracle's public key

**Returns:** Oracle signature requirement struct

### Creating Oracle Signature Witness

```move
public fun new_oracle_signature_witness(
    reported_value: u64,
    signature: ed25519::Signature,
): OracleSignatureWitness
```

**Parameters:**

- `reported_value`: Value reported by the oracle
- `signature`: Oracle's signature

**Returns:** Oracle signature witness for verification

### Starting Oracle Intent Session

```move
public fun start_oracle_intent_session(
    intent: Object<Intent<FungibleAsset, OracleGuardedLimitOrder>>,
): (FungibleAsset, Session<OracleGuardedLimitOrder>)
```

**Parameters:**

- `intent`: The oracle-guarded trade intent

**Returns:** The offered fungible asset and trading session

### Completing Oracle Intent

```move
public fun finish_oracle_intent_session(
    session: Session<OracleGuardedLimitOrder>,
    oracle_witness: OracleSignatureWitness,
): FungibleAsset
```

**Parameters:**

- `session`: The active trading session
- `oracle_witness`: Oracle signature witness proving external data

**Returns:** The fungible asset received in exchange

## Solver Registry API

The solver registry is a permissionless registry that stores solver information on-chain, including Ed25519 public keys for signature verification and connected chain addresses for cross-chain validation.

### Registering a Solver

```move
public entry fun register_solver(
    solver: &signer,
    public_key: vector<u8>,
    connected_chain_evm_address: Option<vector<u8>>,
    connected_chain_mvm_address: Option<address>,
)
```

**Parameters:**

- `solver`: The solver signing the transaction (becomes the solver's hub chain address)
- `public_key`: Ed25519 public key (32 bytes) for signature validation
- `connected_chain_evm_address`: Optional EVM address on connected chain (20 bytes, None if not applicable)
- `connected_chain_mvm_address`: Optional Move VM address on connected chain (None if not applicable)

**Note**: Solvers must be registered before creating reserved intents. The registry stores:

- The solver's Ed25519 public key (used for signature verification)
- The solver's connected chain EVM address (for EVM outflow validation)
- The solver's connected chain Move VM address (for MVM outflow validation)

For outflow intents, the verifier validates that the transaction solver on the connected chain matches the registered connected chain address from the hub registry.

**Aborts:**

- `E_NOT_INITIALIZED`: Solver registry not initialized
- `E_SOLVER_ALREADY_REGISTERED`: Solver is already registered
- `E_PUBLIC_KEY_LENGTH_INVALID`: Public key is not 32 bytes
- `E_EVM_ADDRESS_LENGTH_INVALID`: EVM address is not 20 bytes (if provided)
- `E_INVALID_PUBLIC_KEY`: Public key is not a valid Ed25519 public key

**Usage with Movement CLI:**

When calling `register_solver` via `movement move run`, Option types cannot be passed as "null". Use placeholder values instead:

- For `connected_chain_evm_address`: Use `0x0000000000000000000000000000000000000000` (20 bytes of zeros) if not applicable
- For `connected_chain_mvm_address`: Use `0x0` (zero address) if not applicable

Example:

```bash
movement move run --profile solver-profile \
  --function-id 0x<module_address>::solver_registry::register_solver \
  --args hex:<public_key> hex:<evm_address> address:<mvm_address>
```

### Querying Solver Information

The registry provides view functions to query solver information:

- `get_public_key(solver_addr: address): vector<u8>` - Get solver's Ed25519 public key
- `get_connected_chain_evm_address(solver_addr: address): Option<vector<u8>>` - Get solver's EVM address on connected chain
- `get_connected_chain_mvm_address(solver_addr: address): Option<address>` - Get solver's Move VM address on connected chain
- `is_registered(solver_addr: address): bool` - Check if solver is registered
- `get_solver_info(solver_addr: address): (bool, vector<u8>, Option<vector<u8>>, Option<address>, u64)` - Get all solver information

## Oracle Events

### LimitOrderEvent

Emitted when a fungible asset intent is created:

```move
struct LimitOrderEvent has store, drop {
    intent_address: address,
    intent_id: address,
    offered_metadata: Object<Metadata>,
    offered_amount: u64,
    offered_chain_id: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    desired_chain_id: u64,
    requester: address,
    expiry_time: u64,
    revocable: bool,
}
```

### OracleLimitOrderEvent

Emitted when an oracle-guarded intent or escrow is created:

```move
struct OracleLimitOrderEvent has store, drop {
    intent_address: address,
    intent_id: address,
    offered_metadata: Object<Metadata>,
    offered_amount: u64,
    offered_chain_id: u64,
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    desired_chain_id: u64,
    requester: address,
    expiry_time: u64,
    min_reported_value: u64,
    revocable: bool,
    reserved_solver: Option<address>,
    requester_address_connected_chain: Option<address>,
}
```

## Error Codes

- `EINVALID_SIGNATURE`: Signature verification failed
- `EINVALID_AUTH_KEY_FORMAT`: Authentication key format is invalid (not a single-key Ed25519 account with old format)
- `EPUBLIC_KEY_VALIDATION_FAILED`: Public key extracted from authentication key failed validation
- `EINTENT_EXPIRED`: Intent has passed its expiry time
- `EUNAUTHORIZED_SOLVER`: Attempted execution by unauthorized solver
- `EINVALID_AMOUNT`: Invalid asset amount specified
- `EINVALID_METADATA`: Invalid asset metadata provided
- `ESIGNATURE_REQUIRED`: Oracle signature witness is missing
- `EORACLE_VALUE_TOO_LOW`: Oracle-reported value below threshold

## Type Definitions

### Intent

```move
struct Intent<Source, Args> has key {
    offered_resource: Source,
    argument: Args,
    self_delete_ref: DeleteRef,
    expiry_time: u64,
    witness_type: TypeInfo,
    reservation: Option<IntentReserved>,
    revocable: bool,
}
```

### Session

```move
struct Session<Args> {
    argument: Args,
    witness_type: TypeInfo,
    reservation: Option<IntentReserved>,
}
```

### FungibleAssetLimitOrder

```move
struct FungibleAssetLimitOrder has store, drop {
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    requester: address,
    intent_id: Option<address>,
    offered_chain_id: u64,
    desired_chain_id: u64,
}
```

### OracleSignatureRequirement

```move
struct OracleSignatureRequirement has store, drop {
    min_reported_value: u64,
    public_key: ed25519::UnvalidatedPublicKey,
}
```

### OracleGuardedLimitOrder

```move
struct OracleGuardedLimitOrder has store, drop {
    desired_metadata: Object<Metadata>,
    desired_amount: u64,
    desired_chain_id: u64,
    offered_chain_id: u64,
    requester: address,
    requirement: OracleSignatureRequirement,
    intent_id: address,
    requester_address_connected_chain: Option<address>,
}
```

### OracleSignatureWitness

```move
struct OracleSignatureWitness has drop {
    reported_value: u64,
    signature: ed25519::Signature,
}
```
