// SPDX-FileCopyrightText: 2023 Functori <contact@functori.com>
// SPDX-FileCopyrightText: 2023 Nomadic Labs <contact@nomadic-labs.com>
// SPDX-FileCopyrightText: 2024 Trilitech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT
use crate::error::Error;
use crate::error::UpgradeProcessError::Fallback;
use crate::storage::{
    read_chain_id, read_storage_version, store_storage_version, DELAYED_BRIDGE,
    STORAGE_VERSION,
};
use tezos_smart_rollup_host::runtime::Runtime;

pub enum MigrationStatus {
    None,
    InProgress,
    Done,
}

fn is_etherlink_ghostnet(host: &impl Runtime) -> anyhow::Result<bool> {
    let chain_id = read_chain_id(host)?;
    Ok(chain_id == 128123.into())
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
        if is_etherlink_ghostnet(host)? {
            host.store_write_all(
                &DELAYED_BRIDGE,
                b"KT1J9H3fCg4WxRAR2ELZkWoZZYV9pHJhSWUB",
            )?;
        }
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
