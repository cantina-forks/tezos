// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

//TODO: Move to separate sequencer crate

use std::sync::Arc;

use tokio::sync::broadcast;

pub mod protocol;

pub mod rpc_server;

pub mod cli;

const BUFFER_CAPACITY: usize = 10;

/// Starts the sequencer sidecar. In particular, this functions starts the
/// sequencer
pub async fn start(
    args: cli::Args,
    rx_shutdown: broadcast::Receiver<Arc<dyn std::error::Error + Send + Sync>>,
    tx_shutdown: broadcast::Sender<Arc<dyn std::error::Error + Send + Sync>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let cli::Args {
        rpc_address,
        preblock_time,
    } = args;
    let (tx_proposals, rx_proposals) = tokio::sync::mpsc::channel(BUFFER_CAPACITY);
    let (tx_preblocks, rx_preblocks) = tokio::sync::broadcast::channel(BUFFER_CAPACITY);
    let protocol_runner =
        protocol::ProtocolRunner::spawn(rx_proposals, tx_preblocks, preblock_time.into());
    // It is fine to leak the protocol client, as this reference must be valid for the whole program execution
    // TODO: Handle graceful shutdown
    let protocol_client = protocol::ProtocolClient::new(tx_proposals, rx_preblocks);
    // TODO: Move to async handler, handle graceful shutdown.
    let server = tokio::spawn(rpc_server::start_server(
        rpc_address,
        protocol_client,
        rx_shutdown,
        tx_shutdown,
    ));
    //TODO: Handle shutdowns
    let _ = tokio::join!(server, protocol_runner);
    Ok(())
}
