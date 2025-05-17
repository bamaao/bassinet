module bassinet::floor_price_rule;

use sui::transfer_policy::{
    Self as policy,
    TransferPolicy,
    TransferPolicyCap,
    TransferRequest
};

use bassinet::bassinet_nft::BassinetNFT;

/// The price was lower than the floor price.
const EPriceTooSmall: u64 = 0;

/// The "Rule" witness to authorize the policy.
public struct Rule has drop {}

/// minimum price
public struct Config has store, drop {
    floor_price: u64
}

/// Creator action: Add the Floor Price Rule for the `T`.
public fun add(
    policy: &mut TransferPolicy<BassinetNFT>,
    cap: &TransferPolicyCap<BassinetNFT>,
    floor_price: u64
) {
    policy::add_rule(Rule {}, policy, cap, Config { floor_price })
}

/// Buyer action: Prove that the amount is higher or equal to the floor_price.
public fun prove(
    policy: &mut TransferPolicy<BassinetNFT>,
    request: &mut TransferRequest<BassinetNFT>
) {
    let config: &Config = policy::get_rule(Rule {}, policy);

    assert!(policy::paid(request) >= config.floor_price, EPriceTooSmall);

    policy::add_receipt(Rule {}, request)
}
