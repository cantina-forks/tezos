// SPDX-FileCopyrightText: 2023 PK Lab <contact@pklab.io>
//
// SPDX-License-Identifier: MIT

//! FA bridge precompiled contract.
//!
//! Provides users with EVM interface for:
//!     * Submitting ticket withdrawal requests
//!
//! This is a stateful precompile:
//!     * Alters ticket table (changes balance)
//!     * Increments outbox counter

use evm::{Context, Transfer};
use primitive_types::H160;
use tezos_smart_rollup_host::runtime::Runtime;

use crate::{
    fa_bridge::{execute_fa_withdrawal, withdrawal::FaWithdrawal},
    fail_if_too_much,
    handler::EvmHandler,
    EthereumError,
};

use super::{PrecompileOutcome, FA_BRIDGE_PRECOMPILE_ADDRESS};

/// Overapproximation of the amount of ticks for parsing
/// FA withdrawal from calldata, checking transfer value,
/// and executing the FA withdrawal, excluding the ticks consumed by
/// the inner proxy call.
///
/// Linear regression parameters are obtained by running `bench_fa_withdrawal`
/// script, evaluating `run_transaction_ticks` against `data_size`.
/// Intercept is extended with +50% safe reserve.
pub const FA_WITHDRAWAL_PRECOMPILE_TICKS_INTERCEPT: u64 = 4_000_000;
pub const FA_WITHDRAWAL_PRECOMPILE_TICKS_SLOPE: u64 = 700;

/// Added ("artificial") cost of doing FA withdrawal not including actual gas
/// spent for executing the withdrawal (and inner proxy contract call).
///
/// This is roughly the implied costs of executing the outbox message on L1
/// as a spam prevention mechanism (outbox queue clogging).
/// In particular it prevents cases when a big number of withdrawals is batched
/// together in a single transaction which exploits the system.
///
/// An execution of a single outbox message carrying a FA withdrawal
/// costs around 0.0025ꜩ on L1; assuming current price per L2 gas of 1 Gwei
/// the equivalent amount of gas is 0.0025 * 10^18 / 10^9 = 2_500_000
///
/// Multiplying by 2 to have a safe reserve but at the same time keeping
/// L2 fees per withdrawal below 1 cent.
pub const FA_WITHDRAWAL_PRECOMPILE_ADDED_GAS_COST: u64 = 5_000_000;

macro_rules! precompile_outcome_error {
    ($($arg:tt)*) => {
        crate::precompiles::PrecompileOutcome {
            exit_status: evm::ExitReason::Error(evm::ExitError::Other(
                std::borrow::Cow::from(format!($($arg)*))
            )),
            withdrawals: vec![],
            output: vec![],
            estimated_ticks: 0,
        }
    };
}

/// FA bridge precompile entrypoint.
#[allow(unused)]
pub fn fa_bridge_precompile<Host: Runtime>(
    handler: &mut EvmHandler<Host>,
    input: &[u8],
    context: &Context,
    is_static: bool,
    transfer: Option<Transfer>,
) -> Result<PrecompileOutcome, EthereumError> {
    // We register the cost of the precompile early to prevent cases where inner proxy call
    // consumes more ticks than allowed.
    let estimated_ticks = FA_WITHDRAWAL_PRECOMPILE_TICKS_SLOPE * (input.len() as u64)
        + FA_WITHDRAWAL_PRECOMPILE_TICKS_INTERCEPT;
    handler.estimated_ticks_used += fail_if_too_much!(estimated_ticks, handler);

    // We also record gas cost which consists of computation cost (1 gas unit per 1000 ticks)
    // and added FA withdrawal cost (spam prevention measure).
    let estimated_gas_cost =
        estimated_ticks / 1000 + FA_WITHDRAWAL_PRECOMPILE_ADDED_GAS_COST;
    if handler.record_cost(estimated_gas_cost).is_err() {
        return Ok(precompile_outcome_error!(
            "FA withdrawal: gas limit too low"
        ));
    }

    if is_static {
        // It is a STATICCALL that prevents storage modification
        // see https://eips.ethereum.org/EIPS/eip-214
        return Ok(precompile_outcome_error!(
            "FA withdrawal: static call not allowed"
        ));
    }

    if context.address != FA_BRIDGE_PRECOMPILE_ADDRESS {
        // It is a DELEGATECALL or CALLCODE (deprecated) which can be impersonating
        // see https://eips.ethereum.org/EIPS/eip-7
        return Ok(precompile_outcome_error!(
            "FA withdrawal: delegate call not allowed"
        ));
    }

    if transfer
        .as_ref()
        .map(|t| !t.value.is_zero())
        .unwrap_or(false)
    {
        return Ok(precompile_outcome_error!(
            "FA withdrawal: unexpected value transfer {:?}",
            transfer
        ));
    }

    match input {
        // "withdraw"'s selector | 4 first bytes of keccak256("withdraw(address,bytes,uint256,bytes22,bytes)")
        [0x80, 0xfc, 0x1f, 0xe3, input_data @ ..] => {
            // Withdrawal initiator is the precompile caller.
            // NOTE that since we deny delegate calls, it can either be EOA or
            // a smart contract that calls the precompile directly (e.g. AA wallet).
            match FaWithdrawal::try_parse(input_data, context.caller) {
                Ok(withdrawal) => {
                    // Using Zero account here so that the inner proxy call
                    // has the same sender as during the FA deposit
                    // (so that the proxy contract has a single admin).
                    execute_fa_withdrawal(handler, H160::zero(), withdrawal)
                }
                Err(err) => Ok(precompile_outcome_error!(
                    "FA withdrawal: parsing failed w/ `{err}`"
                )),
            }
        }
        _ => Ok(precompile_outcome_error!(
            "FA withdrawal: unexpected selector"
        )),
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use alloy_sol_types::SolCall;
    use evm::{Config, ExitError, ExitReason};
    use primitive_types::{H160, U256};
    use tezos_smart_rollup_mock::MockHost;

    use crate::{
        account_storage::{init_account_storage, EthereumAccountStorage},
        fa_bridge::{
            deposit::ticket_hash,
            test_utils::{
                convert_h160, convert_u256, dummy_first_block, dummy_ticket,
                kernel_wrapper, set_balance, ticket_balance_add, ticket_id,
            },
        },
        handler::{EvmHandler, ExecutionOutcome, ExtendedExitReason},
        precompiles::{self, FA_BRIDGE_PRECOMPILE_ADDRESS},
        transaction::TransactionContext,
        utilities::{bigint_to_u256, keccak256_hash},
    };

    fn execute_precompile(
        host: &mut MockHost,
        evm_account_storage: &mut EthereumAccountStorage,
        caller: H160,
        value: Option<U256>,
        input: Vec<u8>,
        gas_limit: Option<u64>,
        is_static: bool,
    ) -> ExecutionOutcome {
        let block = dummy_first_block();
        let config = Config::shanghai();
        let callee = FA_BRIDGE_PRECOMPILE_ADDRESS;

        let precompiles = precompiles::precompile_set::<MockHost>(true);

        let mut handler = EvmHandler::new(
            host,
            evm_account_storage,
            caller,
            &block,
            &config,
            &precompiles,
            1_000_000_000,
            U256::from(21000),
            false,
            None,
        );

        handler
            .call_contract(caller, callee, value, input, gas_limit, is_static)
            .expect("Failed to invoke precompile")
    }

    #[test]
    fn fa_bridge_precompile_fails_due_to_bad_selector() {
        let mut mock_runtime = MockHost::default();
        let mut evm_account_storage = init_account_storage().unwrap();

        let outcome = execute_precompile(
            &mut mock_runtime,
            &mut evm_account_storage,
            H160::from_low_u64_be(1),
            None,
            vec![0x00, 0x01, 0x02, 0x03],
            None,
            false,
        );
        assert!(!outcome.is_success());
        assert!(
            matches!(outcome.reason, ExtendedExitReason::Exit(ExitReason::Error(ExitError::Other(err))) if err.contains("unexpected selector"))
        );
    }

    #[test]
    fn fa_bridge_precompile_fails_due_to_low_gas_limit() {
        let mut mock_runtime = MockHost::default();
        let mut evm_account_storage = init_account_storage().unwrap();

        let outcome = execute_precompile(
            &mut mock_runtime,
            &mut evm_account_storage,
            H160::from_low_u64_be(1),
            None,
            vec![0x80, 0xfc, 0x1f, 0xe3],
            // Cover only basic cost
            Some(21000 + 16 * 4),
            false,
        );
        assert!(!outcome.is_success());
        assert!(
            matches!(outcome.reason, ExtendedExitReason::Exit(ExitReason::Error(ExitError::Other(err))) if err.contains("gas limit too low"))
        );
    }

    #[test]
    fn fa_bridge_precompile_fails_due_to_non_zero_value() {
        let mut mock_runtime = MockHost::default();
        let mut evm_account_storage = init_account_storage().unwrap();

        let caller = H160::from_low_u64_be(1);
        set_balance(
            &mut mock_runtime,
            &mut evm_account_storage,
            &caller,
            1_000_000_000.into(),
        );

        let outcome = execute_precompile(
            &mut mock_runtime,
            &mut evm_account_storage,
            caller,
            Some(1_000_000_000.into()),
            vec![0x80, 0xfc, 0x1f, 0xe3],
            None,
            false,
        );
        assert!(!outcome.is_success());
        assert!(
            matches!(outcome.reason, ExtendedExitReason::Exit(ExitReason::Error(ExitError::Other(err))) if err.contains("unexpected value transfer"))
        );
    }

    #[test]
    fn fa_bridge_precompile_fails_due_to_static_call() {
        let mut mock_runtime = MockHost::default();
        let mut evm_account_storage = init_account_storage().unwrap();

        let caller = H160::from_low_u64_be(1);
        let outcome = execute_precompile(
            &mut mock_runtime,
            &mut evm_account_storage,
            caller,
            None,
            vec![0x80, 0xfc, 0x1f, 0xe3],
            None,
            true,
        );
        assert!(!outcome.is_success());
        assert!(
            matches!(outcome.reason, ExtendedExitReason::Exit(ExitReason::Error(ExitError::Other(err))) if err.contains("static call not allowed"))
        );
    }

    #[test]
    fn fa_bridge_precompile_fails_due_to_delegate_call() {
        let mut mock_runtime = MockHost::default();
        let mut evm_account_storage = init_account_storage().unwrap();

        let caller = H160::from_low_u64_be(1);
        let callee = H160::from_low_u64_be(2);
        let block = dummy_first_block();
        let config = Config::shanghai();

        let precompiles = precompiles::precompile_set::<MockHost>(true);

        let mut handler = EvmHandler::new(
            &mut mock_runtime,
            &mut evm_account_storage,
            caller,
            &block,
            &config,
            &precompiles,
            1_000_000_000,
            U256::from(21000),
            false,
            None,
        );

        handler.begin_initial_transaction(false, None).unwrap();

        let result = handler.execute_call(
            FA_BRIDGE_PRECOMPILE_ADDRESS,
            None,
            vec![0x80, 0xfc, 0x1f, 0xe3],
            TransactionContext::new(caller, callee, U256::zero()),
        );

        let outcome = handler.end_initial_transaction(result).unwrap();

        assert!(!outcome.is_success());
        assert!(
            matches!(outcome.reason, ExtendedExitReason::Exit(ExitReason::Error(ExitError::Other(err))) if err.contains("delegate call not allowed"))
        );
    }

    #[test]
    fn fa_bridge_precompile_fails_due_to_invalid_input() {
        let mut mock_runtime = MockHost::default();
        let mut evm_account_storage = init_account_storage().unwrap();

        let outcome = execute_precompile(
            &mut mock_runtime,
            &mut evm_account_storage,
            H160::from_low_u64_be(1),
            None,
            vec![0x80, 0xfc, 0x1f, 0xe3],
            None,
            false,
        );
        assert!(!outcome.is_success());
        assert!(
            matches!(outcome.reason, ExtendedExitReason::Exit(ExitReason::Error(ExitError::Other(err))) if err.contains("parsing failed"))
        );
    }

    #[test]
    fn fa_bridge_precompile_succeeds_without_l2_proxy_contract() {
        let mut mock_runtime = MockHost::default();
        let mut evm_account_storage = init_account_storage().unwrap();

        let ticket_owner = H160::from_low_u64_be(1);
        let ticket = dummy_ticket();
        let ticket_hash = ticket_hash(&ticket).unwrap();
        let amount = bigint_to_u256(ticket.amount()).unwrap();

        // Patch ticket table
        ticket_balance_add(
            &mut mock_runtime,
            &mut evm_account_storage,
            &ticket_hash,
            &ticket_owner,
            amount,
        );

        let (ticketer, content) = ticket_id(&ticket);

        let routing_info = [
            [0u8; 22].to_vec(),
            vec![0x01],
            [0u8; 20].to_vec(),
            vec![0x00],
        ]
        .concat();

        let input = kernel_wrapper::withdrawCall::new((
            convert_h160(&ticket_owner),
            routing_info.into(),
            convert_u256(&amount),
            ticketer.into(),
            content.into(),
        ))
        .abi_encode();

        let outcome = execute_precompile(
            &mut mock_runtime,
            &mut evm_account_storage,
            ticket_owner,
            None,
            input,
            Some(6000000),
            false,
        );
        assert!(outcome.is_success());
        assert_eq!(1, outcome.withdrawals.len());
        assert_eq!(1, outcome.logs.len());
    }

    #[test]
    fn fa_bridge_precompile_address() {
        assert_eq!(
            FA_BRIDGE_PRECOMPILE_ADDRESS,
            H160::from_str("ff00000000000000000000000000000000000002").unwrap()
        );
    }

    #[test]
    fn fa_bridge_precompile_withdraw_method_id() {
        let method_hash =
            keccak256_hash(b"withdraw(address,bytes,uint256,bytes22,bytes)");
        assert_eq!(method_hash.0[0..4], [0x80, 0xfc, 0x1f, 0xe3]);
    }
}
