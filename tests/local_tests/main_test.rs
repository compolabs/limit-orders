use fuels::prelude::{CallParameters, BASE_ASSET_ID, TxParameters};
use fuels::tx::{Address, AssetId, ContractId};

use crate::utils::local_tests_utils::*;
use crate::utils::number_utils::*;

#[tokio::test]
async fn main_test() {
    //--------------- WALLET ---------------
    let wallet = init_wallet().await;
    let address = Address::from(wallet.address());
    println!("Wallet address {address}\n");

    //--------------- TOKENS ---------------
    let (usdt_instance, usdc_instance) = init_tokens(&wallet).await;

    let usdt_methods = usdt_instance.methods();
    let usdt_asset_id = AssetId::from(*usdt_instance.get_contract_id().hash());
    let usdt_symbol = usdt_methods.symbol().simulate().await.unwrap().value;
    let usdt_decimals = usdt_methods.decimals().simulate().await.unwrap().value;

    let usdc_methods = usdc_instance.methods();
    let usdc_asset_id = AssetId::from(*usdc_instance.get_contract_id().hash());
    let usdc_symbol = usdc_methods.symbol().simulate().await.unwrap().value;
    let usdc_decimals = usdc_methods.decimals().simulate().await.unwrap().value;

    println!("Asset1\n id: {usdt_asset_id}\n symbol {usdt_symbol}\n decimals {usdt_decimals}\n");
    println!("Asset2\n id: {usdt_asset_id}\n symbol {usdc_symbol}\n decimals {usdt_decimals}\n");

    print_balances(&wallet).await;

    //--------------- LIMIT ORDERS ---------

    let limit_orders_instance = get_limit_orders_contract_instance(&wallet).await;
    let dapp_methods = limit_orders_instance.methods();

    assert!(dapp_methods.order_by_id(2).simulate().await.is_err());
    println!(
        "Balance {} ETH",
        wallet.get_asset_balance(&BASE_ASSET_ID).await.unwrap()
    );
    let _res = dapp_methods
        .create_order(
            ContractId::from(usdc_instance.get_contract_id()),
            parse_units(10, usdc_decimals),
        )
        .call_params(CallParameters::new(
            Some(parse_units(10, usdt_decimals)),
            Some(usdt_asset_id),
            None,
        ))
        .tx_params(TxParameters::new(Some(100), Some(100_000_000), Some(0)))
        .append_variable_outputs(1)
        .call()
        .await;
    println!("Gas used = {:?}", _res.unwrap().gas_used);
    println!(
        "Balance {} ETH",
        wallet.get_asset_balance(&BASE_ASSET_ID).await.unwrap()
    );
    return;
    println!("\n{} Create Order", if _res.is_ok() { "✅" } else { "❌" });

    let balance = wallet.get_asset_balance(&usdt_asset_id).await.unwrap();
    println!(
        "USDT balance: {} {usdt_symbol}",
        format_units(balance, usdt_decimals)
    );

    let order = dapp_methods.order_by_id(1).simulate().await.unwrap().value;
    println!("{:#?}", order);

    let _res = dapp_methods
        .cancel_order(order.id)
        .append_variable_outputs(1)
        .call()
        .await;
    println!("\n{} Cancel Order", if _res.is_ok() { "✅" } else { "❌" });

    let order = dapp_methods.order_by_id(1).simulate().await.unwrap().value;
    println!("{:#?}", order);

    let balance = wallet.get_asset_balance(&usdt_asset_id).await.unwrap();
    println!(
        "USDT balance: {} {usdt_symbol}",
        format_units(balance, usdt_decimals)
    );

    let _res = dapp_methods
        .create_order(
            ContractId::from(usdc_instance.get_contract_id()),
            parse_units(10, usdc_decimals),
        )
        .call_params(CallParameters::new(
            Some(parse_units(10, usdt_decimals)),
            Some(usdt_asset_id),
            None,
        ))
        .append_variable_outputs(1)
        .call()
        .await;
    println!("\n{} Create Order", if _res.is_ok() { "✅" } else { "❌" });

    let order = dapp_methods.order_by_id(2).simulate().await.unwrap().value;
    println!("{:#?}", order);

    let _res = dapp_methods
        .fulfill_order(2)
        .call_params(CallParameters::new(
            Some(parse_units(10, usdc_decimals)),
            Some(usdc_asset_id),
            None,
        ))
        .append_message_outputs(2)
        .append_variable_outputs(2)
        .call()
        .await;
    println!("\n{} Fulfill Order", if _res.is_ok() { "✅" } else { "❌" });

    let order = dapp_methods.order_by_id(2).simulate().await.unwrap().value;
    println!("{:#?}", order);
}
