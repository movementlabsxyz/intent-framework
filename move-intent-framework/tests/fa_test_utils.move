#[test_only]
module mvmt_intent::fa_test_utils {
    use std::signer;

    use aptos_framework::fungible_asset::{Self, Metadata, MintRef};
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

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
