// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
// SPDX-FileCopyrightText: 2024 Nomadic Labs <contact@nomadic-labs.com>
//
// SPDX-License-Identifier: MIT

use super::{DebuggerApp, Instruction, PC_CONTEXT};
use octez_riscv::{
    machine_state::{bus::Address, csregisters::CSRegister, AccessType},
    parser::{instruction::Instr, parse},
    stepper::test::InterpreterResult,
};
use std::{collections::HashMap, ops::Range};

impl<'a> DebuggerApp<'a> {
    pub(super) fn update_after_step(&mut self, result: InterpreterResult) {
        let (pc, faulting) = self.update_pc_after_step();
        self.update_translation_after_step(faulting);
        self.update_instr_list(pc);

        self.program.next_instr = self
            .program
            .instructions
            .iter()
            .position(|instr| instr.address == pc)
            .unwrap_or_else(|| {
                panic!("pc {pc:x} does not correspond to any instruction's address")
            });

        self.program.state.select(Some(self.program.next_instr));
        self.state.interpreter = result;
    }

    /// Even if pc is not updated, the selected instruction can change,
    /// needing to update the "surrounding" addresses for new instructions.
    pub(super) fn update_selected_context(&mut self) -> Option<()> {
        let selected_offset = self.program.state.selected()?;
        let selected_instr = self.program.instructions.get(selected_offset)?;
        let selected_pc = selected_instr.address;
        self.update_instr_list(selected_pc as Address);
        Some(())
    }

    /// Returns the physical program counter, and if the translation algorithm is faulting
    fn update_pc_after_step(&mut self) -> (Address, bool) {
        let raw_pc = self.interpreter.read_pc();
        let res @ (pc, _faulting) = match self.interpreter.translate_instruction_address(raw_pc) {
            Err(_e) => (self.state.prev_pc, true),
            Ok(pc) => (pc, false),
        };

        self.state.prev_pc = pc;

        res
    }

    /// Updates the state of [`super::TranslationState`]
    fn update_translation_after_step(&mut self, faulting: bool) {
        let effective_mode = self
            .interpreter
            .effective_translation_alg(&AccessType::Instruction);
        let satp_val = self.interpreter.read_csregister(CSRegister::satp);
        self.state
            .translation
            .update(faulting, effective_mode, satp_val)
    }

    /// Given a continuous block of bytes at given `offset`,
    /// return a list of successfully parsed instructions and where they are located.
    /// (nothing guarantees the whole block of memory has valid instructions)
    fn get_addressed_instr(&self, (offset, halfs): (Address, Vec<u16>)) -> Vec<(Address, Instr)> {
        let n = halfs.len();
        let mut i = 0;
        let mut res = vec![];

        while i < n {
            let instr_address = offset + 2 * i as u64;
            let first = halfs[i];
            let second = || {
                if i + 1 < n {
                    i += 1;
                    Ok(halfs[i])
                } else {
                    Err(())
                }
            };

            let _ = parse(first, second)
                .map(|instr| (instr_address, instr))
                .map(|el| res.push(el));

            i += 1;
        }

        res
    }

    /// Obtain a list of [`Instruction`]'s from a given range of bytes in memory.
    fn get_range_instructions(
        &self,
        range: Range<u64>,
        symbols: &HashMap<u64, &str>,
    ) -> Vec<Instruction> {
        let get_u16_at = |addr: Address| -> Option<(Address, u16)> {
            self.interpreter
                .read_bus(addr)
                .ok()
                .map(|bytes| (addr, bytes))
        };

        let instr_halfs = range.clone().step_by(2).filter_map(get_u16_at);

        // Not all memory in the range is readable from the bus.
        // Obtain all the contiguous areas of accessible memory
        let mut last_addr = None;
        let mut groups: Vec<(Address, Vec<u16>)> = vec![];
        instr_halfs.for_each(|(addr, bytes)| {
            if Some(addr - 2) == last_addr {
                if let Some((_offset, halfs)) = groups.last_mut() {
                    halfs.push(bytes)
                }
            } else {
                groups.push((addr, vec![bytes]));
            }
            last_addr = Some(addr);
        });

        groups
            .into_iter()
            .flat_map(|g| self.get_addressed_instr(g))
            .map(|(addr, instr)| Instruction::new(addr, instr.to_string(), symbols))
            .filter(|i| !i.text.contains("unknown"))
            .collect()
    }

    /// Get a range of bytes around `pc` and try to introduce the newly
    /// discovered instructions in the existing list of [`Instruction`]
    fn update_instr_list(&mut self, pc: Address) {
        let pc = pc - pc % 4;
        let range = pc - PC_CONTEXT * 4..pc + PC_CONTEXT * 4;
        let instructions = self.get_range_instructions(range, &self.program.symbols);
        self.program.partial_update(instructions);
    }
}
