// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use super::{PvmHooks, PvmStatus};
use crate::{
    machine_state::{
        bus::{main_memory::MainMemoryLayout, Addressable, OutOfBounds},
        registers::{a0, a1, a2, a3, a6, a7},
        AccessType, MachineState,
    },
    parser::instruction::Instr,
    state_backend::{AllocatedOf, CellRead, CellWrite, EnumCell, EnumCellLayout, Manager},
    traps::{EnvironException, Exception},
};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use std::cmp;
use tezos_smart_rollup_constants::riscv::{
    SBI_CONSOLE_PUTCHAR, SBI_FIRMWARE_TEZOS, SBI_SHUTDOWN, SBI_TEZOS_BLAKE2B_HASH256,
    SBI_TEZOS_ED25519_SIGN, SBI_TEZOS_ED25519_VERIFY, SBI_TEZOS_INBOX_NEXT,
    SBI_TEZOS_METADATA_REVEAL,
};
use thiserror::Error;

/// Fatal errors that occur during SBI handling
#[derive(Debug, Error)]
pub enum PvmSbiFatalError {
    /// The PVM was in an unexpected state.
    #[error("Expected PVM status {expected:?}, got {got:?}")]
    UnexpectedStatus { expected: PvmStatus, got: PvmStatus },

    /// Unsupported SBI extension.
    #[error("Unsupported SBI extension {sbi_extension}")]
    BadSBIExtension { sbi_extension: u64 },

    /// Unsupported Tezos SBI extension function.
    #[error("Unsupported Tezos SBI extension function {sbi_function}")]
    BadTezosSBIFunction { sbi_function: u64 },

    /// Received an ECALL from M-mode.
    #[error("ECALLs from M-mode are not supported")]
    EcallFromMMode,

    /// Encountered a machine exception (e.g. during address translation).
    #[error("Encountered an exception: {exception:?}")]
    Exception {
        #[from]
        exception: Exception,
    },

    /// A memory access was out of bounds.
    #[error("Encountered an out-of-bounds memory access")]
    MemoryAccess {
        #[from]
        oob: OutOfBounds,
    },

    /// A ed25519 operation failed.
    #[error("Error during Ed25519 operation: {error:?}")]
    Ed25519Error {
        #[from]
        error: ed25519_dalek::SignatureError,
    },

    /// A BLAKE2B operation failed.
    #[error("Error during BLAKE2B operation: {error:?}")]
    Blake2BError {
        #[from]
        error: tezos_crypto_rs::blake2b::Blake2bError,
    },
}

/// Layout for [`PvmSbiState`]
pub type PvmSbiLayout = EnumCellLayout<u8>;

/// PVM execution environment state
pub struct PvmSbiState<M: Manager> {
    status: EnumCell<PvmStatus, u8, M>,
}

impl<M: Manager> PvmSbiState<M> {
    /// Get the current PVM status.
    pub fn status(&self) -> PvmStatus {
        self.status.read_default()
    }

    /// Respond to a request for input with no input. Returns `false` in case the
    /// machine wasn't expecting any input, otherwise returns `true`.
    pub fn provide_no_input<ML: MainMemoryLayout>(
        &mut self,
        machine: &mut MachineState<ML, M>,
    ) -> bool {
        // This method should only do something when we're waiting for input.
        match self.status() {
            PvmStatus::WaitingForInput => {}
            _ => return false,
        }

        // We're evaluating again after this.
        self.status.write(PvmStatus::Evaluating);

        // Zeros in all these registers is equivalent to 'None'.
        machine.hart.xregisters.write(a0, 0);
        machine.hart.xregisters.write(a1, 0);
        machine.hart.xregisters.write(a2, 0);

        true
    }

    /// Provide input information to the machine. Returns `false` in case the
    /// machine wasn't expecting any input, otherwise returns `true`.
    pub fn provide_input<ML: MainMemoryLayout>(
        &mut self,
        machine: &mut MachineState<ML, M>,
        level: u64,
        counter: u64,
        payload: &[u8],
    ) -> bool {
        // This method should only do something when we're waiting for input.
        match self.status() {
            PvmStatus::WaitingForInput => {}
            _ => return false,
        }

        // We're evaluating again after this.
        self.status.write(PvmStatus::Evaluating);

        // These arguments should have been set by the previous SBI call.
        let arg_buffer_addr = machine.hart.xregisters.read(a0);
        let arg_buffer_size = machine.hart.xregisters.read(a1);

        // The argument address is a virtual address. We need to translate it to
        // a physical address.
        let phys_dest_addr = match machine.translate(arg_buffer_addr, AccessType::Store) {
            Ok(phys_addr) => phys_addr,
            Err(_exc) => {
                // We back out on failure.
                machine.hart.xregisters.write(a0, 0);
                machine.hart.xregisters.write(a1, 0);
                machine.hart.xregisters.write(a2, 0);
                return true;
            }
        };

        // The SBI caller expects the payload to be returned at [phys_dest_addr]
        // with at maximum [max_buffer_size] bytes written.
        let max_buffer_size = cmp::min(arg_buffer_size as usize, payload.len());
        let write_res = machine
            .bus
            .write_all(phys_dest_addr, &payload[..max_buffer_size]);

        if write_res.is_err() {
            // We back out on failure.
            machine.hart.xregisters.write(a0, 0);
            machine.hart.xregisters.write(a1, 0);
            machine.hart.xregisters.write(a2, 0);
        } else {
            // Write meta information as return data.
            machine.hart.xregisters.write(a0, level);
            machine.hart.xregisters.write(a1, counter);
            machine.hart.xregisters.write(a2, max_buffer_size as u64);
        }

        true
    }

    /// Provide metadata in response to a metadata request. Returns `false`
    /// if the machine is not expecting metadata.
    pub fn provide_metadata<ML: MainMemoryLayout>(
        &mut self,
        machine: &mut MachineState<ML, M>,
        rollup_address: &[u8; 20],
        origination_level: u64,
    ) -> bool {
        // This method should only do something when we're waiting for metadata.
        match self.status() {
            PvmStatus::WaitingForMetadata => {}
            _ => return false,
        }

        // We're evaluating again after this.
        self.status.write(PvmStatus::Evaluating);

        // These arguments should have been set by the previous SBI call.
        let arg_buffer_addr = machine.hart.xregisters.read(a0);

        // The argument address is a virtual address. We need to translate it to
        // a physical address.
        let phys_dest_addr = match machine.translate(arg_buffer_addr, AccessType::Store) {
            Ok(phys_addr) => phys_addr,
            Err(_exc) => {
                // TODO: https://app.asana.com/0/1206655199123740/1207434664665316/f
                // Error handling needs to be improved.
                machine.hart.xregisters.write(a0, 0);
                return true;
            }
        };

        let write_res = machine
            .bus
            .write_all(phys_dest_addr, rollup_address.as_slice());

        if write_res.is_err() {
            // TODO: https://app.asana.com/0/1206655199123740/1207434664665316/f
            // Error handling needs to be improved.
            machine.hart.xregisters.write(a0, 0);
        } else {
            machine.hart.xregisters.write(a0, origination_level);
        }

        true
    }

    /// Handle a [SBI_TEZOS_INBOX_NEXT] call.
    fn handle_tezos_inbox_next(&mut self) -> Result<bool, PvmSbiFatalError> {
        // This method only makes sense when evaluating.
        match self.status() {
            PvmStatus::Evaluating => {}
            status => {
                return Err(PvmSbiFatalError::UnexpectedStatus {
                    expected: PvmStatus::Evaluating,
                    got: status,
                });
            }
        }

        // Prepare the EE state for an input tick.
        self.status.write(PvmStatus::WaitingForInput);

        // We can't evaluate after this. The next step is an input step.
        Ok(false)
    }

    /// Handle a [SBI_TEZOS_META] call.
    fn handle_tezos_metadata_reveal(&mut self) -> Result<bool, PvmSbiFatalError>
    where
        M: Manager,
    {
        // This method only makes sense when evaluating.
        match self.status() {
            PvmStatus::Evaluating => {}
            status => {
                return Err(PvmSbiFatalError::UnexpectedStatus {
                    got: status,
                    expected: PvmStatus::Evaluating,
                })
            }
        }

        // Prepare the EE state for a reveal metadata tick.
        self.status.write(PvmStatus::WaitingForMetadata);

        // We can't evaluate after this. The next step is a revelation step.
        Ok(false)
    }

    /// Produce a Ed25519 signature.
    fn handle_tezos_ed25519_sign<ML: MainMemoryLayout>(
        machine: &mut MachineState<ML, M>,
    ) -> Result<bool, PvmSbiFatalError> {
        let arg_sk_addr = machine.hart.xregisters.read(a0);
        let arg_msg_addr = machine.hart.xregisters.read(a1);
        let arg_msg_len = machine.hart.xregisters.read(a2);
        let arg_sig_addr = machine.hart.xregisters.read(a3);

        let sk_addr = machine.translate(arg_sk_addr, AccessType::Load)?;
        let msg_addr = machine.translate(arg_msg_addr, AccessType::Load)?;
        let sig_addr = machine.translate(arg_sig_addr, AccessType::Store)?;

        let mut sk_bytes = [0u8; 32];
        machine.bus.read_all(sk_addr, &mut sk_bytes)?;
        let sk = SigningKey::try_from(sk_bytes.as_slice())?;
        sk_bytes.fill(0);

        let mut msg_bytes = vec![0; arg_msg_len as usize];
        machine.bus.read_all(msg_addr, &mut msg_bytes)?;

        let sig = sk.sign(msg_bytes.as_slice());
        let sig_bytes: [u8; 64] = sig.to_bytes();
        machine.bus.write_all(sig_addr, &sig_bytes)?;

        Ok(true)
    }

    /// Verify a Ed25519 signature.
    fn handle_tezos_ed25519_verify<ML: MainMemoryLayout>(
        machine: &mut MachineState<ML, M>,
    ) -> Result<bool, PvmSbiFatalError> {
        let arg_pk_addr = machine.hart.xregisters.read(a0);
        let arg_sig_addr = machine.hart.xregisters.read(a1);
        let arg_msg_addr = machine.hart.xregisters.read(a2);
        let arg_msg_len = machine.hart.xregisters.read(a3);

        let pk_addr = machine.translate(arg_pk_addr, AccessType::Load)?;
        let sig_addr = machine.translate(arg_sig_addr, AccessType::Store)?;
        let msg_addr = machine.translate(arg_msg_addr, AccessType::Load)?;

        let mut pk_bytes = [0u8; 32];
        machine.bus.read_all(pk_addr, &mut pk_bytes)?;

        let mut sig_bytes = [0u8; 64];
        machine.bus.read_all(sig_addr, &mut sig_bytes)?;

        let mut msg_bytes = vec![0u8; arg_msg_len as usize];
        machine.bus.read_all(msg_addr, &mut msg_bytes)?;

        let pk = VerifyingKey::try_from(pk_bytes.as_slice())?;
        let sig = Signature::from_slice(sig_bytes.as_slice())?;
        let valid = pk.verify_strict(msg_bytes.as_slice(), &sig).is_ok();

        machine.hart.xregisters.write(a0, valid as u64);

        Ok(true)
    }

    /// Compute a BLAKE2B 256-bit digest.
    fn handle_tezos_blake2b_hash256<ML: MainMemoryLayout>(
        machine: &mut MachineState<ML, M>,
    ) -> Result<bool, PvmSbiFatalError> {
        let arg_out_addr = machine.hart.xregisters.read(a0);
        let arg_msg_addr = machine.hart.xregisters.read(a1);
        let arg_msg_len = machine.hart.xregisters.read(a2);

        let out_addr = machine.translate(arg_out_addr, AccessType::Store)?;
        let msg_addr = machine.translate(arg_msg_addr, AccessType::Load)?;

        let mut msg_bytes = vec![0u8; arg_msg_len as usize];
        machine.bus.read_all(msg_addr, &mut msg_bytes)?;

        let hash = tezos_crypto_rs::blake2b::digest_256(msg_bytes.as_slice())?;
        machine.bus.write_all(out_addr, hash.as_slice())?;

        Ok(true)
    }

    /// Handle a [SBI_SHUTDOWN] call.
    fn handle_shutdown(&self) -> Result<bool, PvmSbiFatalError> {
        // Shutting down in the PVM does nothing at the moment.
        Ok(true)
    }

    /// Handle a [SBI_CONSOLE_PUTCHAR] call.
    fn handle_console_putchar<ML: MainMemoryLayout>(
        &self,
        machine: &mut MachineState<ML, M>,
        hooks: &mut PvmHooks,
    ) -> Result<bool, PvmSbiFatalError> {
        let char = machine.hart.xregisters.read(a0) as u8;
        (hooks.putchar_hook)(char);

        // This call always succeeds.
        machine.hart.xregisters.write(a0, 0);

        Ok(true)
    }

    /// Bind the PVM SBI handler state to the allocated space.
    pub fn bind(space: AllocatedOf<PvmSbiLayout, M>) -> Self {
        Self {
            status: EnumCell::bind(space),
        }
    }

    /// Reset the PVM SBI handler.
    pub fn reset(&mut self) {
        self.status.reset();
    }

    /// Handle a PVM SBI call. Returns `Ok(true)` if it makes sense to continue evaluation.
    pub fn handle_call<ML: MainMemoryLayout>(
        &mut self,
        machine: &mut MachineState<ML, M>,
        hooks: &mut PvmHooks,
        env_exception: EnvironException,
    ) -> Result<bool, PvmSbiFatalError> {
        if let EnvironException::EnvCallFromMMode = env_exception {
            return Err(PvmSbiFatalError::EcallFromMMode);
        }

        // No matter the outcome, we need to bump the
        // program counter because ECALL's don't update it
        // to the following instructions.
        let pc = machine.hart.pc.read() + Instr::Ecall.width();
        machine.hart.pc.write(pc);

        // SBI extension is contained in a7.
        let sbi_extension = machine.hart.xregisters.read(a7);

        match sbi_extension {
            SBI_CONSOLE_PUTCHAR => self.handle_console_putchar(machine, hooks),
            SBI_SHUTDOWN => self.handle_shutdown(),
            SBI_FIRMWARE_TEZOS => {
                let sbi_function = machine.hart.xregisters.read(a6);

                match sbi_function {
                    SBI_TEZOS_INBOX_NEXT => self.handle_tezos_inbox_next(),
                    SBI_TEZOS_METADATA_REVEAL => self.handle_tezos_metadata_reveal(),
                    SBI_TEZOS_ED25519_SIGN => Self::handle_tezos_ed25519_sign(machine),
                    SBI_TEZOS_ED25519_VERIFY => Self::handle_tezos_ed25519_verify(machine),
                    SBI_TEZOS_BLAKE2B_HASH256 => Self::handle_tezos_blake2b_hash256(machine),

                    // Unimplemented
                    _ => Err(PvmSbiFatalError::BadTezosSBIFunction { sbi_function }),
                }
            }

            // Unimplemented
            _ => Err(PvmSbiFatalError::BadSBIExtension { sbi_extension }),
        }
    }
}
