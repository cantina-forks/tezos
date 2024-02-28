// SPDX-FileCopyrightText: 2023 Functori <contact@functori.com>
// SPDX-FileCopyrightText: 2023 Nomadic Labs <contact@nomadic-labs.com>
// SPDX-FileCopyrightText: 2024 Trilitech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT
use crate::error::Error;
use crate::error::UpgradeProcessError::Fallback;
use crate::storage::{
    read_storage_version, store_storage_version, EVM_BASE_FEE_PER_GAS, EVM_BLOCKS,
    EVM_INDEXES, EVM_TRANSACTIONS_OBJECTS, EVM_TRANSACTIONS_RECEIPTS, SEQUENCER_ADMIN,
    SEQUENCER_POOL_PATH, STORAGE_VERSION,
};
use evm_execution::account_storage::EVM_ACCOUNTS_PATH;
use tezos_smart_rollup_host::path::RefPath;
use tezos_smart_rollup_host::runtime::{Runtime, RuntimeError};

pub enum MigrationStatus {
    None,
    InProgress,
    Done,
}

fn allow_path_not_found(res: Result<(), RuntimeError>) -> Result<(), RuntimeError> {
    match res {
        Ok(()) => Ok(()),
        Err(RuntimeError::PathNotFound) => Ok(()),
        Err(err) => Err(err),
    }
}

fn migrate_world_state(host: &mut impl Runtime) -> Result<(), Error> {
    allow_path_not_found(
        host.store_move(&RefPath::assert_from(b"/eth_accounts"), &EVM_ACCOUNTS_PATH),
    )?;
    allow_path_not_found(host.store_move(
        &RefPath::assert_from(b"/transactions_receipts"),
        &EVM_TRANSACTIONS_RECEIPTS,
    ))?;
    allow_path_not_found(host.store_move(
        &RefPath::assert_from(b"/transactions_objects"),
        &EVM_TRANSACTIONS_OBJECTS,
    ))?;
    allow_path_not_found(
        host.store_move(&RefPath::assert_from(b"/blocks"), &EVM_BLOCKS),
    )?;
    allow_path_not_found(
        host.store_move(&RefPath::assert_from(b"/indexes"), &EVM_INDEXES),
    )?;
    allow_path_not_found(host.store_move(
        &RefPath::assert_from(b"/fees/sequencer_pool_address"),
        &SEQUENCER_POOL_PATH,
    ))?;
    allow_path_not_found(host.store_move(
        &RefPath::assert_from(b"/fees"),
        &RefPath::assert_from(b"/world_state/fees"),
    ))?;
    allow_path_not_found(host.store_move(
        &RefPath::assert_from(b"/base_fee_per_gas"),
        &EVM_BASE_FEE_PER_GAS,
    ))?;
    Ok(())
}
fn update_sequencer_admin(host: &mut impl Runtime) -> Result<(), Error> {
    let contract_b58 = "KT1Cy5nsZnCMVLhwMafYDQ46QQLngYifb1Yh";
    let bytes = contract_b58.as_bytes();
    host.store_write_all(&SEQUENCER_ADMIN, bytes)
        .map_err(Into::into)
}

// The workflow for migration is the following:
//
// - bump `storage::STORAGE_VERSION` by one
// - fill the scope inside the conditional in `storage_migration` with all the
//   needed migration functions
// - compile the kernel and run all the E2E migration tests to make sure all the
//   data is still available from the EVM proxy-node.
//
// /!\
//     If the migration takes more than 999 reboots, we will lose the inbox
//     of a level. At least one reboot must be allocated to the stage one
//     to consume the inbox. Therefore, if the migration happens to take more
//     than 999 reboots, you have to rethink this. This limitation exists
//     because we consider that the inbox should not be collected during
//     a migration because it impacts the storage. We could in theory end up
//     in an inconsistent storage.
// /!\
//
fn migration<Host: Runtime>(host: &mut Host) -> anyhow::Result<MigrationStatus> {
    let current_version = read_storage_version(host)?;
    if STORAGE_VERSION == current_version + 1 {
        // MIGRATION CODE - START
        migrate_world_state(host)?;
        update_sequencer_admin(host)?;
        // MIGRATION CODE - END
        store_storage_version(host, STORAGE_VERSION)?;
        return Ok(MigrationStatus::Done);
    }
    Ok(MigrationStatus::None)
}

pub fn storage_migration<Host: Runtime>(
    host: &mut Host,
) -> Result<MigrationStatus, Error> {
    let migration_result = migration(host);
    migration_result.map_err(|_| Error::UpgradeError(Fallback))
}
