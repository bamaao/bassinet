module bassinet::bassinet_coin;

public struct BASSINET_COIN has drop {}

use sui::coin::{Self, Coin, TreasuryCap};
use sui::balance::{Self, Balance};

/// For when there's no profits to claim.
const ENoProfits: u64 = 0;

public struct TreasuryLock has key, store {
    id: UID,
    treasury_cap: TreasuryCap<BASSINET_COIN>,
    // 最大供应量
    max_supply: u64,
    // 总供应量
    total_supply: u64,
    // 挖矿次数
    mint_count: u64,
    // 创作者
    creator: address,
    // 创作者激励
    creator_rewards: Balance<BASSINET_COIN>,
    // 平台方
    platform_provider: address,
    // 平台方激励
    platform_provider_rewards: Balance<BASSINET_COIN>
}

/// 初始调用
fun init(witness: BASSINET_COIN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        6,
        b"BASSINET_COIN",
        b"",
        b"",
        option::none(),
        ctx,
    );
    // let publisher = package::claim(&witness, ctx);
    // transfer::public_transfer(publisher, ctx.sender());
    // Freezing this object makes the metadata immutable, including the title, name, and icon image.
    // If you want to allow mutability, share it with public_share_object instead.
    transfer::public_freeze_object(metadata);

    let creator = @creator;
    let platform_provider = @platform_provider;

    let lock = TreasuryLock {
        id: object::new(ctx),
        treasury_cap: treasury_cap,
        // 10亿*10^6
        max_supply: 1_000_000_000_000_000,
        total_supply: 0,
        mint_count: 0,
        creator: creator,
        creator_rewards: balance::zero<BASSINET_COIN>(),
        platform_provider: platform_provider,
        platform_provider_rewards: balance::zero<BASSINET_COIN>()
    };
    transfer::public_share_object(lock)
}

/// Create BASSINET_COIN using the TreasuryCap.
public(package) fun mint(
    // treasury_cap: &mut TreasuryCap,
    treasury_lock: &mut TreasuryLock,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    if (treasury_lock.total_supply >= treasury_lock.max_supply) {
        return
    };

    let _mint_amount = treasury_lock.max_supply - treasury_lock.total_supply;

    let mint_amount = if (_mint_amount > amount) amount else _mint_amount;
    
    // plan
    // minter 49%
    // creator 30%
    // platform provider 21%
    let recipient_amount = (mint_amount * 49) / 100;
    let creator_amount = (mint_amount * 30) / 100;
    let provider_amount = mint_amount - recipient_amount - creator_amount;

    // mint to recipient
    let coin = coin::mint(&mut treasury_lock.treasury_cap, recipient_amount, ctx);
    transfer::public_transfer(coin, recipient);

    // mint to creator
    let creator_balance = coin::mint_balance(&mut treasury_lock.treasury_cap, creator_amount);
    balance::join(&mut treasury_lock.creator_rewards, creator_balance);

    // mint to platform provider
    let provider_balance = coin::mint_balance(&mut treasury_lock.treasury_cap, provider_amount);
    balance::join(&mut treasury_lock.platform_provider_rewards, provider_balance);
    
    treasury_lock.mint_count = treasury_lock.mint_count + 1;
    treasury_lock.total_supply= treasury_lock.total_supply + mint_amount;
}

/// 领取激励
public entry fun take_rewards(treasury_lock: &mut TreasuryLock, recipient: address, ctx: &mut TxContext) {
    let sender = ctx.sender();
    if (is_creator(sender)) {
        let coin = take_creator_profits(treasury_lock, ctx);
        transfer::public_transfer(coin, recipient);
    }else if (is_platform_provider(sender)) {
        let coin = take_provider_profits(treasury_lock, ctx);
        transfer::public_transfer(coin, recipient);
    };
}

/// 领取创作者激励
fun take_creator_profits(self: &mut TreasuryLock, ctx: &mut TxContext): Coin<BASSINET_COIN> {
    let amount = balance::value(&self.creator_rewards);
    assert!(amount > 0, ENoProfits);
    // Take a transferable `Coin` from a `Balance`
    coin::take(&mut self.creator_rewards, amount, ctx)
}

/// 领取平台激励
fun take_provider_profits(self: &mut TreasuryLock, ctx: &mut TxContext): Coin<BASSINET_COIN> {
    let amount = balance::value(&self.creator_rewards);
    assert!(amount > 0, ENoProfits);
    // Take a transferable `Coin` from a `Balance`
    coin::take(&mut self.creator_rewards, amount, ctx)
}

/// 是否平台方
fun is_platform_provider(operator_address: address): bool {
    let provider_address = @platform_provider;
    provider_address == operator_address
}

/// 是否创作者
fun is_creator(operator_address: address): bool {
    let creator_address = @creator;
    creator_address == operator_address
}