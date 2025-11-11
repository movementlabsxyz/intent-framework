module mvmt_intent::intent_reservation {
    use std::bcs;
    use std::option::{Self, Option};
    use std::signer;
    use aptos_std::ed25519;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::account;
    use aptos_framework::event;

    /// The public key used for verification is invalid.
    const EINVALID_PUBLIC_KEY: u64 = 1;
    /// The signature is invalid.
    const EINVALID_SIGNATURE: u64 = 2;
    /// The signer is not the authorized solver for this intent.
    const EUNAUTHORIZED_SOLVER: u64 = 3;
    /// The authentication key format is invalid (not a single-key Ed25519 account).
    const EINVALID_AUTH_KEY_FORMAT: u64 = 4;
    /// The public key validation failed.
    const EPUBLIC_KEY_VALIDATION_FAILED: u64 = 5;

    #[event]
    struct IntentHashVerificationEvent has store, drop {
        hash: vector<u8>,
    }

    /// Struct to hold reservation details for an intent.
    /// This is stored inside the `TradeIntent` if the intent is reserved for a specific solver.
    struct IntentReserved has store, drop {
        solver: address,
    }

    /// The draft intent data created by the offerer (without solver address).
    struct IntentDraft has copy, drop {
        source_metadata: Object<Metadata>,
        source_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
    }

    /// The data structure that is signed by the solver off-chain.
    public struct IntentToSign has copy, drop {
        source_metadata: Object<Metadata>,
        source_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
        solver: address,
    }

    /// Creates an IntentToSign struct from the provided parameters.
    public fun new_intent_to_sign(
        source_metadata: Object<Metadata>,
        source_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
        solver: address,
    ): IntentToSign {
        IntentToSign {
            source_metadata,
            source_amount,
            desired_metadata,
            desired_amount,
            expiry_time,
            issuer,
            solver,
        }
    }

    /// Hashes the IntentToSign struct for off-chain signing by a solver.
    public fun hash_intent(intent_to_sign: IntentToSign): vector<u8> {
        bcs::to_bytes(&intent_to_sign)
    }

    /// Creates a draft intent without a solver address.
    public fun create_draft_intent(
        source_metadata: Object<Metadata>,
        source_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
    ): IntentDraft {
        IntentDraft {
            source_metadata,
            source_amount,
            desired_metadata,
            desired_amount,
            expiry_time,
            issuer,
        }
    }

    /// Converts draft intent to IntentToSign by adding solver address.
    public fun add_solver_to_draft_intent(
        draft: IntentDraft,
        solver: address,
    ): IntentToSign {
        IntentToSign {
            source_metadata: draft.source_metadata,
            source_amount: draft.source_amount,
            desired_metadata: draft.desired_metadata,
            desired_amount: draft.desired_amount,
            expiry_time: draft.expiry_time,
            issuer: draft.issuer,
            solver: solver,
        }
    }

    /// Verifies a solver's signature against the intent data and creates a reservation.
    /// This version accepts the public key directly for testing purposes.
    public fun verify_and_create_reservation_with_public_key(
        intent_to_sign: IntentToSign,
        solver_signature: vector<u8>,
        solver_public_key: &ed25519::UnvalidatedPublicKey,
    ): Option<IntentReserved> {
        let signature = ed25519::new_signature_from_bytes(solver_signature);
        let message = hash_intent(intent_to_sign);

        if (ed25519::signature_verify_strict(&signature, solver_public_key, message)) {
            option::some(IntentReserved { solver: intent_to_sign.solver })
        } else {
            option::none()
        }
    }

    /// Verifies a solver's signature against the intent data and creates a reservation.
    /// 
    /// # Aborts
    /// - `EINVALID_AUTH_KEY_FORMAT`: Authentication key is not a single-key Ed25519 account (length != 33 or first byte != 0x00)
    /// - `EPUBLIC_KEY_VALIDATION_FAILED`: Public key extracted from authentication key failed validation
    /// - `EINVALID_SIGNATURE`: Signature verification failed
    public fun verify_and_create_reservation(
        intent_to_sign: IntentToSign,
        solver_signature: vector<u8>,
    ): Option<IntentReserved> {
        let solver = intent_to_sign.solver;
        let auth_key = account::get_authentication_key(solver);
        
        // We only support single-key Ed25519 accounts for now.
        // Authentication key format: 33 bytes [0x00, 32-byte Ed25519 public key]
        let auth_key_len = std::vector::length(&auth_key);
        let first_byte = if (auth_key_len > 0) { *std::vector::borrow(&auth_key, 0) } else { 0 };
        
        // Check for old format (33 bytes with 0x00 prefix)
        let public_key_bytes = if (auth_key_len == 33 && first_byte == 0x00) {
            // Old format: extract public key from bytes 1-33
            std::vector::slice(&auth_key, 1, 33)
        } else if (auth_key_len == 32) {
            // New format: authentication key is the account address (32 bytes)
            // For new format accounts, we cannot extract the Ed25519 public key from the address
            // This means accounts created with aptos init (new format) are not supported
            abort std::error::invalid_argument(EINVALID_AUTH_KEY_FORMAT)
        } else {
            // Invalid format
            abort std::error::invalid_argument(EINVALID_AUTH_KEY_FORMAT)
        };

        let unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(public_key_bytes);
        let validated_public_key_opt = ed25519::public_key_validate(&unvalidated_public_key);
        
        if (option::is_none(&validated_public_key_opt)) {
            abort std::error::invalid_argument(EPUBLIC_KEY_VALIDATION_FAILED)
        };

        let signature = ed25519::new_signature_from_bytes(solver_signature);

        let message = hash_intent(intent_to_sign);
        
        // Emit event with hash being verified (useful for debugging signature mismatches)
        event::emit(IntentHashVerificationEvent {
            hash: message,
        });

        if (ed25519::signature_verify_strict(&signature, &unvalidated_public_key, message)) {
            option::some(IntentReserved { solver })
        } else {
            abort std::error::invalid_argument(EINVALID_SIGNATURE)
        }
    }

    /// Ensures the signer of the transaction is the authorized solver.
    public fun ensure_solver_authorized(solver_signer: &signer, reservation: &Option<IntentReserved>) {
        if (option::is_some(reservation)) {
            let intent_reserved = option::borrow(reservation);
            assert!(signer::address_of(solver_signer) == intent_reserved.solver, EUNAUTHORIZED_SOLVER);
        }
    }

    /// Creates an IntentReserved struct for testing or direct use.
    /// This is a simple constructor that doesn't require signature verification.
    public fun new_reservation(solver: address): IntentReserved {
        IntentReserved { solver }
    }
}
