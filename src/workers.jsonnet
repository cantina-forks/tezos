// Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

local grafana = import '../vendors/grafonnet-lib/grafonnet/grafana.libsonnet';
local singlestat = grafana.singlestat;
local statPanel = grafana.statPanel;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local transformation = grafana.transformation;
local namespace = 'octez';
local node_instance = '{' + std.extVar('node_instance_label') + '="$node_instance"}';

//##
// Workers
//##
{
  requests:
    local blockRequests = 'Block validator request count';
    local blockCompletions = 'Block validator completion count';
    local blockErrors = 'Block validator error count';
    local chainRequests = 'Chain validator request count';
    local chainCompletions = 'Chain validator completion count';
    local chainErrors = 'Chain validator error count';
    local prevalidatorRequests = 'Prevalidator validator request count';
    local prevalidatorCompletions = 'Prevalidator validator completion count';
    local prevalidatorErrors = 'Prevalidator validator error count';
    graphPanel.new(
      title='Validation workers requests',
      datasource='Prometheus',
      linewidth=1,
      format='none',
      legend_alignAsTable=true,
      legend_rightSide=true,
      legend_current=true,
      legend_values=true,
    ).addTargets([
      prometheus.target(
        namespace + '_validator_block_worker_request_count' + node_instance,
        legendFormat=blockRequests,
      ),
      prometheus.target(
        namespace + '_validator_block_worker_completion_count' + node_instance,
        legendFormat=blockCompletions,
      ),
      prometheus.target(
        namespace + '_validator_block_worker_request_error_count' + node_instance,
        legendFormat=blockErrors,
      ),
      prometheus.target(
        namespace + '_validator_chain_worker_request_count' + node_instance,
        legendFormat=chainRequests,
      ),
      prometheus.target(
        namespace + '_validator_chain_worker_completion_count' + node_instance,
        legendFormat=chainCompletions,
      ),
      prometheus.target(
        namespace + '_validator_chain_worker_error_count' + node_instance,
        legendFormat=chainErrors,
      ),
      prometheus.target(
        namespace + '_mempool_worker_request_count' + node_instance,
        legendFormat=prevalidatorRequests,
      ),
      prometheus.target(
        namespace + '_mempool_worker_completion_count' + node_instance,
        legendFormat=prevalidatorCompletions,
      ),
      prometheus.target(
        namespace + '_mempool_worker_error_count' + node_instance,
        legendFormat=prevalidatorErrors,
      ),
    ]),

  distributedDB:
    local headers_table = 'headers table';
    local headers_scheduler = 'headers scheduler';
    local operations_table = 'operations table';
    local operations_scheduler = 'operations scheduler';
    local operation_table = 'operation table';
    local operation_scheduler = 'operation scheduler';
    graphPanel.new(
      title='DDB Workers',
      datasource='Prometheus',
      linewidth=1,
      format='none',
      legend_alignAsTable=true,
      legend_current=false,
      legend_avg=true,
      legend_min=true,
      legend_max=true,
      legend_rightSide=true,
      legend_show=true,
      legend_total=false,
      legend_values=true,
      aliasColors={
      },
    ).addTargets([
      prometheus.target(
        namespace + '_distributed_db_requester_table_length{requester_kind="block_header",' + std.extVar('node_instance_label') + '="$node_instance"}',
        legendFormat=headers_table,
      ),
      prometheus.target(
        namespace + '_distributed_db_requester_scheduler_length{requester_kind="block_header",' + std.extVar('node_instance_label') + '="$node_instance"}',
        legendFormat=headers_scheduler,
      ),
      prometheus.target(
        namespace + '_distributed_db_requester_table_length{requester_kind="operations",' + std.extVar('node_instance_label') + '="$node_instance"}',
        legendFormat=operations_table,
      ),
      prometheus.target(
        namespace + '_distributed_db_requester_scheduler_length{requester_kind="operations",' + std.extVar('node_instance_label') + '="$node_instance"}',
        legendFormat=operations_scheduler,
      ),
      prometheus.target(
        namespace + '_distributed_db_requester_table_length{requester_kind="operation",' + std.extVar('node_instance_label') + '="$node_instance"}',
        legendFormat=operation_table,
      ),
      prometheus.target(
        namespace + '_distributed_db_requester_scheduler_length{requester_kind="operation",' + std.extVar('node_instance_label') + '="$node_instance"}',
        legendFormat=operation_scheduler,
      ),
    ]),

  peerValidators:
    local connections = 'connections';
    local invalid_blocks = 'invalid blocks';
    local invalid_locator = 'invalid locator';
    local new_branch_completed = 'new branch completed';
    local new_head_completed = 'new head completed';
    local on_no_request = 'on no request count';
    local new_branch = 'fetching canceled new branch';
    local new_known_valid_head = 'fetching canceled new known valid head';
    local new_unknown_head = 'fetching canceled knew unknown head';
    local system_error = 'system error';
    local too_short_locator = 'too short locator';
    local unavailable_protocol = 'unavailable protocol';
    local unknown_ancestor = 'unknown ancestor';
    local unknown_error = 'unknown error';
    graphPanel.new(
      title='Peer validators',
      datasource='Prometheus',
      linewidth=1,
      format='none',
      logBase1Y=10,
      aliasColors={
        [connections]: 'light-green',
        [invalid_blocks]: 'light-red',
        [invalid_locator]: 'light-orange',
        [new_branch_completed]: 'light-blue',
        [new_head_completed]: 'blue',
        [on_no_request]: 'white',
        [new_branch]: 'green',
        [new_known_valid_head]: 'light-yellow',
        [new_unknown_head]: 'light-orange',
        [system_error]: 'orange',
        [too_short_locator]: 'brown',
        [unavailable_protocol]: 'light-red',
        [unknown_ancestor]: 'yellow',
        [unknown_error]: 'red',
      },
    ).addTargets(
      [
        prometheus.target(
          namespace + '_validator_peer_connections' + node_instance,
          legendFormat=connections,
        ),
        prometheus.target(
          namespace + '_validator_peer_invalid_block' + node_instance,
          legendFormat=invalid_blocks,
        ),
        prometheus.target(
          namespace + '_validator_peer_invalid_locator' + node_instance,
          legendFormat=invalid_locator
        ),
        prometheus.target(
          namespace + '_validator_peer_new_branch_completed' + node_instance,
          legendFormat=new_branch_completed,
        ),
        prometheus.target(
          namespace + '_validator_peer_new_head_completed' + node_instance,
          legendFormat=new_head_completed,
        ),
        prometheus.target(
          namespace + '_validator_peer_on_no_request_count' + node_instance,
          legendFormat=on_no_request,
        ),
        prometheus.target(
          namespace + '_validator_peer_operations_fetching_canceled_new_branch' + node_instance,
          legendFormat=new_branch,
        ),
        prometheus.target(
          namespace + '_validator_peer_operations_fetching_canceled_new_known_valid_head' + node_instance,
          legendFormat=new_known_valid_head,
        ),
        prometheus.target(
          namespace + '_validator_peer_operations_fetching_canceled_new_unknown_head' + node_instance,
          legendFormat=new_unknown_head,
        ),
        prometheus.target(
          namespace + '_validator_peer_system_error' + node_instance,
          legendFormat=system_error,
        ),
        prometheus.target(
          namespace + '_validator_peer_too_short_locator' + node_instance,
          legendFormat=too_short_locator,
        ),
        prometheus.target(
          namespace + '_validator_peer_unavailable_protocol' + node_instance,
          legendFormat=unavailable_protocol,
        ),
        prometheus.target(
          namespace + '_validator_peer_unknown_ancestor' + node_instance,
          legendFormat=unknown_ancestor,
        ),
        prometheus.target(
          namespace + '_validator_peer_unknown_error' + node_instance,
          legendFormat=unknown_error,
        ),
      ]
    )
  ,

  peerValidatorErrorsMean:
    local system_error = namespace + '_validator_peer_system_error' + node_instance;
    local too_short_locator = namespace + '_validator_peer_too_short_locator' + node_instance;
    local unavailable_protocol = namespace + '_validator_peer_unavailable_protocol' + node_instance;
    local unknown_ancestor = namespace + '_validator_peer_unknown_ancestor' + node_instance;
    local unknown_error = namespace + '_validator_peer_unknown_error' + node_instance;
    statPanel.new(
      title='Peer validators errors',
      datasource='Prometheus',
    ).addTargets(
      [
        prometheus.target(
          system_error
        ),
        prometheus.target(
          too_short_locator
        ),
        prometheus.target(
          unavailable_protocol
        ),
        prometheus.target(
          unknown_ancestor
        ),
        prometheus.target(
          unknown_error
        ),
      ],
    ).addThresholds([
      {
        color: 'green',
        value: 0,
      },
      {
        color: 'red',
        value: 1,
      },
    ])
    .addTransformation(transformation.new('calculateField', options={
      mode: 'reduceRow',
      replaceFields: true,
      reducer: { reducer: 'sum' },
    })),

  validatorTreatmentRequests:
    local chainPush = namespace + '_validator_chain_last_finished_request_push_timestamp' + node_instance;
    local chainTreatment = namespace + '_validator_chain_last_finished_request_treatment_timestamp' + node_instance;
    local blockPush = namespace + '_validator_block_last_finished_request_push_timestamp' + node_instance;
    local blockTreatment = namespace + '_validator_block_last_finished_request_treatment_timestamp' + node_instance;
    local chainTreatmentTime = chainTreatment + ' - ' + chainPush;
    local blockTreatmentTime = blockTreatment + ' - ' + blockPush;
    local chain = 'chain validator';
    local block = 'block validator';
    graphPanel.new(
      title='Validators Requests Treatments',
      datasource='Prometheus',
      linewidth=1,
      format='s',
      legend_alignAsTable=true,
      legend_current=false,
      legend_avg=true,
      legend_min=true,
      legend_max=true,
      legend_values=true,
      aliasColors={
        [chain]: 'light-green',
        [block]: 'light-red',
      },
    ).addTargets([
      prometheus.target(
        chainTreatmentTime,
        legendFormat=chain,
      ),
      prometheus.target(
        blockTreatmentTime,
        legendFormat=block,
      ),
    ]),

  validatorCompletionRequests:
    local chainTreatment = namespace + '_validator_chain_last_finished_request_treatment_timestamp' + node_instance;
    local chainCompletion = namespace + '_validator_chain_last_finished_request_completion_timestamp' + node_instance;
    local blockTreatment = namespace + '_validator_block_last_finished_request_treatment_timestamp' + node_instance;
    local blockCompletion = namespace + '_validator_block_last_finished_request_completion_timestamp' + node_instance;
    local chainCompletionTime = chainCompletion + ' - ' + chainTreatment;
    local blockCompletionTime = blockCompletion + ' - ' + blockTreatment;
    local chain = 'chain validator';
    local block = 'block validator';
    graphPanel.new(
      title='Validators Requests Completion',
      datasource='Prometheus',
      linewidth=1,
      format='s',
      legend_alignAsTable=true,
      legend_current=false,
      legend_avg=true,
      legend_min=true,
      legend_max=true,
      legend_values=true,
      aliasColors={
        [chain]: 'light-green',
        [block]: 'light-red',
      },
    ).addTargets([
      prometheus.target(
        chainCompletionTime,
        legendFormat=chain,
      ),
      prometheus.target(
        blockCompletionTime,
        legendFormat=block,
      ),
    ]),

  chainValidatorRequestCompletionMean:
    local chainTreatment = namespace + '_validator_chain_last_finished_request_treatment_timestamp' + node_instance;
    local chainCompletion = namespace + '_validator_chain_last_finished_request_completion_timestamp' + node_instance;
    statPanel.new(
      title='Chain validator request completion',
      datasource='Prometheus',
    ).addTarget(
      prometheus.target(
        chainCompletion + ' - ' + chainTreatment
      )
    ).addThresholds([
      {
        color: 'green',
        value: 0,
      },
      {
        color: 'red',
        value: 1,
      },
    ]),

}
