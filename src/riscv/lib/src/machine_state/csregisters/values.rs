// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use super::root::RootCSRegister;
use crate::struct_layout;
use crate::{
    bits::Bits64,
    state_backend::{AllocatedOf, Atom, Cell, Choreographer, Layout, PlacedOf},
};

/// Representation of a value in a CSR
pub type CSRRepr = u64;

/// Value of a Control or State register
#[derive(
    Copy,
    Clone,
    Debug,
    derive_more::Display,
    derive_more::From,
    derive_more::Into,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
)]
#[repr(transparent)]
pub struct CSRValue(CSRRepr);

impl CSRValue {
    /// Access the underlying representation.
    pub fn repr(self) -> CSRRepr {
        self.0
    }
}

impl Bits64 for CSRValue {
    const WIDTH: usize = CSRRepr::WIDTH;

    fn from_bits(value: u64) -> Self {
        Self(value)
    }

    fn to_bits(&self) -> u64 {
        self.repr()
    }
}

macro_rules! csregisters_boilerplate {
    (
        $struct_v:vis struct $struct_t:ident with layout $layout_t:ty {
            $($name:ident: $cell_repr:ty),+
            $( , )?
        }
    ) => { paste::paste! {
        $struct_v struct $struct_t<M: $crate::state_backend::ManagerBase> {
            $($name: Cell<$cell_repr, M>,)+
        }

        impl<M: $crate::state_backend::ManagerBase> $struct_t<M> {
            pub fn bind(space: AllocatedOf<$layout_t, M>) -> Self {
                Self {
                    $($name: space.$name,)*
                }
            }

            // The raw read / write / replace methods on the underlying "full" CSRs (so no sub-fields)
            // These are allowed to be used only by CSRegisters module since they do not account for
            // CSR rules like side-effects, shadowing, WLRL, WARL, WPRI.
            $(
                #[inline(always)]
                pub(super) fn [<read_ $name>](&self) -> $cell_repr
                where
                    M: $crate::state_backend::ManagerRead
                {
                    self.$name.read()
                }

                #[inline(always)]
                pub(super) fn [<write_ $name>](&mut self, value: $cell_repr)
                where
                    M: $crate::state_backend::ManagerWrite
                {
                    self.$name.write(value)
                }

                #[inline(always)]
                pub(super) fn [<replace_ $name>](&mut self, value: $cell_repr) -> $cell_repr
                where
                    M: $crate::state_backend::ManagerReadWrite
                {

                    self.$name.replace(value)
                }
            )*

            // These methods are needed in the case the access to a CSR
            // is not known statically / at compile time,
            // hence they need to go through a match statement.
            // e.g. the CSRRW / CSRRC etc instructions
            #[inline(always)]
            pub(super) fn general_raw_read(&self, csr: RootCSRegister) -> CSRRepr
            where
                M: $crate::state_backend::ManagerRead
            {
                match csr {
                    $( RootCSRegister::$name => self.[<read_ $name>]() ),*
                }
            }

            #[inline(always)]
            pub(super) fn general_raw_write(&mut self, csr: RootCSRegister, value: CSRRepr)
            where
                M: $crate::state_backend::ManagerWrite
            {
                match csr {
                    $( RootCSRegister::$name => self.[<write_ $name>](value) ),*
                }
            }

            #[inline(always)]
            pub(super) fn general_raw_replace(&mut self, csr: RootCSRegister, value: CSRRepr) -> CSRRepr
            where
                M: $crate::state_backend::ManagerReadWrite
            {

                match csr {
                    $( RootCSRegister::$name => self.[<replace_ $name>](value) ),*
                }
            }
        }
    } };
}

csregisters_boilerplate!(
    pub(super) struct CSRegisterValues with layout CSRegisterValuesLayout {
        mnscratch: CSRRepr,
        mnepc: CSRRepr,
        mncause: CSRRepr,
        mnstatus: CSRRepr,
        cycle: CSRRepr,
        time: CSRRepr,
        instret: CSRRepr,
        mcycle: CSRRepr,
        minstret: CSRRepr,
        hpmcounter3: CSRRepr,
        hpmcounter4: CSRRepr,
        hpmcounter5: CSRRepr,
        hpmcounter6: CSRRepr,
        hpmcounter7: CSRRepr,
        hpmcounter8: CSRRepr,
        hpmcounter9: CSRRepr,
        hpmcounter10: CSRRepr,
        hpmcounter11: CSRRepr,
        hpmcounter12: CSRRepr,
        hpmcounter13: CSRRepr,
        hpmcounter14: CSRRepr,
        hpmcounter15: CSRRepr,
        hpmcounter16: CSRRepr,
        hpmcounter17: CSRRepr,
        hpmcounter18: CSRRepr,
        hpmcounter19: CSRRepr,
        hpmcounter20: CSRRepr,
        hpmcounter21: CSRRepr,
        hpmcounter22: CSRRepr,
        hpmcounter23: CSRRepr,
        hpmcounter24: CSRRepr,
        hpmcounter25: CSRRepr,
        hpmcounter26: CSRRepr,
        hpmcounter27: CSRRepr,
        hpmcounter28: CSRRepr,
        hpmcounter29: CSRRepr,
        hpmcounter30: CSRRepr,
        hpmcounter31: CSRRepr,
        mhpmcounter3: CSRRepr,
        mhpmcounter4: CSRRepr,
        mhpmcounter5: CSRRepr,
        mhpmcounter6: CSRRepr,
        mhpmcounter7: CSRRepr,
        mhpmcounter8: CSRRepr,
        mhpmcounter9: CSRRepr,
        mhpmcounter10: CSRRepr,
        mhpmcounter11: CSRRepr,
        mhpmcounter12: CSRRepr,
        mhpmcounter13: CSRRepr,
        mhpmcounter14: CSRRepr,
        mhpmcounter15: CSRRepr,
        mhpmcounter16: CSRRepr,
        mhpmcounter17: CSRRepr,
        mhpmcounter18: CSRRepr,
        mhpmcounter19: CSRRepr,
        mhpmcounter20: CSRRepr,
        mhpmcounter21: CSRRepr,
        mhpmcounter22: CSRRepr,
        mhpmcounter23: CSRRepr,
        mhpmcounter24: CSRRepr,
        mhpmcounter25: CSRRepr,
        mhpmcounter26: CSRRepr,
        mhpmcounter27: CSRRepr,
        mhpmcounter28: CSRRepr,
        mhpmcounter29: CSRRepr,
        mhpmcounter30: CSRRepr,
        mhpmcounter31: CSRRepr,
        mhpmevent3: CSRRepr,
        mhpmevent4: CSRRepr,
        mhpmevent5: CSRRepr,
        mhpmevent6: CSRRepr,
        mhpmevent7: CSRRepr,
        mhpmevent8: CSRRepr,
        mhpmevent9: CSRRepr,
        mhpmevent10: CSRRepr,
        mhpmevent11: CSRRepr,
        mhpmevent12: CSRRepr,
        mhpmevent13: CSRRepr,
        mhpmevent14: CSRRepr,
        mhpmevent15: CSRRepr,
        mhpmevent16: CSRRepr,
        mhpmevent17: CSRRepr,
        mhpmevent18: CSRRepr,
        mhpmevent19: CSRRepr,
        mhpmevent20: CSRRepr,
        mhpmevent21: CSRRepr,
        mhpmevent22: CSRRepr,
        mhpmevent23: CSRRepr,
        mhpmevent24: CSRRepr,
        mhpmevent25: CSRRepr,
        mhpmevent26: CSRRepr,
        mhpmevent27: CSRRepr,
        mhpmevent28: CSRRepr,
        mhpmevent29: CSRRepr,
        mhpmevent30: CSRRepr,
        mhpmevent31: CSRRepr,
        mcountinhibit: CSRRepr,
        scounteren: CSRRepr,
        mcounteren: CSRRepr,
        fcsr: CSRRepr,
        pmpcfg0: CSRRepr,
        pmpcfg2: CSRRepr,
        pmpcfg4: CSRRepr,
        pmpcfg6: CSRRepr,
        pmpcfg8: CSRRepr,
        pmpcfg10: CSRRepr,
        pmpcfg12: CSRRepr,
        pmpcfg14: CSRRepr,
        pmpaddr0: CSRRepr,
        pmpaddr1: CSRRepr,
        pmpaddr2: CSRRepr,
        pmpaddr3: CSRRepr,
        pmpaddr4: CSRRepr,
        pmpaddr5: CSRRepr,
        pmpaddr6: CSRRepr,
        pmpaddr7: CSRRepr,
        pmpaddr8: CSRRepr,
        pmpaddr9: CSRRepr,
        pmpaddr10: CSRRepr,
        pmpaddr11: CSRRepr,
        pmpaddr12: CSRRepr,
        pmpaddr13: CSRRepr,
        pmpaddr14: CSRRepr,
        pmpaddr15: CSRRepr,
        pmpaddr16: CSRRepr,
        pmpaddr17: CSRRepr,
        pmpaddr18: CSRRepr,
        pmpaddr19: CSRRepr,
        pmpaddr20: CSRRepr,
        pmpaddr21: CSRRepr,
        pmpaddr22: CSRRepr,
        pmpaddr23: CSRRepr,
        pmpaddr24: CSRRepr,
        pmpaddr25: CSRRepr,
        pmpaddr26: CSRRepr,
        pmpaddr27: CSRRepr,
        pmpaddr28: CSRRepr,
        pmpaddr29: CSRRepr,
        pmpaddr30: CSRRepr,
        pmpaddr31: CSRRepr,
        pmpaddr32: CSRRepr,
        pmpaddr33: CSRRepr,
        pmpaddr34: CSRRepr,
        pmpaddr35: CSRRepr,
        pmpaddr36: CSRRepr,
        pmpaddr37: CSRRepr,
        pmpaddr38: CSRRepr,
        pmpaddr39: CSRRepr,
        pmpaddr40: CSRRepr,
        pmpaddr41: CSRRepr,
        pmpaddr42: CSRRepr,
        pmpaddr43: CSRRepr,
        pmpaddr44: CSRRepr,
        pmpaddr45: CSRRepr,
        pmpaddr46: CSRRepr,
        pmpaddr47: CSRRepr,
        pmpaddr48: CSRRepr,
        pmpaddr49: CSRRepr,
        pmpaddr50: CSRRepr,
        pmpaddr51: CSRRepr,
        pmpaddr52: CSRRepr,
        pmpaddr53: CSRRepr,
        pmpaddr54: CSRRepr,
        pmpaddr55: CSRRepr,
        pmpaddr56: CSRRepr,
        pmpaddr57: CSRRepr,
        pmpaddr58: CSRRepr,
        pmpaddr59: CSRRepr,
        pmpaddr60: CSRRepr,
        pmpaddr61: CSRRepr,
        pmpaddr62: CSRRepr,
        pmpaddr63: CSRRepr,
        mhartid: CSRRepr,
        mvendorid: CSRRepr,
        marchid: CSRRepr,
        mimpid: CSRRepr,
        misa: CSRRepr,
        mscratch: CSRRepr,
        mstatus: CSRRepr,
        sscratch: CSRRepr,
        stvec: CSRRepr,
        mtvec: CSRRepr,
        mie: CSRRepr,
        satp: CSRRepr,
        scause: CSRRepr,
        mcause: CSRRepr,
        sepc: CSRRepr,
        mepc: CSRRepr,
        stval: CSRRepr,
        mtval: CSRRepr,
        mtval2: CSRRepr,
        mip: CSRRepr,
        mtinst: CSRRepr,
        senvcfg: CSRRepr,
        menvcfg: CSRRepr,
        mconfigptr: CSRRepr,
        medeleg: CSRRepr,
        mideleg: CSRRepr,
        mseccfg: CSRRepr,
        scontext: CSRRepr,
        hstatus: CSRRepr,
        hedeleg: CSRRepr,
        hideleg: CSRRepr,
        hie: CSRRepr,
        hcounteren: CSRRepr,
        hgeie: CSRRepr,
        htval: CSRRepr,
        hip: CSRRepr,
        hvip: CSRRepr,
        htinst: CSRRepr,
        hgeip: CSRRepr,
        henvcfg: CSRRepr,
        hgatp: CSRRepr,
        hcontext: CSRRepr,
        htimedelta: CSRRepr,
        vsstatus: CSRRepr,
        vsie: CSRRepr,
        vstvec: CSRRepr,
        vsscratch: CSRRepr,
        vsepc: CSRRepr,
        vscause: CSRRepr,
        vstval: CSRRepr,
        vsip: CSRRepr,
        vsatp: CSRRepr,
        tselect: CSRRepr,
        tdata1: CSRRepr,
        tdata2: CSRRepr,
        tdata3: CSRRepr,
        tcontrol: CSRRepr,
        mcontext: CSRRepr,
        dcsr: CSRRepr,
        dpc: CSRRepr,
        dscratch0: CSRRepr,
        dscratch1: CSRRepr,
    }
);

struct_layout!(
    pub struct CSRegisterValuesLayout {
        mnscratch: Atom<CSRRepr>,
        mnepc: Atom<CSRRepr>,
        mncause: Atom<CSRRepr>,
        mnstatus: Atom<CSRRepr>,
        cycle: Atom<CSRRepr>,
        time: Atom<CSRRepr>,
        instret: Atom<CSRRepr>,
        mcycle: Atom<CSRRepr>,
        minstret: Atom<CSRRepr>,
        hpmcounter3: Atom<CSRRepr>,
        hpmcounter4: Atom<CSRRepr>,
        hpmcounter5: Atom<CSRRepr>,
        hpmcounter6: Atom<CSRRepr>,
        hpmcounter7: Atom<CSRRepr>,
        hpmcounter8: Atom<CSRRepr>,
        hpmcounter9: Atom<CSRRepr>,
        hpmcounter10: Atom<CSRRepr>,
        hpmcounter11: Atom<CSRRepr>,
        hpmcounter12: Atom<CSRRepr>,
        hpmcounter13: Atom<CSRRepr>,
        hpmcounter14: Atom<CSRRepr>,
        hpmcounter15: Atom<CSRRepr>,
        hpmcounter16: Atom<CSRRepr>,
        hpmcounter17: Atom<CSRRepr>,
        hpmcounter18: Atom<CSRRepr>,
        hpmcounter19: Atom<CSRRepr>,
        hpmcounter20: Atom<CSRRepr>,
        hpmcounter21: Atom<CSRRepr>,
        hpmcounter22: Atom<CSRRepr>,
        hpmcounter23: Atom<CSRRepr>,
        hpmcounter24: Atom<CSRRepr>,
        hpmcounter25: Atom<CSRRepr>,
        hpmcounter26: Atom<CSRRepr>,
        hpmcounter27: Atom<CSRRepr>,
        hpmcounter28: Atom<CSRRepr>,
        hpmcounter29: Atom<CSRRepr>,
        hpmcounter30: Atom<CSRRepr>,
        hpmcounter31: Atom<CSRRepr>,
        mhpmcounter3: Atom<CSRRepr>,
        mhpmcounter4: Atom<CSRRepr>,
        mhpmcounter5: Atom<CSRRepr>,
        mhpmcounter6: Atom<CSRRepr>,
        mhpmcounter7: Atom<CSRRepr>,
        mhpmcounter8: Atom<CSRRepr>,
        mhpmcounter9: Atom<CSRRepr>,
        mhpmcounter10: Atom<CSRRepr>,
        mhpmcounter11: Atom<CSRRepr>,
        mhpmcounter12: Atom<CSRRepr>,
        mhpmcounter13: Atom<CSRRepr>,
        mhpmcounter14: Atom<CSRRepr>,
        mhpmcounter15: Atom<CSRRepr>,
        mhpmcounter16: Atom<CSRRepr>,
        mhpmcounter17: Atom<CSRRepr>,
        mhpmcounter18: Atom<CSRRepr>,
        mhpmcounter19: Atom<CSRRepr>,
        mhpmcounter20: Atom<CSRRepr>,
        mhpmcounter21: Atom<CSRRepr>,
        mhpmcounter22: Atom<CSRRepr>,
        mhpmcounter23: Atom<CSRRepr>,
        mhpmcounter24: Atom<CSRRepr>,
        mhpmcounter25: Atom<CSRRepr>,
        mhpmcounter26: Atom<CSRRepr>,
        mhpmcounter27: Atom<CSRRepr>,
        mhpmcounter28: Atom<CSRRepr>,
        mhpmcounter29: Atom<CSRRepr>,
        mhpmcounter30: Atom<CSRRepr>,
        mhpmcounter31: Atom<CSRRepr>,
        mhpmevent3: Atom<CSRRepr>,
        mhpmevent4: Atom<CSRRepr>,
        mhpmevent5: Atom<CSRRepr>,
        mhpmevent6: Atom<CSRRepr>,
        mhpmevent7: Atom<CSRRepr>,
        mhpmevent8: Atom<CSRRepr>,
        mhpmevent9: Atom<CSRRepr>,
        mhpmevent10: Atom<CSRRepr>,
        mhpmevent11: Atom<CSRRepr>,
        mhpmevent12: Atom<CSRRepr>,
        mhpmevent13: Atom<CSRRepr>,
        mhpmevent14: Atom<CSRRepr>,
        mhpmevent15: Atom<CSRRepr>,
        mhpmevent16: Atom<CSRRepr>,
        mhpmevent17: Atom<CSRRepr>,
        mhpmevent18: Atom<CSRRepr>,
        mhpmevent19: Atom<CSRRepr>,
        mhpmevent20: Atom<CSRRepr>,
        mhpmevent21: Atom<CSRRepr>,
        mhpmevent22: Atom<CSRRepr>,
        mhpmevent23: Atom<CSRRepr>,
        mhpmevent24: Atom<CSRRepr>,
        mhpmevent25: Atom<CSRRepr>,
        mhpmevent26: Atom<CSRRepr>,
        mhpmevent27: Atom<CSRRepr>,
        mhpmevent28: Atom<CSRRepr>,
        mhpmevent29: Atom<CSRRepr>,
        mhpmevent30: Atom<CSRRepr>,
        mhpmevent31: Atom<CSRRepr>,
        mcountinhibit: Atom<CSRRepr>,
        scounteren: Atom<CSRRepr>,
        mcounteren: Atom<CSRRepr>,
        fcsr: Atom<CSRRepr>,
        pmpcfg0: Atom<CSRRepr>,
        pmpcfg2: Atom<CSRRepr>,
        pmpcfg4: Atom<CSRRepr>,
        pmpcfg6: Atom<CSRRepr>,
        pmpcfg8: Atom<CSRRepr>,
        pmpcfg10: Atom<CSRRepr>,
        pmpcfg12: Atom<CSRRepr>,
        pmpcfg14: Atom<CSRRepr>,
        pmpaddr0: Atom<CSRRepr>,
        pmpaddr1: Atom<CSRRepr>,
        pmpaddr2: Atom<CSRRepr>,
        pmpaddr3: Atom<CSRRepr>,
        pmpaddr4: Atom<CSRRepr>,
        pmpaddr5: Atom<CSRRepr>,
        pmpaddr6: Atom<CSRRepr>,
        pmpaddr7: Atom<CSRRepr>,
        pmpaddr8: Atom<CSRRepr>,
        pmpaddr9: Atom<CSRRepr>,
        pmpaddr10: Atom<CSRRepr>,
        pmpaddr11: Atom<CSRRepr>,
        pmpaddr12: Atom<CSRRepr>,
        pmpaddr13: Atom<CSRRepr>,
        pmpaddr14: Atom<CSRRepr>,
        pmpaddr15: Atom<CSRRepr>,
        pmpaddr16: Atom<CSRRepr>,
        pmpaddr17: Atom<CSRRepr>,
        pmpaddr18: Atom<CSRRepr>,
        pmpaddr19: Atom<CSRRepr>,
        pmpaddr20: Atom<CSRRepr>,
        pmpaddr21: Atom<CSRRepr>,
        pmpaddr22: Atom<CSRRepr>,
        pmpaddr23: Atom<CSRRepr>,
        pmpaddr24: Atom<CSRRepr>,
        pmpaddr25: Atom<CSRRepr>,
        pmpaddr26: Atom<CSRRepr>,
        pmpaddr27: Atom<CSRRepr>,
        pmpaddr28: Atom<CSRRepr>,
        pmpaddr29: Atom<CSRRepr>,
        pmpaddr30: Atom<CSRRepr>,
        pmpaddr31: Atom<CSRRepr>,
        pmpaddr32: Atom<CSRRepr>,
        pmpaddr33: Atom<CSRRepr>,
        pmpaddr34: Atom<CSRRepr>,
        pmpaddr35: Atom<CSRRepr>,
        pmpaddr36: Atom<CSRRepr>,
        pmpaddr37: Atom<CSRRepr>,
        pmpaddr38: Atom<CSRRepr>,
        pmpaddr39: Atom<CSRRepr>,
        pmpaddr40: Atom<CSRRepr>,
        pmpaddr41: Atom<CSRRepr>,
        pmpaddr42: Atom<CSRRepr>,
        pmpaddr43: Atom<CSRRepr>,
        pmpaddr44: Atom<CSRRepr>,
        pmpaddr45: Atom<CSRRepr>,
        pmpaddr46: Atom<CSRRepr>,
        pmpaddr47: Atom<CSRRepr>,
        pmpaddr48: Atom<CSRRepr>,
        pmpaddr49: Atom<CSRRepr>,
        pmpaddr50: Atom<CSRRepr>,
        pmpaddr51: Atom<CSRRepr>,
        pmpaddr52: Atom<CSRRepr>,
        pmpaddr53: Atom<CSRRepr>,
        pmpaddr54: Atom<CSRRepr>,
        pmpaddr55: Atom<CSRRepr>,
        pmpaddr56: Atom<CSRRepr>,
        pmpaddr57: Atom<CSRRepr>,
        pmpaddr58: Atom<CSRRepr>,
        pmpaddr59: Atom<CSRRepr>,
        pmpaddr60: Atom<CSRRepr>,
        pmpaddr61: Atom<CSRRepr>,
        pmpaddr62: Atom<CSRRepr>,
        pmpaddr63: Atom<CSRRepr>,
        mhartid: Atom<CSRRepr>,
        mvendorid: Atom<CSRRepr>,
        marchid: Atom<CSRRepr>,
        mimpid: Atom<CSRRepr>,
        misa: Atom<CSRRepr>,
        mscratch: Atom<CSRRepr>,
        mstatus: Atom<CSRRepr>,
        sscratch: Atom<CSRRepr>,
        stvec: Atom<CSRRepr>,
        mtvec: Atom<CSRRepr>,
        mie: Atom<CSRRepr>,
        satp: Atom<CSRRepr>,
        scause: Atom<CSRRepr>,
        mcause: Atom<CSRRepr>,
        sepc: Atom<CSRRepr>,
        mepc: Atom<CSRRepr>,
        stval: Atom<CSRRepr>,
        mtval: Atom<CSRRepr>,
        mtval2: Atom<CSRRepr>,
        mip: Atom<CSRRepr>,
        mtinst: Atom<CSRRepr>,
        senvcfg: Atom<CSRRepr>,
        menvcfg: Atom<CSRRepr>,
        mconfigptr: Atom<CSRRepr>,
        medeleg: Atom<CSRRepr>,
        mideleg: Atom<CSRRepr>,
        mseccfg: Atom<CSRRepr>,
        scontext: Atom<CSRRepr>,
        hstatus: Atom<CSRRepr>,
        hedeleg: Atom<CSRRepr>,
        hideleg: Atom<CSRRepr>,
        hie: Atom<CSRRepr>,
        hcounteren: Atom<CSRRepr>,
        hgeie: Atom<CSRRepr>,
        htval: Atom<CSRRepr>,
        hip: Atom<CSRRepr>,
        hvip: Atom<CSRRepr>,
        htinst: Atom<CSRRepr>,
        hgeip: Atom<CSRRepr>,
        henvcfg: Atom<CSRRepr>,
        hgatp: Atom<CSRRepr>,
        hcontext: Atom<CSRRepr>,
        htimedelta: Atom<CSRRepr>,
        vsstatus: Atom<CSRRepr>,
        vsie: Atom<CSRRepr>,
        vstvec: Atom<CSRRepr>,
        vsscratch: Atom<CSRRepr>,
        vsepc: Atom<CSRRepr>,
        vscause: Atom<CSRRepr>,
        vstval: Atom<CSRRepr>,
        vsip: Atom<CSRRepr>,
        vsatp: Atom<CSRRepr>,
        tselect: Atom<CSRRepr>,
        tdata1: Atom<CSRRepr>,
        tdata2: Atom<CSRRepr>,
        tdata3: Atom<CSRRepr>,
        tcontrol: Atom<CSRRepr>,
        mcontext: Atom<CSRRepr>,
        dcsr: Atom<CSRRepr>,
        dpc: Atom<CSRRepr>,
        dscratch0: Atom<CSRRepr>,
        dscratch1: Atom<CSRRepr>,
    }
);
