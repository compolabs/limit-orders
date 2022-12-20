contract;
use std::{
    auth::{
        AuthError,
        msg_sender,
    },
    block::timestamp,
    call_frames::msg_asset_id,
    context::msg_amount,
    revert::require,
    storage::StorageVec,
    token::transfer_to_address,
    logging::log,
};

abi StopLoss {
    #[storage(read)]
    fn order_by_id(id: u64) -> Order;

    #[storage(read, write)]
    fn create_order(asset1: ContractId, amount1: u64);

    #[storage(read, write)]
    fn cancel_order(id: u64);

    #[storage(read, write)]
    fn fulfill_order(id: u64);
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
}

storage {
    orders: StorageMap<u64, Order> = StorageMap {},
    orders_amount: u64 = 0,
}

fn get_sender_or_throw() -> Address{
    match msg_sender().unwrap() {
        Identity::Address(addr) => addr,
        _ => revert(0),
    }
}

fn is_order_active(order: Order) -> bool{
    match order.status{
        Status::Active => true,
        _ => false,
    }
}

impl StopLoss for Contract {
    #[storage(read)]
    fn order_by_id(id: u64) -> Order {
        let order = storage.orders.get(id);
        require(id > 0 && order.id == id, "Order is not found");
        order
    }

    #[storage(read, write)]
    fn create_order(asset1: ContractId, amount1: u64) {
        let asset0 = msg_asset_id();
        let amount0 = msg_amount();
        
        require(amount0 > 0 && amount1 > 0, "Amount cannot be less then 1");

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
            owner: get_sender_or_throw(),
        };

        storage.orders_amount = order.id;
        storage.orders.insert(order.id, order);
    }

    #[storage(read, write)]
    fn cancel_order(id: u64){
        let mut order = storage.orders.get(id);

        require(id > 0 && order.id == id, "Order is not found");
        require(get_sender_or_throw() == order.owner, "Access denied");
        require(is_order_active(order), "The order isn't active");

        order.status = Status::Canceled;
        storage.orders.insert(id, order);
        transfer_to_address(order.amount0 - order.fulfilled0, order.asset0, order.owner);
    }

    #[storage(read, write)]
    fn fulfill_order(id: u64){
        let mut order = storage.orders.get(id);
        let paymentAsset = msg_asset_id();
        let paymentAmount = msg_amount();
        
        require(id > 0 && order.id == id, "Order is not found");
        require(is_order_active(order), "The order isn't active");
        require(paymentAmount > 0 && paymentAsset == order.asset1, "Invalid payment");
        
        let amount0Left = order.amount0 - order.fulfilled0;
        let amount1Left = order.amount1 - order.fulfilled1;
        let caller = get_sender_or_throw();
        
        //If paid more than amount1 - close the order and give cashback
        if(paymentAmount >= amount1Left){ 
            // Give the caller asset1 difference like cashback
            transfer_to_address(paymentAmount - amount1Left, order.asset1, caller); 
            //The caller will receive asset0 how much is left
            transfer_to_address(amount0Left, order.asset0, caller); 
            // The owner will receive asset1 how much is left
            transfer_to_address(amount1Left, order.asset1, order.owner); 

            order.fulfilled0 = order.fulfilled0 + amount0Left;
            order.fulfilled1 = order.fulfilled1 + amount1Left;
            order.status = Status::Completed; 
            storage.orders.insert(id, order);
        
        }
        //If payed less - close order partially
        else{
            let amount0 = (order.amount0 * (paymentAmount / order.amount1));
            //The owner will receive paymentAmount1
            transfer_to_address(paymentAmount, order.asset1, order.owner); 
            //The caller will receive a piece of amount0 floored to integer
            transfer_to_address(order.amount0, order.asset0, caller);
            
            order.fulfilled0 = order.fulfilled0 + amount0;
            order.fulfilled1 = order.fulfilled1 + paymentAmount;
            storage.orders.insert(id, order);
        }
    }
}
