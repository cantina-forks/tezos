// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

//! Core-logic implementation of F/D instructions.

use crate::{
    machine_state::{
        csregisters::{CSRValue, CSRegister, CSRegisters},
        hart_state::HartState,
        registers::{FRegister, FValue, XRegister},
    },
    parser::instruction::InstrRoundingMode,
    state_backend as backend,
    traps::Exception,
};
use rustc_apfloat::{ieee::Double, ieee::Single, Float, Round, Status, StatusAnd};

pub trait FloatExt: Float + Into<FValue> + Copy
where
    FValue: Into<Self>,
{
    /// The canonical NaN has a positive sign and all
    /// significand bits clear expect the MSB (the quiet bit).
    fn canonical_nan() -> Self;

    /// Canonicalise floating-point values to the canonical nan.
    fn canonicalise(self) -> Self {
        if self.is_nan() {
            Self::canonical_nan()
        } else {
            self
        }
    }
}

impl FloatExt for Single {
    fn canonical_nan() -> Self {
        Self::from_bits(0x7fc00000_u32 as u128)
    }
}

impl FloatExt for Double {
    fn canonical_nan() -> Self {
        Self::from_bits(0x7ff8000000000000_u64 as u128)
    }
}

impl<M> HartState<M>
where
    M: backend::Manager,
{
    /// `FCLASS.*` instruction.
    ///
    /// Examines the value in the floating-point register rs1 and writes
    /// a 10-bit mask to the integer register `rd`, which indicates the
    /// class of the floating-point number.
    ///
    /// Exactly one bit in `rd` will be set, all other bits are cleared.
    ///
    /// Does not set the floating-point exception flags.
    pub(super) fn run_fclass<F: FloatExt>(&mut self, rs1: FRegister, rd: XRegister)
    where
        FValue: Into<F>,
    {
        let rval: F = self.fregisters.read(rs1).into();

        let is_neg = rval.is_negative();

        let res: u64 = match rval {
            _ if rval.is_neg_infinity() => 1,
            _ if is_neg && rval.is_normal() => 1 << 1,
            _ if is_neg && rval.is_denormal() => 1 << 2,
            _ if rval.is_neg_zero() => 1 << 3,
            _ if rval.is_pos_zero() => 1 << 4,
            _ if rval.is_denormal() => 1 << 5,
            _ if rval.is_normal() => 1 << 6,
            _ if rval.is_pos_infinity() => 1 << 7,
            _ if rval.is_signaling() => 1 << 8,
            _ => 1 << 9,
        };

        self.xregisters.write(rd, res);
    }

    /// `FEQ.*` instruction.
    ///
    /// Writes `1` to `rd` if equal, `0` if not.
    ///
    /// Performs a quiet comparison: only sets the invalid operation exception flag
    /// if either input is a signalling NaN.
    ///
    /// If either input is `NaN`, the result is `0`.
    pub(super) fn run_feq<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: XRegister)
    where
        FValue: Into<F>,
    {
        let rval1: F = self.fregisters.read(rs1).into();
        let rval2: F = self.fregisters.read(rs2).into();

        if rval1.is_signaling() || rval2.is_signaling() {
            self.csregisters.set_exception_flag(Fflag::NV);
        }

        let res = if rval1 == rval2 { 1 } else { 0 };

        self.xregisters.write(rd, res);
    }

    /// `FLT.*` instruction.
    ///
    /// Writes `1` to `rd` if `rs1 < rs2`, `0` if not.
    ///
    /// If either input is `NaN`, the result is `0`, and the invalid operation exception
    /// flag is set.
    pub(super) fn run_flt<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: XRegister)
    where
        FValue: Into<F>,
    {
        let rval1: F = self.fregisters.read(rs1).into();
        let rval2: F = self.fregisters.read(rs2).into();

        if rval1.is_nan() || rval2.is_nan() {
            self.csregisters.set_exception_flag(Fflag::NV);
        }

        let res = if rval1 < rval2 { 1 } else { 0 };

        self.xregisters.write(rd, res);
    }

    /// `FLE.*` instruction.
    ///
    /// Writes `1` to `rd` if `rs1 <= rs2`, `0` if not.
    ///
    /// If either input is `NaN`, the result is `0`, and the invalid operation exception
    /// flag is set.
    pub(super) fn run_fle<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: XRegister)
    where
        FValue: Into<F>,
    {
        let rval1: F = self.fregisters.read(rs1).into();
        let rval2: F = self.fregisters.read(rs2).into();

        if rval1.is_nan() || rval2.is_nan() {
            self.csregisters.set_exception_flag(Fflag::NV);
        }

        let res = if rval1 <= rval2 { 1 } else { 0 };

        self.xregisters.write(rd, res);
    }

    /// `FADD.*` instruction.
    ///
    /// Adds `rs1` to `rs2`, writing the result in `rd`.
    ///
    /// Returns `Exception::IllegalInstruction` on an invalid rounding mode.
    pub(super) fn run_fadd<F: FloatExt>(
        &mut self,
        rs1: FRegister,
        rs2: FRegister,
        rm: InstrRoundingMode,
        rd: FRegister,
    ) -> Result<(), Exception>
    where
        FValue: Into<F>,
    {
        self.f_arith_2(rs1, rs2, rm, rd, F::add_r)
    }

    /// `FSUB.*` instruction.
    ///
    /// Subtracts `rs2` from `rs1`, writing the result in `rd`.
    ///
    /// Returns `Exception::IllegalInstruction` on an invalid rounding mode.
    pub(super) fn run_fsub<F: FloatExt>(
        &mut self,
        rs1: FRegister,
        rs2: FRegister,
        rm: InstrRoundingMode,
        rd: FRegister,
    ) -> Result<(), Exception>
    where
        FValue: Into<F>,
    {
        self.f_arith_2(rs1, rs2, rm, rd, F::sub_r)
    }

    /// `FMUL.*` instruction.
    ///
    /// Multiplies `rs1` by `rs2`, writing the result in `rd`.
    ///
    /// Returns `Exception::IllegalInstruction` on an invalid rounding mode.
    pub(super) fn run_fmul<F: FloatExt>(
        &mut self,
        rs1: FRegister,
        rs2: FRegister,
        rm: InstrRoundingMode,
        rd: FRegister,
    ) -> Result<(), Exception>
    where
        FValue: Into<F>,
    {
        self.f_arith_2(rs1, rs2, rm, rd, F::mul_r)
    }

    /// `FDIV.*` instruction.
    ///
    /// Divides `rs1` by `rs2`, writing the result in `rd`.
    ///
    /// Returns `Exception::IllegalInstruction` on an invalid rounding mode.
    pub(super) fn run_fdiv<F: FloatExt>(
        &mut self,
        rs1: FRegister,
        rs2: FRegister,
        rm: InstrRoundingMode,
        rd: FRegister,
    ) -> Result<(), Exception>
    where
        FValue: Into<F>,
    {
        self.f_arith_2(rs1, rs2, rm, rd, F::div_r)
    }

    /// `FMIN.*` instruction.
    ///
    /// Writes the smaller of `rs1`, `rs2` to `rd`. **NB** `-0.0 < +0.0`.
    ///
    /// If both inputs are NaNs, the result is the canonical NaN. If only one is a NaN,
    /// the result is the non-NaN operand.
    ///
    /// Signaling NaNs set the invalid operation exception flag.
    pub(super) fn run_fmin<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: FRegister)
    where
        FValue: Into<F>,
    {
        self.min_max(rs1, rs2, rd, F::minimum)
    }

    /// `FMAX.*` instruction.
    ///
    /// Writes the larger of `rs1`, `rs2` to `rd`. **NB** `-0.0 < +0.0`.
    ///
    /// If both inputs are NaNs, the result is the canonical NaN. If only one is a NaN,
    /// the result is the non-NaN operand.
    ///
    /// Signaling NaNs set the invalid operation exception flag.
    pub(super) fn run_fmax<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: FRegister)
    where
        FValue: Into<F>,
    {
        self.min_max(rs1, rs2, rd, F::maximum)
    }

    /// `FSGNJ.*` instruction.
    ///
    /// Writes all the bits of `rs1`, except for the sign bit, to `rd`.
    /// The sign bit is taken from `rs2`.
    pub fn run_fsgnj<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: FRegister)
    where
        FValue: Into<F>,
    {
        self.f_sign_injection(rs1, rs2, rd, |_x, y| y);
    }

    /// `FSGNJN.*` instruction.
    ///
    /// Writes all the bits of `rs1`, except for the sign bit, to `rd`.
    /// The sign bit is taken from the negative of `rs2`.
    pub fn run_fsgnjn<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: FRegister)
    where
        FValue: Into<F>,
    {
        self.f_sign_injection(rs1, rs2, rd, |_x, y| !y);
    }

    /// `FSGNJX.*` instruction.
    ///
    /// Writes all the bits of `rs1`, except for the sign bit, to `rd`.
    /// The sign bit is taken from the bitwise XOR of the sign bits from `rs1` & `rs2`.
    pub fn run_fsgnjx<F: FloatExt>(&mut self, rs1: FRegister, rs2: FRegister, rd: FRegister)
    where
        FValue: Into<F>,
    {
        self.f_sign_injection(rs1, rs2, rd, |x, y| x ^ y);
    }

    // perform 2-argument floating-point arithmetic
    fn f_arith_2<F: FloatExt>(
        &mut self,
        rs1: FRegister,
        rs2: FRegister,
        rm: InstrRoundingMode,
        rd: FRegister,
        f: fn(F, F, Round) -> StatusAnd<F>,
    ) -> Result<(), Exception>
    where
        FValue: Into<F>,
    {
        let rval1: F = self.fregisters.read(rs1).into();
        let rval2: F = self.fregisters.read(rs2).into();

        let rm = self.f_rounding_mode(rm)?;

        let StatusAnd { status, value } = f(rval1, rval2, rm).map(F::canonicalise);

        if status != Status::OK {
            self.csregisters.set_exception_flag_status(status);
        }

        self.fregisters.write(rd, value.into());
        Ok(())
    }

    fn f_rounding_mode(&self, rm: InstrRoundingMode) -> Result<Round, Exception> {
        let rm = match rm {
            InstrRoundingMode::Static(rm) => rm,
            InstrRoundingMode::Dynamic => self.csregisters.read(CSRegister::frm).try_into()?,
        };

        Ok(rm.into())
    }

    fn f_sign_injection<F: FloatExt>(
        &mut self,
        rs1: FRegister,
        rs2: FRegister,
        rd: FRegister,
        pick_sign: fn(bool, bool) -> bool,
    ) where
        FValue: Into<F>,
    {
        let rval1: F = self.fregisters.read(rs1).into();
        let rval2: F = self.fregisters.read(rs2).into();

        let sign_bit_1 = rval1.is_negative();
        let sign_bit_2 = rval2.is_negative();

        let sign_bit = pick_sign(sign_bit_1, sign_bit_2);

        let res = if sign_bit == sign_bit_1 {
            rval1
        } else {
            -rval1
        };

        self.fregisters.write(rd, res.into());
    }

    fn min_max<F: FloatExt>(
        &mut self,
        rs1: FRegister,
        rs2: FRegister,
        rd: FRegister,
        cmp: fn(F, F) -> F,
    ) where
        FValue: Into<F>,
    {
        let rval1: F = self.fregisters.read(rs1).into();
        let rval2: F = self.fregisters.read(rs2).into();

        let rval1_nan = rval1.is_nan();
        let rval2_nan = rval2.is_nan();

        let res = match (rval1_nan, rval2_nan) {
            (true, true) => F::canonical_nan(),
            (true, false) => rval2,
            (false, true) => rval1,
            (false, false) => cmp(rval1, rval2),
        };

        if (rval1_nan || rval2_nan) && (rval1.is_signaling() || rval2.is_signaling()) {
            self.csregisters.set_exception_flag(Fflag::NV);
        }

        self.fregisters.write(rd, res.into());
    }
}

/// There are 5 supported rounding modes
#[allow(clippy::upper_case_acronyms)]
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum RoundingMode {
    /// Round to Nearest, ties to Even
    RNE,
    /// Round towards Zero
    RTZ,
    /// Round Down (towards -∞)
    RDN,
    /// Round Up (towrads +∞)
    RUP,
    /// Round to Nearest, ties to Max Magnitude
    RMM,
}

impl TryFrom<CSRValue> for RoundingMode {
    type Error = Exception;

    fn try_from(value: CSRValue) -> Result<Self, Self::Error> {
        match value {
            0b000 => Ok(Self::RNE),
            0b001 => Ok(Self::RTZ),
            0b010 => Ok(Self::RDN),
            0b011 => Ok(Self::RUP),
            0b100 => Ok(Self::RMM),
            _ => Err(Exception::IllegalInstruction),
        }
    }
}

#[allow(clippy::from_over_into)]
impl Into<Round> for RoundingMode {
    fn into(self) -> Round {
        match self {
            Self::RNE => Round::NearestTiesToEven,
            Self::RTZ => Round::TowardZero,
            Self::RUP => Round::TowardPositive,
            Self::RDN => Round::TowardNegative,
            Self::RMM => Round::NearestTiesToAway,
        }
    }
}

#[allow(unused)]
pub enum Fflag {
    /// Inexact
    NX = 0,
    /// Underflow
    UF = 1,
    /// Overflow
    OF = 2,
    /// Divide by Zero
    DZ = 3,
    /// Invalid Operation
    NV = 4,
}

impl<M: backend::Manager> CSRegisters<M> {
    fn set_exception_flag(&mut self, mask: Fflag) {
        self.set_bits(CSRegister::fflags, 1 << mask as usize);
    }

    fn set_exception_flag_status(&mut self, status: Status) {
        let bits = status_to_bits(status);
        self.set_bits(CSRegister::fflags, bits as u64);
    }
}

const fn status_to_bits(status: Status) -> u8 {
    status.bits().reverse_bits() >> 3
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_status_to_bits() {
        assert_eq!(0, status_to_bits(Status::OK));
        assert_eq!(1 << Fflag::NX as usize, status_to_bits(Status::INEXACT));
        assert_eq!(1 << Fflag::UF as usize, status_to_bits(Status::UNDERFLOW));
        assert_eq!(1 << Fflag::OF as usize, status_to_bits(Status::OVERFLOW));
        assert_eq!(1 << Fflag::DZ as usize, status_to_bits(Status::DIV_BY_ZERO));
        assert_eq!(1 << Fflag::NV as usize, status_to_bits(Status::INVALID_OP));
    }
}
