module aptos_intent::test_fa_helper {
    use std::signer;
    use std::option;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object;
    use aptos_framework::event;

    #[event]
    struct APTMetadataAddressEvent has store, drop {
        metadata: address,
    }

    /// Gets APT coin metadata address and returns it via event
    /// For use in E2E tests to get valid metadata addresses
    public entry fun get_apt_metadata_address(
        _account: &signer,
    ) {
        let metadata_opt = coin::paired_metadata<AptosCoin>();
        let metadata_ref = option::borrow(&metadata_opt);
        let metadata_addr = object::object_address(metadata_ref);
        
        event::emit(APTMetadataAddressEvent {
            metadata: metadata_addr,
        });
    }
}

