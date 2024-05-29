// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use crate::{
    cli::{BenchMode, BenchRunOptions},
    commands::bench::{
        data::{BenchData, FineBenchData, InstrGetError, InstrType, SimpleBenchData},
        save_to_file, show_results, BenchStats,
    },
    posix_exit_mode,
};
use enum_tag::EnumTag;
use octez_riscv::{
    exec_env::posix::Posix,
    machine_state::bus::Address,
    parser::{instruction::Instr, parse},
    stepper::test::{TestStepper, TestStepperResult},
};
use std::{error::Error, path::Path};

/// Helper function to look in the [`Interpreter`] to peek for the current [`Instr`]
/// Assumes the program counter will be a multiple of 2.
fn get_current_instr(interpreter: &TestStepper) -> Result<Instr, InstrGetError> {
    let get_half_instr = |raw_pc: Address| -> Result<u16, InstrGetError> {
        let pc = interpreter
            .translate_instruction_address(raw_pc)
            .or(Err(InstrGetError::Translation))?;
        interpreter.read_bus(pc).or(Err(InstrGetError::Parse))
    };
    let pc = interpreter.read_pc();
    let first = get_half_instr(pc)?;
    let second = || get_half_instr(pc + 2);
    parse(first, second)
}

/// Composes "in time" two [`InterpreterResult`] one after another,
/// to obtain the equivalent final [`InterpreterResult`]
fn compose(
    current_state: TestStepperResult,
    following_result: TestStepperResult,
) -> TestStepperResult {
    use TestStepperResult::*;
    match current_state {
        Exit { .. } => current_state,
        Exception { .. } => current_state,
        Running(prev_steps) => match following_result {
            Exit { code, steps } => Exit {
                code,
                steps: prev_steps + steps,
            },
            Exception {
                cause,
                steps,
                message,
            } => Exception {
                cause,
                message,
                steps: prev_steps + steps,
            },
            Running(steps) => Running(prev_steps + steps),
        },
    }
}

fn bench_fine(interpreter: &mut TestStepper, opts: &BenchRunOptions) -> BenchData {
    let mut run_res = TestStepperResult::Running(0);
    let mut bench_data = FineBenchData::new();
    let bench_start = quanta::Instant::now();

    for _step in 0..opts.common.max_steps {
        let instr = match get_current_instr(interpreter) {
            Ok(instr) => InstrType::Instr(instr.tag()),
            Err(err) => InstrType::FetchErr(err),
        };

        let start = quanta::Instant::now();
        let step_res = interpreter.run(1);
        let step_duration = start.elapsed();

        bench_data.add_instr(instr, step_duration);

        run_res = compose(run_res, step_res);
        match run_res {
            TestStepperResult::Exit { .. } => break,
            TestStepperResult::Exception { .. } => break,
            TestStepperResult::Running(_) => (),
        }
    }
    let bench_duration = bench_start.elapsed();

    BenchData::from_fine(bench_data, bench_duration, run_res)
}

/// A single run of the given `interpreter`.
/// Provides basic benchmark data and interpreter result.
fn bench_simple(interpreter: &mut TestStepper, opts: &BenchRunOptions) -> BenchData {
    let start = quanta::Instant::now();
    let res = interpreter.run(opts.common.max_steps);
    let duration = start.elapsed();

    use TestStepperResult::*;
    let steps = match res {
        Exit { steps, .. } => steps,
        Running(steps) => steps,
        Exception { steps, .. } => steps,
    };
    let data = SimpleBenchData::new(duration, steps);

    BenchData::from_simple(data, res)
}

fn bench_iteration(path: &Path, opts: &BenchRunOptions) -> Result<BenchData, Box<dyn Error>> {
    let contents = std::fs::read(path)?;
    let mut backend = TestStepper::<'_, Posix>::create_backend();
    let mut interpreter = TestStepper::new(
        &mut backend,
        &contents,
        None,
        posix_exit_mode(&opts.common.posix_exit_mode),
    )?;

    let data = match opts.mode {
        BenchMode::Simple => bench_simple(&mut interpreter, opts),
        BenchMode::Fine => bench_fine(&mut interpreter, opts),
    };
    Ok(data)
}

pub fn run(opts: BenchRunOptions) -> Result<(), Box<dyn Error>> {
    let mut stats = opts
        .inputs
        .iter()
        .filter_map(|path| run_binary(path, &opts).ok())
        .reduce(|acc, e| e.combine(acc))
        .ok_or("Could not combine benchmark results".to_string())?;
    stats.normalize_instr_data();
    save_to_file(&stats, &opts)?;
    show_results(&stats, &opts);
    Ok(())
}

fn run_binary(path: &Path, opts: &BenchRunOptions) -> Result<BenchStats, Box<dyn Error>> {
    let stats = match opts.repeat {
        0 | 1 => BenchStats::from_data(bench_iteration(path, opts)?)?,
        iterations => {
            let mut data_list = vec![];
            for _ in 0..iterations {
                data_list.push(bench_iteration(path, opts)?)
            }
            BenchStats::from_data_list(data_list)?
        }
    };
    Ok(stats)
}
