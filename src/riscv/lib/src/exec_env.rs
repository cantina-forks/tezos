// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

pub mod posix;
pub mod pvm;

use crate::{
    machine_state::{bus::main_memory::MainMemoryLayout, MachineState},
    state_backend::{self, AllocatedOf, Manager},
    traps::EnvironException,
};

/// An execution environment
pub trait ExecutionEnvironment {
    /// Layout of the EE state
    type Layout: state_backend::Layout;

    /// EE state type
    type State<M: Manager>: ExecutionEnvironmentState<M, ExecutionEnvironment = Self>;

    /// Runtime configuration
    type Config<'a>: Default;
}

/// Outcome of handling an ECALL
#[derive(Debug)]
pub enum EcallOutcome {
    /// Handling the ECALL ended in a fatal error
    Fatal { message: String },

    /// ECALL was handled successfully
    Handled { continue_eval: bool },
}

/// State for an execution environment
pub trait ExecutionEnvironmentState<M: Manager> {
    /// Matching execution environment
    type ExecutionEnvironment: ExecutionEnvironment;

    /// Bind the EE state to the allocated regions.
    fn bind(
        space: AllocatedOf<<Self::ExecutionEnvironment as ExecutionEnvironment>::Layout, M>,
    ) -> Self;

    /// Reset the EE state.
    fn reset(&mut self);

    /// Handle a call to the execution environment.
    fn handle_call<ML: MainMemoryLayout>(
        &mut self,
        machine: &mut MachineState<ML, M>,
        config: &mut <Self::ExecutionEnvironment as ExecutionEnvironment>::Config<'_>,
        exception: EnvironException,
    ) -> EcallOutcome;
}
