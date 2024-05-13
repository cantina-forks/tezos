# Changelog

## Version for NEXT

### Features

- Support daily log files for the observer mode (!13101).
- The RPC `eth_getBalance`, `eth_getCode`, `eth_getTransactionCount`
  and `eth_getStorageAt` support the default block parameter (https://ethereum.org/en/developers/docs/apis/json-rpc/#default-block).
  (!13039, !13056, !13058, !13124)
- Support partially https://eips.ethereum.org/EIPS/eip-1898, the
  `requireCanonical` field is not yet supported. (!12345)
- The RPC `eth_call` supports the default block parameter
  (https://ethereum.org/en/developers/docs/apis/json-rpc/#default-block). (!13110)
- Support the RPC `eth_maxPriorityFeePerGas`, which always returns 0 wei. (!13161)
- Support for specifying an expected time between blocks for the observer node
  in the configuration file, used to detect when the connection with the
  upstream EVM node endpoint is stalled. (!13265)
- Support for the `charset` specifier for `Content-Type: application/json`. (!13256)

### Experimental

- Support for write-ahead log journal mode for the EVM node’s store. (!13192)

### Bug fixes

### Breaking changes

### Internal

## Version for b9f6c9138719220db83086f0548e49c5c4c8421f

### Features

- Add `run <mode>` command and deprecate other commands (!12789). Now
  the preferred way to run any mode are:
  - `run proxy`
  - `run sequencer`
  - `run observer`
- Add config for: (!12920)
  - max blueprints lag
  - max blueprints ahead
  - max blueprints catchup
  - catchup cooldown
  - log filter max number of blocks
  - log filter max number of logs
  - log filter chunk size
- Generalize 'keep-alive' option to all mode and rpc to the rollup
  node, not only when bootstrapping the proxy mode. 'keep-alive' retry
  rpcs to the rollup node when it fails with a connection
  error. (!12800)
- Add command "make kernel installer config <file>" that generates a
  configuration file filled with all the values given in
  argument. (!12764)
- Add a 'keep_alive' line in the configuration. (!12800)
- Add a `verbose` line for logs in the configuration. It sets the
  verbose level of the logs ( `debug`, `info`, `notice`, `warning`,
  `error`, `fatal`). Command line option `--verbose` set it `debug`,
  by default it's `notice`. (!12917, !12345)
- The transaction pool is now removing any transaction that was included more
  than a defined threshold ago (one hour by default). (!12741)
- The transaction pool imposes a limit of users permitted simultaneously
  (4000 by default). (!12749)
- The transaction pool has a threshold of simultaneous transactions allowed per user
  (16 by default). (!12749)
- The transaction pool will reject transactions that can not be contained within
  the size of a blueprint. (!12834)
- The new command `replay blueprint` allows to replay a given blueprint with
  arbitrary kernels. (!12850, !12854, !12855)
- The new command `init config` allows to initialize a new configuration file
  for an EVM node. (!12798)
- Observers now try to reconnect to their EVM endpoint if necessary. (!12772)
- The sequencer can read its smart rollup address from its store and check
  whether it's consistent with the rollup node endpoint. (!12345)

### Bug fixes

- The blueprints streaming RPC accepts to start from the next blueprint level.
  (!12753)
- The RPC `eth_getLogs` now fails when a request exceeds its limits (in blocks
  range or log numbers). (!12905)
- Observers do not stop when the rollup node they are connected to advertise a
  blueprint application for a level in the future. (!12753)
- The observer does not hang anymore when trying to reconnect to a sequencer that
  is still down. (!13024)
- Preimages default directory is now `<data_dir>/wasm_2_0_0` instead of
  `$HOME/.octez-evm-node/_evm_installer_preimages`. (!13070)

### Breaking changes

- The `mode` field of the configuration file has been removed, and replaced
  with `proxy`, `sequencer` and `observer` to configure each mode individually.
  (!12743)
- The EVM node will no longer modify its configuration file based on its
  CLI arguments. (!12799)
- Replace `observer.rollup_node_endpoint`,
  `proxy.rollup_node_endpoint` and `sequencer.rollup_node_endpoint`
  with `rollup_node_endpoint` in the configuration. (!12764)
- Remove `proxy` in the configuration. (!12764)
- `sequencer.sequencer` in the configuration now is the secret key
   instead of the public key hash (e.g. "unencrypted:<edsk...>",
   "encrypted:...", "tcp://...", ). (!12918)

### Internal

## Version for d517020b58afef0e15c768ee0b5acbda1786cdd8

### Features

- Observers now follows a rollup node. (!12547)
- Wait for rollup node to reconnect if it's not available. (!12561)
- Filter out irrelevant events in observer mode. (!12607)
- Forward delayed transactions to observer nodes. (!12606)
- Limit the size of blueprints. (!12666)

### Bug fixes

- Store last known level even if there are no events. (!12590)

### Breaking changes

### Internal

- Improve internal storage handling. (!12551,!12516, !12572, !12627)
- Merge publishable and executable blueprints. (!12571)
- Store delayed transactions in the EVM Context. (!12605)
- Reduce verbosity of events. (!12622)

## Version for 0a81ce76b3d4f57d8c5194bcb9418f9294fd2be1

### Features

- The private RPC server is no longer launched by default. You need to provide
  the parameter `--private-rpc-port` to launch it. (!12449)
- Delayed EVM transactions no longer pay data-availability fee. (!12401)
- Stop block production if the rollup is lagging behind. (!12482)
- Add a private RPC to access the storage. (!12504)
- The kernel logs are now stored under `<data-dir>/kernel_logs/` and events
  are emitted. (!12345)

### Bug fixes

- The transaction pool checks if a transaction can be prepayed before
  inclusion and injection. (!12342)

### Breaking changes

- Delayed Transactions use a dedicated encoding tag in the block in progress. (!12401)
- Record timestamps in executable blueprints. (!12487)

### Internal

- If an error occurs during transaction injection, the trace of errors is
  logged. (!12451)
- Improve resiliency to errors. (!12431)
- Better catchup of possibly missed events. (!12365)
- Improve upgrade detection. (!12459)
- Don't import the delayed inbox when initializing from rollup. (!12506)
- Forbid raw delayed transactions in blueprints sent to the rollup. (!12508)
- Add event for delayed transactions. (!12513)

## Version for 79509a69d01c38eeba38d6cc7a323b4d69c58b94

### Features

- Fetch WASM preimages from a remote endpoint. (!12060)
- When the sequencer evm node diverged from rollup node it fails with
  exit code 100. (!12214)
- Add a new RPC (tez_kernelRootHash) to retrieve the root hash used during the
  last upgrade (!12352)

### Bug fixes

### Breaking changes

### Internal

## Version for 624a144032d6dc6431697c39eb81790bccaacff9

### Features

- Detect when a sequencer upgrade evm event is seen in the rollup node
  kernel. The sequencer upgrade is applied to the sequencer local
  storage. (!12046)
- Version the sequencer store and supports migrations. (!12165)
- Revert message are now propagated in the `data` field of the error. (!11906)

### Bug fixes

### Breaking changes

### Internal

## Version for kernel 20ab639f09a8c7c76f982383c3d9e1f831f38088

### Features

- The sequencer node supports the latest format of the delayed inbox including
  a timeout in number of blocks. (!11811)

### Bug fixes

- Fix `address` parameter to `eth_getLogs` RPC service. (!11990)

### Breaking Changes

- The sequencer and observer nodes now store their locally applied blueprints
  in a sqlite database (as a consquence, the node now depends on `libsqlite3`).
  (!11948)


## Version for kernel c5969505b81b52a779270b69f48b6a66c84da429

### Features

- The sequencer node produces blueprints mentioning the expected context hash
  on which it should be applied. (!11644)
- The sequencer node features a “catch-up mechanism” where it tries sending
  its blueprints again when the difference between its local head and the one
  of the rollup node it is connected to becomes to large. (!11808)
- The sequencer node supports the new features of the delayed inbox, namely the
  timeout mechanism. (!11667)
- The observer node now applies the executable blueprints streamed by other EVM
  node endpoints locally. (!11803)
- The observer node now exposes the JSON RPC API endpoint and the EVM node
  specific services. (!11741)
- Improve the simulation endpoint (in particular to be more meaningful in case
  of errors). (!11816)
- Support parameterizing the limit on the number of active connections. (!11870)
- Support daily log files. (!11752)

### Breaking changes

- The sequencer node now stores its blueprint in `$data_dir/blueprint/execute`
  and `$data_dir/blueprint/publish` (previously, it was only storing the
  executable blueprint in `$data_dir/blueprint`). (!11878)

## Version for kernel 9978f3a5f8bee0be78686c5c568109d2e6148f13

### Features

- Stream the L2 blocks to give a faster and more consistent inclusion of
  transactions on the L1. (!11102)
- Add a keep alive argument that waits until the connection is made with the
  rollup node. (!11236)
- The chunker can also produce blueprints out of the given bytes. (!11497)

### Bug fixes

- Simulation errors are better propagated. (!11381)

### Breaking changes

- The node no longer show the RPC requests by default, you need to specify the
  `--verbose` flag to log the inputs and outputs of RPC. (!11475)
