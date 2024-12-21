local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local lokiEnabled = params.components.lokistack.enabled;
local forwarderEnabled = lokiEnabled || std.length(params.clusterLogForwarder) > 0;

// Make sure the default output is added to the pipelines `outputRefs`,
// if the logging stack is not disabled.
local pipelineOutputRefs(pipeline) =
  local default = if lokiEnabled then [ 'default' ] else [];
  std.get(pipeline, 'forwarders', []) + default;

// clusterLogForwarderSpec:
// Consecutively apply patches to result of previous apply.
local clusterLogForwarderSpec = {
  local appsPipeline = std.get(std.get(params.clusterLogForwarder, 'pipelines', {}), 'application-logs', {}),
  local infraPipeline = std.get(std.get(params.clusterLogForwarder, 'pipelines', {}), 'infrastructure-logs', {}),
  local auditPipeline = std.get(std.get(params.clusterLogForwarder, 'pipelines', {}), 'audit-logs', {}),

  inputs: {},
  outputs: {},
  pipelines: {
    [if lokiEnabled || std.length(appsPipeline) > 0 then 'application-logs']: {
      inputRefs: [ 'application' ],
      outputRefs: pipelineOutputRefs(appsPipeline),
    },
    [if lokiEnabled || std.length(infraPipeline) > 0 then 'infrastructure-logs']: {
      inputRefs: [ 'infrastructure' ],
      outputRefs: pipelineOutputRefs(infraPipeline),
    },
    [if std.length(auditPipeline) > 0 then 'audit-logs']: {
      inputRefs: [ 'audit' ],
    },
  },
} + com.makeMergeable(params.clusterLogForwarder);

// Unfold objects into array for ClusterLogForwarder resource.
local unfoldSpecs(specs) = {
  // Unfold objects into array.
  [if std.length(specs.inputs) > 0 then 'inputs']: [
    { name: name } + specs.inputs[name]
    for name in std.objectFields(specs.inputs)
  ],
  [if std.length(specs.outputs) > 0 then 'outputs']: [
    { name: name } + specs.outputs[name]
    for name in std.objectFields(specs.outputs)
  ],
  [if std.length(specs.pipelines) > 0 then 'pipelines']: [
    { name: name } + specs.pipelines[name]
    for name in std.objectFields(specs.pipelines)
  ],
} + {
  // Import remaining specs as is.
  [key]: specs[key]
  for key in std.objectFields(specs)
  if !std.member([ 'inputs', 'outputs', 'pipelines' ], key)
};

// ClusterLogForwarder:
// Create definitive ClusterLogForwarder resource from specs.
local clusterLogForwarder = kube._Object('observability.openshift.io/v1', 'ClusterLogForwarder', 'instance') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
    },
    namespace: params.namespace,
  },
  spec: unfoldSpecs(clusterLogForwarderSpec),
};

// Define outputs below
if forwarderEnabled then
  {
    '40_log_forwarder': clusterLogForwarder,
  }
else
  std.trace(
    'Log forwarding disabled, not deploying ClusterLogForwarder',
    {}
  )
