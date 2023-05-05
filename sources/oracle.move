module fenture::oracle {

    use std::acl::{Self, ACL};
    use std::signer;
    use std::vector;
    use std::string::String;
    use std::table::{Self, Table};

    use aptos_std::event::{Self, EventHandle};
    use aptos_std::type_info::type_name;

    use aptos_framework::account;

    // errors
    const ENOT_ADMIN: u64 = 1;
    const ENOT_PRICE_FEEDER: u64 = 2;
    const EORACLE_NOT_INIT: u64 = 3;
    const ENO_SUCH_PRICE: u64 = 4;
    const EORACLE_ALREADY_INIT: u64 = 5;
    const EINVALID_ARGS: u64 = 6;

    struct OracleStore has key {
        price_feeders: ACL,
        prices: Table<String, u128>,
        price_posted_events: EventHandle<PricePostedEvent>,
    }

    struct PricePostedEvent has drop, store {
        coin: String,
        previous_price_mantissa: u128,
        requested_price_mantissa: u128,
        new_price_mantissa: u128,
    }

    public entry fun set_underlying_price_type_args<CoinType>(price_feeder: &signer, new_price_mantissa: u128) acquires OracleStore {
        set_underlying_price(price_feeder, type_name<CoinType>(), new_price_mantissa);
    }

    public entry fun set_underlying_price(price_feeder: &signer, coin_type: String, new_price_mantissa: u128) acquires OracleStore {
        only_price_feeder(price_feeder);
        let oracle_store_ref = borrow_global_mut<OracleStore>(admin());
        let previous_price_mantissa = if (table::contains<String, u128>(&oracle_store_ref.prices, coin_type)) {
            *table::borrow<String, u128>(&oracle_store_ref.prices, coin_type)
        } else {
            0
        };
        table::upsert<String, u128>(&mut oracle_store_ref.prices, coin_type, new_price_mantissa);
        event::emit_event<PricePostedEvent>(
            &mut oracle_store_ref.price_posted_events,
            PricePostedEvent {
                coin: coin_type,
                previous_price_mantissa,
                requested_price_mantissa: new_price_mantissa,
                new_price_mantissa,
            },
        );
    }

    public entry fun set_underlying_price_batch(price_feeder: &signer, coin_type_batch: vector<String>, new_price_mantissa_batch: vector<u128>) acquires OracleStore {
        only_price_feeder(price_feeder);
        let index = vector::length<String>(&coin_type_batch);
        assert!(index == vector::length<u128>(&new_price_mantissa_batch), EINVALID_ARGS);
        while (index > 0) {
            index = index - 1;
            let coin_type = *vector::borrow<String>(&coin_type_batch, index);
            let new_price_mantissa = *vector::borrow<u128>(&new_price_mantissa_batch, index);
            set_underlying_price(price_feeder, coin_type, new_price_mantissa);
        }
    }
    
    public fun get_underlying_price_no_type_args(coin_type: String): u128 acquires OracleStore {
        assert!(exists<OracleStore>(admin()), EORACLE_NOT_INIT);
        let prices_table_ref = &borrow_global<OracleStore>(admin()).prices;
        assert!(table::contains<String, u128>(prices_table_ref, coin_type), ENO_SUCH_PRICE);
        *table::borrow<String, u128>(prices_table_ref, coin_type)
    }

    public fun get_underlying_price<CoinType>(): u128 acquires OracleStore {
        get_underlying_price_no_type_args(type_name<CoinType>())
    }

    // admin functions
    public entry fun init(admin: &signer) {
        only_admin(admin);
        assert!(!exists<OracleStore>(admin()), EORACLE_ALREADY_INIT);
        move_to<OracleStore>(admin, OracleStore {
            price_feeders: acl::empty(),
            prices: table::new<String, u128>(),
            price_posted_events: account::new_event_handle<PricePostedEvent>(admin),
        });
    }

    public entry fun add_price_feeder(admin: &signer, new_feeder: address) acquires OracleStore {
        only_admin(admin);
        assert!(exists<OracleStore>(admin()), EORACLE_NOT_INIT);
        let oracle_store_ref = borrow_global_mut<OracleStore>(admin());
        acl::add(&mut oracle_store_ref.price_feeders, new_feeder);
    }
    public entry fun remove_price_feeder(admin: &signer, feeder: address) acquires OracleStore {
        only_admin(admin);
        assert!(exists<OracleStore>(admin()), EORACLE_NOT_INIT);
        let oracle_store_ref = borrow_global_mut<OracleStore>(admin());
        acl::remove(&mut oracle_store_ref.price_feeders, feeder);
    }

    // internal functions
    fun admin(): address { @fenture }
    fun only_admin(account: &signer) {
        assert!(signer::address_of(account) == admin(), ENOT_ADMIN);
    }
    fun only_price_feeder(account: &signer) acquires OracleStore {
        let account_addr = signer::address_of(account);
        let oracle_store_ref = borrow_global<OracleStore>(admin());
        assert!(acl::contains(&oracle_store_ref.price_feeders, account_addr), ENOT_PRICE_FEEDER);
    }
}