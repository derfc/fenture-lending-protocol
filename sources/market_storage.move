module fenture::market_storage {

    use std::vector;
    use std::signer;
    use std::string::{Self, String};

    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::type_name;
    use aptos_std::event::{Self, EventHandle};

    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};

    use fenture::constants;
    use fenture_finance_dao::fenture_finance_dao::FentureFinanceDao;

    friend fenture::market;

    // errors
    const ENOT_ADMIN: u64 = 1;
    const EALREADY_APPROVED: u64 = 2;
    const EALREADY_LISTED: u64 = 3;
    const ENOT_APPROVED: u64 = 4;
    const EALREADY_REGISTERED: u64 = 5;
    const EMARKET_FENTURE_DISTRIBUTION_NOT_INIT: u64 = 6;
    const EMARKET_FENTURE_DISTRIBUTION_ALREADY_INIT: u64 = 7;
    const ECLOSE_FACTOR_OUT_OF_BOUNDS: u64 = 8;
    const ECOLLATERAL_FACTOR_OUT_OF_BOUNDS: u64 = 9;
    const ELIQUIDATION_INCENTIVE_OUT_OF_BOUNDS: u64 = 10;
    const EALREADY_INITIALIZED: u64 = 11;

    //
    // events
    //

    struct MarketListedEvent has drop, store {
        coin: String,
    } 

    struct MarketEnteredEvent has drop, store {
        coin: String,
        account: address,
    }

    struct MarketExitedEvent has drop, store {
        coin: String,
        account: address,
    }

    struct NewPauseGuardianEvent has drop, store {
        old_pause_guardian: address,
        new_pause_guardian: address,
    }

    struct GlobalActionPausedEvent has drop, store {
        action: String,
        pause_state: bool,
    }

    struct MarketActionPausedEvent has drop, store {
        coin: String,
        action: String,
        pause_state: bool,
    }

    struct NewCloseFactorEvent has drop, store {
        old_close_factor_mantissa: u128,
        new_close_factor_mantissa: u128,
    }

    struct NewCollateralFactorEvent has drop, store {
        coin: String,
        old_collateral_factor_mantissa: u128,
        new_collateral_factor_mantissa: u128,
    }

    struct NewLiquidationIncentiveEvent has drop, store {
        old_liquidation_incentive_mantissa: u128,
        new_liquidation_incentive_mantissa: u128,
    }

    struct MarketabeledEvent has drop, store {
        coin: String,
        is_fentureed: bool,
    }

    struct NewFentureRateEvent has drop, store {
        old_fenture_rate: u128,
        new_fenture_rate: u128,
    }

    struct FentureSpeedUpdatedEvent has drop, store {
        coin: String,
        new_speed: u128,
    }

    struct DistributedSupplierFentureEvent has drop, store {
        coin: String,
        supplier: address,
        fenture_delta: u128,
        fenture_supply_index: u128,
    }

    struct DistributedBorrowerFentureEvent has drop, store {
        coin: String,
        borrower: address,
        fenture_delta: u128,
        fenture_borrow_index: u128,
    }

    //
    // structs
    //
    struct FentureMarketState has store, copy, drop {
        index: u128,
        block: u64,
    }

    struct MarketabelDistributionInfo has store, copy, drop {
        is_fentureed: bool,
        fenture_speed: u128,
        supply_state: FentureMarketState,
        borrow_state: FentureMarketState,
    }

    struct FentureDistribution has key {
        market_distribution_info: Table<String, MarketabelDistributionInfo>,
        fenture_rate: u128,
        treasury: Coin<FentureFinanceDao>,
        market_fentureed_events: EventHandle<MarketabeledEvent>,
        new_fenture_rate_events: EventHandle<NewFentureRateEvent>,
        fenture_speed_updated_events: EventHandle<FentureSpeedUpdatedEvent>,
        distribute_supplier_fenture_events: EventHandle<DistributedSupplierFentureEvent>,
        distribute_borrower_fenture_events: EventHandle<DistributedBorrowerFentureEvent>,
    }

    struct UserFentureDistributionInfo has key {
        fenture_supplier_index: Table<String, u128>,
        fenture_borrower_index: Table<String, u128>,
        fenture_accrued: u128,
    }

    struct MarketInfo has store, copy, drop {
        collateral_factor_mantissa: u128,
    }

    struct GlobalConfig has key {
        all_markets: vector<String>,
        markets_info: Table<String, MarketInfo>,
        close_factor_mantissa: u128,
        liquidation_incentive_mantissa: u128,
        pause_guardian: address,
        mint_guardian_paused: bool,
        borrow_guardian_paused: bool,
        deposit_guardian_paused: bool,
        seize_guardian_paused: bool,
        market_listed_events: EventHandle<MarketListedEvent>,
        new_pause_guardian_events: EventHandle<NewPauseGuardianEvent>,
        global_action_paused_events: EventHandle<GlobalActionPausedEvent>,
        new_close_factor_events: EventHandle<NewCloseFactorEvent>,
        new_liquidation_incentive_events: EventHandle<NewLiquidationIncentiveEvent>,
    }

    struct MarketConfig<phantom CoinType> has key {
        is_approved: bool,
        is_listed: bool,
        mint_guardian_paused: bool,
        borrow_guardian_paused: bool,
        market_action_paused_events: EventHandle<MarketActionPausedEvent>,
        new_collateral_factor_events: EventHandle<NewCollateralFactorEvent>,
    }

    struct UserStorage has key {
        account_assets: vector<String>,
        market_membership: Table<String, bool>,
        market_entered_events: EventHandle<MarketEnteredEvent>,
        market_exited_events: EventHandle<MarketExitedEvent>,
    }

    // 
    // getter functions
    //
    public fun admin(): address {
        @fenture
    }

    public fun all_markets(): vector<String> acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).all_markets
    }

    public fun close_factor_mantissa(): u128 acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).close_factor_mantissa
    }

    public fun liquidation_incentive_mantissa(): u128 acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).liquidation_incentive_mantissa
    }

    public fun is_approved<CoinType>(): bool acquires MarketConfig {
        if (!exists<MarketConfig<CoinType>>(admin())) { return false };
        borrow_global<MarketConfig<CoinType>>(admin()).is_approved
    }

    public fun is_listed<CoinType>(): bool acquires MarketConfig {
        if (!exists<MarketConfig<CoinType>>(admin())) { return false };
        borrow_global<MarketConfig<CoinType>>(admin()).is_listed
    }

    public fun is_account_registered(account: address): bool {
        exists<UserStorage>(account) && exists<UserFentureDistributionInfo>(account)
    }

    public fun account_assets(account: address): vector<String> acquires UserStorage {
        borrow_global<UserStorage>(account).account_assets
    }

    public fun account_membership<CoinType>(account: address): bool acquires UserStorage {
        if (!exists<UserStorage>(account)) {
            return false
        };
        let coin_type = type_name<CoinType>();
        let membership_table_ref = &borrow_global<UserStorage>(account).market_membership;
        if (!table::contains<String, bool>(membership_table_ref, coin_type)) {
            false
        } else {
            *table::borrow(membership_table_ref, coin_type)
        }
    }

    public fun account_membership_no_type_args(coin_type: String, account: address): bool acquires UserStorage {
        if (!exists<UserStorage>(account)) {
            return false
        };
        let membership_table_ref = &borrow_global<UserStorage>(account).market_membership;
        if (!table::contains<String, bool>(membership_table_ref, coin_type)) {
            false
        } else {
            *table::borrow(membership_table_ref, coin_type)
        }
    }

    public fun pause_guardian(): address acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).pause_guardian
    }

    public fun mint_guardian_paused<CoinType>(): bool acquires MarketConfig {
        borrow_global<MarketConfig<CoinType>>(admin()).mint_guardian_paused
    }

    public fun borrow_guardian_paused<CoinType>(): bool acquires MarketConfig {
        borrow_global<MarketConfig<CoinType>>(admin()).borrow_guardian_paused
    }

    public fun deposit_guardian_paused(): bool acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).deposit_guardian_paused
    }

    public fun seize_guardian_paused(): bool acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).seize_guardian_paused
    }

    public fun collateral_factor_mantissa(coin_type: String): u128 acquires GlobalConfig {
        table::borrow(&borrow_global<GlobalConfig>(admin()).markets_info, coin_type).collateral_factor_mantissa
    }

    public fun is_fentureed<CoinType>(): bool acquires FentureDistribution {
        is_fentureed_no_type_args(type_name<CoinType>())
    }
    public fun is_fentureed_no_type_args(coin_type: String): bool acquires FentureDistribution {
        let tabel_ref = &borrow_global<FentureDistribution>(admin()).market_distribution_info;
        if (!table::contains<String, MarketabelDistributionInfo>(tabel_ref, coin_type)) { return false };
        table::borrow<String, MarketabelDistributionInfo>(tabel_ref, coin_type).is_fentureed
    }

    public fun fenture_rate(): u128 acquires FentureDistribution {
        borrow_global<FentureDistribution>(admin()).fenture_rate
    }

    public fun fenture_speed_public<CoinType>(): u128 acquires FentureDistribution {
        let coin_type = type_name<CoinType>();
        let tabel_ref = &borrow_global<FentureDistribution>(admin()).market_distribution_info;
        table::borrow<String, MarketabelDistributionInfo>(tabel_ref, coin_type).fenture_speed
    }

    public(friend) fun fenture_speed(coin_type: String): u128 acquires FentureDistribution {
        let tabel_ref = &borrow_global<FentureDistribution>(admin()).market_distribution_info;
        table::borrow<String, MarketabelDistributionInfo>(tabel_ref, coin_type).fenture_speed
    }

    public(friend) fun fenture_supply_state(coin_type: String): (u128, u64) acquires FentureDistribution {
        let tabel_ref = &borrow_global<FentureDistribution>(admin()).market_distribution_info;
        let supply_state = &table::borrow<String, MarketabelDistributionInfo>(tabel_ref, coin_type).supply_state;
        (supply_state.index, supply_state.block)
    }

    public(friend) fun fenture_borrow_state(coin_type: String): (u128, u64) acquires FentureDistribution {
        let tabel_ref = &borrow_global<FentureDistribution>(admin()).market_distribution_info;
        let borrow_state = &table::borrow<String, MarketabelDistributionInfo>(tabel_ref, coin_type).borrow_state;
        (borrow_state.index, borrow_state.block)
    }

    public fun fenture_treasury_balance(): u64 acquires FentureDistribution {
        coin::value<FentureFinanceDao>(&borrow_global<FentureDistribution>(admin()).treasury)
    }

    public(friend) fun fenture_supplier_index(coin_type: String, account: address): u128 acquires UserFentureDistributionInfo {
        let tabel_ref = &mut borrow_global_mut<UserFentureDistributionInfo>(account).fenture_supplier_index;
        if (!table::contains<String, u128>(tabel_ref, coin_type)) {
            table::add<String, u128>(tabel_ref, coin_type, constants::Fenture_Initial_Index());
        };
        *table::borrow<String, u128>(tabel_ref, coin_type)
    }

    public(friend) fun fenture_borrower_index(coin_type: String, account: address): u128 acquires UserFentureDistributionInfo {
        let tabel_ref = &mut borrow_global_mut<UserFentureDistributionInfo>(account).fenture_borrower_index;
        if (!table::contains<String, u128>(tabel_ref, coin_type)) {
            table::add<String, u128>(tabel_ref, coin_type, constants::Fenture_Initial_Index());
        };
        *table::borrow<String, u128>(tabel_ref, coin_type)
    }

    public fun fenture_accrued(account: address): u128 acquires UserFentureDistributionInfo {
        borrow_global<UserFentureDistributionInfo>(account).fenture_accrued
    }

    // init
    public entry fun init(admin: &signer) {
        assert!(signer::address_of(admin) == admin(), ENOT_ADMIN);
        assert!(!exists<GlobalConfig>(admin()) || !exists<FentureDistribution>(admin()), EALREADY_INITIALIZED);
        if (!exists<GlobalConfig>(admin())) {
            move_to(admin, GlobalConfig {
                all_markets: vector::empty<String>(),
                markets_info: table::new<String, MarketInfo>(),
                close_factor_mantissa: constants::Close_Factor_Default_Mantissa(),
                liquidation_incentive_mantissa: constants::Liquidation_Incentive_Default_Mantissa(),
                pause_guardian: admin(),
                mint_guardian_paused: false,
                borrow_guardian_paused: false,
                deposit_guardian_paused: false,
                seize_guardian_paused: false,
                market_listed_events: account::new_event_handle<MarketListedEvent>(admin),
                new_pause_guardian_events: account::new_event_handle<NewPauseGuardianEvent>(admin),
                global_action_paused_events: account::new_event_handle<GlobalActionPausedEvent>(admin),  
                new_close_factor_events: account::new_event_handle<NewCloseFactorEvent>(admin),
                new_liquidation_incentive_events: account::new_event_handle<NewLiquidationIncentiveEvent>(admin),
            });
        };
        if (!exists<FentureDistribution>(admin())) {
            move_to(admin, FentureDistribution {
                market_distribution_info: table::new<String, MarketabelDistributionInfo>(),
                fenture_rate: 0,
                treasury: coin::zero<FentureFinanceDao>(),
                market_fentureed_events: account::new_event_handle<MarketabeledEvent>(admin),
                new_fenture_rate_events: account::new_event_handle<NewFentureRateEvent>(admin),
                fenture_speed_updated_events: account::new_event_handle<FentureSpeedUpdatedEvent>(admin),
                distribute_supplier_fenture_events: account::new_event_handle<DistributedSupplierFentureEvent>(admin),
                distribute_borrower_fenture_events: account::new_event_handle<DistributedBorrowerFentureEvent>(admin),
            });
        };
    }

    public entry fun register(account: &signer) {
        assert!(!is_account_registered(signer::address_of(account)), EALREADY_REGISTERED);
        let account_addr = signer::address_of(account);
        if (!exists<UserStorage>(account_addr)) {
            move_to(account, UserStorage {
                account_assets: vector::empty<String>(),
                market_membership: table::new<String, bool>(),
                market_entered_events: account::new_event_handle<MarketEnteredEvent>(account),
                market_exited_events: account::new_event_handle<MarketExitedEvent>(account),
            });
        };
        if (!exists<UserFentureDistributionInfo>(account_addr)) {
            move_to(account, UserFentureDistributionInfo {
                fenture_supplier_index: table::new<String, u128>(),
                fenture_borrower_index: table::new<String, u128>(),
                fenture_accrued: 0,
            });
        };
    }

    // 
    // emit events
    //
    public(friend) fun emit_distribute_supplier_fenture_event(
        coin: String,
        supplier: address,
        fenture_delta: u128,
        fenture_supply_index: u128,
    ) acquires FentureDistribution {
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        event::emit_event<DistributedSupplierFentureEvent>(
            &mut fenture_distribution.distribute_supplier_fenture_events,
            DistributedSupplierFentureEvent { 
                coin,
                supplier,
                fenture_delta,
                fenture_supply_index,
            },
        );
    }

    public(friend) fun emit_distribute_borrower_fenture_event(
        coin: String,
        borrower: address,
        fenture_delta: u128,
        fenture_borrow_index: u128,
    ) acquires FentureDistribution {
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        event::emit_event<DistributedBorrowerFentureEvent>(
            &mut fenture_distribution.distribute_borrower_fenture_events,
            DistributedBorrowerFentureEvent { 
                coin,
                borrower,
                fenture_delta,
                fenture_borrow_index,
            },
        );
    }


    // 
    // friend functions (only market)
    //
    public(friend) fun approve_market<CoinType>(admin: &signer) acquires MarketConfig {
        assert!(signer::address_of(admin) == admin(), ENOT_ADMIN);
        assert!(!is_approved<CoinType>(), EALREADY_APPROVED);
        if (!exists<GlobalConfig>(admin())) {
            init(admin);
        };
        move_to(admin, MarketConfig<CoinType> {
            is_approved: true,
            is_listed: false,
            mint_guardian_paused: false,
            borrow_guardian_paused: false,
            market_action_paused_events: account::new_event_handle<MarketActionPausedEvent>(admin),
            new_collateral_factor_events: account::new_event_handle<NewCollateralFactorEvent>(admin),
        });
    }

    public(friend) fun support_market<CoinType>() acquires MarketConfig, GlobalConfig, FentureDistribution {
        assert!(is_approved<CoinType>(), ENOT_APPROVED);
        assert!(!is_listed<CoinType>(), EALREADY_LISTED);

        let coin_type = type_name<CoinType>();

        let market_config = borrow_global_mut<MarketConfig<CoinType>>(admin());
        market_config.is_listed = true;

        let global_status = borrow_global_mut<GlobalConfig>(admin());
        vector::push_back<String>(&mut global_status.all_markets, coin_type);
        table::add<String, MarketInfo>(&mut global_status.markets_info, coin_type, MarketInfo{
            collateral_factor_mantissa: constants::Collateral_Factor_Default_Mantissa(),
        });

        if (!table::contains<String, MarketabelDistributionInfo>(&borrow_global<FentureDistribution>(admin()).market_distribution_info, coin_type)) {
            init_market_fenture_distribution(coin_type);
        };

        event::emit_event<MarketListedEvent>(
            &mut global_status.market_listed_events,
            MarketListedEvent {
                coin: type_name<CoinType>(),
            },
        );
    }

    public(friend) fun enter_market<CoinType>(account: address) acquires UserStorage {
        let user_store = borrow_global_mut<UserStorage>(account);
        let coin_type = type_name<CoinType>();
        vector::push_back(&mut user_store.account_assets, coin_type);
        table::upsert(&mut user_store.market_membership, coin_type, true);
        event::emit_event<MarketEnteredEvent>(
            &mut user_store.market_entered_events,
            MarketEnteredEvent { 
                coin: coin_type,
                account, 
            },
        );
    }

    public(friend) fun exit_market<CoinType>(account: address) acquires UserStorage {
        let user_store = borrow_global_mut<UserStorage>(account);
        let coin_type = type_name<CoinType>();
        table::upsert(&mut user_store.market_membership, coin_type, false);
        let account_assets_list = &mut user_store.account_assets;
        let len = vector::length(account_assets_list);
        let index: u64 = 0;
        while (index < len) {
            if (*vector::borrow(account_assets_list, index) == coin_type) {
                vector::swap_remove(account_assets_list, index);
                break
            };
            index = index + 1;
        };
        event::emit_event<MarketExitedEvent>(
            &mut user_store.market_exited_events,
            MarketExitedEvent { 
                coin: coin_type,
                account, 
            },
        );
    }

    public(friend) fun set_close_factor(new_close_factor_mantissa: u128) acquires GlobalConfig {
        assert!(new_close_factor_mantissa <= constants::Close_Factor_Max_Mantissa(), ECLOSE_FACTOR_OUT_OF_BOUNDS);
        assert!(new_close_factor_mantissa >= constants::Close_Factor_Min_Mantissa(), ECLOSE_FACTOR_OUT_OF_BOUNDS);

        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let old_close_factor_mantissa = global_status.close_factor_mantissa;
        global_status.close_factor_mantissa = new_close_factor_mantissa;
        event::emit_event<NewCloseFactorEvent>(
            &mut global_status.new_close_factor_events,
            NewCloseFactorEvent {
                old_close_factor_mantissa,
                new_close_factor_mantissa,
            },
        );
    }

    public(friend) fun set_collateral_factor<CoinType>(new_collateral_factor_mantissa: u128) acquires MarketConfig, GlobalConfig {
        assert!(new_collateral_factor_mantissa <= constants::Collateral_Factor_Max_Mantissa(), ECOLLATERAL_FACTOR_OUT_OF_BOUNDS);

        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let coin_type = type_name<CoinType>();
        let old_collateral_factor_mantissa = table::borrow(&global_status.markets_info, coin_type).collateral_factor_mantissa;

        table::borrow_mut<String, MarketInfo>(&mut global_status.markets_info, coin_type).collateral_factor_mantissa = new_collateral_factor_mantissa;

        let market_info = borrow_global_mut<MarketConfig<CoinType>>(admin());
        event::emit_event<NewCollateralFactorEvent>(
            &mut market_info.new_collateral_factor_events,
            NewCollateralFactorEvent { 
                coin: type_name<CoinType>(),
                old_collateral_factor_mantissa,
                new_collateral_factor_mantissa,
            },
        );
    }

    public(friend) fun set_liquidation_incentive(new_liquidation_incentive_mantissa: u128) acquires GlobalConfig {
        assert!(new_liquidation_incentive_mantissa <= constants::Liquidation_Incentive_Max_Mantissa(), ELIQUIDATION_INCENTIVE_OUT_OF_BOUNDS);
        assert!(new_liquidation_incentive_mantissa >= constants::Liquidation_Incentive_Min_Mantissa(), ELIQUIDATION_INCENTIVE_OUT_OF_BOUNDS);

        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let old_liquidation_incentive_mantissa = global_status.liquidation_incentive_mantissa;
        global_status.liquidation_incentive_mantissa = new_liquidation_incentive_mantissa;
        event::emit_event<NewLiquidationIncentiveEvent>(
            &mut global_status.new_liquidation_incentive_events,
            NewLiquidationIncentiveEvent {
                old_liquidation_incentive_mantissa,
                new_liquidation_incentive_mantissa,
            },
        );
    }

    public(friend) fun set_pause_guardian(new_pause_guardian: address) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let old_pause_guardian = global_status.pause_guardian;
        global_status.pause_guardian = new_pause_guardian;
        event::emit_event<NewPauseGuardianEvent>(
            &mut global_status.new_pause_guardian_events,
            NewPauseGuardianEvent { 
                old_pause_guardian,
                new_pause_guardian, 
            },
        );
    }

    public(friend) fun set_mint_paused<CoinType>(state: bool) acquires MarketConfig {
        let market_info = borrow_global_mut<MarketConfig<CoinType>>(admin());
        market_info.mint_guardian_paused = state;
        event::emit_event<MarketActionPausedEvent>(
            &mut market_info.market_action_paused_events,
            MarketActionPausedEvent { 
                coin: type_name<CoinType>(),
                action: string::utf8(b"Mint"),
                pause_state: state, 
            },
        );
    }

    public(friend) fun set_borrow_paused<CoinType>(state: bool) acquires MarketConfig {
        let market_info = borrow_global_mut<MarketConfig<CoinType>>(admin());
        market_info.borrow_guardian_paused = state;
        event::emit_event<MarketActionPausedEvent>(
            &mut market_info.market_action_paused_events,
            MarketActionPausedEvent { 
                coin: type_name<CoinType>(),
                action: string::utf8(b"Borrow"),
                pause_state: state, 
            },
        );
    }

    public(friend) fun set_deposit_paused(state: bool) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        global_status.deposit_guardian_paused = state;
        event::emit_event<GlobalActionPausedEvent>(
            &mut global_status.global_action_paused_events,
            GlobalActionPausedEvent { 
                action: string::utf8(b"Deposit"),
                pause_state: state, 
            },
        );
    }

    public(friend) fun set_seize_paused(state: bool) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        global_status.seize_guardian_paused = state;
        event::emit_event<GlobalActionPausedEvent>(
            &mut global_status.global_action_paused_events,
            GlobalActionPausedEvent { 
                action: string::utf8(b"Seize"),
                pause_state: state, 
            },
        );
    }

    public(friend) fun init_market_fenture_distribution(coin_type: String) acquires FentureDistribution {
        let tabel_ref = &mut borrow_global_mut<FentureDistribution>(admin()).market_distribution_info;
        assert!(!table::contains<String, MarketabelDistributionInfo>(tabel_ref, coin_type), EMARKET_FENTURE_DISTRIBUTION_ALREADY_INIT);
        table::add<String, MarketabelDistributionInfo>(tabel_ref, coin_type, MarketabelDistributionInfo {
            is_fentureed: false,
            fenture_speed: 0,
            supply_state: FentureMarketState {
                index: constants::Fenture_Initial_Index(),
                block: timestamp::now_seconds(),
            },
            borrow_state: FentureMarketState {
                index: constants::Fenture_Initial_Index(),
                block: timestamp::now_seconds(),
            },
        });
    }

    public(friend) fun set_fenture_rate(new_fenture_rate: u128) acquires FentureDistribution {
        let old_fenture_rate = fenture_rate();
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        fenture_distribution.fenture_rate = new_fenture_rate;
        event::emit_event<NewFentureRateEvent>(
            &mut fenture_distribution.new_fenture_rate_events,
            NewFentureRateEvent { 
                old_fenture_rate,
                new_fenture_rate,
            },
        );
    }

    public(friend) fun add_fenture_market(coin_type: String) acquires FentureDistribution {
        if (!table::contains<String, MarketabelDistributionInfo>(&borrow_global<FentureDistribution>(admin()).market_distribution_info, coin_type)) {
            init_market_fenture_distribution(coin_type);
        };
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        table::borrow_mut<String, MarketabelDistributionInfo>(&mut fenture_distribution.market_distribution_info, coin_type).is_fentureed = true;
        event::emit_event<MarketabeledEvent>(
            &mut fenture_distribution.market_fentureed_events,
            MarketabeledEvent { 
                coin: coin_type,
                is_fentureed: true,
            },
        );
    }

    public(friend) fun drop_fenture_market(coin_type: String) acquires FentureDistribution {
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        table::borrow_mut<String, MarketabelDistributionInfo>(&mut fenture_distribution.market_distribution_info, coin_type).is_fentureed = false;
        event::emit_event<MarketabeledEvent>(
            &mut fenture_distribution.market_fentureed_events,
            MarketabeledEvent { 
                coin: coin_type,
                is_fentureed: false,
            },
        );
    }

    public(friend) fun update_fenture_speed(coin_type: String, new_speed: u128) acquires FentureDistribution {
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        table::borrow_mut<String, MarketabelDistributionInfo>(&mut fenture_distribution.market_distribution_info, coin_type).fenture_speed = new_speed;
        event::emit_event<FentureSpeedUpdatedEvent>(
            &mut fenture_distribution.fenture_speed_updated_events,
            FentureSpeedUpdatedEvent { 
                coin: coin_type,
                new_speed,
            },
        );
    }

    public(friend) fun update_fenture_supply_state(coin_type: String, index: u128, block: u64) acquires FentureDistribution {
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        table::borrow_mut<String, MarketabelDistributionInfo>(&mut fenture_distribution.market_distribution_info, coin_type).supply_state = FentureMarketState{
            index,
            block,
        };
    }

    public(friend) fun update_fenture_borrow_state(coin_type: String, index: u128, block: u64) acquires FentureDistribution {
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        table::borrow_mut<String, MarketabelDistributionInfo>(&mut fenture_distribution.market_distribution_info, coin_type).borrow_state = FentureMarketState{
            index,
            block,
        };
    }

    public(friend) fun update_fenture_supplier_state(coin_type: String, account: address, index: u128) acquires UserFentureDistributionInfo {
        let tabel_ref = &mut borrow_global_mut<UserFentureDistributionInfo>(account).fenture_supplier_index;
        table::upsert<String, u128>(tabel_ref, coin_type, index);
    }

    public(friend) fun update_fenture_borrower_state(coin_type: String, account: address, index: u128) acquires UserFentureDistributionInfo {
        let tabel_ref = &mut borrow_global_mut<UserFentureDistributionInfo>(account).fenture_borrower_index;
        table::upsert<String, u128>(tabel_ref, coin_type, index);
    }

    public(friend) fun update_fenture_accrued(account: address, user_accrued: u128) acquires UserFentureDistributionInfo {
        borrow_global_mut<UserFentureDistributionInfo>(account).fenture_accrued = user_accrued;
    }

    public(friend) fun transfer_fenture(user: address, user_accrued: u128, threshold: u128): u128 acquires FentureDistribution {
        if (user_accrued >= threshold && user_accrued > 0) {
            if (user_accrued <= (fenture_treasury_balance() as u128)) {
                let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
                let fenture_to_user = coin::extract<FentureFinanceDao>(&mut fenture_distribution.treasury, (user_accrued as u64));
                user_accrued = 0;
                coin::deposit<FentureFinanceDao>(user, fenture_to_user);
            };
        };
        user_accrued
    }

    public fun deposit_fenture(coin: Coin<FentureFinanceDao>) acquires FentureDistribution {
        let fenture_distribution = borrow_global_mut<FentureDistribution>(admin());
        coin::merge<FentureFinanceDao>(&mut fenture_distribution.treasury, coin);           
    }

}