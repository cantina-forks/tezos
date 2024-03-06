// SPDX-FileCopyrightText: 2024 Functori <contact@functori.com>
// SPDX-FileCopyrightText: 2023 draganrakita
//
// SPDX-License-Identifier: MIT

use std::{
    borrow::Cow,
    cmp::{max, min},
};

use crate::{
    handler::EvmHandler,
    precompiles::PrecompileOutcome,
    utilities::{get_right_padded, get_right_padded_vec, left_padding, left_padding_vec},
    EthereumError,
};
use aurora_engine_modexp::modexp;
use evm::{Context, ExitError, ExitReason, ExitSucceed, Transfer};
use host::runtime::Runtime;
use primitive_types::U256;
use tezos_evm_logging::log;
use tezos_evm_logging::Level::Info;

fn calculate_iteration_count(exp_length: u64, exp_highp: &U256) -> u64 {
    let mut iteration_count: u64 = 0;

    if exp_length <= 32 && *exp_highp == U256::zero() {
        iteration_count = 0;
    } else if exp_length <= 32 {
        iteration_count = exp_highp.bits() as u64 - 1;
    } else if exp_length > 32 {
        iteration_count = (8 * (exp_length - 32)) + max(1, exp_highp.bits() as u64) - 1;
    }

    max(iteration_count, 1)
}

// Calculate gas cost according to EIP 2565:
// https://eips.ethereum.org/EIPS/eip-2565
fn gas_calc(base_length: u64, exp_length: u64, mod_length: u64, exp_highp: &U256) -> u64 {
    fn calculate_multiplication_complexity(base_length: u64, mod_length: u64) -> U256 {
        let max_length = max(base_length, mod_length);
        let mut words = max_length / 8;
        if max_length % 8 > 0 {
            words += 1;
        }
        let words = U256::from(words);
        words * words
    }

    let multiplication_complexity =
        calculate_multiplication_complexity(base_length, mod_length);
    let iteration_count = calculate_iteration_count(exp_length, exp_highp);
    let gas = (multiplication_complexity * U256::from(iteration_count)) / U256::from(3);

    if gas.0[1] != 0 || gas.0[2] != 0 || gas.0[3] != 0 {
        u64::MAX
    } else {
        max(200, gas.0[0])
    }
}

fn modexp_mod_overflow_exit(reason: &'static str) -> PrecompileOutcome {
    PrecompileOutcome {
        exit_status: ExitReason::Error(ExitError::Other(Cow::Borrowed(reason))),
        output: vec![],
        withdrawals: vec![],
        estimated_ticks: 0,
    }
}

// The format of input is:
// <length_of_BASE> <length_of_EXPONENT> <length_of_MODULUS> <BASE> <EXPONENT> <MODULUS>
// Where every length is a 32-byte left-padded integer representing the number of bytes
// to be taken up by the next value
const HEADER_LENGTH: usize = 96;

pub fn modexp_precompile<Host: Runtime>(
    handler: &mut EvmHandler<Host>,
    input: &[u8],
    _context: &Context,
    _is_static: bool,
    _transfer: Option<Transfer>,
) -> Result<PrecompileOutcome, EthereumError> {
    log!(handler.borrow_host(), Info, "Calling modexp precompile");

    // Extract the header.
    let base_len = U256::from_big_endian(&get_right_padded::<32>(input, 0));
    let exp_len = U256::from_big_endian(&get_right_padded::<32>(input, 32));
    let mod_len = U256::from_big_endian(&get_right_padded::<32>(input, 64));

    let estimated_ticks = tick::model(base_len, exp_len, mod_len);

    // cast base and modulus to usize, it does not make sense to handle larger values
    let Ok(base_len) = usize::try_from(base_len) else {
        return Ok(modexp_mod_overflow_exit("base length: modexp mod overflow"));
    };
    // cast mod length to usize, it does not make sense to handle larger values.
    let Ok(mod_len) = usize::try_from(mod_len) else {
        return Ok(modexp_mod_overflow_exit("mod length: modexp mod overflow"));
    };

    // Handle a special case when both the base and mod length is zero
    if base_len == 0 && mod_len == 0 {
        if let Err(err) = handler.record_cost(200) {
            return Ok(PrecompileOutcome {
                exit_status: ExitReason::Error(err),
                output: vec![],
                withdrawals: vec![],
                estimated_ticks,
            });
        }

        return Ok(PrecompileOutcome {
            exit_status: ExitReason::Succeed(ExitSucceed::Returned),
            output: vec![],
            withdrawals: vec![],
            estimated_ticks,
        });
    }

    // cast exponent length to usize, it does not make sense to handle larger values.
    let Ok(exp_len) = usize::try_from(exp_len) else {
        return Ok(modexp_mod_overflow_exit("exponent length: modexp mod overflow"));
    };

    // Used to extract ADJUSTED_EXPONENT_LENGTH.
    let exp_highp_len = min(exp_len, 32);

    // throw away the header data as we already extracted lengths.
    let input = if input.len() >= HEADER_LENGTH {
        &input[HEADER_LENGTH..]
    } else {
        // or set input to zero if there is no more data
        &[]
    };

    let exp_highp = {
        // get right padded bytes so if data.len is less then exp_len we will get right padded zeroes.
        let right_padded_highp = get_right_padded::<32>(input, base_len);
        // If exp_len is less then 32 bytes get only exp_len bytes and do left padding.
        let out = left_padding::<32>(&right_padded_highp[..exp_highp_len]);
        U256::from_big_endian(&out)
    };

    // calculate gas spent.
    let gas_cost = gas_calc(base_len as u64, exp_len as u64, mod_len as u64, &exp_highp);

    if let Err(err) = handler.record_cost(gas_cost) {
        return Ok(PrecompileOutcome {
            exit_status: ExitReason::Error(err),
            output: vec![],
            withdrawals: vec![],
            estimated_ticks,
        });
    }

    // Padding is needed if the input does not contain all 3 values.
    let base = get_right_padded_vec(input, 0, base_len);
    let exponent = get_right_padded_vec(input, base_len, exp_len);
    let modulus = get_right_padded_vec(input, base_len.saturating_add(exp_len), mod_len);

    // Call the modexp.
    let output = modexp(&base, &exponent, &modulus);

    Ok(PrecompileOutcome {
        exit_status: ExitReason::Succeed(ExitSucceed::Returned),
        // left pad the result to modulus length. bytes will always by less or equal to modulus length.
        output: left_padding_vec(&output, mod_len),
        withdrawals: vec![],
        estimated_ticks,
    })
}

mod tick {
    use primitive_types::U256;

    const MIN_LEADING_ZEROS: u32 = 256 - 32;
    const TICKS_BASE_COST: u64 = 100_000;

    const ESIZE_FACTOR1: u64 = 241;
    const ESIZE_FACTOR2: u64 = 6480;
    const ESIZE_FACTOR3: u64 = 114172;
    const MSIZE_FACTOR: u64 = 9346;
    const CONSTANT_TERM: u64 = 112053;

    pub fn model(bsize: U256, esize: U256, msize: U256) -> u64 {
        // If either of bsize, esize or msize are bigger than what can be held in 63 bits, then
        // the number of ticks needed to compute modexp is way too high.
        if bsize.leading_zeros() < MIN_LEADING_ZEROS {
            return TICKS_BASE_COST;
        }
        if esize.leading_zeros() < MIN_LEADING_ZEROS {
            return TICKS_BASE_COST;
        }
        if msize.leading_zeros() < MIN_LEADING_ZEROS {
            return TICKS_BASE_COST;
        }

        let esize: u64 = esize.low_u64();
        let msize: u64 = msize.low_u64();

        let estimated_ticks = ESIZE_FACTOR1 * msize * msize * esize
            + ESIZE_FACTOR2 * msize * esize
            + ESIZE_FACTOR3 * esize
            + MSIZE_FACTOR * msize
            + CONSTANT_TERM;

        estimated_ticks.max(TICKS_BASE_COST)
    }
}
