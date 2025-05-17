module bassinet::basinet;
use bassinet::bassinet_nft::{Self, Mint, BassinetNFT};
use sui::sui::SUI;
use std::string::{String};
use sui::coin::{Coin};
use sui::transfer_policy::{TransferPolicy, TransferPolicyCap};
use bassinet::royalty_rule::{Self};
use bassinet::floor_price_rule::{Self};
use bassinet_coin::bassinet_coin::{TreasuryLock, AdminCap};

const ENoProfits: u64 = 0;

/// 领取激励
entry fun take_rewards(
    self: &mut Mint, 
    recipient: address, 
    ctx: &mut TxContext) {
    let profits = bassinet_nft::take_profits(self, ctx);
    assert!(profits.value() > 0, ENoProfits);
    transfer::public_transfer(profits, recipient);
}

/// 筹造NFT
entry fun mint(
    mint: &mut Mint,
    lock: &mut TreasuryLock,
    paid: &mut Coin<SUI>,
    name: String,
    ctx: &mut TxContext) {
        let (nft, coin) = bassinet_nft::mint(mint, lock, paid, name, ctx);
        let sender = ctx.sender();
        transfer::public_transfer(nft, sender);
        transfer::public_transfer(coin, sender);
    }

/// 配置并授权
entry fun authorize(
    admin_cap: &AdminCap,
    self: &mut Mint,
    policy: &mut TransferPolicy<BassinetNFT>,
    policy_cap: &TransferPolicyCap<BassinetNFT>,
    app_name: String,
    description: vector<u8>,
    collection_id: vector<u8>,
    collection_url: vector<u8>,
    limit: u64,
    rewards_quantity: u64,
    minting_price: u64
) {
    // 交易收成 10%,min 0.1SUI
    royalty_rule::add(policy, policy_cap, 1000u16, 100_000_000u64);
    // 地板价
    floor_price_rule::add(policy, policy_cap, minting_price);
    bassinet_nft::authorize_(admin_cap, self, app_name, description, collection_id, collection_url, limit, rewards_quantity, minting_price);
}

/// 解除授权
entry fun deauthorize(
    admin_cap: &AdminCap,
    self: &mut Mint) {
    bassinet_nft::deauthorize_(admin_cap, self);
}

/// 更改筹造price
entry fun change_minting_price_(
    admin_cap: &AdminCap,
    self: &mut Mint,
    price: u64,
    ctx: &mut TxContext) {
    bassinet_nft::change_minting_price_(admin_cap, self, price, ctx);
}

/// 更改owner
entry fun change_owner(
    self: &mut BassinetNFT,
    ctx: &mut TxContext) {
    bassinet_nft::change_owner_(self, ctx);
}