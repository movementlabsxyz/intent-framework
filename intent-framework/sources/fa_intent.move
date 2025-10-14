module aptos_intent::fa_intent {
    use std::error;
    use std::signer;
    use std::option::{Self, Option};
    use std::vector;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, FungibleStore};
    use aptos_intent::intent::{Self, TradeSession, TradeIntent};
    use aptos_intent::intent_reservation::{Self, IntentReserved};
    use aptos_framework::object::{Self, DeleteRef, ExtendRef, Object};
    use aptos_framework::primary_fungible_store;

    /// The token offered is not the desired fungible asset.
    const ENOT_DESIRED_TOKEN: u64 = 0;

    /// The token offered does not meet amount requirement.
    const EAMOUNT_NOT_MEET: u64 = 1;
    /// The solver signature is invalid and cannot be verified.
    const EINVALID_SIGNATURE: u64 = 2;

    /// Manages a fungible asset store for intent execution.
    /// Contains references needed to withdraw assets from the store.
    struct FungibleStoreManager has store {
        extend_ref: ExtendRef,
        delete_ref: DeleteRef,
    }

    /// Trading conditions for a fungible asset limit order.
    /// Specifies what token type and amount the intent creator wants to receive.
    struct FungibleAssetLimitOrder has store, drop {
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        issuer: address,
    }

    /// Witness type for fungible asset intent completion.
    /// Empty struct that can only be created after verifying trading conditions.
    struct FungibleAssetRecipientWitness has drop {}

    #[event]
    /// Event emitted when a fungible asset limit order intent is created.
    /// Contains all the trading details that solvers need to evaluate the opportunity.
    struct LimitOrderEvent has store, drop {
        source_metadata: Object<Metadata>,
        source_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        issuer: address,
        expiry_time: u64,
    }

    /// Creates a fungible asset to fungible asset trading intent.
    /// 
    /// This function locks the source fungible asset in a store and creates an intent
    /// that can only be completed by providing the desired fungible asset.
    /// 
    /// # Arguments
    /// - `source_fungible_asset`: The fungible asset being offered
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Minimum amount of the desired token required
    /// - `expiry_time`: Unix timestamp when the intent expires
    /// - `issuer`: Address of the intent creator
    /// 
    /// # Returns
    /// - `Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>>`: Intent object
    public fun create_fa_to_fa_intent(
        source_fungible_asset: FungibleAsset,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        issuer: address,
        reservation: Option<IntentReserved>,
    ): Object<TradeIntent<FungibleStoreManager, FungibleAssetLimitOrder>> {
        event::emit(LimitOrderEvent {
            source_metadata: fungible_asset::asset_metadata(&source_fungible_asset),
            source_amount: fungible_asset::amount(&source_fungible_asset),
            desired_metadata,
            desired_amount,
            expiry_time,
            issuer,
        });

        let coin_store_ref = object::create_object(issuer);
        let extend_ref = object::generate_extend_ref(&coin_store_ref);
        let delete_ref = object::generate_delete_ref(&coin_store_ref);
        let transfer_ref = object::generate_transfer_ref(&coin_store_ref);
        let linear_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_ref, object::address_from_constructor_ref(&coin_store_ref));

        fungible_asset::create_store(&coin_store_ref, fungible_asset::metadata_from_asset(&source_fungible_asset));
        fungible_asset::deposit(
            object::object_from_constructor_ref<FungibleStore>(&coin_store_ref),
            source_fungible_asset
        );
        intent::create_intent<FungibleStoreManager, FungibleAssetLimitOrder, FungibleAssetRecipientWitness>(
            FungibleStoreManager { extend_ref, delete_ref},
            FungibleAssetLimitOrder { desired_metadata, desired_amount, issuer },
            expiry_time,
            issuer,
            FungibleAssetRecipientWitness {},
            reservation,
        )
    }

    /// Entry function to create a fungible asset limit order intent.
    /// 
    /// This function withdraws the specified amount of source tokens from the caller's
    /// primary fungible store and creates a limit order intent.
    /// 
    /// # Arguments
    /// - `account`: Signer of the account creating the intent
    /// - `source_metadata`: Metadata of the token being offered
    /// - `source_amount`: Amount of source tokens to offer
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Minimum amount of desired tokens required
    /// - `expiry_time`: Unix timestamp when the intent expires
    /// - `_issuer`: Address of the intent creator (must match signer)
    public entry fun create_fa_to_fa_intent_entry(
        account: &signer,
        source_metadata: Object<Metadata>,
        source_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        solver: address,
        solver_signature: vector<u8>,
    ) {
        let issuer = signer::address_of(account);
        let reservation = if (vector::is_empty(&solver_signature)) {
            option::none()  // Explicitly unreserved intent
        } else {
            let intent_to_sign = intent_reservation::new_intent_to_sign(
                source_metadata,
                source_amount,
                desired_metadata,
                desired_amount,
                expiry_time,
                issuer,
                solver,
            );
            let result = intent_reservation::verify_and_create_reservation(
                intent_to_sign,
                solver_signature,
            );
            // Fail if signature verification failed instead of silently falling back
            assert!(option::is_some(&result), error::invalid_argument(EINVALID_SIGNATURE));
            result
        };

        let fa = primary_fungible_store::withdraw(account, source_metadata, source_amount);
        create_fa_to_fa_intent(
            fa,
            desired_metadata,
            desired_amount,
            expiry_time,
            signer::address_of(account),
            reservation,
        );
    }

    /// Starts a fungible asset offering session by unlocking the stored assets.
    /// 
    /// This function extracts the fungible assets from the store manager and
    /// returns them along with the trading session.
    /// 
    /// # Arguments
    /// - `intent`: Object reference to the fungible asset intent
    /// 
    /// # Returns
    /// - `FungibleAsset`: The unlocked fungible asset
    /// - `TradeSession<Args>`: Trading session containing the conditions
    public fun start_fa_offering_session<Args: store + drop>(
        solver: &signer,
        intent: Object<TradeIntent<FungibleStoreManager, Args>>
    ): (FungibleAsset, TradeSession<Args>) {
        let (store_manager, session) = intent::start_intent_session(intent);
        let reservation = intent::get_reservation(&session);
        intent_reservation::ensure_solver_authorized(solver, reservation);
        (destroy_store_manager(store_manager), session)
    }

    /// Destroys a fungible store manager and extracts all assets from the store.
    /// 
    /// This helper function withdraws all fungible assets from the store and
    /// cleans up the store references.
    /// 
    /// # Arguments
    /// - `store_manager`: The store manager to destroy
    /// 
    /// # Returns
    /// - `FungibleAsset`: All assets that were in the store
    fun destroy_store_manager(store_manager: FungibleStoreManager): FungibleAsset {
        let FungibleStoreManager { extend_ref, delete_ref } = store_manager;
        let store_signer = object::generate_signer_for_extending(&extend_ref);
        let fa_store = object::object_from_delete_ref<FungibleStore>(&delete_ref);
        let fa = fungible_asset::withdraw(&store_signer, fa_store, fungible_asset::balance(fa_store));
        fungible_asset::remove_store(&delete_ref);
        object::delete(delete_ref);
        fa
    }

    /// Completes a fungible asset intent session by verifying and depositing the received assets.
    /// 
    /// This function verifies that the received fungible asset matches the trading
    /// conditions (correct token type and sufficient amount) and deposits it to
    /// the intent creator's primary fungible store.
    /// 
    /// # Arguments
    /// - `session`: The trading session to complete (consumed)
    /// - `received_fa`: The fungible asset received from the trade
    /// 
    /// # Aborts
    /// - `ENOT_DESIRED_TOKEN`: If the received asset is not the desired token type
    /// - `EAMOUNT_NOT_MEET`: If the received amount is less than the required amount
    public fun finish_fa_receiving_session(
        session: TradeSession<FungibleAssetLimitOrder>,
        received_fa: FungibleAsset,
    ) {
        let argument = intent::get_argument(&session);
        assert!(
            fungible_asset::metadata_from_asset(&received_fa) == argument.desired_metadata,
            error::invalid_argument(ENOT_DESIRED_TOKEN)
        );
        assert!(
            fungible_asset::amount(&received_fa) >= argument.desired_amount,
            error::invalid_argument(EAMOUNT_NOT_MEET),
        );

        primary_fungible_store::deposit(argument.issuer, received_fa);
        intent::finish_intent_session(session, FungibleAssetRecipientWitness {})
    }

    /// Entry function to revoke a fungible asset intent and return the locked assets.
    /// 
    /// This function allows the intent owner to cancel their intent and get back
    /// their locked fungible assets before the intent expires or is completed.
    /// 
    /// # Arguments
    /// - `account`: Signer of the intent owner
    /// - `intent`: Object reference to the intent to revoke
    public entry fun revoke_fa_intent<Args: store + drop>(
        account: &signer,
        intent: Object<TradeIntent<FungibleStoreManager, Args>>
    ) {
        let store_manager = intent::revoke_intent(account, intent);
        let fa = destroy_store_manager(store_manager);
        primary_fungible_store::deposit(signer::address_of(account), fa);
    }

}
