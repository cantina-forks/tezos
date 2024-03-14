// SPDX-FileCopyrightText: 2022-2023 TriliTech <contact@trili.tech>
// SPDX-FileCopyrightText: 2024 Functori <contact@functori.com>
//
// SPDX-License-Identifier: MIT

use crate::handler::EvmHandler;
use crate::precompiles::tick_model;
use crate::precompiles::PrecompileOutcome;
use crate::{abi, fail_if_too_much, EthereumError};
use evm::{Context, ExitReason, ExitRevert, ExitSucceed, Transfer};
use host::runtime::Runtime;
use primitive_types::U256;
use tezos_ethereum::withdrawal::Withdrawal;
use tezos_evm_logging::log;
use tezos_evm_logging::Level::Info;

/// Cost of doing a withdrawal. A valid call to this precompiled contract
/// takes almost 880000 ticks, and one gas unit takes 1000 ticks.
/// The ticks/gas ratio is from benchmarks on `ecrecover`.
const WITHDRAWAL_COST: u64 = 880;

/// Implementation of Etherlink specific withdrawals precompiled contract.
pub fn withdrawal_precompile<Host: Runtime>(
    handler: &mut EvmHandler<Host>,
    input: &[u8],
    _context: &Context,
    _is_static: bool,
    transfer: Option<Transfer>,
) -> Result<PrecompileOutcome, EthereumError> {
    let estimated_ticks = fail_if_too_much!(tick_model::ticks_of_withdraw(), handler);
    fn revert_withdrawal() -> PrecompileOutcome {
        PrecompileOutcome {
            exit_status: ExitReason::Revert(ExitRevert::Reverted),
            output: vec![],
            withdrawals: vec![],
            estimated_ticks: tick_model::ticks_of_withdraw(),
        }
    }

    if let Err(err) = handler.record_cost(WITHDRAWAL_COST) {
        log!(
            handler.borrow_host(),
            Info,
            "Couldn't record the cost of withdrawal {:?}",
            err
        );
        return Ok(PrecompileOutcome {
            exit_status: ExitReason::Error(err),
            output: vec![],
            withdrawals: vec![],
            estimated_ticks,
        });
    }

    let Some(transfer) = transfer else {
        log!(handler.borrow_host(), Info, "Withdrawal precompiled contract: no transfer");
        return Ok(revert_withdrawal())
    };

    if U256::is_zero(&transfer.value) {
        log!(
            handler.borrow_host(),
            Info,
            "Withdrawal precompiled contract: transfer of 0"
        );
        return Ok(revert_withdrawal());
    }

    match input {
        [0xcd, 0xa4, 0xfe, 0xe2, rest @ ..] => {
            let Some(address_str) = abi::string_parameter(rest, 0) else {
                log!(handler.borrow_host(), Info, "Withdrawal precompiled contract: unable to get address argument");
                return Ok(revert_withdrawal())
            };

            log!(
                handler.borrow_host(),
                Info,
                "Withdrawal to {:?}",
                address_str
            );

            let Some(target) = Withdrawal::address_from_str(address_str) else {
                log!(handler.borrow_host(), Info, "Withdrawal precompiled contract: invalid target address string");
                return Ok(revert_withdrawal())
            };

            // TODO Check that the outbox ain't full yet

            // TODO we need to measure number of ticks and translate this number into
            // Ethereum gas units

            let withdrawals = vec![Withdrawal {
                target,
                amount: transfer.value,
            }];

            Ok(PrecompileOutcome {
                exit_status: ExitReason::Succeed(ExitSucceed::Returned),
                output: vec![],
                withdrawals,
                estimated_ticks,
            })
        }
        // TODO A contract "function" to do withdrawal to byte encoded address
        _ => {
            log!(
                handler.borrow_host(),
                Info,
                "Withdrawal precompiled contract: invalid function selector"
            );
            Ok(revert_withdrawal())
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        handler::ExecutionOutcome,
        precompiles::{test_helpers::execute_precompiled, withdrawal::WITHDRAWAL_COST},
    };
    use evm::{ExitReason, ExitRevert, ExitSucceed, Transfer};
    use primitive_types::{H160, U256};
    use std::str::FromStr;
    use tezos_ethereum::withdrawal::Withdrawal;
    use tezos_smart_rollup_encoding::contract::Contract;

    #[test]
    fn call_withdraw_with_implicit_address() {
        // Format of input - generated by eg remix to match withdrawal ABI
        // 1. function identifier (_not_ the parameter block)
        // 2. location of first parameter (measured from start of parameter block)
        // 3. Number of bytes in string argument
        // 4. A Layer 1 contract address, hex-encoded
        // 5. Zero padding for hex-encoded address

        let input: &[u8] = &hex::decode(
            "cda4fee2\
             0000000000000000000000000000000000000000000000000000000000000020\
             0000000000000000000000000000000000000000000000000000000000000024\
             747a31526a745a5556654c6841444648444c385577445a4136766a5757686f6a70753577\
             00000000000000000000000000000000000000000000000000000000",
        )
        .unwrap();

        let source = H160::from_low_u64_be(118u64);
        let target = H160::from_str("ff00000000000000000000000000000000000001").unwrap();
        let value = U256::from(100);

        let transfer = Some(Transfer {
            source,
            target,
            value,
        });

        let result = execute_precompiled(target, input, transfer, Some(25000));

        let expected_output = vec![];
        let expected_target =
            Contract::from_b58check("tz1RjtZUVeLhADFHDL8UwDZA6vjWWhojpu5w").unwrap();

        let expected_gas = 21000 // base cost, no additional cost for withdrawal
    + 1032 // transaction data cost (90 zero bytes + 42 non zero bytes)
    + WITHDRAWAL_COST; // cost of calling withdrawal precompiled contract

        let expected = ExecutionOutcome {
            gas_used: expected_gas,
            reason: ExitReason::Succeed(ExitSucceed::Returned).into(),
            is_success: true,
            new_address: None,
            logs: vec![],
            result: Some(expected_output),
            withdrawals: vec![Withdrawal {
                target: expected_target,
                amount: 100.into(),
            }],
            estimated_ticks_used: 880_000,
        };

        assert_eq!(Ok(expected), result);
    }

    #[test]
    fn call_withdraw_with_kt1_address() {
        // Format of input - generated by eg remix to match withdrawal ABI
        // 1. function identifier (_not_ the parameter block)
        // 2. location of first parameter (measured from start of parameter block)
        // 3. Number of bytes in string argument
        // 4. A Layer 1 contract address, hex-encoded
        // 5. Zero padding for hex-encoded address

        let input: &[u8] = &hex::decode(
            "cda4fee2\
             0000000000000000000000000000000000000000000000000000000000000020\
             0000000000000000000000000000000000000000000000000000000000000024\
             4b54314275455a7462363863315134796a74636b634e6a47454c71577435365879657363\
             00000000000000000000000000000000000000000000000000000000",
        )
        .unwrap();

        let source = H160::from_low_u64_be(118u64);
        let target = H160::from_str("ff00000000000000000000000000000000000001").unwrap();
        let value = U256::from(100);

        let transfer = Some(Transfer {
            source,
            target,
            value,
        });

        let result = execute_precompiled(target, input, transfer, Some(25000));

        let expected_output = vec![];

        let expected_target =
            Contract::from_b58check("KT1BuEZtb68c1Q4yjtckcNjGELqWt56Xyesc").unwrap();

        let expected_gas = 21000 // base cost, no additional cost for withdrawal
    + 1032 // transaction data cost (90 zero bytes + 42 non zero bytes)
    + WITHDRAWAL_COST; // cost of calling withdrawal precompiled contract

        let expected = ExecutionOutcome {
            gas_used: expected_gas,
            reason: ExitReason::Succeed(ExitSucceed::Returned).into(),
            is_success: true,
            new_address: None,
            logs: vec![],
            result: Some(expected_output),
            withdrawals: vec![Withdrawal {
                target: expected_target,
                amount: 100.into(),
            }],
            // TODO (#6426): estimate the ticks consumption of precompiled contracts
            estimated_ticks_used: 880_000,
        };

        assert_eq!(Ok(expected), result);
    }

    #[test]
    fn call_withdrawal_fails_without_transfer() {
        let input: &[u8] = &hex::decode(
            "cda4fee2\
             0000000000000000000000000000000000000000000000000000000000000020\
             0000000000000000000000000000000000000000000000000000000000000024\
             747a31526a745a5556654c6841444648444c385577445a4136766a5757686f6a70753577\
             00000000000000000000000000000000000000000000000000000000",
        )
        .unwrap();

        // 1. Fails with no transfer

        let target = H160::from_str("ff00000000000000000000000000000000000001").unwrap();

        let transfer: Option<Transfer> = None;

        let result = execute_precompiled(target, input, transfer, Some(25000));

        let expected_gas = 21000 // base cost, no additional cost for withdrawal
    + 1032 // transaction data cost (90 zero bytes + 42 non zero bytes)
    + WITHDRAWAL_COST; // cost of calling the withdrawals precompiled contract.

        let expected = ExecutionOutcome {
            gas_used: expected_gas,
            reason: ExitReason::Revert(ExitRevert::Reverted).into(),
            is_success: false,
            new_address: None,
            logs: vec![],
            result: Some(vec![]),
            withdrawals: vec![],
            estimated_ticks_used: 880_000,
        };

        assert_eq!(Ok(expected), result);

        // 2. Fails with transfer of 0 amount.

        let source = H160::from_low_u64_be(118u64);

        let transfer: Option<Transfer> = Some(Transfer {
            target,
            source,
            value: U256::zero(),
        });

        let expected = ExecutionOutcome {
            gas_used: expected_gas,
            reason: ExitReason::Revert(ExitRevert::Reverted).into(),
            is_success: false,
            new_address: None,
            logs: vec![],
            result: Some(vec![]),
            withdrawals: vec![],
            estimated_ticks_used: 880_000,
        };

        let result = execute_precompiled(target, input, transfer, Some(25000));

        assert_eq!(Ok(expected), result);
    }
}
