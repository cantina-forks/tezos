local grafana = import '../vendors/grafonnet-lib/grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local template = grafana.template;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local logPanel = grafana.logPanel;
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

  checkpointLevel:
    singlestat.new(
      title='Current checkpoint level',
      datasource='Prometheus',
      format='none',
      valueName='max',
    ).addTarget(
      prometheus.target(
        'tezos_metrics_chain_checkpoint_level',
        legendFormat='current checkpoint level',
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

  headOperations:
    local transaction = 'Transaction';
    local endorsement = 'Endorsement';
    local double_baking_evidence = 'Double baking evidence';
    local delegation = 'delegation';
    local ballot = 'ballot';
    local double_endorsement_evidence = 'double endorsement evidence';
    local origination = 'origination';
    local proposals = 'proposals';
    local seed_nonce_revelation = 'seed nonce revelation';
    local reveal = 'reveal';
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
        'tezos_metrics_chain_head_double_baking_evidence',
        legendFormat=double_baking_evidence,
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
        'tezos_metrics_chain_head_double_endorsement_evidence',
        legendFormat=double_endorsement_evidence,
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
    ),

  //## GC

  gcOperations:
    local minor = 'Minor collections';
    local major = 'Major collections';
    local compact = 'Heap compactions';
    graphPanel.new(
      title='CG maintenance operations',
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
      title='CG minor and mjor word sizes',
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
