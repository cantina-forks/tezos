local grafana = import '../vendors/grafonnet-lib/grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local template = grafana.template;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local row = grafana.row;


local node = import './node.jsonnet';
local p2p = import './p2p.jsonnet';
local node_hardware = import './node_hardware.jsonnet';
local delegate_hardware = import './delegate_hardware.jsonnet';
local workers = import './workers.jsonnet';
local logs = import './logs.jsonnet';

local boardtitle = 'Tezos full dashboard - branch: ' + std.extVar('branch');


//Position variables
local node_hardware_y = 47;
local p2p_y = 72;
local worker_y = 89;
local misc_y = 114;
local delegate_hardware_y = 123;
local logs_y = 132;

//###
// Grafana main stuffs
//##
dashboard.new(
  title=boardtitle,
  tags=['tezos', 'octez', 'hardware', 'logs'],
  schemaVersion=18,
  editable=true,
  time_from='now-3h',
  refresh='',
)

.addTemplate(
  template.new(
    name='node_instance',
    datasource='Prometheus',
    query='label_values(octez_version,' + std.extVar('node_instance_label') + ')',
    refresh='load',
    label='Node instance'
  )
)

#Node a grid is 24 slots wide
.addPanels(
  [
    //#######
    row.new(
      title='Node stats',
      repeat='',
      showTitle=true,
    ),
    node.bootstrapStatus { gridPos: { h: 3, w: 2, x: 0, y: 1 } },
    node.syncStatus { gridPos: { h: 3, w: 2, x: 2, y: 1 } },
    node.chainNameInfo { gridPos: { h: 3, w: 4, x: 4, y: 1 } },
    node.releaseVersionInfo { gridPos: { h: 3, w: 3, x: 8, y: 1 } },
    node.releaseCommitInfo { gridPos: { h: 3, w: 3, x: 11, y: 1 } },
    node.uptime { gridPos: { h: 3, w: 4, x: 0, y: 4 } },
    node.headLevel { gridPos: { h: 3, w: 4, x: 0, y: 7 } },
    node.p2pVersion { gridPos: { h: 3, w: 2, x: 0, y: 10 } },
    node.distributedDbVersion { gridPos: { h: 3, w: 2, x: 2, y: 10 } },
    node.savepointLevel { gridPos: { h: 3, w: 2, x: 0, y: 13 } },
    node.checkpointLevel { gridPos: { h: 3, w: 2, x: 2, y: 13 } },
    node.cabooseLevel { gridPos: { h: 3, w: 2, x: 0, y: 16 } },
    node.headCycleLevel { gridPos: { h: 3, w: 2, x: 2, y: 16 } },
    p2p.trustedPoints { gridPos: { h: 3, w: 2, x: 0, y: 19 } },
    p2p.privateConnections { gridPos: { h: 3, w: 2, x: 2, y: 19 } },
    node.headHistory { gridPos: { h: 10, w: 10, x: 4, y: 4 } },
    node.blocksValidationTime { gridPos: { h: 8, w: 10, x: 4, y: 14 } },
    logs.nodelogs { gridPos: { h: 21, w: 10, x: 14, y: 0 } },
    node.headOperations { gridPos: { h: 8, w: 14, x: 0, y: 22 } },
    node.invalidBlocksHistory { gridPos: { h: 8, w: 10, x: 14, y: 22 } },
    node.gasConsumedHistory { gridPos: { h: 8, w: 14, x: 0, y: 30 } },
    node.roundHistory { gridPos: { h: 8, w: 10, x: 14, y: 30 } },
    node.storeMergeTimeGraph { gridPos: { h: 8, w: 14, x: 0, y: 38 } },
    node.writtenBlockSize { gridPos: { h: 8, w: 10, x: 14, y: 38 } },

    //#######
    row.new(
      title='Node Hardware stats',
      repeat='',
      showTitle=true,
    ) + { gridPos: { h: 0, w: 8, x: 0, y: node_hardware_y } },
    node_hardware.cpu { gridPos: { h: 8, w: 12, x: 0, y: node_hardware_y } },
    node_hardware.memory { gridPos: { h: 8, w: 12, x: 12, y: node_hardware_y } },


    node_hardware.diskFreeSpace { gridPos: { h: 8, w: 2, x: 0, y: node_hardware_y + 8 } },
    node_hardware.storage { gridPos: { h: 8, w: 11, x: 2, y: node_hardware_y + 8 } },
    node_hardware.ios { gridPos: { h: 8, w: 11, x: 13, y: node_hardware_y + 8 } },

    node_hardware.networkIOS { gridPos: { h: 8, w: 12, x: 0, y: node_hardware_y + 16 } },
    node_hardware.fileDescriptors { gridPos: { h: 8, w: 12, x: 12, y: node_hardware_y + 16 } },

    //#######
    row.new(
      title='P2P stats',
      repeat='',
      showTitle=true,
    ) + { gridPos: { h: 0, w: 8, x: 0, y: p2p_y } },
    p2p.mempoolPending { gridPos: { h: 8, w: 12, x: 0, y: p2p_y } },
    p2p.totalConnections { gridPos: { h: 8, w: 12, x: 12, y: p2p_y } },

    p2p.peers { gridPos: { h: 8, w: 12, x: 0, y: p2p_y + 8 } },
    p2p.points { gridPos: { h: 8, w: 12, x: 12, y: p2p_y + 8 } },

    //#######
    row.new(
      title='Workers stats',
      repeat='',
      showTitle=true,
    ) + { gridPos: { h: 0, w: 8, x: 0, y: worker_y } },
    workers.requests { gridPos: { h: 8, w: 12, x: 0, y: worker_y } },
    workers.distributedDB { gridPos: { h: 8, w: 12, x: 12, y: worker_y } },
    workers.validatorTreatmentRequests { gridPos: { h: 8, w: 12, x: 0, y: worker_y + 16 } },
    workers.validatorCompletionRequests { gridPos: { h: 8, w: 12, x: 12, y: worker_y + 16 } },
    workers.peerValidators { gridPos: { h: 8, w: 12, x: 0, y: worker_y + 24 } },

    //#######
    row.new(
      title='Miscellaneous',
      repeat='',
      showTitle=true,
    ) + { gridPos: { h: 8, w: 8, x: 0, y: misc_y } },
    node.gcOperations { gridPos: { h: 8, w: 12, x: 0, y: misc_y } },
    node.gcMajorHeap { gridPos: { h: 8, w: 12, x: 12, y: misc_y } },

    //#######
    row.new(
      title='Delegates Hardware stats',
      repeat='',
      showTitle=true,
    ) + { gridPos: { h: 0, w: 8, x: 0, y: delegate_hardware_y } },
    delegate_hardware.cpu { gridPos: { h: 8, w: 8, x: 0, y: delegate_hardware_y } },
    delegate_hardware.memory { gridPos: { h: 8, w: 8, x: 8, y: delegate_hardware_y } },
    delegate_hardware.ios { gridPos: { h: 8, w: 8, x: 16, y: delegate_hardware_y } },

    //#######
    row.new(
      title='Logs',
      repeat='',
      showTitle=true,
    ) + { gridPos: { h: 0, w: 8, x: 0, y: logs_y } },
    logs.nodelogs { gridPos: { h: 10, w: 8, x: 0, y: logs_y } },
    logs.bakerlogs { gridPos: { h: 10, w: 8, x: 8, y: logs_y } },
    logs.accuserlogs { gridPos: { h: 10, w: 8, x: 16, y: logs_y } },
    logs.systemlogs { gridPos: { h: 14, w: 12, x: 0, y: logs_y + 10 } },

  ]
)
