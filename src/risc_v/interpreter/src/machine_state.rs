// SPDX-FileCopyrightText: 2023 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

#![deny(rustdoc::broken_intra_doc_links)]

pub mod bus;
pub mod csregisters;
pub mod hart_state;
pub mod mode;
pub mod registers;

#[cfg(test)]
extern crate proptest;

use self::{
    bus::{Addressable, OutOfBounds},
    hart_state::{HartState, HartStateLayout},
};
use crate::{program::Program, state_backend as backend};
use bus::{main_memory, Address, Bus};

/// RISC-V exceptions
#[derive(PartialEq, Eq, thiserror::Error, strum::Display, Debug)]
pub enum Exception {
    IllegalInstruction,
    Breakpoint,
    LoadAccessFault,
    StoreAccessFault,
    EnvCallFromUMode,
    EnvCallFromSMode,
    EnvCallFromMMode,
}

/// Layout for the machine state
pub type MachineStateLayout<ML> = (HartStateLayout, bus::BusLayout<ML>);

/// Machine state
pub struct MachineState<ML: main_memory::MainMemoryLayout, M: backend::Manager> {
    pub hart: HartState<M>,
    pub bus: Bus<ML, M>,
}

impl<ML: main_memory::MainMemoryLayout, M: backend::Manager> MachineState<ML, M> {
    /// Bind the machine state to the given allocated space.
    pub fn bind(space: backend::AllocatedOf<MachineStateLayout<ML>, M>) -> Self {
        Self {
            hart: HartState::bind(space.0),
            bus: Bus::bind(space.1),
        }
    }

    /// Reset the machine state.
    pub fn reset(&mut self) {
        self.hart.reset(bus::start_of_main_memory::<ML>());
        self.bus.reset();
    }

    /// Perform one instruction.
    pub fn step(&mut self) {
        // TODO: https://gitlab.com/tezos/tezos/-/issues/6944
        // Implement stepper function
        todo!("Step function is not implemented")
    }

    /// Perform at most `max` instructions. Returns the actual number of
    /// instructions that have been performed.
    pub fn step_many<F: FnMut(&Self) -> bool>(
        &mut self,
        max: usize,
        mut should_continue: F,
    ) -> usize {
        let mut steps_done = 0;

        while steps_done < max && should_continue(self) {
            self.step();
            steps_done += 1;
        }

        steps_done
    }

    /// Install a program and set the program counter to its start.
    pub fn setup_boot(&mut self, program: &Program) -> Result<(), MachineError> {
        // Write program to main memory and point the PC at its start
        for (addr, data) in program.segments.iter() {
            self.bus.write_all(*addr, data)?;
        }
        self.hart.pc.write(program.entrypoint);

        // Set booting Hart ID (a0) to 0
        self.hart.xregisters.write(registers::a0, 0);

        // TODO: https://gitlab.com/tezos/tezos/-/issues/6941
        // Write device tree
        let dtb_addr = program
            .segments
            .iter()
            .map(|(base, data)| base + data.len() as Address)
            .max()
            .unwrap_or(bus::start_of_main_memory::<ML>());

        // Point DTB boot argument (a1) at the written device tree
        self.hart.xregisters.write(registers::a1, dtb_addr);

        // Start in supervisor mode
        self.hart.mode.write(mode::Mode::Supervisor);

        // Make sure to forward all exceptions and interrupts to supervisor mode
        self.hart
            .csregisters
            .write(csregisters::CSRegister::medeleg, !0);
        self.hart
            .csregisters
            .write(csregisters::CSRegister::mideleg, !0);

        Ok(())
    }
}

/// Errors that occur from interacting with the [MachineState]
#[derive(Debug, Clone, derive_more::From)]
pub enum MachineError {
    AddressError(OutOfBounds),
}

#[cfg(test)]
mod tests {
    use super::{
        backend::tests::{test_determinism, ManagerFor},
        bus::main_memory::tests::T1K,
        mode, MachineState, MachineStateLayout,
    };
    use crate::backend_test;

    backend_test!(test_machine_state_reset, F, {
        test_determinism::<F, MachineStateLayout<T1K>, _>(|space| {
            let mut machine: MachineState<T1K, ManagerFor<'_, F, MachineStateLayout<T1K>>> =
                MachineState::bind(space);
            machine.reset();
        });
    });
}
