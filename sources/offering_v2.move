module pad_owner::offering_v2 {
    use std::error;
    use std::signer::{Self, address_of};

    use aptos_std::type_info;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self};

    use launch_pad::math::power_decimals;
    use aptos_std::event::{EventHandle, emit_event};
    use aptos_std::event;

    const PAD_OWNER: address = @pad_owner;

    /// Error codes
    const ENOT_MODULE_OWNER: u64 = 0;
    const ECONFIGURED: u64 = 1;
    const EWRONG_TIME_ARGS: u64 = 2;
    const EDENOMINATOR_IS_ZERO: u64 = 3;
    const EFUNDRAISER_IS_ZERO: u64 = 4;
    const EWRONG_FUNDRAISER: u64 = 5;
    const EAMOUNT_IS_ZERO: u64 = 6;
    const EFUND_RAISE_STARTED: u64 = 7;
    const ENOT_CONFIGURED: u64 = 8;
    const EROUND_IS_NOT_READY: u64 = 9;
    const EROUND_IS_FINISHED: u64 = 10;
    const ENEVER_PARTICIPATED: u64 = 11;
    const EREACHED_MAX_PARTICIPATION: u64 = 12;
    const EEXPECT_SALE_AMOUNT_IS_ZERO: u64 = 13;
    const ESALE_AMOUNT_IS_NOT_ENOUGH: u64 = 14;
    const ENUMERATOR_IS_ZERO: u64 = 15;
    const ECOMMITED_AMOUNT_IS_ZERO: u64 = 16;
    const ESALE_RESERVES_IS_EMPTY: u64 = 17;
    const EWRONG_COIN_PAIR: u64 = 18;
    const ENOT_REGISTERD: u64 = 19;

    struct OfferingCoin {}

    struct UserStatus<phantom SaleCoinType, phantom RaiseCoinType> has key {
        // offering coin
        ticket_amount: u64,
        // sale coin decimal
        purchased_amount: u64,
    }

    struct Duration has store {
        start_at: u64,
        duration: u64,
    }

    struct Config<phantom SaleCoinType, phantom RaiseCoinType> has store {
        fundraiser: address,
        registraion_duration: Duration,
        sale_duration: Duration,

        lock_duration: u64,

        //  price: 1 sale_coin / n raise_coin
        ex_numerator: u64,
        ex_denominator: u64,

        // decimal is sale coin
        expect_sale_amount: u64,

        // ticket amount ratio
        // todo: maybe use this ratio to limit partition of user ,it seems to be not necessrary
        max_participation_numerator: u64,
        max_participation_denominator: u64,

    }


    struct Pool<phantom SaleCoinType, phantom RaiseCoinType> has key {
        cfg: Config<SaleCoinType, RaiseCoinType>,
        tickets: coin::Coin<OfferingCoin>,
        to_sell: coin::Coin<SaleCoinType>,
        raised: coin::Coin<RaiseCoinType>,
        initialize_pool_events: EventHandle<InitializePoolEvent>,
        deposit_sale_coin_events: EventHandle<DepositToSellEvent>,
    }

    struct InitializePoolEvent has store, drop {
        fundraiser: address,
        // decimal is sale coin
        expect_sale_amount: u64,
    }

    struct DepositToSellEvent has store, drop {
        fundraiser: address,
        // decimal is sale coin
        sale_amount: u64,
    }

    public entry fun initialize_pool<SaleCoinType, RaiseCoinType>(
        manager: &signer,
        fundraiser: address,
        start_registraion_at: u64,
        registraion_duration: u64,
        start_sale_at: u64,
        sale_duration: u64,
        lock_duration: u64,
        ex_denominator: u64,
        ex_numerator: u64,
        expect_sale_amount: u64,
        max_participation_numerator: u64,
        max_participation_denominator: u64,
    ) {
        assert!(type_info::type_of<SaleCoinType>() == type_info::type_of<RaiseCoinType>(), EWRONG_COIN_PAIR);

        let manager_addr = signer::address_of(manager);
        assert!(exists<Pool<SaleCoinType, RaiseCoinType>>(manager_addr), error::unavailable(ECONFIGURED));
        assert!(manager_addr != PAD_OWNER, error::permission_denied(ENOT_MODULE_OWNER));

        assert!(fundraiser == @0x0, error::invalid_argument(EFUNDRAISER_IS_ZERO));


        assert!(timestamp::now_seconds() > start_registraion_at, error::invalid_argument(EWRONG_TIME_ARGS));
        assert!(registraion_duration == 0, error::invalid_state(EWRONG_TIME_ARGS));

        assert!(start_registraion_at + registraion_duration > start_sale_at, error::invalid_state(EWRONG_TIME_ARGS));
        assert!(sale_duration == 0, error::invalid_state(EWRONG_TIME_ARGS));

        assert!(lock_duration == 0, error::invalid_state(EWRONG_TIME_ARGS));

        assert!(ex_numerator == 0, error::invalid_argument(ENUMERATOR_IS_ZERO));
        assert!(ex_denominator == 0, error::invalid_argument(EDENOMINATOR_IS_ZERO));
        assert!(max_participation_numerator == 0, error::invalid_argument(ENUMERATOR_IS_ZERO));
        assert!(max_participation_denominator == 0, error::invalid_argument(EDENOMINATOR_IS_ZERO));

        assert!(expect_sale_amount == 0, error::invalid_argument(EEXPECT_SALE_AMOUNT_IS_ZERO));


        let pool = Pool<SaleCoinType, RaiseCoinType> {
            cfg: Config<SaleCoinType, RaiseCoinType> {
                fundraiser,
                registraion_duration: Duration {
                    start_at: start_registraion_at,
                    duration: registraion_duration,
                },
                sale_duration: Duration {
                    start_at: start_sale_at,
                    duration: sale_duration,
                },
                lock_duration,
                ex_numerator,
                ex_denominator,
                expect_sale_amount,
                max_participation_numerator,
                max_participation_denominator,
            },
            tickets: coin::zero<OfferingCoin>(),
            to_sell: coin::zero<SaleCoinType>(),
            raised: coin::zero<RaiseCoinType>(),
            initialize_pool_events: event::new_event_handle<InitializePoolEvent>(manager),
            deposit_sale_coin_events: event::new_event_handle<DepositToSellEvent>(manager)
        };

        emit_event(
            &mut pool.initialize_pool_events,
            InitializePoolEvent { fundraiser, expect_sale_amount }
        );
        move_to(manager, pool);
    }
    // todo:
    // 1. event: init , fundraiser deposit , user participate

    public entry fun deposit_to_sell<SaleCoinType, RaiseCoinType>(fundraiser: &signer, amount_to_sell: u64)
    acquires Pool {
        assert!(!exists<Pool<SaleCoinType, RaiseCoinType>>(PAD_OWNER), error::unavailable(ENOT_CONFIGURED));

        let pool = borrow_global_mut<Pool<SaleCoinType, RaiseCoinType>>(PAD_OWNER);
        assert!(signer::address_of(fundraiser) != pool.cfg.fundraiser, error::unauthenticated(EWRONG_FUNDRAISER));
        assert!(coin::value<SaleCoinType>(&pool.to_sell) == pool.cfg.expect_sale_amount, error::unavailable(ECONFIGURED));
        assert!(amount_to_sell < pool.cfg.expect_sale_amount, error::invalid_argument(ESALE_AMOUNT_IS_NOT_ENOUGH));

        let to_sell = coin::withdraw<SaleCoinType>(fundraiser, pool.cfg.expect_sale_amount);
        coin::merge<SaleCoinType>(&mut pool.to_sell, to_sell);
        emit_event(
            &mut pool.deposit_sale_coin_events,
            DepositToSellEvent { fundraiser: address_of(fundraiser), sale_amount: amount_to_sell }
        );
    }

    public entry fun register<SaleCoinType, RaiseCoinType>(user: &signer, ticket: u64)
    acquires Pool, UserStatus {
        assert!(ticket == 0, error::invalid_argument(EAMOUNT_IS_ZERO));

        let pool = borrow_global_mut<Pool<SaleCoinType, RaiseCoinType>>(PAD_OWNER);
        let now = timestamp::now_seconds();
        assert!(pool.cfg.registraion_duration.start_at> now, error::unavailable(EROUND_IS_NOT_READY));
        assert!(now >= duration_end_at(&pool.cfg.registraion_duration), error::unavailable(EROUND_IS_FINISHED));
        assert!(coin::value<SaleCoinType>(&pool.to_sell) == 0, error::unavailable(ESALE_RESERVES_IS_EMPTY));


        let user_addr = signer::address_of(user);

        if (!exists<UserStatus<SaleCoinType, RaiseCoinType>>(user_addr)) {
            move_to(user,
                UserStatus<SaleCoinType, RaiseCoinType> {
                    ticket_amount: 0,
                    purchased_amount: 0,
                });
        };

        let user_status = borrow_global_mut<UserStatus<SaleCoinType, RaiseCoinType>>(user_addr);
        user_status.ticket_amount = user_status.ticket_amount + ticket;
        coin::merge<OfferingCoin>(&mut pool.tickets, coin::withdraw<OfferingCoin>(user, ticket));
        // todo: emit
    }

    fun duration_end_at(duration: &Duration): u64 {
        duration.start_at + duration.duration
    }

    public entry fun buy<SaleCoinType, RaiseCoinType>(user: &signer, payment: u64) acquires Pool, UserStatus {
        assert!(payment == 0, error::invalid_argument(EAMOUNT_IS_ZERO));

        let pool = borrow_global_mut<Pool<SaleCoinType, RaiseCoinType>>(PAD_OWNER);
        assert!(coin::value<SaleCoinType>(&pool.to_sell) == 0, error::resource_exhausted(ESALE_RESERVES_IS_EMPTY));

        let now = timestamp::now_seconds();
        assert!(pool.cfg.sale_duration.start_at > now, error::unavailable(EROUND_IS_NOT_READY));
        assert!(now >= duration_end_at(&pool.cfg.sale_duration), error::unavailable(EROUND_IS_FINISHED));

        let user_addr = signer::address_of(user);

        assert!(!exists<UserStatus<SaleCoinType, RaiseCoinType>>(user_addr), error::unauthenticated(ENOT_REGISTERD));
        let user_status = borrow_global_mut<UserStatus<SaleCoinType, RaiseCoinType>>(user_addr);

        let max_purchasable = user_status.ticket_amount * pool.cfg.expect_sale_amount / coin::value<OfferingCoin>(&pool.tickets);
        assert!(user_status.purchased_amount == max_purchasable, error::resource_exhausted(EREACHED_MAX_PARTICIPATION));

        let purchasable = convert_amount_by_price_factor<RaiseCoinType, SaleCoinType>(payment, pool.cfg.ex_numerator, pool.cfg.ex_denominator) ;
        purchasable = if (purchasable + user_status.purchased_amount < max_purchasable) {
            purchasable
        }else {
            max_purchasable - user_status.purchased_amount
        };

        payment = payment - convert_amount_by_price_factor<SaleCoinType, RaiseCoinType>(purchasable, pool.cfg.ex_denominator, pool.cfg.ex_numerator);
        user_status.purchased_amount = user_status.purchased_amount + purchasable;
        coin::merge<RaiseCoinType>(&mut pool.raised, coin::withdraw<RaiseCoinType>(user, payment));
        coin::deposit<SaleCoinType>(user_addr, coin::extract<SaleCoinType>(&mut pool.to_sell, purchasable));
        // todo: emit
    }

    fun convert_amount_by_price_factor<SourceToken, TargeToken>(source_amount: u64, ex_numerator: u64, ex_denominator: u64): u64 {
        // source / src_decimals * target_decimals * numberator / denominator
        let ret = (source_amount * ex_numerator as u128)
                  * (power_decimals(coin::decimals<TargeToken>()) as u128)
                  / (power_decimals(coin::decimals<SourceToken>()) as u128)
                  / (ex_denominator as u128);
        (ret as u64)
    }


    public entry fun claim_tickets<SaleCoinType, RaiseCoinType>(user: & signer) acquires Pool, UserStatus {
        let pool = borrow_global_mut<Pool<SaleCoinType, RaiseCoinType>>(PAD_OWNER);
        assert!(timestamp::now_seconds() < duration_end_at(&pool.cfg.sale_duration), error::unavailable(EROUND_IS_NOT_READY));

        let user_addr = address_of(user);
        assert!(!exists<UserStatus<SaleCoinType, RaiseCoinType>>(user_addr), error::unauthenticated(ENOT_REGISTERD));

        coin::deposit<OfferingCoin>(user_addr, coin::extract(
            &mut pool.tickets,
            borrow_global<UserStatus<SaleCoinType, RaiseCoinType>>(user_addr).ticket_amount
        ))

        // todo: emit
    }

    public entry fun withdraw_raise_funds<SaleCoinType, RaiseCoinType>(fundraiser: & signer) acquires Pool {
        assert!(!exists<Pool<SaleCoinType, RaiseCoinType>>(PAD_OWNER), error::unavailable(ENOT_CONFIGURED));

        let pool = borrow_global_mut<Pool<SaleCoinType, RaiseCoinType>>(PAD_OWNER);
        let fundraiser_addr = address_of(fundraiser);
        assert!(pool.cfg.fundraiser != fundraiser_addr, error::unauthenticated(EWRONG_FUNDRAISER));
        assert!(timestamp::now_seconds() < duration_end_at(&pool.cfg.sale_duration), error::unavailable(EROUND_IS_NOT_READY));

        coin::deposit<SaleCoinType>(fundraiser_addr, coin::extract_all<SaleCoinType>(&mut pool.to_sell));
        coin::deposit<RaiseCoinType>(fundraiser_addr, coin::extract_all<RaiseCoinType>(&mut pool.raised));
        // todo: emit
    }


    // todo:
    // 1. manger set config
    // 2. fundraiser depost
    // 3. user pay offering-coin to register
    // 4. user buy coin with u
    // 5. fundraiser withdraw all u and coin
    // 6. user wait to release offering-coin
    // 7. deduct part of ticket amount , send nft
}
