/// USDxyz - A simple fungible asset token for testing cross-chain swaps.
/// This token is used in E2E tests to demonstrate swapping tokens (not native APT).
module test_tokens::usdxyz {
    use std::string;
    use std::signer;
    use std::option;
    use aptos_framework::fungible_asset::{Self, MintRef, BurnRef, TransferRef, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    /// Only the module deployer can mint tokens.
    const E_NOT_AUTHORIZED: u64 = 1;

    /// Stores the refs needed to manage the token.
    /// Stored at the metadata object address.
    struct USDxyzRefs has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    /// Token metadata constants
    const TOKEN_NAME: vector<u8> = b"USDxyz";
    const TOKEN_SYMBOL: vector<u8> = b"USDxyz";
    const TOKEN_DECIMALS: u8 = 8;
    const TOKEN_ICON_URI: vector<u8> = b"";
    const TOKEN_PROJECT_URI: vector<u8> = b"";

    /// Initialize the USDxyz token. Called automatically when module is deployed.
    fun init_module(deployer: &signer) {
        // Create a named object for the token metadata
        let constructor_ref = object::create_named_object(deployer, TOKEN_NAME);
        
        // Enable primary fungible store for easy token management
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(), // max supply (none = unlimited)
            string::utf8(TOKEN_NAME),
            string::utf8(TOKEN_SYMBOL),
            TOKEN_DECIMALS,
            string::utf8(TOKEN_ICON_URI),
            string::utf8(TOKEN_PROJECT_URI),
        );

        // Generate refs for minting, burning, and transferring
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);

        // Store refs at the metadata object
        let metadata_signer = object::generate_signer(&constructor_ref);
        move_to(&metadata_signer, USDxyzRefs {
            mint_ref,
            burn_ref,
            transfer_ref,
        });
    }

    #[view]
    /// Get the metadata object for USDxyz token.
    /// This is needed to interact with the token in other modules.
    public fun get_metadata(): Object<Metadata> {
        let metadata_address = object::create_object_address(&@test_tokens, TOKEN_NAME);
        object::address_to_object<Metadata>(metadata_address)
    }

    /// Mint USDxyz tokens to a recipient.
    /// Only the module deployer can mint.
    public entry fun mint(
        admin: &signer,
        recipient: address,
        amount: u64,
    ) acquires USDxyzRefs {
        // Only deployer can mint
        assert!(signer::address_of(admin) == @test_tokens, E_NOT_AUTHORIZED);
        
        let metadata = get_metadata();
        let refs = borrow_global<USDxyzRefs>(object::object_address(&metadata));
        
        let fa = fungible_asset::mint(&refs.mint_ref, amount);
        primary_fungible_store::deposit(recipient, fa);
    }

    #[view]
    /// Get the balance of USDxyz tokens for an account.
    public fun balance(account: address): u64 {
        let metadata = get_metadata();
        primary_fungible_store::balance(account, metadata)
    }

    // ============================================================================
    // TEST HELPERS
    // ============================================================================

    #[test_only]
    use aptos_framework::account;

    #[test_only]
    /// Initialize for testing (creates the deployer account and initializes the module)
    public fun init_for_testing(deployer: &signer) {
        init_module(deployer);
    }

    #[test(deployer = @test_tokens, alice = @0x123)]
    fun test_mint_and_balance(deployer: &signer, alice: &signer) acquires USDxyzRefs {
        // Setup
        account::create_account_for_test(@test_tokens);
        account::create_account_for_test(signer::address_of(alice));
        
        // Initialize
        init_module(deployer);
        
        // Mint to alice
        let alice_addr = signer::address_of(alice);
        mint(deployer, alice_addr, 1000000000); // 10 USDxyz (8 decimals)
        
        // Check balance
        assert!(balance(alice_addr) == 1000000000, 0);
    }
}

