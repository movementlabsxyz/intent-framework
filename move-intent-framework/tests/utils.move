#[test_only]
module mvmt_intent::utils {
    use aptos_std::ed25519;

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    #[test_only]
    /// Helper function to generate a key pair from a private key.
    /// Returns the secret key (for signing) and unvalidated public key (for verification).
    /// This is useful for testing signature verification flows where you need to generate
    /// a key pair, sign data with the secret key, and verify with the public key.
    public fun generate_key_pair(): (ed25519::SecretKey, ed25519::UnvalidatedPublicKey) {
        let (secret_key, validated_public_key) = ed25519::generate_keys();
        let public_key_bytes = ed25519::validated_public_key_to_bytes(&validated_public_key);
        let unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(public_key_bytes);
        (secret_key, unvalidated_public_key)
    }
}

