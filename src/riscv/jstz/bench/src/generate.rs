// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use base64::{engine::general_purpose::URL_SAFE, Engine};
use http::{HeaderMap, Method, Uri};
use jstz_crypto::{keypair_from_passphrase, public_key::PublicKey, secret_key::SecretKey};
use jstz_proto::context::account::{Address, Nonce, ParsedCode};
use jstz_proto::operation::{Content, DeployFunction, Operation, RunFunction, SignedOperation};
use serde::{Serialize, Serializer};
use std::error::Error;
use std::path::Path;
use tezos_smart_rollup::utils::inbox::file::{InboxFile, Message};

const FA2: &str = include_str!("../../fa2.js");

const DEFAULT_GAS_LIMIT: u32 = 100_000;

type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// Generate the requested 'FA2 transfers', writing to `./inbox.json`.
///
/// This includes setup (contract deployment/minting) as well as balance checks at the end.
/// The transfers are generated with a 'follow on' strategy. For example 'account 0' will
/// have `num_accounts` minted of 'token 0'. It will then transfer all of them to 'account 1',
/// which will transfer `num_accounts - 1` to the next account, etc.
pub fn handle_generate(inbox_file: &Path, transfers: usize) -> Result<()> {
    let accounts = accounts_for_transfers(transfers);

    if accounts == 0 {
        return Err("--transfers must be greater than zero".into());
    }

    let mut accounts = gen_keys(accounts)?;

    // Level 1 - setup
    let (fa2_address, deploy) = deploy_fa2(accounts.first_mut().unwrap())?;
    let batch_mint = batch_mint(&mut accounts, &fa2_address)?;

    let level1 = vec![deploy, batch_mint];

    // Level 2 - transfers
    let len = accounts.len();
    let mut transfers = Vec::with_capacity(transfers);

    'outer: for token_id in 0..len {
        for (from, amount) in (token_id..(token_id + len)).zip(1..len) {
            if transfers.capacity() == transfers.len() {
                break 'outer;
            }

            let to = accounts[(from + 1) % len].address.clone();
            let transfer = Transfer {
                token_id,
                amount: len - amount,
                to,
            };

            let account = &mut accounts[from % len];
            let op = transfer_op(account, &fa2_address, &transfer)?;

            transfers.push(op);
        }
    }

    // Level 3 - checking
    let tokens = 0..accounts.len();
    let balances = accounts
        .iter_mut()
        .map(|a| balance(a, &fa2_address, tokens.clone()))
        .collect::<Result<Vec<_>>>()?;

    // Output inbox file
    let inbox = InboxFile(vec![level1, transfers, balances]);
    inbox.save(inbox_file)?;
    Ok(())
}

#[derive(Debug, Serialize)]
struct MintNew<'a> {
    token_id: usize,
    #[serde(serialize_with = "address_ser")]
    owner: &'a Address,
    amount: usize,
}

#[derive(Debug, Serialize)]
struct BalanceRequest<'a> {
    token_id: usize,
    #[serde(serialize_with = "address_ser")]
    owner: &'a Address,
}

#[derive(Debug, Serialize)]
struct Transfer {
    token_id: usize,
    amount: usize,
    #[serde(serialize_with = "address_ser")]
    to: Address,
}

#[derive(Debug, Serialize)]
struct TransferToken<'a> {
    #[serde(serialize_with = "address_ser")]
    from: &'a Address,
    transfers: &'a [&'a Transfer],
}

fn address_ser<S>(address: &Address, ser: S) -> std::result::Result<S::Ok, S::Error>
where
    S: Serializer,
{
    let address = address.to_base58();
    String::serialize(&address, ser)
}

fn transfer_op(account: &mut Account, fa2: &Address, transfer: &Transfer) -> Result<Message> {
    let transfer = [TransferToken {
        from: &account.address,
        transfers: &[&transfer],
    }];

    let body = serde_json::ser::to_vec(&transfer)?;

    let content = Content::RunFunction(RunFunction {
        uri: Uri::try_from(format!("tezos://{fa2}/transfer"))?,
        method: Method::POST,
        headers: HeaderMap::default(),
        body: Some(body),
        gas_limit: DEFAULT_GAS_LIMIT.try_into()?,
    });

    account.operation_to_message(content)
}

fn balance(
    account: &mut Account,
    fa2: &Address,
    tokens: std::ops::Range<usize>,
) -> Result<Message> {
    let reqs: Vec<_> = tokens
        .map(|i| BalanceRequest {
            owner: &account.address,
            token_id: i,
        })
        .collect();
    let query = serde_json::ser::to_vec(&reqs)?;
    let query = URL_SAFE.encode(query);

    let content = Content::RunFunction(RunFunction {
        uri: Uri::try_from(format!("tezos://{fa2}/balance_of?requests={query}"))?,
        method: Method::GET,
        headers: HeaderMap::default(),
        body: None,
        gas_limit: DEFAULT_GAS_LIMIT.try_into()?,
    });

    account.operation_to_message(content)
}

fn batch_mint(accounts: &mut [Account], fa2: &Address) -> Result<Message> {
    let amount = accounts.len() + 1;
    let mints: Vec<_> = accounts
        .iter()
        .enumerate()
        .map(|(i, a)| MintNew {
            token_id: i,
            owner: &a.address,
            amount,
        })
        .collect();

    let body = serde_json::ser::to_vec(&mints)?;
    let account = &mut accounts[0];

    let content = Content::RunFunction(RunFunction {
        uri: Uri::try_from(format!("tezos://{fa2}/mint_new"))?,
        method: Method::POST,
        headers: HeaderMap::default(),
        body: Some(body),
        gas_limit: DEFAULT_GAS_LIMIT.try_into()?,
    });

    account.operation_to_message(content)
}

fn deploy_fa2(account: &mut Account) -> Result<(Address, Message)> {
    let code: ParsedCode = FA2.to_string().try_into()?;

    let address = Address::digest(
        format!("{}{}{}", &account.address, code, account.nonce.next()).as_bytes(),
    )?;

    let content = Content::DeployFunction(DeployFunction {
        function_code: code,
        account_credit: 0,
    });

    let message = account.operation_to_message(content)?;

    Ok((address, message))
}

fn gen_keys(num: usize) -> Result<Vec<Account>> {
    let mut res = Vec::with_capacity(num);

    for i in 0..num {
        let (sk, pk) = keypair_from_passphrase(&i.to_string())?;
        let account = Account {
            address: Address::try_from(&pk)?,
            sk,
            pk,
            nonce: Default::default(),
        };
        res.push(account)
    }

    Ok(res)
}

struct Account {
    nonce: Nonce,
    sk: SecretKey,
    pk: PublicKey,
    address: Address,
}

impl Account {
    fn operation_to_message(&mut self, content: Content) -> Result<Message> {
        let op = Operation {
            source: self.address.clone(),
            nonce: self.nonce,
            content,
        };

        let hash = op.hash();
        let signed_op = SignedOperation::new(self.pk.clone(), self.sk.sign(hash)?, op);

        let bytes = bincode::serialize(&signed_op)?;

        self.nonce = self.nonce.next();
        let message = Message::External { external: bytes };

        Ok(message)
    }
}

/// The generation strategy supports up to `num_accounts ^ 2` transfers,
/// find the smallest number of accounts which will allow for this.
fn accounts_for_transfers(transfers: usize) -> usize {
    f64::sqrt(transfers as f64).ceil() as usize + 1
}
