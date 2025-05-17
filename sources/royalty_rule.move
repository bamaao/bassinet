module bassinet::royalty_rule;

use bassinet::bassinet_nft::BassinetNFT;
use sui::sui::SUI;
use sui::coin::{Self, Coin};
use sui::transfer_policy::{
    Self as policy,
    TransferPolicy,
    TransferPolicyCap,
    TransferRequest
};

/// The `amount_bp` passed is more than 100%.
const EIncorrectArgument: u64 = 0;
/// The `Coin` used for payment is not enough to cover the fee.
const EInsufficientAmount: u64 = 1;

/// Max value for the `amount_bp`.
const MAX_BPS: u16 = 10_000;

/// The "Rule" witness to authorize the policy.
public struct Rule has drop {}

/// Configuration for the Rule. The `amount_bp` is the percentage
/// of the transfer amount to be paid as a royalty fee. The `min_amount`
/// is the minimum amount to be paid if the percentage based fee is
/// lower than the `min_amount` setting.
public struct Config has store, drop {
    amount_bp: u16,
    min_amount: u64
}

/// Creator action: Add the Royalty Rule for the `T`.
public fun add(
    policy: &mut TransferPolicy<BassinetNFT>,
    cap: &TransferPolicyCap<BassinetNFT>,
    amount_bp: u16,
    min_amount: u64
) {
    assert!(amount_bp <= MAX_BPS, EIncorrectArgument);
    policy::add_rule(Rule {}, policy, cap, Config { amount_bp, min_amount })
}

/// Buyer action: Pay the royalty fee for the transfer.
public fun pay(
    policy: &mut TransferPolicy<BassinetNFT>,
    request: &mut TransferRequest<BassinetNFT>,
    payment: Coin<SUI>
) {
    let paid = policy::paid(request);
    let amount = fee_amount(policy, paid);

    assert!(coin::value(&payment) == amount, EInsufficientAmount);

    policy::add_to_balance(Rule {}, policy, payment);
    policy::add_receipt(Rule {}, request)
}

public fun fee_amount(policy: &TransferPolicy<BassinetNFT>, paid: u64): u64 {
    let config: &Config = policy::get_rule(Rule {}, policy);
    let mut amount = (((paid as u128) * (config.amount_bp as u128) / 10_000) as u64);

    if (amount < config.min_amount) {
        amount = config.min_amount
    };

    amount
}