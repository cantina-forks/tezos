// SPDX-FileCopyrightText: 2023 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

// Allow dead code while this module contains stubs.
#![allow(dead_code)]

pub mod dummy_pvm;

use crate::{
    exec_env::{
        self,
        pvm::{PvmSbi, PvmStatus},
        ExecutionEnvironment, ExecutionEnvironmentState,
    },
    machine_state::{self, bus::main_memory, StepManyResult},
    range_utils::{range_bounds_saturating_sub, range_max, range_min},
    state_backend,
    traps::EnvironException,
};
use std::ops::RangeBounds;

/// PVM state layout
pub type PvmLayout<EE, ML> = (
    state_backend::Atom<u64>,
    machine_state::MachineStateLayout<ML>,
    <EE as ExecutionEnvironment>::Layout,
);

/// Value for the initial version
const INITIAL_VERSION: u64 = 0;

/// Proof-generating virtual machine
pub struct Pvm<
    EE: ExecutionEnvironment,
    ML: main_memory::MainMemoryLayout,
    M: state_backend::Manager,
> {
    version: state_backend::Cell<u64, M>,
    pub(crate) machine_state: machine_state::MachineState<ML, M>,

    /// Execution environment state
    pub exec_env_state: EE::State<M>,
}

impl<EE: ExecutionEnvironment, ML: main_memory::MainMemoryLayout, M: state_backend::Manager>
    Pvm<EE, ML, M>
{
    /// Bind the PVM to the given allocated region.
    pub fn bind(space: state_backend::AllocatedOf<PvmLayout<EE, ML>, M>) -> Self {
        // Ensure we're binding a version we can deal with
        assert_eq!(space.0.read(), INITIAL_VERSION);

        Self {
            version: space.0,
            machine_state: machine_state::MachineState::bind(space.1),
            exec_env_state: EE::State::<M>::bind(space.2),
        }
    }

    /// Reset the PVM state.
    pub fn reset(&mut self) {
        self.version.write(INITIAL_VERSION);
        self.machine_state.reset();
        self.exec_env_state.reset();
    }

    /// Handle an exception using the defined Execution Environment.
    pub fn handle_exception(
        &mut self,
        config: &mut EE::Config<'_>,
        exception: EnvironException,
    ) -> exec_env::EcallOutcome {
        match exception {
            EnvironException::EnvCallFromUMode
            | EnvironException::EnvCallFromSMode
            | EnvironException::EnvCallFromMMode => {
                self.exec_env_state
                    .handle_call(&mut self.machine_state, config, exception)
            }
        }
    }

    /// Perform one evaluation step.
    pub fn eval_one(&mut self, config: &mut EE::Config<'_>) -> Result<(), EvalError> {
        if let Err(exc) = self.machine_state.step() {
            if let exec_env::EcallOutcome::Fatal { message } = self.handle_exception(config, exc) {
                return Err(EvalError {
                    cause: exc,
                    message,
                });
            }
        }

        Ok(())
    }

    /// Perform a range of evaluation steps. Returns the actual number of steps
    /// performed.
    ///
    /// If an environment trap is raised, handle it and
    /// return the number of retired instructions until the raised trap
    ///
    /// NOTE: instructions which raise exceptions / are interrupted are NOT retired
    ///       See section 3.3.1 for context on retired instructions.
    /// e.g: a load instruction raises an exception but the first instruction
    /// of the trap handler will be executed and retired,
    /// so in the end the load instruction which does not bubble it's exception up to
    /// the execution environment will still retire an instruction, just not itself.
    /// (a possible case: the privilege mode access violation is treated in EE,
    /// but a page fault is not)

    // Trampoline style function for [eval_range]
    pub fn eval_range<F>(
        &mut self,
        config: &mut EE::Config<'_>,
        step_bounds: &impl RangeBounds<usize>,
        mut should_continue: F,
    ) -> EvalManyResult
    where
        F: FnMut(&machine_state::MachineState<ML, M>) -> bool,
    {
        let min = range_min(step_bounds);
        let max = range_max(step_bounds);
        let mut bounds = min..=max;

        // initial state
        let mut total_steps: usize = 0;

        // Evaluation loop.
        // Runs the evaluation function until either:
        // reached the max steps,
        // or has stopped at an exception, handled or otherwise
        let error = loop {
            let StepManyResult {
                mut steps,
                exception,
            } = self.machine_state.step_range(&bounds, &mut should_continue);

            total_steps = total_steps.saturating_add(steps);

            if let Some(exc) = exception {
                // Raising the exception is not a completed step. Trying to handle it is.
                // We don't have to check against `max_steps` because running the
                // instruction that triggered the exception meant that `max_steps > 0`.
                total_steps = total_steps.saturating_add(1);
                steps = steps.saturating_add(1);

                match self.handle_exception(config, exc) {
                    // EE encountered an error.
                    exec_env::EcallOutcome::Fatal { message } => {
                        break Some(EvalError {
                            cause: exc,
                            message,
                        });
                    }

                    // EE hints we may continue evaluation.
                    exec_env::EcallOutcome::Handled {
                        continue_eval: true,
                    } => {
                        // update min max by shifting the bounds
                        bounds = range_bounds_saturating_sub(&bounds, steps);
                        // loop
                        continue;
                    }

                    // EE suggests to stop evaluation.
                    exec_env::EcallOutcome::Handled {
                        continue_eval: false,
                    } => {
                        break None;
                    }
                }
            } else {
                break None;
            }
        };
        EvalManyResult {
            steps: total_steps,
            error,
        }
    }
}

impl<ML: main_memory::MainMemoryLayout, M: state_backend::Manager> Pvm<PvmSbi, ML, M> {
    /// Provide input. Returns `false` if the machine state is not expecting
    /// input.
    pub fn provide_input(&mut self, level: u64, counter: u64, payload: &[u8]) -> bool {
        self.exec_env_state
            .provide_input(&mut self.machine_state, level, counter, payload)
    }

    /// Get the current machine status.
    pub fn status(&self) -> PvmStatus {
        self.exec_env_state.status()
    }
}

/// Error during evaluation
#[derive(Debug)]
pub struct EvalError {
    pub cause: EnvironException,
    pub message: String,
}

/// Result of [`Pvm::eval_range`]
pub struct EvalManyResult {
    pub steps: usize,
    pub error: Option<EvalError>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        exec_env::pvm::PvmSbiConfig,
        machine_state::{
            bus::{main_memory::M1M, start_of_main_memory, Addressable},
            registers::{a0, a1, a2, a6, a7},
        },
        state_backend::{memory_backend::InMemoryBackend, Backend},
    };
    use rand::{thread_rng, Fill};
    use std::mem;
    use tezos_smart_rollup_constants::riscv::{
        SBI_CONSOLE_PUTCHAR, SBI_FIRMWARE_TEZOS, SBI_TEZOS_INBOX_NEXT,
    };

    #[test]
    fn test_read_input() {
        type ML = M1M;
        type L = PvmLayout<PvmSbi, ML>;

        // Setup PVM
        let (mut backend, placed) = InMemoryBackend::<L>::new();
        let space = backend.allocate(placed);
        let mut pvm = Pvm::<PvmSbi, ML, _>::bind(space);
        pvm.reset();

        let buffer_addr = start_of_main_memory::<ML>();
        const BUFFER_LEN: usize = 1024;

        // Configure machine for 'sbi_tezos_inbox_next'
        pvm.machine_state.hart.xregisters.write(a0, buffer_addr);
        pvm.machine_state
            .hart
            .xregisters
            .write(a1, BUFFER_LEN as u64);
        pvm.machine_state
            .hart
            .xregisters
            .write(a7, SBI_FIRMWARE_TEZOS);
        pvm.machine_state
            .hart
            .xregisters
            .write(a6, SBI_TEZOS_INBOX_NEXT);

        // Should be in evaluating mode
        assert_eq!(pvm.status(), PvmStatus::Evaluating);

        // Handle the ECALL successfully
        let outcome =
            pvm.handle_exception(&mut Default::default(), EnvironException::EnvCallFromUMode);
        assert!(matches!(
            outcome,
            exec_env::EcallOutcome::Handled {
                continue_eval: false
            }
        ));

        // After the ECALL we should be waiting for input
        assert_eq!(pvm.status(), PvmStatus::WaitingForInput);

        // Respond to the request for input
        let level = rand::random();
        let counter = rand::random();
        let mut payload = [0u8; BUFFER_LEN + 10];
        payload.try_fill(&mut thread_rng()).unwrap();
        assert!(pvm.provide_input(level, counter, &payload));

        // The status should switch from WaitingForInput to Evaluating
        assert_eq!(pvm.status(), PvmStatus::Evaluating);

        // Returned meta data is as expected
        assert_eq!(pvm.machine_state.hart.xregisters.read(a0), level);
        assert_eq!(pvm.machine_state.hart.xregisters.read(a1), counter);
        assert_eq!(
            pvm.machine_state.hart.xregisters.read(a2) as usize,
            BUFFER_LEN
        );

        // Payload in memory should be as expected
        for (offset, &byte) in payload[..BUFFER_LEN].iter().enumerate() {
            let addr = buffer_addr + offset as u64;
            let byte_written: u8 = pvm.machine_state.bus.read(addr).unwrap();
            assert_eq!(
                byte, byte_written,
                "Byte at {addr:x} (offset {offset}) is not the same"
            );
        }

        // Data after the buffer should be untouched
        assert!((BUFFER_LEN..4096)
            .map(|offset| {
                let addr = buffer_addr + offset as u64;
                pvm.machine_state.bus.read(addr).unwrap()
            })
            .all(|b: u8| b == 0));
    }

    #[test]
    fn test_write_debug() {
        type ML = M1M;
        type L = PvmLayout<PvmSbi, ML>;

        let mut buffer = Vec::new();
        let mut pvm_config = PvmSbiConfig::new(|c| buffer.push(c));

        // Setup PVM
        let (mut backend, placed) = InMemoryBackend::<L>::new();
        let space = backend.allocate(placed);
        let mut pvm = Pvm::<PvmSbi, ML, _>::bind(space);
        pvm.reset();

        // Prepare subsequent ECALLs to use the SBI_CONSOLE_PUTCHAR extension
        pvm.machine_state
            .hart
            .xregisters
            .write(a7, SBI_CONSOLE_PUTCHAR);

        // Write characters
        let mut written = Vec::new();
        for _ in 0..10 {
            let char: u8 = rand::random();
            pvm.machine_state.hart.xregisters.write(a0, char as u64);
            written.push(char);

            let outcome = pvm.handle_exception(&mut pvm_config, EnvironException::EnvCallFromUMode);
            assert!(
                matches!(
                    outcome,
                    exec_env::EcallOutcome::Handled {
                        continue_eval: true
                    }
                ),
                "Unexpected outcome: {outcome:?}"
            );
        }

        // Drop `pvm_config` to regain access to the mutable references it kept
        mem::drop(pvm_config);

        // Compare what characters have been passed to the hook verrsus what we
        // intended to write
        assert_eq!(written, buffer);
    }
}
