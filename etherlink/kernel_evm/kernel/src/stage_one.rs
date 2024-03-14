// SPDX-FileCopyrightText: 2023 Nomadic Labs <contact@nomadic-labs.com>
//
// SPDX-License-Identifier: MIT

use crate::blueprint::Blueprint;
use crate::blueprint_storage::{
    store_immediate_blueprint, store_inbox_blueprint, store_sequencer_blueprint,
};
use crate::configuration::{Configuration, ConfigurationMode, TezosContracts};
use crate::current_timestamp;
use crate::delayed_inbox::DelayedInbox;
use crate::inbox::InboxContent;
use crate::inbox::{read_proxy_inbox, read_sequencer_inbox};
use crate::read_last_info_per_level_timestamp;
use crate::storage::read_l1_level;
use anyhow::Ok;
use std::ops::Add;
use tezos_crypto_rs::hash::ContractKt1Hash;
use tezos_evm_logging::{log, Level::*};
use tezos_smart_rollup_encoding::public_key::PublicKey;
use tezos_smart_rollup_host::metadata::RAW_ROLLUP_ADDRESS_SIZE;

use tezos_smart_rollup_host::runtime::Runtime;

pub fn fetch_proxy_blueprints<Host: Runtime>(
    host: &mut Host,
    smart_rollup_address: [u8; RAW_ROLLUP_ADDRESS_SIZE],
    tezos_contracts: &TezosContracts,
) -> Result<(), anyhow::Error> {
    if let Some(InboxContent {
        transactions,
        sequencer_blueprints: _,
    }) = read_proxy_inbox(host, smart_rollup_address, tezos_contracts)?
    {
        let timestamp = current_timestamp(host);
        let blueprint = Blueprint {
            transactions,
            timestamp,
        };
        // Store the blueprint.
        store_inbox_blueprint(host, blueprint)?;
    }
    Ok(())
}

fn fetch_delayed_transactions<Host: Runtime>(
    host: &mut Host,
    delayed_inbox: &mut DelayedInbox,
) -> anyhow::Result<()> {
    let timestamp = current_timestamp(host);
    // Number for the first forced blueprint
    let base = crate::blueprint_storage::read_next_blueprint_number(host)?;
    // Accumulator of how many blueprints we fetched
    let mut offset: u32 = 0;

    while let Some(timed_out) = delayed_inbox.next_delayed_inbox_blueprint(host)? {
        log!(
            host,
            Info,
            "Creating blueprint from timed out delayed transactions of length {}",
            timed_out.len()
        );
        // Create a new blueprint with the timed out transactions
        let blueprint = Blueprint {
            transactions: timed_out,
            timestamp,
        };
        // Store the blueprint.
        store_immediate_blueprint(host, blueprint, base.add(offset))?;
        offset += 1;
    }

    Ok(())
}

fn fetch_sequencer_blueprints<Host: Runtime>(
    host: &mut Host,
    smart_rollup_address: [u8; RAW_ROLLUP_ADDRESS_SIZE],
    tezos_contracts: &TezosContracts,
    delayed_bridge: ContractKt1Hash,
    delayed_inbox: &mut DelayedInbox,
    sequencer: PublicKey,
) -> Result<(), anyhow::Error> {
    if let Some(InboxContent {
        transactions,
        sequencer_blueprints,
    }) = read_sequencer_inbox(
        host,
        smart_rollup_address,
        tezos_contracts,
        delayed_bridge,
        sequencer,
    )? {
        let previous_timestamp = read_last_info_per_level_timestamp(host)?;
        let level = read_l1_level(host)?;
        // Store the transactions in the delayed inbox.
        for transaction in transactions {
            delayed_inbox.save_transaction(
                host,
                transaction,
                previous_timestamp,
                level,
            )?;
        }
        // Check if there are timed-out transactions in the delayed inbox
        let timed_out = delayed_inbox.first_has_timed_out(host)?;
        if timed_out {
            fetch_delayed_transactions(host, delayed_inbox)?
        } else {
            // Store the sequencer blueprints.
            log!(
                host,
                Benchmarking,
                "number of blueprint chunks read: {}",
                sequencer_blueprints.len()
            );
            for seq_blueprint in sequencer_blueprints {
                log!(
                    host,
                    Debug,
                    "Storing chunk {} of sequencer blueprint number {}",
                    seq_blueprint.blueprint.chunk_index,
                    seq_blueprint.blueprint.number
                );
                store_sequencer_blueprint(host, seq_blueprint)?
            }
        }
    }
    Ok(())
}

pub fn fetch<Host: Runtime>(
    host: &mut Host,
    smart_rollup_address: [u8; RAW_ROLLUP_ADDRESS_SIZE],
    config: &mut Configuration,
) -> Result<(), anyhow::Error> {
    match &mut config.mode {
        ConfigurationMode::Sequencer {
            delayed_bridge,
            delayed_inbox,
            sequencer,
        } => fetch_sequencer_blueprints(
            host,
            smart_rollup_address,
            &config.tezos_contracts,
            delayed_bridge.clone(),
            delayed_inbox,
            sequencer.clone(),
        ),
        ConfigurationMode::Proxy => {
            fetch_proxy_blueprints(host, smart_rollup_address, &config.tezos_contracts)
        }
    }
}

#[cfg(test)]
mod tests {
    use tezos_crypto_rs::hash::HashTrait;
    use tezos_data_encoding::types::Bytes;
    use tezos_smart_rollup::{
        michelson::{
            ticket::FA2_1Ticket, MichelsonBytes, MichelsonOption, MichelsonOr,
            MichelsonPair,
        },
        types::PublicKeyHash,
    };
    use tezos_smart_rollup_encoding::contract::Contract;
    use tezos_smart_rollup_mock::{MockHost, TransferMetadata};

    use crate::{blueprint_storage::read_next_blueprint, parsing::RollupType};

    use super::*;

    fn dummy_sequencer_config() -> Configuration {
        let mut host = MockHost::default();
        let delayed_inbox =
            DelayedInbox::new(&mut host).expect("Delayed inbox should be created");
        let delayed_bridge: ContractKt1Hash =
            ContractKt1Hash::from_base58_check("KT18amZmM5W7qDWVt2pH6uj7sCEd3kbzLrHT")
                .unwrap();
        // This is tezt/lib_tezos/account: bootstrap1
        let sequencer: PublicKey = PublicKey::from_b58check(
            "edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav",
        )
        .unwrap();

        let contracts = TezosContracts::default();
        Configuration {
            tezos_contracts: TezosContracts {
                ticketer: Some(ContractKt1Hash::from_b58check(DUMMY_TICKETER).unwrap()),
                ..contracts
            },
            mode: ConfigurationMode::Sequencer {
                delayed_bridge,
                delayed_inbox: Box::new(delayed_inbox),
                sequencer,
            },
        }
    }

    fn dummy_proxy_configuration() -> Configuration {
        let contracts = TezosContracts::default();
        Configuration {
            tezos_contracts: TezosContracts {
                ticketer: Some(ContractKt1Hash::from_b58check(DUMMY_TICKETER).unwrap()),
                ..contracts
            },
            mode: ConfigurationMode::Proxy,
        }
    }

    const DUMMY_BLUEPRINT_CHUNK: &str = "00000000000000000000000000000000000000000003f897adeca0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc0c0880000000000000000a00000000000000000000000000000000000000000000000000000000000000000820100820000b84093cc9ec356f5cf9d61d1f0cda20d6546aafd77de31737066af586c2f681d41492b7a1a5cceff6620dd2fe848f134c86bfde1ec10f435f25e9a7be9657e867f03";
    const DUMMY_BLUEPRINT_CHUNK_UNPARSABLE: &str = "00000000000000000000000000000000000000000003f897adeca0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc0c0880000000000000000a00000000000000000000000000000000000000000000000000000000000000000820100820000b8403b4f48059e64cbe8a60fef482bff04ed453291d17fe888d2bae4420a623157570af4bd7ab944354583bcdce1149d004a4699b027c7370cd5e0b16172f3340406";

    const DUMMY_RAW_TRANSACTION: &str = "f873808402faf08083c71b0094f0affc80a5f69f4a9a3ee01a640873b6ba53e5398d01431e0fae6d7210000000000080820a96a0a4160335a080cd3501fd88fe4d28cc3cd8f1283fa597c10f59028c0517efce27a0444512519b3346609d2ca7c400dc1f5263d2bdad8a2ac0a5ab942336e7ed603a";
    const DUMMY_TRANSACTION: &str = "00000000000000000000000000000000000000000000bca8ac5e67ba4cb84d1d223be2cd900491012e9848fcdc496aa2d5e4566d564bf873808402faf08083c71b0094f0affc80a5f69f4a9a3ee01a640873b6ba53e5398d01431e0fae6d7210000000000080820a96a0a4160335a080cd3501fd88fe4d28cc3cd8f1283fa597c10f59028c0517efce27a0444512519b3346609d2ca7c400dc1f5263d2bdad8a2ac0a5ab942336e7ed603a";

    const DUMMY_NEW_CHUNKED_TX: &str = "00000000000000000000000000000000000000000001b00a070bfab8455de52f9a4256b1e4ec01d402ad48db395fc626cf56784da3a50200e9a4b3236353a4975255c3c4fe87ef26ee784eedc8f304eb6f7d7051e7ce95566606ba1560324fefe61abd1810149603e9cc8b11d0f07449b553496a25980368";

    const DUMMY_CHUNK1: &str= "00000000000000000000000000000000000000000002b00a070bfab8455de52f9a4256b1e4ec01d402ad48db395fc626cf56784da3a501006606ba1560324fefe61abd1810149603e9cc8b11d0f07449b553496a25980368565b9150509250925092565b600060ff82169050919050565b610b8281610b6c565b82525050565b6000602082019050610b9d6000830184610b79565b92915050565b600060208284031215610bb957610bb86109e0565b5b6000610bc784828501610a64565b91505092915050565b600060208284031215610be657610be56109e0565b5b6000610bf484828501610a2e565b91505092915050565b60008060408385031215610c1457610c136109e0565b5b6000610c2285828601610a2e565b9250506020610c3385828601610a2e565b9150509250929050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052602260045260246000fd5b60006002820490506001821680610c8457607f821691505b602082108103610c9757610c96610c3d565b5b50919050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052601160045260246000fd5b6000610cd782610a43565b9150610ce283610a43565b9250828203905081811115610cfa57610cf9610c9d565b5b92915050565b6000610d0b82610a43565b9150610d1683610a43565b9250828201905080821115610d2e57610d2d610c9d565b5b9291505056fea264697066735822122030971f380a01674dace4fc0292dcf2896b91915c6e633e0f2cf32f3e0969e9b864736f6c63430008150033820a96a0444b512de8e10806032b4e61579d347e8f7fd168d20b53e6d16a595e4598c5f1a03d18d45f44571af791cfb84e74ac0455cb3e46fa06f3c03f90edb8b21cf0016f";

    const DUMMY_CHUNK2: &str = "00000000000000000000000000000000000000000002b00a070bfab8455de52f9a4256b1e4ec01d402ad48db395fc626cf56784da3a50000e9a4b3236353a4975255c3c4fe87ef26ee784eedc8f304eb6f7d7051e7ce9556f911f2808402faf0808416487a008080b9119d60806040526040518060400160405280601381526020017f536f6c6964697479206279204578616d706c6500000000000000000000000000815250600390816200004a91906200033c565b506040518060400160405280600781526020017f534f4c4259455800000000000000000000000000000000000000000000000000815250600490816200009191906200033c565b506012600560006101000a81548160ff021916908360ff160217905550348015620000bb57600080fd5b5062000423565b600081519050919050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fd5b7f4e487b7100000000000000000000000000000000000000000000000000000000600052602260045260246000fd5b600060028204905060018216806200014457607f821691505b6020821081036200015a5762000159620000fc565b5b50919050565b60008190508160005260206000209050919050565b60006020601f8301049050919050565b600082821b905092915050565b600060088302620001c47fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8262000185565b620001d0868362000185565b95508019841693508086168417925050509392505050565b6000819050919050565b6000819050919050565b60006200021d620002176200021184620001e8565b620001f2565b620001e8565b9050919050565b6000819050919050565b6200023983620001fc565b62000251620002488262000224565b84845462000192565b825550505050565b600090565b6200026862000259565b620002758184846200022e565b505050565b5b818110156200029d57620002916000826200025e565b6001810190506200027b565b5050565b601f821115620002ec57620002b68162000160565b620002c18462000175565b81016020851015620002d1578190505b620002e9620002e08562000175565b8301826200027a565b50505b505050565b600082821c905092915050565b60006200031160001984600802620002f1565b1980831691505092915050565b60006200032c8383620002fe565b9150826002028217905092915050565b6200034782620000c2565b67ffffffffffffffff811115620003635762000362620000cd565b5b6200036f82546200012b565b6200037c828285620002a1565b600060209050601f831160018114620003b457600084156200039f578287015190505b620003ab85826200031e565b8655506200041b565b601f198416620003c48662000160565b60005b82811015620003ee57848901518255600182019150602085019450602081019050620003c7565b868310156200040e57848901516200040a601f891682620002fe565b8355505b6001600288020188555050505b505050505050565b610d6a80620004336000396000f3fe608060405234801561001057600080fd5b50600436106100a95760003560e01c806342966c681161007157806342966c681461016857806370a082311461018457806395d89b41146101b4578063a0712d68146101d2578063a9059cbb146101ee578063dd62ed3e1461021e576100a9565b806306fdde03146100ae578063095ea7b3146100cc57806318160ddd146100fc57806323b872dd1461011a578063313ce5671461014a575b600080fd5b6100b661024e565b6040516100c391906109be565b60405180910390f35b6100e660048036038101906100e19190610a79565b6102dc565b6040516100f39190610ad4565b60405180910390f35b6101046103ce565b6040516101119190610afe565b60405180910390f35b610134600480360381019061012f9190610b19565b6103d4565b6040516101419190610ad4565b60405180910390f35b610152610585565b60405161015f9190610b88565b60405180910390f35b610182600480360381019061017d9190610ba3565b610598565b005b61019e60048036038101906101999190610bd0565b61066f565b6040516101ab9190610afe565b60405180910390f35b6101bc610687565b6040516101c991906109be565b60405180910390f35b6101ec60048036038101906101e79190610ba3565b610715565b005b61020860048036038101906102039190610a79565b6107ec565b6040516102159190610ad4565b60405180910390f35b61023860048036038101906102339190610bfd565b610909565b6040516102459190610afe565b60405180910390f35b6003805461025b90610c6c565b80601f016020809104026020016040519081016040528092919081815260200182805461028790610c6c565b80156102d45780601f106102a9576101008083540402835291602001916102d4565b820191906000526020600020905b8154815290600101906020018083116102b757829003601f168201915b505050505081565b600081600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040516103bc9190610afe565b60405180910390a36001905092915050565b60005481565b600081600260008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008282546104629190610ccc565b9250508190555081600160008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008282546104b89190610ccc565b9250508190555081600160008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825461050e9190610d00565b925050819055508273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040516105729190610afe565b60405180910390a3600190509392505050565b600560009054906101000a900460ff1681565b80600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008282546105e79190610ccc565b92505081905550806000808282546105ff9190610ccc565b92505081905550600073ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef836040516106649190610afe565b60405180910390a350565b60016020528060005260406000206000915090505481565b6004805461069490610c6c565b80601f01602080910402602001604051908101604052809291908181526020018280546106c090610c6c565b801561070d5780601f106106e25761010080835404028352916020019161070d565b820191906000526020600020905b8154815290600101906020018083116106f057829003601f168201915b505050505081565b80600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008282546107649190610d00565b925050819055508060008082825461077c9190610d00565b925050819055503373ffffffffffffffffffffffffffffffffffffffff16600073ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef836040516107e19190610afe565b60405180910390a350565b600081600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825461083d9190610ccc565b9250508190555081600160008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008282546108939190610d00565b925050819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040516108f79190610afe565b60405180910390a36001905092915050565b6002602052816000526040600020602052806000526040600020600091509150505481565b600081519050919050565b600082825260208201905092915050565b60005b8381101561096857808201518184015260208101905061094d565b60008484015250505050565b6000601f19601f8301169050919050565b60006109908261092e565b61099a8185610939565b93506109aa81856020860161094a565b6109b381610974565b840191505092915050565b600060208201905081810360008301526109d88184610985565b905092915050565b600080fd5b600073ffffffffffffffffffffffffffffffffffffffff82169050919050565b6000610a10826109e5565b9050919050565b610a2081610a05565b8114610a2b57600080fd5b50565b600081359050610a3d81610a17565b92915050565b6000819050919050565b610a5681610a43565b8114610a6157600080fd5b50565b600081359050610a7381610a4d565b92915050565b60008060408385031215610a9057610a8f6109e0565b5b6000610a9e85828601610a2e565b9250506020610aaf85828601610a64565b9150509250929050565b60008115159050919050565b610ace81610ab9565b82525050565b6000602082019050610ae96000830184610ac5565b92915050565b610af881610a43565b82525050565b6000602082019050610b136000830184610aef565b92915050565b600080600060608486031215610b3257610b316109e0565b5b6000610b4086828701610a2e565b9350506020610b5186828701610a2e565b9250506040610b6286828701610a64";

    const DUMMY_TICKETER: &str = "KT1VEjeQfDBSfpDH5WeBM5LukHPGM2htYEh3";

    const DUMMY_INVALID_TICKETER: &str = "KT1Nn8bjcPSpg7EUHcZwYPCcfT1W8Z5Q8ug5";

    const DEFAULT_SR_ADDRESS: [u8; 20] = [0; 20];

    fn dummy_deposit(ticketer: ContractKt1Hash) -> RollupType {
        let receiver = MichelsonBytes(
            hex::decode("CdaC74220Da1399A78C3c850d2cA4b24ac4051E1")
                .unwrap()
                .to_vec(),
        );
        let ticket: FA2_1Ticket = FA2_1Ticket::new(
            Contract::from_b58check(&ticketer.to_base58_check()).unwrap(),
            MichelsonPair(0.into(), MichelsonOption(None)),
            1_000_000,
        )
        .unwrap();
        MichelsonOr::Left(MichelsonOr::Left(MichelsonPair(receiver, ticket)))
    }

    fn dummy_delayed_transaction() -> RollupType {
        let raw_tx = hex::decode(DUMMY_RAW_TRANSACTION).unwrap();
        MichelsonOr::Left(MichelsonOr::Right(MichelsonBytes(raw_tx.to_vec())))
    }

    fn delayed_bridge(conf: &Configuration) -> ContractKt1Hash {
        match &conf.mode {
            ConfigurationMode::Proxy => panic!("No delayed bridge in proxy mode"),
            ConfigurationMode::Sequencer { delayed_bridge, .. } => delayed_bridge.clone(),
        }
    }

    fn delayed_inbox_is_empty<Host: Runtime>(
        conf: &Configuration,
        host: &mut Host,
    ) -> bool {
        match &conf.mode {
            ConfigurationMode::Proxy => panic!("No delayed inbox in proxy mode"),
            ConfigurationMode::Sequencer { delayed_inbox, .. } => {
                delayed_inbox.is_empty(host).unwrap()
            }
        }
    }

    #[test]
    fn test_parsing_proxy_transaction() {
        let mut host = MockHost::default();
        host.add_external(Bytes::from(hex::decode(DUMMY_TRANSACTION).unwrap()));
        let mut conf = dummy_proxy_configuration();
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        match read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
        {
            Some(Blueprint { transactions, .. }) => assert!(transactions.len() == 1),
            _ => panic!("There should be a blueprint"),
        }
    }

    #[test]
    fn test_parsing_proxy_chunked_transaction() {
        let mut host = MockHost::default();
        host.add_external(Bytes::from(hex::decode(DUMMY_NEW_CHUNKED_TX).unwrap()));
        host.add_external(Bytes::from(hex::decode(DUMMY_CHUNK1).unwrap()));
        host.add_external(Bytes::from(hex::decode(DUMMY_CHUNK2).unwrap()));
        let mut conf = dummy_proxy_configuration();
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        match read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
        {
            Some(Blueprint { transactions, .. }) => assert!(transactions.len() == 1),
            _ => panic!("There should be a blueprint"),
        }
    }

    #[test]
    fn test_sequencer_reject_proxy_transactions() {
        let mut host = MockHost::default();
        host.add_external(Bytes::from(hex::decode(DUMMY_TRANSACTION).unwrap()));
        let mut conf = dummy_sequencer_config();
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        if read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
            .is_some()
        {
            panic!("No blueprint should have been produced")
        }
    }

    #[test]
    fn test_sequencer_reject_proxy_chunked_transactions() {
        let mut host = MockHost::default();
        host.add_external(Bytes::from(hex::decode(DUMMY_NEW_CHUNKED_TX).unwrap()));
        host.add_external(Bytes::from(hex::decode(DUMMY_CHUNK1).unwrap()));
        host.add_external(Bytes::from(hex::decode(DUMMY_CHUNK2).unwrap()));
        let mut conf = dummy_sequencer_config();
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        if read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
            .is_some()
        {
            panic!("No blueprint should have been produced")
        }
    }

    #[test]
    fn test_parsing_valid_sequencer_chunk() {
        let mut host = MockHost::default();
        host.add_external(Bytes::from(hex::decode(DUMMY_BLUEPRINT_CHUNK).unwrap()));
        let mut conf = dummy_sequencer_config();
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        if read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
            .is_none()
        {
            panic!("There should be a blueprint")
        }
    }

    #[test]
    fn test_parsing_invalid_sequencer_chunk() {
        let mut host = MockHost::default();
        host.add_external(Bytes::from(
            hex::decode(DUMMY_BLUEPRINT_CHUNK_UNPARSABLE).unwrap(),
        ));
        let mut conf = dummy_sequencer_config();
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        if read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
            .is_some()
        {
            panic!("There shouldn't be a blueprint, the chunk is signed by the wrong key")
        }
    }

    #[test]
    fn test_proxy_rejects_sequencer_chunk() {
        let mut host = MockHost::default();
        host.add_external(Bytes::from(hex::decode(DUMMY_BLUEPRINT_CHUNK).unwrap()));
        let conf = dummy_sequencer_config();

        match read_proxy_inbox(&mut host, DEFAULT_SR_ADDRESS, &conf.tezos_contracts)
            .unwrap()
        {
            None => panic!("There should be an InboxContent"),
            Some(InboxContent {
                sequencer_blueprints,
                ..
            }) => assert_eq!(
                sequencer_blueprints,
                vec![],
                "The blueprint shouldn't contain any transaction as it has been "
            ),
        };
    }

    #[test]
    fn test_parsing_delayed_inbox() {
        let mut host = MockHost::default();
        let mut conf = dummy_sequencer_config();
        let metadata = TransferMetadata::new(
            delayed_bridge(&conf),
            PublicKeyHash::from_b58check("tz1NiaviJwtMbpEcNqSP6neeoBYj8Brb3QPv").unwrap(),
        );
        host.add_transfer(dummy_delayed_transaction(), &metadata);
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        if read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
            .is_some()
        {
            panic!("There shouldn't be a blueprint, the transaction comes from the delayed bridge")
        }

        if delayed_inbox_is_empty(&conf, &mut host) {
            panic!("The delayed inbox shouldn't be empty")
        }
    }

    #[test]
    fn test_parsing_l1_contract_inbox() {
        let mut host = MockHost::default();
        let mut conf = dummy_sequencer_config();
        let metadata = TransferMetadata::new(
            ContractKt1Hash::from_b58check(DUMMY_INVALID_TICKETER).unwrap(),
            PublicKeyHash::from_b58check("tz1NiaviJwtMbpEcNqSP6neeoBYj8Brb3QPv").unwrap(),
        );
        host.add_transfer(dummy_delayed_transaction(), &metadata);
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        if read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
            .is_some()
        {
            panic!("There shouldn't be a blueprint, the transaction comes from the delayed bridge")
        }

        if !delayed_inbox_is_empty(&conf, &mut host) {
            panic!("The delayed inbox should be empty, as it comes from the wrong delayed bridge")
        }
    }

    #[test]
    fn test_parsing_delayed_inbox_rejected_in_proxy() {
        let mut host = MockHost::default();
        let mut conf = dummy_proxy_configuration();
        let metadata = TransferMetadata::new(
            ContractKt1Hash::from_b58check(DUMMY_INVALID_TICKETER).unwrap(),
            PublicKeyHash::from_b58check("tz1NiaviJwtMbpEcNqSP6neeoBYj8Brb3QPv").unwrap(),
        );
        host.add_transfer(dummy_delayed_transaction(), &metadata);
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        match read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
        {
            None => panic!("There should be a blueprint"),
            Some(Blueprint { transactions, .. }) =>
                assert_eq!(transactions.len(), 0,
                           "The transaction from the delayed bridge entrypoint should have been rejected in proxy mode"),
        }
    }

    #[test]
    fn test_deposit_in_proxy_mode() {
        let mut host = MockHost::default();
        let mut conf = dummy_proxy_configuration();
        let metadata = TransferMetadata::new(
            conf.tezos_contracts.ticketer.clone().unwrap(),
            PublicKeyHash::from_b58check("tz1NiaviJwtMbpEcNqSP6neeoBYj8Brb3QPv").unwrap(),
        );
        host.add_transfer(
            dummy_deposit(conf.tezos_contracts.ticketer.clone().unwrap()),
            &metadata,
        );
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        match read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
        {
            None => panic!("There should be a blueprint"),
            Some(Blueprint { transactions, .. }) => assert_eq!(
                transactions.len(),
                1,
                "The deposit should have been picked in the blueprint"
            ),
        }
    }

    #[test]
    fn test_deposit_with_invalid_ticketer() {
        let mut host = MockHost::default();
        let mut conf = dummy_proxy_configuration();
        let metadata = TransferMetadata::new(
            ContractKt1Hash::from_b58check(DUMMY_INVALID_TICKETER).unwrap(),
            PublicKeyHash::from_b58check("tz1NiaviJwtMbpEcNqSP6neeoBYj8Brb3QPv").unwrap(),
        );
        host.add_transfer(
            dummy_deposit(
                ContractKt1Hash::from_b58check(DUMMY_INVALID_TICKETER).unwrap(),
            ),
            &metadata,
        );
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        match read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
        {
            None => panic!("There should be a blueprint"),
            Some(Blueprint { transactions, .. }) => assert_eq!(
                transactions.len(),
                0,
                "The deposit shouldn't have been picked in the blueprint as it is invalid"
            ),
        }
    }

    #[test]
    fn test_deposit_in_sequencer_mode() {
        let mut host = MockHost::default();
        let mut conf = dummy_sequencer_config();
        let metadata = TransferMetadata::new(
            conf.tezos_contracts.ticketer.clone().unwrap(),
            PublicKeyHash::from_b58check("tz1NiaviJwtMbpEcNqSP6neeoBYj8Brb3QPv").unwrap(),
        );
        host.add_transfer(
            dummy_deposit(conf.tezos_contracts.ticketer.clone().unwrap()),
            &metadata,
        );
        fetch(&mut host, DEFAULT_SR_ADDRESS, &mut conf).expect("fetch failed");

        if read_next_blueprint(&mut host, &mut conf)
            .expect("Blueprint reading shouldn't fail")
            .is_some()
        {
            panic!("There shouldn't be a blueprint, the transaction comes from the delayed bridge")
        }

        if delayed_inbox_is_empty(&conf, &mut host) {
            panic!("The delayed inbox shouldn't be empty")
        }
    }
}
