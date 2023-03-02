use fuels::prelude::abigen;
use fuels::{
    prelude::{Contract, StorageConfiguration, TxParameters},
    signers::WalletUnlocked,
};

abigen!(Contract(
    name = "LimitOrdersContract",
    abi = "out/debug/limit_orders-abi.json"
),);

pub async fn deploy_limit_orders_contract(admin: &WalletUnlocked) -> LimitOrdersContract {
    let id = Contract::deploy(
        "./out/debug/limit_orders.bin",
        &admin,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/limit_orders-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    LimitOrdersContract::new(id, admin.clone())
}

pub mod limit_orders_abi_calls {

    use fuels::{
        prelude::{CallParameters, BASE_ASSET_ID},
        programs::call_response::FuelCallResponse,
        types::ContractId,
    };

    use super::*;

    // pub async fn get_deposit_by_address(contract: &LimitOrdersContract, address: Address) -> u64 {
    //     contract
    //         .methods()
    //         .get_deposit_by_address(address)
    //         .simulate()
    //         .await
    //         .unwrap()
    //         .value
    // }

    // pub async fn orders_amount(contract: &LimitOrdersContract) -> u64 {
    //     contract
    //         .methods()
    //         .orders_amount()
    //         .simulate()
    //         .await
    //         .unwrap()
    //         .value
    // }

    pub async fn order_by_id(
        contract: &LimitOrdersContract,
        id: u64,
    ) -> Result<FuelCallResponse<Order>, fuels::prelude::Error> {
        contract.methods().order_by_id(id).simulate().await
    }

    pub async fn deposit(
        contract: &LimitOrdersContract,
        amount: u64,
    ) -> Result<FuelCallResponse<()>, fuels::prelude::Error> {
        let call_params = CallParameters::new(Some(amount), Some(BASE_ASSET_ID), None);
        let tx_params = TxParameters::new(Some(100), Some(100_000_000), Some(0));
        contract
            .methods()
            .deposit()
            .call_params(call_params)
            .unwrap()
            .tx_params(tx_params)
            // .append_variable_outputs(1)
            .call()
            .await
    }
    // pub async fn withdraw(
    //     contract: &LimitOrdersContract,
    //     amount: u64,
    // ) -> Result<FuelCallResponse<()>, fuels::prelude::Error> {
    //     let tx_params = TxParameters::new(Some(100), Some(100_000_000), Some(0));
    //     contract
    //         .methods()
    //         .withdraw(amount)
    //         .tx_params(tx_params)
    //         // .append_variable_outputs(1)
    //         .call()
    //         .await
    // }

    pub struct CreatreOrderArguments {
        pub asset0: fuels::tx::AssetId,
        pub amount0: u64,
        pub asset1: ContractId,
        pub amount1: u64,
        pub matcher_fee: u64,
    }

    pub async fn create_order(
        contract: &LimitOrdersContract,
        args: &CreatreOrderArguments,
    ) -> Result<FuelCallResponse<u64>, fuels::prelude::Error> {
        let call_params = CallParameters::new(Some(args.amount0), Some(args.asset0), None);
        let tx_params = TxParameters::new(Some(100), Some(100_000_000), Some(0));
        contract
            .methods()
            .create_order(args.asset1, args.amount1, args.matcher_fee)
            .tx_params(tx_params)
            .call_params(call_params)
            .unwrap()
            .append_variable_outputs(1)
            .call()
            .await
    }

    pub async fn cancel_order(
        contract: &LimitOrdersContract,
        id: u64,
    ) -> Result<FuelCallResponse<()>, fuels::prelude::Error> {
        let tx_params = TxParameters::new(Some(100), Some(100_000_000), Some(0));
        contract
            .methods()
            .cancel_order(id)
            .tx_params(tx_params)
            .append_variable_outputs(1)
            .call()
            .await
    }

    pub struct FulfillOrderArguments {
        pub id: u64,
        pub amount1: u64,
        pub asset1: fuels::tx::AssetId,
    }

    pub async fn fulfill_order(
        contract: &LimitOrdersContract,
        args: &FulfillOrderArguments,
    ) -> Result<FuelCallResponse<()>, fuels::prelude::Error> {
        let call_params = CallParameters::new(Some(args.amount1), Some(args.asset1), None);
        let tx_params = TxParameters::new(Some(100), Some(100_000_000), Some(0));
        contract
            .methods()
            .fulfill_order(args.id)
            .tx_params(tx_params)
            .call_params(call_params)
            .unwrap()
            .append_variable_outputs(2)
            .append_variable_outputs(1)
            .call()
            .await
    }
    pub async fn match_orders(
        contract: &LimitOrdersContract,
        order_id_a: u64,
        order_id_b: u64,
    ) -> Result<FuelCallResponse<()>, fuels::prelude::Error> {
        let tx_params = TxParameters::new(Some(100), Some(100_000_000), Some(0));
        contract
            .methods()
            .match_orders(order_id_a, order_id_b)
            .tx_params(tx_params)
            .append_variable_outputs(4)
            .append_message_outputs(4)
            .call()
            .await
    }
}
