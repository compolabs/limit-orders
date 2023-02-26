contract;

use std::{
    auth::{
        AuthError,
        msg_sender,
    },
    block::timestamp,
    call_frames::msg_asset_id,
    constants::BASE_ASSET_ID,
    context::msg_amount,
    logging::log,
    revert::require,
    storage::StorageVec,
    token::transfer_to_address,
};

abi LimitOrders {
    #[storage(read)]
    fn get_deposit_by_address(address: Address) -> u64;

    #[storage(read, write)]
    fn deposit();

    #[storage(read, write)]
    fn withdraw(amount: u64);

    #[storage(read)]
    fn orders_amount() -> u64;

    #[storage(read)]
    fn order_by_id(id: u64) -> Order;

    #[storage(read, write)]
    fn create_order(asset1: ContractId, amount1: u64, matcher_fee: u64);

    #[storage(read, write)]
    fn cancel_order(id: u64);

    #[storage(read, write)]
    fn fulfill_order(id: u64);
    #[storage(read, write)]
    fn match_orders(order_id_a: u64, order_id_b: u64);
}

enum Status {
    Active: (),
    Canceled: (),
    Completed: (),
}

pub struct Order {
    asset0: ContractId,
    amount0: u64,
    asset1: ContractId,
    amount1: u64,
    status: Status,
    fulfilled0: u64,
    fulfilled1: u64,
    owner: Address,
    id: u64,
    timestamp: u64,
    matcher_fee: u64,
    matcher_fee_used: u64,
}

storage {
    orders: StorageMap<u64, Order> = StorageMap {},
    orders_amount: u64 = 0,
    deposits: StorageMap<Address, u64> = StorageMap {},
}

fn get_sender_or_throw() -> Address {
    match msg_sender().unwrap() {
        Identity::Address(addr) => addr,
        _ => revert(0),
    }
}

fn is_order_active(order: Order) -> bool {
    match order.status {
        Status::Active => true,
        _ => false,
    }
}

impl LimitOrders for Contract {
    #[storage(read)]
    fn get_deposit_by_address(address: Address) -> u64 {
        storage.deposits.get(address)
    }

    #[storage(read, write)]
    fn deposit() {
        let amount = msg_amount();
        let caller = get_sender_or_throw();
        require(amount > 0 && msg_asset_id() == BASE_ASSET_ID, "Invalid payment");
        let deposit = storage.deposits.get(caller);
        storage.deposits.insert(caller, deposit + amount);
    }

    #[storage(read, write)]
    fn withdraw(amount: u64) {
        let caller = get_sender_or_throw();
        let deposit = storage.deposits.get(caller);
        require(amount <= deposit, "Insufficient funds");
        storage.deposits.insert(caller, deposit - amount);
        transfer_to_address(deposit - amount, BASE_ASSET_ID, caller);
    }

    #[storage(read)]
    fn orders_amount() -> u64 {
        storage.orders_amount
    }

    #[storage(read)]
    fn order_by_id(id: u64) -> Order {
        let order = storage.orders.get(id);
        require(id > 0 && order.id == id, "Order is not found");
        order
    }

    #[storage(read, write)]
    fn create_order(asset1: ContractId, amount1: u64, matcher_fee: u64) {
        let asset0 = msg_asset_id();
        let amount0 = msg_amount();
        let caller = get_sender_or_throw();
        let deposit = storage.deposits.get(caller);
        require(amount0 > 0 && amount1 > 0, "Amount cannot be less then 1");
        require(deposit >= matcher_fee, "Not enough deposit");

        let order = Order {
            asset0,
            amount0,
            asset1,
            amount1,
            fulfilled0: 0,
            fulfilled1: 0,
            status: Status::Active,
            id: storage.orders_amount + 1,
            timestamp: timestamp(),
            owner: caller,
            matcher_fee,
            matcher_fee_used: 0,
        };

        storage.orders_amount = order.id;
        storage.orders.insert(order.id, order);
        storage.deposits.insert(caller, deposit - matcher_fee);
    }

    #[storage(read, write)]
    fn cancel_order(id: u64) {
        let mut order = storage.orders.get(id);
        let deposit = storage.deposits.get(order.owner);
        require(id > 0 && order.id == id, "Order is not found");
        require(get_sender_or_throw() == order.owner, "Access denied");
        require(is_order_active(order), "The order isn't active");

        order.status = Status::Canceled;
        storage.orders.insert(id, order);
        storage.deposits.insert(order.owner, deposit + order.matcher_fee - order.matcher_fee_used);
        transfer_to_address(order.amount0 - order.fulfilled0, order.asset0, order.owner);
    }

    #[storage(read, write)]
    fn fulfill_order(id: u64) {
        let mut order = storage.orders.get(id);
        let payment_asset = msg_asset_id();
        let payment_amount = msg_amount();

        require(id > 0 && order.id == id, "Order is not found");
        require(is_order_active(order), "The order isn't active");
        require(payment_amount > 0 && payment_asset == order.asset1, "Invalid payment");

        let amount0_left = order.amount0 - order.fulfilled0;
        let amount1_left = order.amount1 - order.fulfilled1;
        let caller = get_sender_or_throw();

                //If paid more than amount1 - close the order and give cashback
        if (payment_amount >= amount1_left) { 
            // Give the caller asset1 difference like cashback
            transfer_to_address(payment_amount - amount1_left, order.asset1, caller); 
            //The caller will receive asset0 how much is left
            transfer_to_address(amount0_left, order.asset0, caller); 
            // The owner will receive asset1 how much is left
            transfer_to_address(amount1_left, order.asset1, order.owner);
            order.fulfilled0 = order.fulfilled0 + amount0_left;
            order.fulfilled1 = order.fulfilled1 + amount1_left;
            order.status = Status::Completed;
            storage.orders.insert(id, order);

            let deposit = storage.deposits.get(order.owner);
            storage.deposits.insert(order.owner, deposit + order.matcher_fee - order.matcher_fee_used);
        }
        //If payed less - close order partially
        else {
            let amount0 = (order.amount0 * (payment_amount / order.amount1));
            //The owner will receive payment_amount1
            transfer_to_address(payment_amount, order.asset1, order.owner); 
            //The caller will receive a piece of amount0 floored to integer
            transfer_to_address(order.amount0, order.asset0, caller);

            order.fulfilled0 = order.fulfilled0 + amount0;
            order.fulfilled1 = order.fulfilled1 + payment_amount;
            storage.orders.insert(id, order);
        }
    }

    #[storage(read, write)]
    //TODO orders_ids_a: u64[], orders_ids_b: u64[]
    fn match_orders(order_id_a: u64, order_id_b: u64) {
        let matcher = get_sender_or_throw();
        let order_a = storage.orders.get(order_id_a);
        let order_b = storage.orders.get(order_id_b);
        require(order_id_a > 0 && order_a.id == order_id_a, "Order a is not found");
        require(order_id_b > 0 && order_b.id == order_id_b, "Order b is not found");
        require(order_a.asset0 == order_b.asset1 && order_a.asset1 == order_b.asset0, "Orders don't match");

        let price_a = order_a.amount1 / order_a.amount0;
        let price_b = order_b.amount0 / order_b.amount1;
        let (mut order0, mut order1) = if price_a <= price_b {
            (order_a, order_b)
        } else {
            (order_b, order_a)
        };

        let order0_amount0_left = order0.amount0 - order0.fulfilled0;
        let order0_amount1_left = order0.amount1 - order0.fulfilled1;
        let order0_matcher_fee_left = order0.matcher_fee - order0.matcher_fee_used;

        let order1_amount0_left = order1.amount0 - order1.fulfilled0;
        let order1_amount1_left = order1.amount1 - order1.fulfilled1;
        let order1_matcher_fee_left = order1.matcher_fee - order1.matcher_fee_used;

        if order0_amount0_left >= order1_amount1_left {   
        // Transfer order1_amount1 from order0 to order1
            order0.fulfilled0 += order1_amount1_left;
            order1.fulfilled1 += order1_amount1_left;
            transfer_to_address(order1_amount1_left, order1.asset1, order1.owner);
            order1.status = Status::Completed;
        // Transfer order0_fulfill_percent * order0_amount1 / 100 from order1 to order0
            let order0_fulfill_percent = order1_amount1_left * 100 / order0_amount0_left;
            let order0_fulfill_amount = order0_fulfill_percent * order0_amount1_left / 100;
            order1.fulfilled0 += order0_fulfill_amount;
            order0.fulfilled1 += order0_fulfill_amount;
            transfer_to_address(order0_fulfill_amount, order0.asset1, order0.owner);
            if order0_fulfill_percent == 100 {
                order0.status = Status::Completed;
            }

        // Transfer order1_amount0 - order0_fulfill_percent * order0_amount1 / 100 from order1 to matcher 
            let matcher_reward_amount = order1_amount0_left - order0_fulfill_amount;
            if matcher_reward_amount > 0 {
                transfer_to_address(matcher_reward_amount, order1.asset0, matcher);
            }
        // Mathcer fee
            let order0_matcher_fee = order0_matcher_fee_left * order0_fulfill_percent;
            order0.matcher_fee_used += order0_matcher_fee;
            let order1_matcher_fee = order1.matcher_fee - order1.matcher_fee_used;
            order1.matcher_fee_used += order1_matcher_fee;
            transfer_to_address(order0_matcher_fee + order1_matcher_fee, BASE_ASSET_ID, matcher);
        } else {
        // Transfer order0_amount0 from order0 to order1
            order0.fulfilled0 += order0_amount0_left;
            order1.fulfilled1 += order0_amount0_left;
            transfer_to_address(order0_amount0_left, order0.asset0, order1.owner);
        // Transfer order0_amount1 from order1 to order0
            order0.fulfilled1 += order0_amount1_left;
            order1.fulfilled0 += order0_amount1_left;
            transfer_to_address(order0_amount1_left, order0.asset1, order0.owner);
            order0.status = Status::Completed;
        // Transfer order1_amount0 * order1_fulfill_percent - order0_amount1 (a: 0.01 BTC, b: 0 BTC) from order1 to matcher 
            let order1_fulfill_percent = order0_amount0_left / order1_amount1_left * 100;
            let matcher_reward_amount = order1_amount0_left * order1_fulfill_percent - order0_amount1_left;
            if matcher_reward_amount > 0 {
                transfer_to_address(matcher_reward_amount, order1.asset0, matcher);
            }
        // Matcher fee
            let order0_matcher_fee = order0.matcher_fee - order0.matcher_fee_used;
            order0.matcher_fee_used += order0_matcher_fee;
            let order1_matcher_fee = order1_matcher_fee_left * order1_fulfill_percent;
            order1.matcher_fee_used += order1_matcher_fee;
            transfer_to_address(order0_matcher_fee + order1_matcher_fee, BASE_ASSET_ID, matcher);
        }
        storage.orders.insert(order0.id, order0);
        storage.orders.insert(order1.id, order1);
    }
}
