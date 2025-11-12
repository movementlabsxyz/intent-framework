#[test_only]
module mvmt_intent::test_utils {
    use std::signer;
    use std::vector;
    use aptos_std::ed25519;
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef};
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

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

    #[test_only]
    /// Creates a test EVM address (20 bytes) with sequential values starting from `start`
    /// Example: create_test_evm_address(0) creates [0, 1, 2, ..., 19]
    public fun create_test_evm_address(start: u8): vector<u8> {
        let evm_address = vector::empty<u8>();
        let i = 0;
        while (i < 20) {
            vector::push_back(&mut evm_address, start + i);
            i = i + 1;
        };
        evm_address
    }

    #[test_only]
    /// Creates a test EVM address (20 bytes) with reverse sequential values starting from `start`
    /// Example: create_test_evm_address_reverse(20) creates [20, 19, 18, ..., 1]
    public fun create_test_evm_address_reverse(start: u8): vector<u8> {
        let evm_address = vector::empty<u8>();
        let i = 0;
        while (i < 20) {
            vector::push_back(&mut evm_address, start - i);
            i = i + 1;
        };
        evm_address
    }

    #[test_only]
    /// Helper function to register a token type and mint initial tokens for testing.
    /// Sets up timestamp system and creates one token type with specified mint amount.
    public fun register_and_mint_tokens(
        aptos_framework: &signer,
        minter: &signer,
        mint_amount: u64,
    ): (object::Object<Metadata>, MintRef) {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let (creator_ref, fa_type) = fungible_asset::create_test_token(minter);
        primary_fungible_store::init_test_metadata_with_primary_store_enabled(&creator_ref);
        let mint_ref = fungible_asset::generate_mint_ref(&creator_ref);

        if (mint_amount > 0) {
            let fa = fungible_asset::mint(&mint_ref, mint_amount);
            primary_fungible_store::deposit(signer::address_of(minter), fa);
            assert!(
                primary_fungible_store::balance(signer::address_of(minter), fa_type) == mint_amount
            );
        } else {
            assert!(
                primary_fungible_store::balance(signer::address_of(minter), fa_type) == 0
            );
        };

        (object::convert(fa_type), mint_ref)
    }
}

