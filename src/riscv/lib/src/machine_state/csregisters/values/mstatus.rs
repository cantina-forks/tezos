// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use super::CSRRepr;
use crate::{
    bits::{Bits64, ConstantBits},
    machine_state::csregisters::{
        effects::CSREffect,
        xstatus::{ExtensionValue, MPPValue, MStatus, SPPValue, XLenValue},
    },
    state_backend::{
        AllocatedOf, Atom, Cell, EnumCell, EnumCellLayout, ManagerBase, ManagerRead,
        ManagerReadWrite, ManagerWrite,
    },
    struct_layout,
};

/// RISCV CSRegister.mstatus register state.
/// Accounts for CSR rules like WPRI, WARL, WLRL.
/// Contains only real fields (no shadows) hence it is a public field in [`super::CSRegisterValues`]
pub struct MStatusValue<M: ManagerBase> {
    // Individual fields can be public since they are well typed and respect the WPRI, WARL, WLRL rules.
    // Except for fields which have side-effects. These ones have custom read/write/replace methods
    // to return side-effects to be accounted for
    sie: Cell<bool, M>,
    mie: Cell<bool, M>,
    pub spie: Cell<bool, M>,
    pub ube: Cell<bool, M>,
    pub mpie: Cell<bool, M>,
    pub spp: EnumCell<SPPValue, u8, M>,
    pub mpp: EnumCell<MPPValue, u8, M>,
    pub fs: EnumCell<ExtensionValue, u8, M>,
    pub xs: EnumCell<ExtensionValue, u8, M>,
    // vs is always OFF as we do not support the virtualisation extension
    pub mprv: Cell<bool, M>,
    pub sum: Cell<bool, M>,
    pub mxr: Cell<bool, M>,
    pub tvm: Cell<bool, M>,
    pub tw: Cell<bool, M>,
    pub tsr: Cell<bool, M>,
    pub uxl: EnumCell<XLenValue, u8, M>,
    pub sxl: EnumCell<XLenValue, u8, M>,
    pub sbe: Cell<bool, M>,
    pub mbe: Cell<bool, M>,
}

impl<M: ManagerBase> MStatusValue<M> {
    pub fn bind(space: AllocatedOf<MStatusLayout, M>) -> Self {
        Self {
            sie: space.sie,
            mie: space.mie,
            spie: space.spie,
            ube: space.ube,
            mpie: space.mpie,
            spp: EnumCell::bind(space.spp),
            mpp: EnumCell::bind(space.mpp),
            fs: EnumCell::bind(space.fs),
            xs: EnumCell::bind(space.xs),
            mprv: space.mprv,
            sum: space.sum,
            mxr: space.mxr,
            tvm: space.tvm,
            tw: space.tw,
            tsr: space.tsr,
            uxl: EnumCell::bind(space.uxl),
            sxl: EnumCell::bind(space.sxl),
            sbe: space.sbe,
            mbe: space.mbe,
        }
    }
}

struct_layout!(
    pub struct MStatusLayout {
        sie: Atom<bool>,
        mie: Atom<bool>,
        spie: Atom<bool>,
        ube: Atom<bool>,
        mpie: Atom<bool>,
        spp: EnumCellLayout<u8>,
        mpp: EnumCellLayout<u8>,
        fs: EnumCellLayout<u8>,
        xs: EnumCellLayout<u8>,
        mprv: Atom<bool>,
        sum: Atom<bool>,
        mxr: Atom<bool>,
        tvm: Atom<bool>,
        tw: Atom<bool>,
        tsr: Atom<bool>,
        uxl: EnumCellLayout<u8>,
        sxl: EnumCellLayout<u8>,
        sbe: Atom<bool>,
        mbe: Atom<bool>,
    }
);

// Impl block for mie & sie fields.
// Required to return side-effects which should be handled with [`super::effects::handle_csr_effect`]
impl<M: ManagerBase> MStatusValue<M> {
    #[inline(always)]
    pub fn mie_read(&self) -> bool
    where
        M: ManagerRead,
    {
        self.mie.read()
    }

    #[inline(always)]
    pub fn mie_write(&mut self, value: bool) -> Option<CSREffect>
    where
        M: ManagerWrite,
    {
        self.mie.write(value);
        Some(CSREffect::InvalidateTranslationCacheXIE)
    }

    #[inline(always)]
    pub fn mie_replace(&mut self, value: bool) -> (bool, Option<CSREffect>)
    where
        M: ManagerReadWrite,
    {
        let old_value = self.mie.replace(value);
        (old_value, Some(CSREffect::InvalidateTranslationCacheXIE))
    }

    #[inline(always)]
    pub fn sie_read(&self) -> bool
    where
        M: ManagerRead,
    {
        self.sie.read()
    }

    #[inline(always)]
    pub fn sie_write(&mut self, value: bool) -> Option<CSREffect>
    where
        M: ManagerWrite,
    {
        self.sie.write(value);
        Some(CSREffect::InvalidateTranslationCacheXIE)
    }

    #[inline(always)]
    pub fn sie_replace(&mut self, value: bool) -> (bool, Option<CSREffect>)
    where
        M: ManagerReadWrite,
    {
        let old_value = self.sie.replace(value);
        (old_value, Some(CSREffect::InvalidateTranslationCacheXIE))
    }
}

#[inline(always)]
fn compute_sd(fs: ExtensionValue, xs: ExtensionValue) -> bool {
    fs == ExtensionValue::Dirty || xs == ExtensionValue::Dirty
}

// Impl block for fields which are derived from other values or do not need to be stored in the backend.
impl<M: ManagerBase> MStatusValue<M> {
    /// Read mstatus.fs field
    #[inline(always)]
    pub fn read_sd(&self) -> bool
    where
        M: ManagerRead,
    {
        compute_sd(self.fs.read(), self.xs.read())
    }

    /// Read `mstatus.vs` field. For our implementation, this is a constant.
    #[inline(always)]
    pub const fn read_vs(&self) -> ExtensionValue {
        ExtensionValue::Off
    }
}

// This impl block is here for compatibility with the bits api.
impl<M: ManagerBase> MStatusValue<M> {
    /// Read mstatus as in its 64 bit representation
    #[inline]
    pub fn read(&self) -> CSRRepr
    where
        M: ManagerRead,
    {
        let mstatus = &self;
        let fs = mstatus.fs.read();
        let xs = mstatus.xs.read();
        MStatus::new(
            ConstantBits,
            mstatus.sie.read(),
            ConstantBits,
            mstatus.mie.read(),
            ConstantBits,
            mstatus.spie.read(),
            mstatus.ube.read(),
            mstatus.mpie.read(),
            mstatus.spp.read(),
            ConstantBits,
            mstatus.mpp.read(),
            fs,
            xs,
            mstatus.mprv.read(),
            mstatus.sum.read(),
            mstatus.mxr.read(),
            mstatus.tvm.read(),
            mstatus.tw.read(),
            mstatus.tsr.read(),
            ConstantBits,
            mstatus.uxl.read(),
            mstatus.sxl.read(),
            mstatus.sbe.read(),
            mstatus.mbe.read(),
            ConstantBits,
            compute_sd(xs, fs),
        )
        .to_bits()
    }

    /// Write to mstatus the `value` given in 64 bit representation
    #[inline]
    pub fn write(&mut self, value: CSRRepr) -> Option<CSREffect>
    where
        M: ManagerWrite,
    {
        let value = MStatus::from_bits(value);
        let mstatus = self;

        let effect_sie = mstatus.sie_write(value.sie());
        let effect_mie = mstatus.mie_write(value.mie());
        debug_assert_eq!(effect_sie, Some(CSREffect::InvalidateTranslationCacheXIE));
        debug_assert_eq!(effect_mie, Some(CSREffect::InvalidateTranslationCacheXIE));

        mstatus.spie.write(value.spie());
        mstatus.ube.write(value.ube());
        mstatus.mpie.write(value.mpie());
        mstatus.spp.write(value.spp());
        mstatus.mpp.write(value.mpp());
        mstatus.fs.write(value.fs());
        mstatus.xs.write(value.xs());
        mstatus.mprv.write(value.mprv());
        mstatus.sum.write(value.sum());
        mstatus.mxr.write(value.mxr());
        mstatus.tvm.write(value.tvm());
        mstatus.tw.write(value.tw());
        mstatus.tsr.write(value.tsr());
        mstatus.uxl.write(value.uxl());
        mstatus.sxl.write(value.sxl());
        mstatus.sbe.write(value.sbe());
        mstatus.mbe.write(value.mbe());

        Some(CSREffect::InvalidateTranslationCacheXIE)
    }

    /// Replace mstatus with `value` given in 64 bit representation
    #[inline]
    pub fn replace(&mut self, value: CSRRepr) -> (CSRRepr, Option<CSREffect>)
    where
        M: ManagerReadWrite,
    {
        let value = MStatus::from_bits(value);
        let mstatus = self;

        let (sie, effect_sie) = mstatus.sie_replace(value.sie());
        let (mie, effect_mie) = mstatus.mie_replace(value.mie());
        debug_assert_eq!(effect_sie, Some(CSREffect::InvalidateTranslationCacheXIE));
        debug_assert_eq!(effect_mie, Some(CSREffect::InvalidateTranslationCacheXIE));

        let spie = mstatus.spie.replace(value.spie());
        let ube = mstatus.ube.replace(value.ube());
        let mpie = mstatus.mpie.replace(value.mpie());
        let spp = mstatus.spp.replace(value.spp());
        let mpp = mstatus.mpp.replace(value.mpp());
        let fs = mstatus.fs.replace(value.fs());
        let xs = mstatus.xs.replace(value.xs());
        let mprv = mstatus.mprv.replace(value.mprv());
        let sum = mstatus.sum.replace(value.sum());
        let mxr = mstatus.mxr.replace(value.mxr());
        let tvm = mstatus.tvm.replace(value.tvm());
        let tw = mstatus.tw.replace(value.tw());
        let tsr = mstatus.tsr.replace(value.tsr());
        let uxl = mstatus.uxl.replace(value.uxl());
        let sxl = mstatus.sxl.replace(value.sxl());
        let sbe = mstatus.sbe.replace(value.sbe());
        let mbe = mstatus.mbe.replace(value.mbe());
        let sd = compute_sd(fs, xs);

        let old_value = MStatus::new(
            ConstantBits::from_bits(0),
            sie,
            ConstantBits::from_bits(0),
            mie,
            ConstantBits::from_bits(0),
            spie,
            ube,
            mpie,
            spp,
            ConstantBits::from_bits(0),
            mpp,
            fs,
            xs,
            mprv,
            sum,
            mxr,
            tvm,
            tw,
            tsr,
            ConstantBits::from_bits(0),
            uxl,
            sxl,
            sbe,
            mbe,
            ConstantBits::from_bits(0),
            sd,
        )
        .to_bits();

        (old_value, Some(CSREffect::InvalidateTranslationCacheXIE))
    }
}
