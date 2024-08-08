// SPDX-FileCopyrightText: 2023 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use super::{Address, Addressable};
use crate::state_backend::{self as backend};
use std::mem;

/// Configuration object for memory size
pub enum Sizes<const BYTES: usize> {}

/// Generates a variant of [Sizes] with all length parameters instantiated.
macro_rules! gen_memory_layout {
    ($name:ident = $size_in_g:literal GiB) => {
        pub type $name =
            crate::machine_state::bus::main_memory::Sizes<{ $size_in_g * 1024 * 1024 * 1024 }>;
    };

    ($name:ident = $size_in_m:literal MiB) => {
        pub type $name =
            crate::machine_state::bus::main_memory::Sizes<{ $size_in_m * 1024 * 1024 }>;
    };

    ($name:ident = $size_in_k:literal KiB) => {
        pub type $name = crate::machine_state::bus::main_memory::Sizes<{ $size_in_k * 1024 }>;
    };
}

gen_memory_layout!(M1K = 1 KiB);
gen_memory_layout!(M1M = 1 MiB);
gen_memory_layout!(M100M = 100 MiB);
gen_memory_layout!(M1G = 1 GiB);
gen_memory_layout!(M4G = 4 GiB);

/// Main memory layout, i.e. specifies how much memory there is
// XXX: We can't associate these region types directly with [Sizes] because
// inherent associated types are unstable. Hence we must go through a dummy
// trait.
pub trait MainMemoryLayout: backend::Layout {
    type Data<M: backend::ManagerBase>;

    const BYTES: usize;

    fn refl<M: backend::ManagerBase>(space: backend::AllocatedOf<Self, M>) -> MainMemory<Self, M>;

    /// Read an element in the region. `address` is in bytes.
    fn data_read<E: backend::Elem, M: backend::Manager>(data: &Self::Data<M>, address: usize) -> E;

    /// Read elements from the region. `address` is in bytes.
    fn data_read_all<E: backend::Elem, M: backend::Manager>(
        data: &Self::Data<M>,
        address: usize,
        values: &mut [E],
    );

    /// Update an element in the region. `address` is in bytes.
    fn data_write<E: backend::Elem, M: backend::Manager>(
        data: &mut Self::Data<M>,
        address: usize,
        value: E,
    );

    /// Update multiple elements in the region. `address` is in bytes.
    fn data_write_all<E: backend::Elem, M: backend::Manager>(
        data: &mut Self::Data<M>,
        address: usize,
        values: &[E],
    );
}

impl<const BYTES: usize> MainMemoryLayout for Sizes<BYTES> {
    type Data<M: backend::ManagerBase> = backend::DynCells<BYTES, M>;

    const BYTES: usize = BYTES;

    fn refl<M: backend::ManagerBase>(space: backend::AllocatedOf<Self, M>) -> MainMemory<Self, M> {
        space
    }

    fn data_read<E: backend::Elem, M: backend::Manager>(data: &Self::Data<M>, address: usize) -> E {
        data.read(address)
    }

    fn data_read_all<E: backend::Elem, M: backend::Manager>(
        data: &Self::Data<M>,
        address: usize,
        values: &mut [E],
    ) {
        data.read_all(address, values);
    }

    fn data_write<E: backend::Elem, M: backend::Manager>(
        data: &mut Self::Data<M>,
        address: usize,
        value: E,
    ) {
        data.write(address, value);
    }

    fn data_write_all<E: backend::Elem, M: backend::Manager>(
        data: &mut Self::Data<M>,
        address: usize,
        values: &[E],
    ) {
        data.write_all(address, values);
    }
}

impl<const BYTES: usize> backend::Layout for Sizes<BYTES> {
    type Placed = backend::Location<[u8; BYTES]>;

    fn place_with(alloc: &mut backend::Choreographer) -> Self::Placed {
        // Most architectures have a 4 KiB minimum page size. We use it to
        // ensure our main memory is not only well-aligned with respect to the
        // values you might access in it, but also with respect to host's page
        // layout where our main memory lies.
        alloc.alloc_min_align(4096)
    }

    type Allocated<M: backend::ManagerBase> = MainMemory<Self, M>;

    fn allocate<M: backend::Manager>(backend: &mut M, placed: Self::Placed) -> Self::Allocated<M> {
        let data = backend.allocate_dyn_region(placed);
        let data = backend::DynCells::bind(data);
        MainMemory { data }
    }
}

/// Main memory state for the given layout
pub struct MainMemory<L: MainMemoryLayout + ?Sized, M: backend::ManagerBase> {
    pub data: L::Data<M>,
}

impl<L: MainMemoryLayout, M: backend::Manager> MainMemory<L, M> {
    /// Bind the main memory state to the given allocated space.
    pub fn bind(space: backend::AllocatedOf<L, M>) -> Self {
        L::refl(space)
    }

    /// Reset to the initial state.
    pub fn reset(&mut self) {
        for i in 0..L::BYTES {
            L::data_write(&mut self.data, i, 0u8);
        }
    }
}

impl<E: backend::Elem, L: MainMemoryLayout, M: backend::Manager> Addressable<E>
    for MainMemory<L, M>
{
    #[inline(always)]
    fn read(&self, addr: super::Address) -> Result<E, super::OutOfBounds> {
        if addr as usize + mem::size_of::<E>() > L::BYTES {
            return Err(super::OutOfBounds);
        }

        Ok(L::data_read(&self.data, addr as usize))
    }

    #[inline(always)]
    fn read_all(&self, addr: super::Address, values: &mut [E]) -> Result<(), super::OutOfBounds> {
        if addr as usize + mem::size_of_val(values) > L::BYTES {
            return Err(super::OutOfBounds);
        }

        L::data_read_all(&self.data, addr as usize, values);

        Ok(())
    }

    fn write(&mut self, addr: super::Address, value: E) -> Result<(), super::OutOfBounds> {
        if addr as usize + mem::size_of::<E>() > L::BYTES {
            return Err(super::OutOfBounds);
        }

        L::data_write(&mut self.data, addr as usize, value);

        Ok(())
    }

    fn write_all(&mut self, addr: Address, values: &[E]) -> Result<(), super::OutOfBounds> {
        let addr = addr as usize;

        if addr + mem::size_of_val(values) > L::BYTES {
            return Err(super::OutOfBounds);
        }

        L::data_write_all(&mut self.data, addr, values);

        Ok(())
    }
}

#[cfg(test)]
pub mod tests {
    use crate::{
        backend_test, create_backend,
        machine_state::{
            backend::{tests::test_determinism, Backend, Layout},
            bus::Addressable,
        },
    };

    gen_memory_layout!(T1K = 1 KiB);

    backend_test!(test_endianess, F, {
        let mut backend = create_backend!(T1K, F);
        let mut memory = backend.allocate(T1K::placed().into_location());

        memory.write(0, 0x1122334455667788u64).unwrap();

        macro_rules! check_address {
            ($ty:ty, $addr:expr, $value:expr) => {
                assert_eq!(Addressable::<$ty>::read(&memory, $addr), Ok($value));
            };
        }

        check_address!(u64, 0, 0x1122334455667788);

        check_address!(u32, 0, 0x55667788);
        check_address!(u32, 4, 0x11223344);

        check_address!(u16, 0, 0x7788);
        check_address!(u16, 2, 0x5566);
        check_address!(u16, 4, 0x3344);
        check_address!(u16, 6, 0x1122);

        check_address!(u8, 0, 0x88);
        check_address!(u8, 1, 0x77);
        check_address!(u8, 2, 0x66);
        check_address!(u8, 3, 0x55);
        check_address!(u8, 4, 0x44);
        check_address!(u8, 5, 0x33);
        check_address!(u8, 6, 0x22);
        check_address!(u8, 7, 0x11);
    });

    backend_test!(test_reset, F, {
        test_determinism::<F, T1K, _>(|mut memory| {
            memory.reset();
        });
    });
}
