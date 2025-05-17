module bassinet::bassinet_nft;

use std::string::{Self, utf8, String};
use sui::coin::{Self, Coin};
use sui::event;
use sui::url::{Url};
use bassinet_coin::bassinet_coin::TreasuryLock;
use sui::package;
use sui::display;
use sui::sui::SUI;
use std::type_name::{Self};
use sui::balance::{Self, Balance};
use sui::transfer_policy::{Self};
use bassinet_coin::bassinet_coin::{Self, AdminCap, BASSINET_COIN};

const EMintCaplimited: u64 = 0;
const EAmountIncorrect: u64 = 1;
const EMintNotStarted: u64 = 2;
const EMintStarted: u64 = 3;
const EMintNotAuthorized: u64 = 4;
const ENoProfits: u64 = 5;

/// An bassinet NFT
public struct BassinetNFT has key, store {
    id: UID,
    nft_id: u64,
    name: std::string::String,
    description: std::string::String,
    collection_url: Url,
    owner: address
}

public struct Mint has key, store {
    id: UID,
    /// The fee that user has to pay for minting. Can be changed through method that requires admin capability
    minting_price: u64,
    /// 限制
    limit: u64,
    /// 统计mint次数
    minting_counter: u64,
    /// Mint记录
    /// record: Table<address, u64>,
    creator: address,
    platform_provider: address,
    /// The profits
    creator_profits: Balance<SUI>,
    platform_profits: Balance<SUI>,
    /// 基本信息
    description: Option<std::string::String>,
    collection_url: Option<Url>,
    collection_id: Option<std::string::String>,
    is_mintable: bool
}

public struct BASSINET_NFT has drop {}

// ===== Events =====
public struct BassinetNFTCreated has copy, drop {
    mint_id: ID,
    creator: address
}

public struct NFTMinted has copy, drop {
    // The Object ID of the NFT
    object_id: ID,
    // The creator of the NFT
    creator: address,
    name:  std::string::String,
    description:  std::string::String,
    ntf_type:  std::ascii::String,
    collection_id: std::string::String,
    collection_url:  std::ascii::String
}

#[allow(lint(share_owned, self_transfer))]
/// init
fun init(otw: BASSINET_NFT, ctx: &mut TxContext) {
    let keys = vector[
        utf8(b"name"),
        utf8(b"description"),
        utf8(b"image_url"),
        utf8(b"thumbnail_url"),
        utf8(b"project_url")
    ];

    let values = vector[
        utf8(b"{name}"),
        utf8(b"{description}"),
        utf8(b"{collection_url}/image"),
        utf8(b"{collection_url}/thumbnail"),
        utf8(b"{collection_url}")
    ];

    // Claim the `Publisher` for the package!
    let publisher = package::claim(otw, ctx);

    // Get a new `Display` object for the `BassinetNFT` type.
    let mut display = display::new_with_fields<BassinetNFT>(&publisher, keys, values, ctx);

    // Commit first version of `Display` to apply changes.
    display.update_version();

    let sender = ctx.sender();

    let id = object::new(ctx);
    let mint_id = id.to_inner();
    // 初始化
    let mint = Mint {
        id: id,
        minting_price: 0,
        limit: 0,
        minting_counter: 0,
        // record: table::new<address, u64>(ctx),
        creator: @creator,
        platform_provider: @platform_provider,
        // The profits
        creator_profits: balance::zero<SUI>(),
        platform_profits: balance::zero<SUI>(),
        // 基本信息
        description: option::none(),
        collection_url: option::none(),
        collection_id: option::none(),
        is_mintable: false
    };
    // 发布事件
    event::emit(BassinetNFTCreated{ mint_id: mint_id, creator: @creator });

    let (policy, policy_cap) = transfer_policy::new<BassinetNFT>(&publisher, ctx);
    transfer::public_share_object(policy);
    transfer::public_transfer(policy_cap, sender);

    transfer::public_transfer(publisher, sender);
    transfer::public_transfer(display, sender);
    
    transfer::public_share_object(mint)
}

/// 筹造NFT
public fun mint(
    self: &mut Mint,
    lock: &mut TreasuryLock,
    paid: &mut Coin<SUI>,
    name: String,
    ctx: &mut TxContext): (BassinetNFT, Coin<BASSINET_COIN>) {
    assert!(self.is_mintable == true, EMintNotStarted);
    assert!(bassinet_coin::is_authorized<BassinetNFT>(&self.id), EMintNotAuthorized);
    assert!(self.minting_counter < self.limit, EMintCaplimited);

    handle_payment(self, paid, ctx);

    let sender = ctx.sender();

    let collection_url = *self.collection_url.borrow();
    let nft = BassinetNFT {
        id: object::new(ctx),
        nft_id: self.minting_counter + 1,
        name: name,
        description: *self.description.borrow(),
        collection_url: collection_url,
        owner: sender
    };
    
    // 激励
    let rewards_coin = bassinet_coin::mint<BassinetNFT>(&mut self.id, lock, ctx);
    
    self.minting_counter = self.minting_counter + 1;

    event::emit(NFTMinted {
        object_id: object::id(&nft),
        creator: sender,
        name: nft.name,
        description: *self.description.borrow(),
        ntf_type: type_name::into_string(type_name::get<BassinetNFT>()),
        collection_id: *self.collection_id.borrow(),
        collection_url: collection_url.inner_url()
    });

    (nft, rewards_coin)
}

fun handle_payment(self: &mut Mint, paid: &mut Coin<SUI>, ctx: &mut TxContext) {
    let price = self.minting_price;
    assert!(price <= coin::value(paid), EAmountIncorrect);

    let creator = ((((price as u128) * (70 as u128)) / 100) as u64);
    let platform_provider = price - creator;

    let creator_coin = coin::split(paid, creator, ctx);
    coin::put(&mut self.creator_profits, creator_coin);

    let platform_coin = coin::split(paid, platform_provider, ctx);
    coin::put(&mut self.platform_profits, platform_coin);
}

/// 配置并授权
public fun authorize_(
    admin_cap: &AdminCap,
    self: &mut Mint,
    app_name: string::String,
    description: vector<u8>,
    collection_id: vector<u8>,
    collection_url: vector<u8>,
    limit: u64,
    rewards_quantity: u64,
    minting_price: u64
) {
    assert!(self.is_mintable == false, EMintStarted);
    let url = sui::url::new_unsafe_from_bytes(collection_url);
    self.limit = limit;
    self.minting_price = minting_price;
    self.description.fill(utf8(description));
    self.collection_id.fill(utf8(collection_id));
    self.collection_url.fill(url);
    self.is_mintable = true;

    // 激励限制为20% * limit
    let minting_limit = ((((limit as u128) * (20 as u128)) / 100) as u64);
    
    bassinet_coin::authorize_app<BassinetNFT>(
        admin_cap,
        &mut self.id,
        app_name,
        rewards_quantity,
        minting_limit
    )
}

/// 解除授权
public fun deauthorize_(admin_cap: &AdminCap, self: &mut Mint) {
    bassinet_coin::revoke_auth<BassinetNFT>(admin_cap, &mut self.id)
}

/// 更改筹造价格
public fun change_minting_price_(
    _: &AdminCap,
    self: &mut Mint,
    price: u64,
    _: &mut TxContext) {
    self.minting_price = price;
}

/// 更改owner
public fun change_owner_(
    self: &mut BassinetNFT,
    ctx: &mut TxContext) {
    self.owner = ctx.sender();
}

public fun is_mintable(self: &Mint): bool {
    self.is_mintable
}

public fun collection_id(self: &Mint): &Option<std::string::String> {
    &self.collection_id
}

// ===== Public view functions =====

public fun nft_id(nft: &BassinetNFT): u64 {
    nft.nft_id
}

/// Get the NFT's `name`
public fun name(nft: &BassinetNFT): &std::string::String {
    &nft.name
}

/// Get the NFT's `description`
public fun description(nft: &BassinetNFT): &std::string::String {
    &nft.description
}

/// Get the NFT's `url`
public fun url(nft: &BassinetNFT): &sui::url::Url {
    &nft.collection_url
}

public fun owner(nft: &BassinetNFT): address {
    nft.owner
}

// ===== Profits =====

/// 领取激励
public fun take_profits(self: &mut Mint, ctx: &mut TxContext): Coin<SUI> {
    let sender = ctx.sender();
    if (is_creator(self, sender)) {
        return take_creator_profits(self, ctx)
    }else if (is_platform_provider(self, sender)) {
        return take_provider_profits(self, ctx)
    };
    coin::zero<SUI>(ctx)
}

/// 领取创作者激励
fun take_creator_profits(self: &mut Mint, ctx: &mut TxContext): Coin<SUI> {
    let amount = balance::value(&self.creator_profits);
    assert!(amount > 0, ENoProfits);
    // Take a transferable `Coin` from a `Balance`
    coin::take(&mut self.creator_profits, amount, ctx)
}

/// 领取平台激励
fun take_provider_profits(self: &mut Mint, ctx: &mut TxContext): Coin<SUI> {
    let amount = balance::value(&self.platform_profits);
    assert!(amount > 0, ENoProfits);
    // Take a transferable `Coin` from a `Balance`
    coin::take(&mut self.platform_profits, amount, ctx)
}

/// 是否平台方
fun is_platform_provider(self: &Mint, operator_address: address): bool {
    self.platform_provider == operator_address
}

/// 是否创作者
fun is_creator(self: &Mint, operator_address: address): bool {
    self.creator == operator_address
}
