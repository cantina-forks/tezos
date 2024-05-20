// SPDX-FileCopyrightText: 2023 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use crate::{
    machine_state::csregisters::Privilege,
    state_backend::{EnumCell, EnumCellLayout},
};

/// Modes the hardware state can be in when running code
#[derive(Debug, PartialEq, PartialOrd, Eq, Copy, Clone, strum::EnumIter)]
#[repr(u8)]
pub enum Mode {
    User = 0b000,
    Supervisor = 0b001,
    Machine = 0b011,
}

impl Mode {
    /// Obtain the corresponding [`Privilege`] for [`Mode`].
    pub fn privilege(&self) -> Privilege {
        match self {
            Mode::User => Privilege::Unprivileged,
            Mode::Supervisor => Privilege::Supervisor,
            Mode::Machine => Privilege::Machine,
        }
    }
}

impl TryFrom<u8> for Mode {
    type Error = String;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        let x = match value {
            0 => Mode::User,
            1 => Mode::Supervisor,
            3 => Mode::Machine,
            _ => return Err(format!("Invalid value for Mode: {}", value)),
        };

        Ok(x)
    }
}

impl Default for Mode {
    fn default() -> Self {
        Self::Machine
    }
}

impl From<Mode> for u8 {
    fn from(value: Mode) -> Self {
        value as u8
    }
}

/// Hart mode cell
pub type ModeCell<M> = EnumCell<Mode, u8, M>;

/// Layout for [Mode]
pub type ModeLayout = EnumCellLayout<u8>;

/// Modes the hardware state can trap into, a sub-enum of [`Mode`]
#[derive(Debug, PartialEq, PartialOrd, Eq, Copy, Clone, strum::EnumIter)]
#[repr(u8)]
pub enum TrapMode {
    Supervisor = Mode::Supervisor as u8,
    Machine = Mode::Machine as u8,
}

impl TrapMode {
    /// Construct the mode corresponding to the trap mode.
    pub fn as_mode(&self) -> Mode {
        match self {
            Self::Supervisor => Mode::Supervisor,
            Self::Machine => Mode::Machine,
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        backend_test,
        machine_state::{
            backend::{tests::test_determinism, Backend, Layout},
            mode::{Mode, ModeCell, ModeLayout},
        },
    };
    use strum::IntoEnumIterator;

    backend_test!(test_mode_reset, F, {
        test_determinism::<F, ModeLayout, _>(|space| {
            let mut mode1 = ModeCell::bind(space);
            mode1.reset();
        });
    });

    backend_test!(test_mode_read_write, F, {
        let mut backend = F::new::<ModeLayout>();

        Mode::iter().for_each(|mode| {
            let first_value = mode;
            let offset = {
                let loc = ModeLayout::placed().into_location();
                let offset = loc.offset();
                let mut inst = ModeCell::bind(backend.allocate(loc));

                inst.write(first_value);
                assert_eq!(inst.read_default(), first_value);

                offset
            };

            let first_value_read = &mut [72u8];
            backend.read(offset, first_value_read);
            let value_read = first_value_read[0];
            assert_eq!(Mode::try_from(value_read), Ok(first_value));
        });

        assert!(Mode::try_from(42).is_err());
    });
}
