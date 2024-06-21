// SPDX-FileCopyrightText: 2024 Nomadic Labs <contact@nomadic-labs.com>
//
// SPDX-License-Identifier: MIT

//! Reservation set for Load-Reserved/Store-Conditional instructions
//! in the RISC-V A extension
//!
//! Section 8.2 - Unprivileged spec

/// Executing a LR.x instructions registers a reservation set on the address
/// from which data was loaded. The success of a SC.x instruction is conditional
/// on there being a valid reservation which includes the word or doubleword
/// being stored. Every SC.x, wether successful or not, invalidates the hart's
/// reservation set.
///
/// "The invalidation of a hart’s reservation when it executes an LR or SC implies
/// that a hart can only hold one reservation at a time, and that an SC can only
/// pair with the most recent LR, and LR with the next following SC, in program
/// order."
use crate::{
    machine_state::backend::{self, Cell},
    state_backend::{CellRead, CellWrite},
};

pub struct ReservationSet<M: backend::Manager> {
    start_addr: Cell<u64, M>,
}

/// Layout for [ReservationSet]
pub type ReservationSetLayout = backend::Atom<u64>;

/// The size of the reservation set is 8 bytes in order to accommodate
/// LR.D/SC.D instructions which work on doubles.
///
/// "An implementation can register an arbitrarily large reservation set on
/// each LR, provided the reservation set includes all bytes of the addressed
/// data word or doubleword. [...] The Unix platform is expected to require of
/// main memory that the reservation set be of fixed size, contiguous, naturally
/// aligned, and no greater than the virtual memory page size."
const SIZE: u64 = 8;

const UNSET_VALUE: u64 = u64::MAX;

const fn align_address(address: u64, align: u64) -> u64 {
    let offset = address.rem_euclid(align);
    if offset > 0 {
        return address + align - offset;
    }
    address
}

impl<M: backend::Manager> ReservationSet<M> {
    #[inline(always)]
    fn write(&mut self, addr: u64) {
        self.start_addr.write(addr)
    }

    #[inline(always)]
    fn read(&self) -> u64 {
        self.start_addr.read()
    }

    /// Bind the reservation set cell to the given allocated space
    pub fn bind(space: backend::AllocatedOf<ReservationSetLayout, M>) -> Self {
        Self { start_addr: space }
    }

    /// Unset any reservation
    pub fn reset(&mut self) {
        self.write(UNSET_VALUE);
    }

    /// Set the reservation set as `addr` aligned to the nearest double
    pub fn set(&mut self, addr: u64) {
        self.write(align_address(addr, SIZE))
    }

    /// Check wether the `addr` is within the reservation set
    pub fn test_and_unset(&mut self, addr: u64) -> bool {
        let start_addr = self.read();
        // Regardless of success or failure, executing an SC.x instruction
        // invalidates any reservation held by this hart.
        self.reset();
        start_addr != UNSET_VALUE && start_addr == align_address(addr, SIZE)
    }
}
