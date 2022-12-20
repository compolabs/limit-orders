use fuels::prelude::*;

use crate::utils::number_utils::parse_units;

abigen!(LimitOrdersContract, "out/debug/limit_orders-abi.json");
abigen!(UsdtContract, "tests/artefacts/usdt/token_contract-abi.json");
abigen!(UsdcContract, "tests/artefacts/usdc/token_contract-abi.json");

pub async fn init_wallet() -> WalletUnlocked {
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(1),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await;
    wallets.pop().unwrap()
}

pub async fn init_tokens(wallet: &WalletUnlocked) -> (UsdtContract, UsdcContract){
    let usdt_instance = get_usdt_token_contract_instance(wallet).await;
    let usdt_methods = usdt_instance.methods();

    let usdt_decimals = usdt_methods.decimals().simulate().await.unwrap().value;
    let mint_amount = parse_units(10000, usdt_decimals);

    let _res = usdt_methods.initialize(mint_amount, Address::from(wallet.address())).call().await;
    let _res = usdt_methods.mint().append_variable_outputs(1).call().await;


    let usdc_instance = get_usdc_token_contract_instance(wallet).await;
    let usdc_methods = usdc_instance.methods();

    let usdc_decimals = usdc_methods.decimals().simulate().await.unwrap().value;
    let mint_amount = parse_units(10000, usdc_decimals);

    let _res = usdc_methods.initialize(mint_amount, Address::from(wallet.address())).call().await;
    let _res = usdc_methods.mint().append_variable_outputs(1).call().await;

    (usdt_instance, usdc_instance)
}

pub async fn get_limit_orders_contract_instance(wallet: &WalletUnlocked) -> LimitOrdersContract{
    let id = Contract::deploy(
        "./out/debug/limit_orders.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./out/debug/limit_orders-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    LimitOrdersContract::new(id, wallet.clone())
}

pub async fn get_usdt_token_contract_instance(wallet: &WalletUnlocked) -> UsdtContract{
    let id = Contract::deploy(
        "./tests/artefacts/usdt/token_contract.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./tests/artefacts/usdt/token_contract-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    UsdtContract::new(id, wallet.clone())
}

pub async fn get_usdc_token_contract_instance(wallet: &WalletUnlocked) -> UsdcContract{
    let id = Contract::deploy(
        "./tests/artefacts/usdc/token_contract.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::with_storage_path(Some(
            "./tests/artefacts/usdc/token_contract-storage_slots.json".to_string(),
        )),
    )
    .await
    .unwrap();

    UsdcContract::new(id, wallet.clone())
}

pub async fn print_balances(wallet: &WalletUnlocked) {
    let balances = wallet.get_balances().await.unwrap();
    println!("{:#?}\n", balances);
}