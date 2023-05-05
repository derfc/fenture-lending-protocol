module fenture::market {
    
    use std::vector;
    use std::signer;
    use std::string::{String};

    use aptos_std::type_info::type_name;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_framework::coin;

    use fenture::market_storage as storage;
    use fenture::acoin;
    use fenture_finance_dao::fenture_finance_dao::FentureFinanceDao;
    use fenture::oracle;
    use fenture::constants::{Self, Exp_Scale, Half_Scale};

    const ENONZERO_BORROW_BALANCE: u64 = 1;
    const EEXIT_MARKET_REJECTION: u64 = 2;
    const EMINT_PAUSED: u64 = 3;
    const EBORROW_PAUSED: u64 = 4;
    const EDEPOSIT_PAUSED: u64 = 5;
    const ESEIZE_PAUSED: u64 = 6;
    const ENOT_ADMIN: u64 = 7;
    const ENOT_ADMIN_NOR_PAUSE_GUARDIAN: u64 = 8;

    // hook errors
    const NO_ERROR: u64 = 0;
    const EMARKET_NOT_LISTED: u64 = 101;
    const EINSUFFICIENT_LIQUIDITY: u64 = 102;
    const EREDEEM_TOKENS_ZERO: u64 = 103;
    const ENOT_MARKET_MEMBER: u64 = 104;
    const EPRICE_ERROR: u64 = 105;
    const EINSUFFICIENT_SHORTFALL: u64 = 106;
    const ETOO_MUCH_REPAY: u64 = 107;
    const EMARKET_NOT_APPROVED: u64 = 108;

    // enter/exit market
    public entry fun try_register(account: &signer) {
        if (!storage::is_account_registered(signer::address_of(account))) {
            storage::register(account);
        };
    }
    public entry fun enter_market<CoinType>(account: &signer) {
        let account_addr = signer::address_of(account);

        // market not listed
        assert!(storage::is_listed<CoinType>(), EMARKET_NOT_LISTED);

        // already joined
        if (storage::account_membership<CoinType>(account_addr)) {
            return
        };

        if (!acoin::is_account_registered<CoinType>(account_addr)) {
            acoin::register<CoinType>(account);
        };

        if (!storage::is_account_registered(account_addr)) {
            storage::register(account);
        };

        storage::enter_market<CoinType>(account_addr);
    }
    public entry fun exit_market<CoinType>(account: &signer) {
        let account_addr = signer::address_of(account);
        let (tokens_held, amount_owed, _) = acoin::get_account_snapshot<CoinType>(account_addr);

        // Fail if the sender has a borrow balance 
        assert!(amount_owed == 0, ENONZERO_BORROW_BALANCE);

        // Fail if the sender is not permitted to redeem all of their tokens 
        assert!(withdraw_allowed_internal<CoinType>(account_addr, tokens_held) == NO_ERROR, EEXIT_MARKET_REJECTION );

        // already not in
        if (!storage::account_membership<CoinType>(account_addr)) {
            return
        };
        
        storage::exit_market<CoinType>(account_addr);
    }

    // claim fenture
    public entry fun claim_fenture(holder: address) {
        let all_markets = storage::all_markets();
        let market_len = vector::length<String>(&all_markets);
        refresh_fenture_speeds();
        let index = 0;
        while (index < market_len) {
            let coin_type = *vector::borrow<String>(&all_markets, index);

            if (acoin::is_account_registered_no_type_args(coin_type, holder)) {
                let borrow_index = acoin::borrow_index_no_type_args(coin_type);
                update_fenturefinancedao_borrow_index_no_type_args(coin_type, borrow_index);
                distribute_borrower_fenturefinancedao_no_type_args(coin_type, holder, borrow_index, true);

                update_fenturefinancedao_supply_index_no_type_args(coin_type);
                distribute_supplier_fenturefinancedao_no_type_args(coin_type, holder, true);
            };
            index = index + 1;
        };

    }


    // policy hooks
    public fun init_allowed<CoinType>(_initializer: address, _name: String, _symbol: String, _decimals: u8, _initial_exchange_rate_mantissa: u128): u64 {
        if (!storage::is_approved<CoinType>()) {
            return EMARKET_NOT_APPROVED
        };
        return NO_ERROR
    }
    public fun init_verify<CoinType>(_initializer: address, _name: String, _symbol: String, _decimals: u8, _initial_exchange_rate_mantissa: u128) {
        if (acoin::is_coin_initialized<CoinType>() && !storage::is_listed<CoinType>()) {
            market_listed<CoinType>();
        };
    }

    public fun mint_allowed<CoinType>(minter: address, _mint_amount: u64): u64 {
        assert!(!storage::mint_guardian_paused<CoinType>(), EMINT_PAUSED);

        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        update_fenturefinancedao_supply_index<CoinType>();
        distribute_supplier_fenturefinancedao<CoinType>(minter, false);

        NO_ERROR
    }
    public fun mint_verify<CoinType>(_minter: address, _mint_amount: u64, _mint_tokens: u64) {
        // currently nothing to do
    }

    public fun redeem_allowed<CoinType>(redeemer: address, redeem_tokens: u64): u64 {
        let allowed = withdraw_allowed_internal<CoinType>(redeemer, redeem_tokens);
        if (allowed != NO_ERROR) {
            return allowed
        };

        allowed = redeem_with_fund_allowed_internal<CoinType>(redeemer, redeem_tokens);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_fenturefinancedao_supply_index<CoinType>();
        distribute_supplier_fenturefinancedao<CoinType>(redeemer, false);

        NO_ERROR
    }
    public fun redeem_with_fund_allowed<CoinType>(redeemer: address, redeem_tokens: u64): u64 {
        let allowed = redeem_with_fund_allowed_internal<CoinType>(redeemer, redeem_tokens);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_fenturefinancedao_supply_index<CoinType>();
        distribute_supplier_fenturefinancedao<CoinType>(redeemer, false);

        NO_ERROR
    }
    public fun redeem_verify<CoinType>(_redeemer: address, redeem_amount: u64, redeem_tokens: u64) {
        assert!(redeem_tokens != 0 || redeem_amount == 0, EREDEEM_TOKENS_ZERO);
    }

    public fun borrow_allowed<CoinType>(borrower: address, borrow_amount: u64): u64 {
        assert!(!storage::borrow_guardian_paused<CoinType>(), EBORROW_PAUSED);

        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        if (!storage::account_membership<CoinType>(borrower)) {
            return ENOT_MARKET_MEMBER
        };

        if (oracle::get_underlying_price<CoinType>() == 0) {
            return EPRICE_ERROR
        };

        let (_, shortfall) = get_hypothetical_account_liquidity_internal<CoinType>(borrower, 0, borrow_amount);
        if (shortfall > 0) {
            return EINSUFFICIENT_LIQUIDITY
        };
        
        let borrow_index = acoin::borrow_index<CoinType>();
        update_fenturefinancedao_borrow_index<CoinType>(borrow_index);
        distribute_borrower_fenturefinancedao<CoinType>(borrower, borrow_index, false);

        NO_ERROR
    }
    public fun borrow_verify<CoinType>(_borrower: address, _borrow_amount: u64) {
        // currently nothing to do
    }

    public fun repay_borrow_allowed<CoinType>(_payer: address, borrower: address, _repay_amount: u64): u64 {
        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        let borrow_index = acoin::borrow_index<CoinType>();
        update_fenturefinancedao_borrow_index<CoinType>(borrow_index);
        distribute_borrower_fenturefinancedao<CoinType>(borrower, borrow_index, false);

        NO_ERROR
    }
    public fun repay_borrow_verify<CoinType>(_payer: address, _borrower: address, _repay_amount: u64, _borrower_index: u128) {
        // currently nothing to do
    }

    public fun liquidate_borrow_allowed<BorrowedCoinType, CollateralCoinType>(_liquidator: address, borrower: address, repay_amount: u64): u64 {
        if (!storage::is_listed<BorrowedCoinType>() || !storage::is_listed<CollateralCoinType>()) {
            return EMARKET_NOT_LISTED
        };

        let (_, shortfall) = get_account_liquidity_internal(borrower);
        if (shortfall == 0) {
            return EINSUFFICIENT_SHORTFALL
        };

        let borrow_balance = acoin::borrow_balance<BorrowedCoinType>(borrower);
        let max_close = storage::close_factor_mantissa() * (borrow_balance as u128) / Exp_Scale();
        if ((repay_amount as u128) > max_close) {
            return ETOO_MUCH_REPAY
        };

        NO_ERROR
    }
    public fun liquidate_borrow_verify<BorrowedCoinType, CollateralCoinType>(_liquidator: address, _borrower: address, _repay_amount: u64, _seize_tokens: u64) {
        // currently nothing to do
    }

    public fun seize_allowed<CollateralCoinType, BorrowedCoinType>(liquidator: address, borrower: address, _seize_tokens: u64): u64 {
        assert!(!storage::seize_guardian_paused(), ESEIZE_PAUSED);

        if (!storage::is_listed<BorrowedCoinType>() || !storage::is_listed<CollateralCoinType>()) {
            return EMARKET_NOT_LISTED
        };

        update_fenturefinancedao_supply_index<CollateralCoinType>();
        distribute_supplier_fenturefinancedao<CollateralCoinType>(borrower, false);
        distribute_supplier_fenturefinancedao<CollateralCoinType>(liquidator, false);

        NO_ERROR
    }
    public fun seize_verify<CollateralCoinType, BorrowedCoinType>(_liquidator: address, _borrower: address, _seize_tokens: u64) {
        // currently nothing to do
    }

    public fun withdraw_allowed<CoinType>(src: address, amount: u64): u64 {
        let allowed = withdraw_allowed_internal<CoinType>(src, amount);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_fenturefinancedao_supply_index<CoinType>();
        distribute_supplier_fenturefinancedao<CoinType>(src, false);

        NO_ERROR
    }
    public fun withdraw_verify<CoinType>(_src: address, _amount: u64) {
        // currently nothing to do
    }

    public fun deposit_allowed<CoinType>(dst: address, amount: u64): u64 {
        let allowed = deposit_allowed_internal<CoinType>(dst, amount);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_fenturefinancedao_supply_index<CoinType>();
        distribute_supplier_fenturefinancedao<CoinType>(dst, false);

        NO_ERROR
    }
    public fun deposit_verify<CoinType>(_dst: address, _amount: u64) {
        // currently nothing to do
    }

    public fun liquidate_calculate_seize_tokens<BorrowedCoinType, CollateralCoinType>(repay_amount: u64): u64 {
        let price_borrowed_mantissa = oracle::get_underlying_price<BorrowedCoinType>();
        let price_collateral_mantissa = oracle::get_underlying_price<CollateralCoinType>();
        let exchange_rate_mantissa = acoin::exchange_rate_mantissa<CollateralCoinType>();
        let liquidation_incentive_mantissa = storage::liquidation_incentive_mantissa();
        let numerator = liquidation_incentive_mantissa * price_borrowed_mantissa / Exp_Scale();
        let denominator = price_collateral_mantissa * exchange_rate_mantissa / Exp_Scale();
        let ratio = numerator * Exp_Scale() / denominator;
        (ratio * (repay_amount as u128) / Exp_Scale() as u64)
    }

    public fun get_hypothetical_account_liquidity<ModifyCoinType>(account: address, redeem_tokens: u64, borrow_amount: u64): (u64, u64) {
        get_hypothetical_account_liquidity_internal<ModifyCoinType>(account, redeem_tokens, borrow_amount)
    }

    // internal functions
    fun get_account_liquidity_internal(account: address): (u64, u64) {
        get_hypothetical_account_liquidity_internal<AptosCoin>(account, 0, 0)
    }
    fun get_hypothetical_account_liquidity_internal<ModifyCoinType>(account: address, redeem_tokens: u64, borrow_amount: u64): (u64, u64) {
        let assets = storage::account_assets(account);
        let index = vector::length<String>(&assets);
        let modify_coin_type = type_name<ModifyCoinType>();
        let sum_collateral: u128 = 0;
        let sum_borrow_plus_effects: u128 = 0;
        while (index > 0) {
            index = index - 1;
            let asset = *vector::borrow<String>(&assets, index);
            if (!acoin::is_account_registered_no_type_args(asset, account)) continue;
            let (acoin_balance, borrow_balance, exchange_rate_mantissa) = acoin::get_account_snapshot_no_type_args(asset, account);
            let collateral_factor_mantissa = storage::collateral_factor_mantissa(asset);
            let oracle_price_mantissa = oracle::get_underlying_price_no_type_args(asset);
            let tokens_to_denom = mulExp(mulExp(collateral_factor_mantissa, exchange_rate_mantissa), oracle_price_mantissa);
            sum_collateral = sum_collateral + tokens_to_denom * (acoin_balance as u128) / Exp_Scale();
            sum_borrow_plus_effects = sum_borrow_plus_effects + oracle_price_mantissa * (borrow_balance as u128) / Exp_Scale();
            if (asset == modify_coin_type) {
                sum_borrow_plus_effects = sum_borrow_plus_effects + tokens_to_denom * (redeem_tokens as u128) / Exp_Scale();
                sum_borrow_plus_effects = sum_borrow_plus_effects + oracle_price_mantissa * (borrow_amount as u128) / Exp_Scale();
            };
        };
        if (sum_collateral > sum_borrow_plus_effects) {
            ((sum_collateral - sum_borrow_plus_effects as u64), 0)
        } else {
            (0, (sum_borrow_plus_effects - sum_collateral as u64))
        }
    }
    fun mulExp(a: u128, b: u128): u128 {
        (a * b + Half_Scale())/Exp_Scale()
    }

    fun redeem_with_fund_allowed_internal<CoinType>(_redeemer: address, _redeem_tokens: u64): u64 {
        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        NO_ERROR
    }
    fun withdraw_allowed_internal<CoinType>(src: address, amount: u64): u64 {
        // If the src is not 'in' the market, then we can bypass the liquidity check 
        if (!storage::account_membership<CoinType>(src)) {
            return NO_ERROR
        };

        let (_, shortfall) = get_hypothetical_account_liquidity_internal<CoinType>(src, amount, 0);
        if (shortfall > 0) {
            return EINSUFFICIENT_LIQUIDITY
        };

        NO_ERROR
    }
    fun deposit_allowed_internal<CoinType>(_dst: address, _amount: u64): u64 {
        assert!(!storage::deposit_guardian_paused(), EDEPOSIT_PAUSED);

        NO_ERROR
    } 

    fun market_listed<CoinType>() {
        storage::support_market<CoinType>();
    } 

    // admin functions
    fun only_admin(account: &signer) {
        assert!(signer::address_of(account) == storage::admin(), ENOT_ADMIN);
    }

    fun only_admin_or_pause_guardian(account: &signer) {
        let guy = signer::address_of(account);
        assert!(guy == storage::admin() || guy == storage::pause_guardian(), ENOT_ADMIN_NOR_PAUSE_GUARDIAN);
    }

    public entry fun set_close_factor(admin: &signer, new_close_factor_mantissa: u128) {
        only_admin(admin);
        storage::set_close_factor(new_close_factor_mantissa);
    }

    public entry fun set_collateral_factor<CoinType>(admin: &signer, new_collateral_factor_mantissa: u128) {
        only_admin(admin);
        assert!(storage::is_listed<CoinType>(), EMARKET_NOT_LISTED);
        storage::set_collateral_factor<CoinType>(new_collateral_factor_mantissa);
    }

    public entry fun set_liquidation_incentive(admin: &signer, new_liquidation_incentive_mantissa: u128) {
        only_admin(admin);
        storage::set_liquidation_incentive(new_liquidation_incentive_mantissa);
    }

    public entry fun approve_market<CoinType>(admin: &signer) {
        only_admin(admin);
        storage::approve_market<CoinType>(admin);
    }   

    public entry fun set_pause_guardian(admin: &signer, new_pause_guardian: address) {
        only_admin(admin);
        storage::set_pause_guardian(new_pause_guardian);
    }

    public entry fun set_mint_paused<CoinType>(guardian: &signer, state: bool) {
        only_admin_or_pause_guardian(guardian);
        storage::set_mint_paused<CoinType>(state);
    }

    public entry fun set_borrow_paused<CoinType>(guardian: &signer, state: bool) {
        only_admin_or_pause_guardian(guardian);
        storage::set_borrow_paused<CoinType>(state);
    }

    public entry fun set_deposit_paused(guardian: &signer, state: bool) {
        only_admin_or_pause_guardian(guardian);
        storage::set_deposit_paused(state);
    }

    public entry fun set_seize_paused(guardian: &signer, state: bool) {
        only_admin_or_pause_guardian(guardian);
        storage::set_seize_paused(state);
    }



    // FENTURE admin functions
    public entry fun fund_fenture_treasury(funder: &signer, amount: u64) {
        storage::deposit_fenture(coin::withdraw<FentureFinanceDao>(funder, amount));
    }

    public entry fun set_fenture_rate(admin: &signer, fenture_rate: u128) {
        only_admin(admin);
        storage::set_fenture_rate(fenture_rate);
        refresh_fenture_speeds();
    }

    public entry fun add_fenture_market<CoinType>(admin: &signer) {
        only_admin(admin);
        storage::add_fenture_market(type_name<CoinType>());
        refresh_fenture_speeds();
    }

    public entry fun drop_fenture_market<CoinType>(admin: &signer) {
        only_admin(admin);
        storage::drop_fenture_market(type_name<CoinType>());
        refresh_fenture_speeds();
    }

    // FENTURE Distribution
    public entry fun refresh_fenture_speeds() {
        let all_markets = storage::all_markets();
        let market_len = vector::length<String>(&all_markets);

        let index = 0;
        while (index < market_len) {
            let coin_type = *vector::borrow<String>(&all_markets, index);
            let borrow_index = acoin::borrow_index_no_type_args(coin_type);
            update_fenturefinancedao_supply_index_no_type_args(coin_type);
            update_fenturefinancedao_borrow_index_no_type_args(coin_type, borrow_index);
            index = index + 1;
        };

        let total_utility: u128 = 0;
        let utilities = vector::empty<u128>();
        index = 0;
        while (index < market_len) {
            let coin_type = *vector::borrow<String>(&all_markets, index);
            if (storage::is_fentureed_no_type_args(coin_type)) {
                let asset_price = oracle::get_underlying_price_no_type_args(coin_type);
                let interest_per_block = acoin::borrow_rate_per_block_no_type_args(coin_type) * acoin::total_borrows_no_type_args(coin_type);
                let utility = interest_per_block * asset_price / Exp_Scale();
                vector::push_back(&mut utilities, utility);
                total_utility = total_utility + utility;
            } else {
                vector::push_back(&mut utilities, 0);
            };
            index = index + 1;
        };

        index = 0;
        while (index < market_len) {
            let coin_type = *vector::borrow<String>(&all_markets, index);
            let utility = *vector::borrow<u128>(&utilities, index);
            let new_speed = if (total_utility == 0) {
                0
            } else {
                storage::fenture_rate() * utility / total_utility
            };
            storage::update_fenture_speed(coin_type, new_speed);
            index = index + 1;
        };
    }
    public fun claimable_borrower_fenturefinancedao(coin_type: String, borrower: address): u128 {
        if (!acoin::is_account_registered_no_type_args(coin_type, borrower)) {
            return 0
        };
        let market_borrow_index = acoin::borrow_index_no_type_args(coin_type);
        update_fenturefinancedao_borrow_index_no_type_args(coin_type, market_borrow_index);
        let (borrow_index, _) = storage::fenture_borrow_state(coin_type);
        let borrower_index = storage::fenture_borrower_index(coin_type, borrower);
        let delta_index = borrow_index - borrower_index;
        let borrower_amount = (acoin::borrow_balance_no_type_args(coin_type, borrower) as u128) * Exp_Scale() / market_borrow_index;
        borrower_amount * delta_index / Exp_Scale()
    }
    public fun claimable_supplier_fenturefinancedao(coin_type: String, supplier: address): u128 {
        if (!acoin::is_account_registered_no_type_args(coin_type, supplier)) {
            return 0
        };
        update_fenturefinancedao_supply_index_no_type_args(coin_type);
        let (supply_index, _) = storage::fenture_supply_state(coin_type);
        let supplier_index = storage::fenture_supplier_index(coin_type, supplier);
        let delta_index = supply_index - supplier_index;
        let supplier_tokens = acoin::balance_no_type_args(coin_type, supplier);
        (supplier_tokens as u128) * delta_index / Exp_Scale()
    }
    public fun claimable_fenturefinancedao_each(coin_type: String, holder: address): u128 {
        if (!acoin::is_account_registered_no_type_args(coin_type, holder)) {
            return 0
        };
        claimable_borrower_fenturefinancedao(coin_type, holder) + claimable_supplier_fenturefinancedao(coin_type, holder)
    }
    public fun claimable_fenturefinancedao(holder: address): u128 {
        let all_markets = storage::all_markets();
        let market_len = vector::length<String>(&all_markets);
        let claimable_fenturefinancedao: u128 = storage::fenture_accrued(holder);
        let index = 0;
        while (index < market_len) {
            let coin_type = *vector::borrow<String>(&all_markets, index);
            if (acoin::is_account_registered_no_type_args(coin_type, holder)) {
                claimable_fenturefinancedao = claimable_fenturefinancedao + claimable_fenturefinancedao_each(coin_type, holder);
            };
            index = index + 1;
        };
        claimable_fenturefinancedao
    }


    fun update_fenturefinancedao_supply_index<CoinType>() {
        update_fenturefinancedao_supply_index_no_type_args(type_name<CoinType>());
    }
    fun distribute_supplier_fenturefinancedao<CoinType>(supplier: address, distribute_all: bool) {
        distribute_supplier_fenturefinancedao_no_type_args(type_name<CoinType>(), supplier, distribute_all);
    }
    fun update_fenturefinancedao_borrow_index<CoinType>(market_borrow_index: u128) {
        update_fenturefinancedao_borrow_index_no_type_args(type_name<CoinType>(), market_borrow_index);
    }
    fun distribute_borrower_fenturefinancedao<CoinType>(borrower: address, market_borrow_index: u128, distribute_all: bool) {
        distribute_borrower_fenturefinancedao_no_type_args(type_name<CoinType>(), borrower, market_borrow_index, distribute_all);
    }

    fun update_fenturefinancedao_supply_index_no_type_args(coin_type: String) {
        let (supply_state_index, supply_state_block) = storage::fenture_supply_state(coin_type);
        let supply_speed = storage::fenture_speed(coin_type);
        let block_number = timestamp::now_seconds();
        let delta_blocks = block_number - supply_state_block;
        if (delta_blocks > 0 && supply_speed > 0) {
            let supply_tokens = acoin::total_supply_no_type_args(coin_type);
            let fenture_accrued = (delta_blocks as u128) * supply_speed;
            let ratio = if (supply_tokens > 0) {
                fenture_accrued * Exp_Scale() / supply_tokens
            } else { 0 };
            let new_index = supply_state_index + ratio;
            storage::update_fenture_supply_state(coin_type, new_index, block_number);
        } else if (delta_blocks > 0) { 
            storage::update_fenture_supply_state(coin_type, supply_state_index, block_number);
        };
    }
    fun distribute_supplier_fenturefinancedao_no_type_args(coin_type: String, supplier: address, distribute_all: bool) {
        let (supply_index, _) = storage::fenture_supply_state(coin_type);
        let supplier_index = storage::fenture_supplier_index(coin_type, supplier);
        storage::update_fenture_supplier_state(coin_type, supplier, supply_index);

        let delta_index = supply_index - supplier_index;
        let supplier_tokens = acoin::balance_no_type_args(coin_type, supplier);
        let supplier_delta = (supplier_tokens as u128) * delta_index / Exp_Scale();
        let supplier_accrued = storage::fenture_accrued(supplier) + supplier_delta;
        let threshold = if (distribute_all) { 0 } else { constants::Fenture_Claim_Threshold() };
        storage::update_fenture_accrued(supplier, storage::transfer_fenture(supplier, supplier_accrued, threshold));
        storage::emit_distribute_supplier_fenture_event(coin_type, supplier, supplier_delta, supply_index);
    }

    fun update_fenturefinancedao_borrow_index_no_type_args(coin_type: String, market_borrow_index: u128) {
        let (borrow_state_index, borrow_state_block) = storage::fenture_borrow_state(coin_type);
        let borrow_speed = storage::fenture_speed(coin_type);
        let block_number = timestamp::now_seconds();
        let delta_blocks = block_number - borrow_state_block;
        if (delta_blocks > 0 && borrow_speed > 0) {
            let borrow_amount = acoin::total_borrows_no_type_args(coin_type) * Exp_Scale() / market_borrow_index;
            let fenture_accrued = (delta_blocks as u128) * borrow_speed;
            let ratio = if (borrow_amount > 0) {
                fenture_accrued * Exp_Scale() / borrow_amount
            } else { 0 };
            let new_index = borrow_state_index + ratio;
            storage::update_fenture_borrow_state(coin_type, new_index, block_number);
        } else if (delta_blocks > 0) {
            storage::update_fenture_borrow_state(coin_type, borrow_state_index, block_number);
        };
    }
    fun distribute_borrower_fenturefinancedao_no_type_args(coin_type: String, borrower: address, market_borrow_index: u128, distribute_all: bool) {
        let (borrow_index, _) = storage::fenture_borrow_state(coin_type);
        let borrower_index = storage::fenture_borrower_index(coin_type, borrower);
        storage::update_fenture_borrower_state(coin_type, borrower, borrow_index);

        let delta_index = borrow_index - borrower_index;
        let borrower_amount = (acoin::borrow_balance_no_type_args(coin_type, borrower) as u128) * Exp_Scale() / market_borrow_index;
        let borrower_delta = borrower_amount * delta_index / Exp_Scale();
        let borrower_accrued = storage::fenture_accrued(borrower) + borrower_delta;
        let threshold = if (distribute_all) { 0 } else { constants::Fenture_Claim_Threshold() };
        storage::update_fenture_accrued(borrower, storage::transfer_fenture(borrower, borrower_accrued, threshold));
        storage::emit_distribute_borrower_fenture_event(coin_type, borrower, borrower_delta, borrow_index);
    }

}