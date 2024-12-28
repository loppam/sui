module my_token::managed {
    use sui::coin::{Self, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use std::option;
    use sui::sui::SUI;
    use sui::event;


    // Error codes
    const E_TRADING_DISABLED: u64 = 1;
    const E_INSUFFICIENT_PAYMENT: u64 = 2;
    const E_UNAUTHORIZED: u64 = 3;
    const E_ZERO_AMOUNT: u64 = 4;

    /// The type identifier of our token
    struct MANAGED_TOKEN has drop {}

    /// Holds the config for trading
    struct TradingConfig has key {
        id: UID,
        trading_enabled: bool,
        current_exchange_rate: u64,
        fee_collector: address,
        treasury_cap: TreasuryCap<MANAGED_TOKEN>
    }

    // Events
    #[allow(unused_field)]
    struct MintEvent has copy, drop {
        amount: u64,
        recipient: address,
        exchange_rate: u64
    }

    #[allow(unused_field)]
    struct SellEvent has copy, drop {
        amount: u64,
        recipient: address,
        exchange_rate: u64
    }

    #[allow(unused_field)]
    struct ExchangeRateUpdateEvent has copy, drop {
        old_rate: u64,
        new_rate: u64
    }

    #[allow(unused_field)]
    struct TradingToggleEvent has copy, drop {
        enabled: bool
    }

    /// Module initializer - called once on module publish
    fun init(ctx: &mut TxContext) {
        let witness = MANAGED_TOKEN {};
        let (treasury_cap, metadata) = coin::create_currency(
            witness, 
            9, // decimals
            b"MTK", // symbol
            b"My Token", // name
            b"A Sui-based token with dynamic exchange rate", // description
            option::none(), // icon url
            ctx
        );

        // Create trading config with mainnet-appropriate initial settings
        let trading_config = TradingConfig {
            id: object::new(ctx),
            trading_enabled: true,
            current_exchange_rate: 1_000_000_000, // Initial rate 1:1
            fee_collector: tx_context::sender(ctx),
            treasury_cap
        };

        // Share the config object and freeze metadata
        transfer::share_object(trading_config);
        transfer::public_freeze_object(metadata);
    }

    public entry fun mint(
        config: &mut TradingConfig,
        payment: &mut coin::Coin<SUI>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        // Validation checks
        assert!(config.trading_enabled, E_TRADING_DISABLED);
        assert!(amount > 0, E_ZERO_AMOUNT);
        assert!(coin::value(payment) >= amount, E_INSUFFICIENT_PAYMENT);

        let tokens_to_mint = (amount * config.current_exchange_rate) / 1_000_000_000;
        let old_rate = config.current_exchange_rate;
        
        // Update exchange rate with price impact
        config.current_exchange_rate = config.current_exchange_rate + (config.current_exchange_rate / 100);
        
        // Transfer SUI to fee collector
        transfer::public_transfer(coin::split(payment, amount, ctx), config.fee_collector);
        
        // Mint and transfer tokens to recipient
        coin::mint_and_transfer(&mut config.treasury_cap, tokens_to_mint, recipient, ctx);

        // Emit events
        event::emit(MintEvent {
            amount: tokens_to_mint,
            recipient,
            exchange_rate: config.current_exchange_rate
        });
        
        event::emit(ExchangeRateUpdateEvent {
            old_rate,
            new_rate: config.current_exchange_rate
        });
    }

    public entry fun sell(
        config: &mut TradingConfig,
        token: coin::Coin<MANAGED_TOKEN>,
        payment: &mut coin::Coin<SUI>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        assert!(config.trading_enabled, E_TRADING_DISABLED);

        let amount_tokens = coin::value(&token);
        assert!(amount_tokens > 0, E_ZERO_AMOUNT);
        
        let amount_sui = (amount_tokens * 1_000_000_000) / config.current_exchange_rate;
        assert!(coin::value(payment) >= amount_sui, E_INSUFFICIENT_PAYMENT);
        
        let old_rate = config.current_exchange_rate;
        
        // Burn the tokens
        coin::burn(&mut config.treasury_cap, token);
        
        // Transfer SUI to recipient
        transfer::public_transfer(coin::split(payment, amount_sui, ctx), recipient);
        
        // Update exchange rate with price impact
        if (config.current_exchange_rate > 1_000_000_000) {
            config.current_exchange_rate = config.current_exchange_rate - (config.current_exchange_rate / 200);
        };

        // Emit events
        event::emit(SellEvent {
            amount: amount_tokens,
            recipient,
            exchange_rate: config.current_exchange_rate
        });
        
        event::emit(ExchangeRateUpdateEvent {
            old_rate,
            new_rate: config.current_exchange_rate
        });
    }

    public entry fun update_exchange_rate(
        config: &mut TradingConfig,
        new_rate: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.fee_collector, E_UNAUTHORIZED);
        assert!(new_rate > 0, E_ZERO_AMOUNT);
        let old_rate = config.current_exchange_rate;
        config.current_exchange_rate = new_rate;
        event::emit(ExchangeRateUpdateEvent {
            old_rate,
            new_rate
        });
    }

    public entry fun toggle_trading(
        config: &mut TradingConfig,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == config.fee_collector, E_UNAUTHORIZED);
        config.trading_enabled = !config.trading_enabled;
        event::emit(TradingToggleEvent {
            enabled: config.trading_enabled
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}