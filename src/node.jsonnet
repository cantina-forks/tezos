local grafana = import '../vendors/grafonnet-lib/grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local template = grafana.template;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local logPanel = grafana.logPanel;
local heatmapPanel = grafana.heatmapPanel;
local loki = grafana.loki;
local prometheus = grafana.prometheus;

//##
// Tezos related stats
//##

{
  buildInfo:
    singlestat.new(
      title='Node release version',
      datasource='Prometheus',
      format='none',
      valueName='name',
    ).addTarget(
      prometheus.target(
        'tezos_metrics_info_version',
        legendFormat='{{ version }}<br/>{{ commit_hash }}'
      )
    ),

  # Reflects the uptime of the monitoring of the job, not the uptime
  # of the process.
  uptime:
    singlestat.new(
      title='Node uptime',
      datasource='Prometheus',
      format='dtdhms',
      valueName='max',
      description= 'Reflects the uptime of the monitoring of the job, not the uptime of the process.',
    ).addTarget(
      prometheus.target(
	'time()-(process_start_time_seconds{job="node"})',
	legendFormat='node uptime'
      )
    ),

  headLevel:
    singlestat.new(
      title='Current head level',
      datasource='Prometheus',
      format='none',
      valueName='max',
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_current_level',
        legendFormat='current head level',
      )
    ),

  savepointLevel:
    singlestat.new(
      title='Current savepoint level',
      datasource='Prometheus',
      format='none',
      valueName='max',
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_checkpoint_savepoint',
        legendFormat='current savepoint',
      )
    ),

  cabooseLevel:
    singlestat.new(
      title='Current caboose level',
      datasource='Prometheus',
      format='none',
      valueName='max',
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_checkpoint_caboose',
        legendFormat='current caboose',
      )
    ),

  headCycleLevel:
    singlestat.new(
      title='Current cycle',
      datasource='Prometheus',
      format='none',
      valueName='max',
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_current_cycle',
        legendFormat='Current cycle',
      )
    ),

  headHistory:
    local head = 'Head level';
    graphPanel.new(
      title='Head level history',
      datasource='Prometheus',
      linewidth=1,
      format='none',
      aliasColors={
        [head]: 'light-green',
      },
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_current_level',
        legendFormat=head,
      )
    ),

  invalidBlocksHistory:
    local blocks = 'Invalid blocks';
    graphPanel.new(
      title='Invalid blocks history',
      datasource='Prometheus',
      linewidth=1,
      format='none',
      aliasColors={
        [blocks]: 'light-green',
      },
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_invalid_blocks',
        legendFormat=blocks,
      )
    ),

  blocksPerSecond:
    heatmapPanel.new(
      title='Blocks per second',
      datasource='Prometheus',
      hideZeroBuckets=false,
      highlightCards=true,
      tooltip_show=true,
      tooltip_showHistogram=true,
    ).addTarget(
      prometheus.target(
	'rate(tezos_metrics_chain_current_level[5m])',
	format='time_series',
	legendFormat='5 minutes mean',)
    ),

  headOperations:
    local transaction = 'Transaction';
    local endorsement = 'Endorsement';
    local double_baking_evidence = 'Double baking evidence';
    local delegation = 'Delegation';
    local ballot = 'Ballot';
    local double_endorsement_evidence = 'Double endorsement evidence';
    local origination = 'Origination';
    local proposals = 'Proposals';
    local seed_nonce_revelation = 'Seed nonce revelation';
    local reveal = 'Reveal';
    graphPanel.new(
      title='Head operations',
      datasource='Prometheus',
      linewidth=1,
      format='none',
      decimals=0,
      legend_alignAsTable=true,
      legend_current=true,
      legend_avg=true,
      legend_min=true,
      legend_max=true,
      legend_rightSide=true,
      legend_show=true,
      legend_total=true,
      legend_values=true,
      aliasColors={
      },
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_transaction',
        legendFormat=transaction,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_endorsement_with_slot',
        legendFormat=endorsement,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_delegation',
        legendFormat=delegation,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_ballot',
        legendFormat=ballot,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_origination',
        legendFormat=origination,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_proposals',
        legendFormat=proposals,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_seed_nonce_revelation',
        legendFormat=seed_nonce_revelation,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_reveal',
        legendFormat=reveal,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_double_baking_evidence',
        legendFormat=double_baking_evidence,
      )
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_head_double_endorsement_evidence',
        legendFormat=double_endorsement_evidence,
      )
    ),

  //## GC

  gcOperations:
    local minor = 'Minor collections';
    local major = 'Major collections';
    local compact = 'Heap compactions';
    graphPanel.new(
      title='GC maintenance operations',
      datasource='Prometheus',
      linewidth=1,
      format='none',
      aliasColors={
        [minor]: 'light-green',
        [major]: 'light-yellow',
        [compact]: 'light-blue',
      },
    ).addTarget(
      prometheus.target(
        'ocaml_gc_minor_collections',
        legendFormat=minor,
      )
    ).addTarget(
      prometheus.target(
        'ocaml_gc_major_collections',
        legendFormat=major,
      )
    ).addTarget(
      prometheus.target(
        'ocaml_gc_major_compactions',
        legendFormat=compact,
      )
    ),

  gcMajorHeap:
    local major = 'Major heap';
    local top = 'Top major heap';
    graphPanel.new(
      title='GC minor and major word sizes',
      datasource='Prometheus',
      linewidth=1,
      format='bytes',
      aliasColors={
        [major]: 'light-green',
        [top]: 'light-blue',
      },
    ).addTarget(
      prometheus.target(
        'ocaml_gc_heap_words',
        legendFormat=major,
      )
    ).addTarget(
      prometheus.target(
        'ocaml_gc_top_heap_words',
        legendFormat=top,
      )
    ),

  //## Logs with Loky
  //# TODO
  logs:
    logPanel.new(
      title='Node logs',
      datasource='Loki'
    ).addTarget(
      prometheus.target(
        '{job="varlogs"}',
        legendFormat='Node logs',
      )
    ),

}
