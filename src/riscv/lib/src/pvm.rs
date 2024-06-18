// SPDX-FileCopyrightText: 2023 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

pub mod dummy_pvm;
mod sbi;

use crate::{
    machine_state::{self, bus::main_memory, StepManyResult},
    state_backend,
    traps::EnvironException,
};
use sbi::{PvmSbiFatalError, PvmSbiLayout, PvmSbiState};
use std::{
    io::{stdout, Write},
    ops::RangeBounds,
};

/// PVM configuration
pub struct PvmHooks<'a> {
    pub putchar_hook: Box<dyn FnMut(u8) + 'a>,
}

impl<'a> PvmHooks<'a> {
    /// Create a new configuration.
    pub fn new<F: FnMut(u8) + 'a>(putchar: F) -> Self {
        Self {
            putchar_hook: Box::new(putchar),
        }
    }
}

/// The default PVM configuration prints all debug information from the kernel
/// to the standard output.
impl<'a> Default for PvmHooks<'a> {
    fn default() -> Self {
        fn putchar(char: u8) {
            stdout().lock().write_all(&[char]).unwrap();
        }

        Self::new(putchar)
    }
}

/// PVM state layout
pub type PvmLayout<ML> = (
    state_backend::Atom<u64>,
    machine_state::MachineStateLayout<ML>,
    PvmSbiLayout,
);

/// PVM status
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum PvmStatus {
    Evaluating,
    WaitingForInput,
    WaitingForMetadata,
}

impl Default for PvmStatus {
    fn default() -> Self {
        Self::Evaluating
    }
}

impl TryFrom<u8> for PvmStatus {
    type Error = u8;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        const EVALUATING: u8 = PvmStatus::Evaluating as u8;
        const WAITING_FOR_INPUT: u8 = PvmStatus::WaitingForInput as u8;
        const WAITING_FOR_METADATA: u8 = PvmStatus::WaitingForMetadata as u8;

        match value {
            EVALUATING => Ok(Self::Evaluating),
            WAITING_FOR_INPUT => Ok(Self::WaitingForInput),
            WAITING_FOR_METADATA => Ok(Self::WaitingForMetadata),
            _ => Err(value),
        }
    }
}

impl From<PvmStatus> for u8 {
    fn from(value: PvmStatus) -> Self {
        value as u8
    }
}

/// Value for the initial version
const INITIAL_VERSION: u64 = 0;

/// Proof-generating virtual machine
pub struct Pvm<ML: main_memory::MainMemoryLayout, M: state_backend::Manager> {
    version: state_backend::Cell<u64, M>,
    pub(crate) machine_state: machine_state::MachineState<ML, M>,

    /// Execution environment state
    sbi_state: PvmSbiState<M>,
}

impl<ML: main_memory::MainMemoryLayout, M: state_backend::Manager> Pvm<ML, M> {
    /// Bind the PVM to the given allocated region.
    pub fn bind(space: state_backend::AllocatedOf<PvmLayout<ML>, M>) -> Self {
        // Ensure we're binding a version we can deal with
        assert_eq!(space.0.read(), INITIAL_VERSION);

        Self {
            version: space.0,
            machine_state: machine_state::MachineState::bind(space.1),
            sbi_state: PvmSbiState::<M>::bind(space.2),
        }
    }

    /// Reset the PVM state.
    pub fn reset(&mut self) {
        self.version.write(INITIAL_VERSION);
        self.machine_state.reset();
        self.sbi_state.reset();
    }

    /// Handle an exception using the defined Execution Environment.
    pub fn handle_exception(
        &mut self,
        hooks: &mut PvmHooks<'_>,
        exception: EnvironException,
    ) -> Result<bool, PvmSbiFatalError> {
        match exception {
            EnvironException::EnvCallFromUMode
            | EnvironException::EnvCallFromSMode
            | EnvironException::EnvCallFromMMode => {
                self.sbi_state
                    .handle_call(&mut self.machine_state, hooks, exception)
            }
        }
    }

    /// Perform one evaluation step.
    pub fn eval_one(&mut self, hooks: &mut PvmHooks<'_>) -> Result<(), EvalError> {
        if let Err(exc) = self.machine_state.step() {
            if let Err(err) = self.handle_exception(hooks, exc) {
                return Err(EvalError {
                    cause: exc,
                    error: err,
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
    pub fn eval_range_while<F>(
        &mut self,
        hooks: &mut PvmHooks<'_>,
        step_bounds: &impl RangeBounds<usize>,
        should_continue: F,
    ) -> EvalManyResult
    where
        F: FnMut(&machine_state::MachineState<ML, M>) -> bool,
    {
        self.machine_state
            .step_range_handle(step_bounds, should_continue, |machine_state, exc| {
                self.sbi_state
                    .handle_call(machine_state, hooks, exc)
                    .map_err(|err| EvalError {
                        cause: exc,
                        error: err,
                    })
            })
    }

    /// Respond to a request for input with no input. Returns `false` in case the
    /// machine wasn't expecting any input, otherwise returns `true`.
    pub fn provide_no_input(&mut self) -> bool {
        self.sbi_state.provide_no_input(&mut self.machine_state)
    }

    /// Provide input. Returns `false` if the machine state is not expecting
    /// input.
    pub fn provide_input(&mut self, level: u64, counter: u64, payload: &[u8]) -> bool {
        self.sbi_state
            .provide_input(&mut self.machine_state, level, counter, payload)
    }

    /// Provide metadata in response to a metadata request. Returns `false`
    /// if the machine is not expecting metadata.
    pub fn provide_metadata(&mut self, rollup_address: &[u8; 20], origination_level: u64) -> bool {
        self.sbi_state
            .provide_metadata(&mut self.machine_state, rollup_address, origination_level)
    }

    /// Get the current machine status.
    pub fn status(&self) -> PvmStatus {
        self.sbi_state.status()
    }
}

/// Error during evaluation
#[derive(Debug)]
pub struct EvalError {
    pub cause: EnvironException,
    pub error: PvmSbiFatalError,
}

/// Result of [`Pvm::eval_range`]
pub type EvalManyResult = StepManyResult<EvalError>;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
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
        type L = PvmLayout<ML>;

        // Setup PVM
        let (mut backend, placed) = InMemoryBackend::<L>::new();
        let space = backend.allocate(placed);
        let mut pvm = Pvm::<ML, _>::bind(space);
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
        assert!(matches!(outcome, Ok(false)));

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
        type L = PvmLayout<ML>;

        let mut buffer = Vec::new();
        let mut hooks = PvmHooks::new(|c| buffer.push(c));

        // Setup PVM
        let (mut backend, placed) = InMemoryBackend::<L>::new();
        let space = backend.allocate(placed);
        let mut pvm = Pvm::<ML, _>::bind(space);
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

            let outcome = pvm.handle_exception(&mut hooks, EnvironException::EnvCallFromUMode);
            assert!(
                matches!(outcome, Ok(true)),
                "Unexpected outcome: {outcome:?}"
            );
        }

        // Drop `hooks` to regain access to the mutable references it kept
        mem::drop(hooks);

        // Compare what characters have been passed to the hook verrsus what we
        // intended to write
        assert_eq!(written, buffer);
    }
}
