module aptos_intent::intent_reservation {
    use std::bcs;
    use std::option::{Self, Option};
    use std::signer;
    use aptos_std::ed25519;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::account;

    /// The public key used for verification is invalid.
    const EINVALID_PUBLIC_KEY: u64 = 1;
    /// The signature is invalid.
    const EINVALID_SIGNATURE: u64 = 2;
    /// The signer is not the authorized solver for this intent.
    const EUNAUTHORIZED_SOLVER: u64 = 3;

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
    public fun verify_and_create_reservation(
        intent_to_sign: IntentToSign,
        solver_signature: vector<u8>,
    ): Option<IntentReserved> {
        let solver = intent_to_sign.solver;
        let auth_key = account::get_authentication_key(solver);
        // We only support single-key Ed25519 accounts for now.
        if (std::vector::length(&auth_key) != 33 || auth_key[0] != 0x00) {
            return option::none()
        };
        let public_key_bytes = std::vector::slice(&auth_key, 1, 33);

        let unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(public_key_bytes);
        let validated_public_key_opt = ed25519::public_key_validate(&unvalidated_public_key);
        if (option::is_none(&validated_public_key_opt)) {
            return option::none()
        };

        let signature = ed25519::new_signature_from_bytes(solver_signature);

        let message = hash_intent(intent_to_sign);

        if (ed25519::signature_verify_strict(&signature, &unvalidated_public_key, message)) {
            option::some(IntentReserved { solver })
        } else {
            option::none()
        }
    }

    /// Ensures the signer of the transaction is the authorized solver.
    public fun ensure_solver_authorized(solver_signer: &signer, reservation: &Option<IntentReserved>) {
        if (option::is_some(reservation)) {
            let intent_reserved = option::borrow(reservation);
            assert!(signer::address_of(solver_signer) == intent_reserved.solver, EUNAUTHORIZED_SOLVER);
        }
    }
}
