module bassinet::bassinet_nft;

use std::string::{Self, utf8, String};
use sui::event;
use std::ascii;
use sui::url::Url;
use bassinet::bassinet_coin::TreasuryLock;
use bassinet::bassinet_coin;
use sui::package;
use sui::display;

/// Admin
public struct AdminCap has key, store { id: UID }

/// An bassinet NFT
public struct BassinetNFT has key, store {
    id: UID,
    nft_id: u64,
    // Name for the token
    name: string::String,
    symbol: ascii::String,
    // Description of the token
    description: string::String,
    // URL for the token
    url: Option<Url>,
    did: Option<String>,
    // TODO: allow custom attributes
    // 所属资产Nft
    asset_nft_id: ID
}

public struct BASSINET_NFT has drop {}

// ===== Events =====
public struct NFTMinted has copy, drop {
    // The Object ID of the NFT
    object_id: ID,
    // The creator of the NFT
    creator: address,
    // The name of the NFT
    name: String,
    did: Option<String>
}

/// init
fun init(otw: BASSINET_NFT, ctx: &mut TxContext) {
    let keys = vector[
        utf8(b"name"),
        utf8(b"description"),
        utf8(b"link"),
        utf8(b"image_url"),
        utf8(b"thumbnail_url"),
        utf8( b"project_url"),
        utf8(b"creator")
    ];

    let values = vector[
        // For `name` one can use the `BASSINET_NFT.name` property
        utf8(b"{name}"),
        utf8(b"{description}"),
        utf8(b"{did}"),
        utf8(b"{url}"),
        utf8(b"{url}"),
        utf8(b""),
        utf8(b"{asset_nft_id}")
    ];

    // Claim the `Publisher` for the package!
    let publisher = package::claim(otw, ctx);

    // Get a new `Display` object for the `BassinetNFT` type.
    let mut display = display::new_with_fields<BassinetNFT>(
        &publisher, keys, values, ctx
    );

    // Commit first version of `Display` to apply changes.
    display.update_version();

    let sender = ctx.sender();

    transfer::public_transfer(publisher, sender);
    transfer::public_transfer(display, sender);

    let provider_admin_cap = AdminCap {
        id: object::new(ctx)
    };
    // transfer::public_transfer(provider_admin_cap, provider_address);
    transfer::public_transfer(provider_admin_cap, sender)
}

// ===== Public view functions =====

public fun nft_id(nft: &BassinetNFT): u64 {
    nft.nft_id
}

/// Get the NFT's `name`
public fun name(nft: &BassinetNFT): &string::String {
    &nft.name
}

public fun symbol(nft: &BassinetNFT): &ascii::String {
    &nft.symbol
}

/// Get the NFT's `description`
public fun description(nft: &BassinetNFT): &string::String {
    &nft.description
}

/// Get the NFT's `url`
public fun url(nft: &BassinetNFT): &Option<Url> {
    &nft.url
}

public fun did(nft: &BassinetNFT): &Option<String> {
    &nft.did
}

/// Get the NFT's asset_nft_id
public fun asset_nft_id(nft: &BassinetNFT): &ID {
    &nft.asset_nft_id
}

/// TODO 参考kiosk，交易时要收费
/// Transfer `nft` to `recipient`
public entry fun transfer(nft: BassinetNFT, recipient: address, _: &mut TxContext) {
    transfer::public_transfer(nft, recipient)
}

/// Permanently delete `nft`
public entry fun burn(nft: BassinetNFT, _: &mut TxContext) {
    // 不需要回收Mint记录
    let BassinetNFT { id, nft_id: _, name: _, symbol: _, description: _, url: _, did: _, asset_nft_id : _} = nft;
    object::delete(id)
}

/// mint NFT
public(package) fun mint(
    asset: &UID,
    treasury_lock: &mut TreasuryLock,
    name: String,
    symbol: ascii::String,
    description: String,
    icon_url: Option<Url>,
    did: Option<String>,
    nft_id: u64,
    rewards_amount: u64,
    recipient: address,
    ctx: &mut TxContext): BassinetNFT {

    let nft = BassinetNFT {
        id: object::new(ctx),
        nft_id: nft_id,
        name: name,
        symbol: symbol,
        description: description,
        url: icon_url,
        did: did,
        asset_nft_id: object::uid_to_inner(asset)
    };

    // 激励
    bassinet_coin::mint(treasury_lock, rewards_amount, recipient, ctx);

    event::emit(NFTMinted {
        object_id: object::id(&nft),
        creator: recipient,
        name: nft.name,
        did: nft.did
    });

    nft
}