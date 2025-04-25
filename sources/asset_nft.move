#[allow(unused_const)]
module bassinet::asset_nft;

use std::string::{Self, String};
use sui::vec_set::{Self, VecSet};
use std::ascii;
use sui::event;
use sui::url::{Self, Url};
use sui::balance::{Self,Balance};
use sui::coin::{Self,Coin};
use sui::table::{Self, Table};
use sui::sui::SUI;
use bassinet::bassinet_nft::AdminCap;
use bassinet::bassinet_coin::TreasuryLock;
use bassinet::bassinet_nft;

/// Default fee for minting, 8 SUI
const DEFAULT_MINTING_PRICE: u64 = 8_000_000_000;
/// 最大发行量1亿
const DEFAULT_MAX_SUPPLY: u64 = 100_000_000;

/// 错误码：供应不足
const ENotEnoughSupply: u64 = 0;
/// 错误码：不能重复发行
const EDontMintAgain: u64 = 1;
/// The amount paid does not match the expected.
const EAmountIncorrect: u64 = 2;
/// For when there's no profits to claim.
const ENoProfits: u64 = 3;
/// 名称已存在
const ENameAlreadyExists: u64 = 4;
/// 不是创作者
const ENotCreator: u64 = 5;
/// 不是平台方
const ENotPlatformProvider: u64 = 6;
/// 不可更改
const EUnchangeable: u64 = 7;
/// DID不存在
const ENoDID: u64 = 8;
/// DID已存在
const EDIDAlreadyExists: u64 = 9;
/// DID无效
const EInvalidDID: u64 = 10;

// ===== Events =====
public struct AssetNFTIssuanced has copy, drop {
    // The Object ID of the NFT
    object_id: ID,
    // The creator of the NFT
    creator: address,
    // The name of the NFT
    name: String,
    symbol: ascii::String
}

public struct ASSET_NFT has drop {} 

public struct AuthorCap has key, store {
    id: UID
}

public struct AssetProfile has store, copy, drop {
    name: String,
    symbol: ascii::String,
    description: String,
    icon_url: Option<Url>,
    did: Option<String>
}

/// 发行资产
public struct AssetNft has key, store {
    id: UID,
    profile: AssetProfile,
    // 最大发行量
    max_supply: u64,
    // 总发行量
    total_supply: u64,
    // Mint记录
    record: Table<address, u64>,
    // The fee that user has to pay for minting. Can be changed through method that requires admin capability
    minting_price: u64,
    // 奖励数量
    rewards_amount: u64,
    // The profits collected from mint
    // profits: Balance<SUI>,
    // 创作者
    creator: address,
    // 平台方
    // platform_provider: address
    // 创作者收益
    creator_profits: Balance<SUI>,
    // 平台方收益
    platform_provider_profits: Balance<SUI>,
    // 是否可mint
    is_mintable: bool,
    // 是否禁止
    is_banned: bool
}

/// 发行记录
public struct IssuanceRecord has key, store {
    id: UID,
    issuance_names: VecSet<String>,
    creator: address,
    platform_provider: address,
    asset_nfts: VecSet<ID>
}

fun init(_otw: ASSET_NFT, ctx: &mut TxContext) {
    let creator_address = @creator;
    let provider_address = @platform_provider;

    let record = IssuanceRecord {
        id: object::new(ctx),
        issuance_names: vec_set::empty(),
        creator: creator_address,
        platform_provider: provider_address,
        asset_nfts: vec_set::empty()
    };
    transfer::public_share_object(record);

    let author_cap = AuthorCap {
        id: object::new(ctx)
    };
    transfer::public_transfer(author_cap, creator_address);
}

/// 发行新的Asset NFT
public entry fun issuance_assetnft(
    _: &AuthorCap,
    issuance_record: &mut IssuanceRecord,
    name: String,
    symbol: ascii::String,
    description: String,
    icon_url: ascii::String,
    // 最大发行量
    max_supply: u64,
    // 发行价格SUI
    mint_price: u64,
    // 激励数量
    rewards_amount: u64,
    ctx: &mut TxContext)  {
    // 创作者才能操作
    let sender = tx_context::sender(ctx);
    let creator = @creator;
    assert!(sender == creator, ENotCreator);

    // 名称不能重复
    assert!(!vec_set::contains(&issuance_record.issuance_names, &name), ENameAlreadyExists);

    // 最大发行量
    let supply: u64 = if (max_supply > 0) max_supply else DEFAULT_MAX_SUPPLY;

    let price: u64 = if (mint_price > 0) mint_price else DEFAULT_MINTING_PRICE;

    let url = if (ascii::is_empty(&icon_url)) option::none<Url>() else option::some<Url>(url::new_unsafe(icon_url));

    let profile = AssetProfile {
        name:name,
        symbol: symbol,
        description: description,
        icon_url: url,
        did: option::none()
    };

    let asset_nft = AssetNft {
        id: object::new(ctx),
        profile: profile,
        // 最大发行量
        max_supply: supply,
        // 总发行量
        total_supply: 0,
        // Mint记录
        record: table::new<address, u64>(ctx),
        // The fee that user has to pay for minting. Can be changed through method that requires admin capability
        minting_price: price,
        // 奖励数量
        rewards_amount: rewards_amount,
        creator: sender,
        creator_profits: balance::zero<SUI>(),
        platform_provider_profits: balance::zero<SUI>(),
        is_mintable: false,
        is_banned: false
    };

    let id = object::uid_to_inner(&asset_nft.id);

    // 发行emit event
    event::emit(AssetNFTIssuanced {
        object_id: id,
        creator: creator,
        name: asset_nft.profile.name,
        symbol: asset_nft.profile.symbol
    });

    vec_set::insert(&mut issuance_record.issuance_names, name);
    vec_set::insert(&mut issuance_record.asset_nfts, id);

    // share_object 
    transfer::public_share_object(asset_nft)
}

/// 撤销发行的资产NFT
public entry fun revoke_assetnft(_: &AuthorCap, issuance_record: &mut IssuanceRecord, asset_nft: AssetNft, _: &mut TxContext) {
    assert!(is_changeable(&asset_nft) == true, EUnchangeable);

    vec_set::remove(&mut issuance_record.issuance_names, &asset_nft.profile.name);
    let AssetNft{
        id,
        profile: _,
        max_supply: _,
        total_supply: _,
        record,
        minting_price: _,
        rewards_amount: _,
        creator: _,
        creator_profits,
        platform_provider_profits,
        is_mintable: _,
        is_banned: _
    } = asset_nft;
    table::destroy_empty(record);
    balance::destroy_zero(creator_profits);
    balance::destroy_zero(platform_provider_profits);
    object::delete(id);
}

/// Modifies the minting price. Requires Admin Capabilities
public entry fun set_minting_price(_: &AdminCap, self: &mut AssetNft, new_minting_price: u64) {
    self.minting_price = new_minting_price
}

/// Returns the minting price currently defined in the Mint App
public fun get_minting_price(self: &AssetNft ) : u64 {
    self.minting_price
}

public entry fun set_rewards_amount(_: &AdminCap, self: &mut AssetNft, new_rewards_amount: u64) {
    self.rewards_amount = new_rewards_amount
}

public fun get_rewards_amount(self: &AssetNft): u64 {
    self.rewards_amount
}

public entry fun set_description(_: &AuthorCap, self: &mut AssetNft, description: String) {
    assert!(is_changeable(self) == true, EUnchangeable);
    self.profile.description = description;
}

public fun get_description(self: &AssetNft): &String {
    &self.profile.description
}

public entry fun set_did(_: &AdminCap, issuance_record: &mut IssuanceRecord, self: &mut AssetNft, did: String) {
    assert!(is_changeable(self) == true, EUnchangeable);
    // did不存在
    assert!(option::is_none<String>(&self.profile.did), EDIDAlreadyExists);
    assert!(!vec_set::contains(&issuance_record.issuance_names, &did), EDIDAlreadyExists);
    assert!(!string::is_empty(&did), EInvalidDID);
    self.profile.did = option::some(did);
    vec_set::insert(&mut issuance_record.issuance_names, did)
}

public fun get_did(self: &AssetNft): &Option<String> {
    &self.profile.did
}

/// 是否允许更改基础信息
fun is_changeable(self: &AssetNft): bool{
    !self.is_mintable && !self.is_banned
}

// /// 是否创作者
// fun is_creator(operator: address): bool {
//     let creator = @creator;
//     creator == operator
// }

public entry fun start_mining(_: &AdminCap, self: &mut AssetNft) {
    // 验证did
    assert!(option::is_none<String>(&self.profile.did), ENoDID);
    self.is_mintable = true
}

public entry fun stop_mining(_: &AdminCap, self: &mut AssetNft) {
    if (self.is_mintable == true) {
        self.is_mintable = false;
    };
    if (self.is_banned == false) {
        self.is_banned = true;
    };
}

/// 设置did并允许mint
public entry fun set_did_and_allow_mining(_: &AdminCap, issuance_record: &mut IssuanceRecord, self: &mut AssetNft, did: String) {
    // 没有开启mining
    assert!(is_changeable(self) == true, EUnchangeable);
    // did不存在
    assert!(option::is_none(&self.profile.did), EDIDAlreadyExists);
    // 验证did
    assert!(!string::is_empty(&did), EInvalidDID);
    assert!(!vec_set::contains(&issuance_record.issuance_names, &did), EDIDAlreadyExists);
    self.profile.did = option::some(did);
    self.is_mintable = true
}

/// 购买NFT
#[allow(lint(self_transfer))]
public entry fun mint_to_sender(
    asset_nft: &mut AssetNft,
    treasury_lock: &mut TreasuryLock,
    paid: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();

    assert!(!table::contains(&asset_nft.record, sender), EDontMintAgain);
    let nft_id = table::length(&asset_nft.record) + 1;
    assert!(nft_id <= asset_nft.max_supply, ENotEnoughSupply);

    // 支付
    handle_payment(asset_nft, paid, ctx);

    // mint
    table::add(&mut asset_nft.record, sender, nft_id);
    let nft = bassinet_nft::mint(&asset_nft.id, treasury_lock, asset_nft.profile.name, asset_nft.profile.symbol, asset_nft.profile.description, asset_nft.profile.icon_url, asset_nft.profile.did, nft_id, asset_nft.rewards_amount, sender, ctx);

    transfer::public_transfer(nft, sender)
}

/// Private function for handling coins received from mixing payments.
/// It breaks flow with an exception message if the payment coin does not cover the price
fun handle_payment(self: &mut AssetNft, paid: &mut Coin<SUI>, ctx: &mut TxContext){
    let price = self.minting_price;
    assert!(price <= coin::value(paid), EAmountIncorrect);

    let creator_price = (price * 70) / 100;
    let platform_provider_price = price - creator_price;

    let creator_payment_coin = coin::split(paid, creator_price, ctx);

    let provider_payment_coin = coin::split(paid, platform_provider_price, ctx);
    coin::put(&mut self.creator_profits, creator_payment_coin);
    coin::put(&mut self.platform_provider_profits, provider_payment_coin);
}

/// 创作者获取收益
public entry fun take_creator_profits(self: &mut AssetNft, recipient: address, ctx: &mut TxContext) {
    let coin = take_creator_profits_(self, ctx);
    transfer::public_transfer(coin, recipient);
}

/// 平台方获取收益
public entry fun take_provider_profits(self: &mut AssetNft, recipient: address, ctx: &mut TxContext) {
    let coin = take_provider_profits_(self, ctx);
    transfer::public_transfer(coin, recipient);
}

/// 创作者获取收益
public fun take_creator_profits_(self: &mut AssetNft, ctx: &mut TxContext): Coin<SUI> {
    let sender = tx_context::sender(ctx);
    let creator = @creator;
    assert!(sender == creator, ENotCreator);
    let amount = balance::value(&self.creator_profits);
    assert!(amount > 0, ENoProfits);
    // Take a transferable `Coin` from a `Balance`
    coin::take(&mut self.creator_profits, amount, ctx)
}

/// 平台方获取收益
public fun take_provider_profits_(self: &mut AssetNft, ctx: &mut TxContext): Coin<SUI> {
    let sender = tx_context::sender(ctx);
    let provider = @platform_provider;
    assert!(sender == provider, ENotPlatformProvider);
    let amount = balance::value(&self.platform_provider_profits);
    assert!(amount > 0, ENoProfits);
    // Take a transferable `Coin` from a `Balance`
    coin::take(&mut self.platform_provider_profits, amount, ctx)
}

/// 获取所有发行NFT
public fun asset_nft_ids(record: &IssuanceRecord): &vector<ID> {
    vec_set::keys(&record.asset_nfts)
}