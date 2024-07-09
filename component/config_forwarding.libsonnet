local kap = import 'lib/kapitan.libjsonnet';
local lib = import 'lib/openshift4-logging.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local deployLokistack = params.components.lokistack.enabled;
local deployElasticsearch = params.components.elasticsearch.enabled;
local forwardingOnly = !deployLokistack && !deployElasticsearch;

local pipelineOutputRefs(pipeline) =
  local default = if forwardingOnly then [] else [ 'default' ];
  std.get(pipeline, 'forwarders', []) + default;

// Apply default config for application logs.
local patchAppLogDefaults = {
  local outputRefs = pipelineOutputRefs(params.clusterLogForwarding.application_logs),
  local enablePipeline = std.length(outputRefs) > 0,

  pipelines: {
    [if enablePipeline then 'application-logs']: {
      inputRefs: [ 'application' ],
      outputRefs: outputRefs,
    },
  },
};

// Apply default config for infra logs.
local patchInfraLogDefaults = {
  local outputRefs = pipelineOutputRefs(params.clusterLogForwarding.infrastructure_logs),
  local enablePipeline = params.clusterLogForwarding.infrastructure_logs.enabled && std.length(outputRefs) > 0,

  pipelines: {
    [if enablePipeline then 'infrastructure-logs']: {
      inputRefs: [ 'infrastructure' ],
      outputRefs: outputRefs,
    },
  },
};

// Apply default config for audit logs.
local patchAuditLogDefaults = {
  local outputRefs = pipelineOutputRefs(params.clusterLogForwarding.audit_logs),
  local enablePipeline = params.clusterLogForwarding.audit_logs.enabled && std.length(outputRefs) > 0,

  pipelines: {
    [if enablePipeline then 'audit-logs']: {
      inputRefs: [ 'audit' ],
      outputRefs: outputRefs,
    },
  },
};

// Enable json parsing for default pipelines if configured.
local patchJsonLogging = {
  local enableAppLogs = std.get(params.clusterLogForwarding.application_logs, 'json', false),
  local enableInfraLogs = std.get(params.clusterLogForwarding.infrastructure_logs, 'json', false),

  pipelines: {
    [if enableAppLogs then 'application-logs']: { parse: 'json' },
    [if enableInfraLogs then 'infrastructure-logs']: { parse: 'json' },
  },
  [if deployElasticsearch && params.clusterLogForwarding.json.enabled then 'outputDefaults']: {
    elasticsearch: {
      structuredTypeKey: params.clusterLogForwarding.json.typekey,
      structuredTypeName: params.clusterLogForwarding.json.typename,
    },
  },
};

// Enable detectMultilineErrors for default pipelines if configured.
local patchMultilineErrors = {
  local enableAppLogs = std.get(params.clusterLogForwarding.application_logs, 'detectMultilineErrors', false),
  local enableInfraLogs = std.get(params.clusterLogForwarding.infrastructure_logs, 'detectMultilineErrors', false),

  pipelines: {
    [if enableAppLogs then 'application-logs']: { detectMultilineErrors: true },
    [if enableInfraLogs then 'infrastructure-logs']: { detectMultilineErrors: true },
  },
};

// --- patch deprecated `clusterLogForwarding.namespace` config
local namespaceGroups = (
  if std.objectHas(params.clusterLogForwarding, 'namespaces') then
    {
      [ns]: {
        namespaces: [ ns ],
        forwarders: [ params.clusterLogForwarding.namespaces[ns].forwarder ],
      }
      for ns in std.objectFields(params.clusterLogForwarding.namespaces)
    } else {}
) + params.clusterLogForwarding.namespace_groups;
// --- patch end

// Add inputs entry for every namespace_group defined in `clusterLogForwarding.namespace_groups`.
local patchCustomInputs = {
  [if std.length(namespaceGroups) > 0 then 'inputs']: {
    [group]: {
      application: {
        namespaces: namespaceGroups[group].namespaces,
      },
    }
    for group in std.objectFields(namespaceGroups)
  },
};

// Add pipelines entry for every namespace_group defined in `clusterLogForwarding.namespace_groups`.
local patchCustomPipelines = {
  [if std.length(namespaceGroups) > 0 then 'pipelines']: {
    local enableJson = std.get(namespaceGroups[group], 'json', false),
    local enableMultilineError = std.get(namespaceGroups[group], 'detectMultilineErrors', false),

    [group]: {
      inputRefs: [ group ],
      outputRefs: std.get(namespaceGroups[group], 'forwarders', []),
      [if enableJson then 'parse']: 'json',
      [if enableMultilineError then 'detectMultilineErrors']: true,
    }
    for group in std.objectFields(namespaceGroups)
  },
};

// Add outputs entry for every forwarder defined in `clusterLogForwarding.forwarders`.
local patchCustomOutputs = {
  [if std.length(params.clusterLogForwarding.forwarders) > 0 then 'outputs']: {
    [name]: params.clusterLogForwarding.forwarders[name]
    for name in std.objectFields(params.clusterLogForwarding.forwarders)
  },
};

// ClusterLogForwarderSpecs:
// Consecutively apply patches to result of previous apply.
local clusterLogForwarderSpec = std.foldl(
  // we use std.mergePatch here, because this way we don't need
  // to make each patch object mergeable by suffixing all keys with a +.
  function(manifest, patch) std.mergePatch(manifest, patch),
  [
    patchAppLogDefaults,
    patchInfraLogDefaults,
    patchAuditLogDefaults,
    patchJsonLogging,
    patchMultilineErrors,
    patchCustomInputs,
    patchCustomOutputs,
    patchCustomPipelines,
  ],
  {
    inputs: {},
    outputs: {},
    pipelines: {},
  }
);

// ClusterLogForwarder:
// Create definitive ClusterLogForwarder resource from specs.
local clusterLogForwarder = lib.ClusterLogForwarder(params.namespace, 'instance') {
  spec: {
    // Unfold objects into array.
    [if std.length(clusterLogForwarderSpec.inputs) > 0 then 'inputs']: [
      { name: name } + clusterLogForwarderSpec.inputs[name]
      for name in std.objectFields(clusterLogForwarderSpec.inputs)
    ],
    [if std.length(clusterLogForwarderSpec.outputs) > 0 then 'outputs']: [
      { name: name } + clusterLogForwarderSpec.outputs[name]
      for name in std.objectFields(clusterLogForwarderSpec.outputs)
    ],
    [if std.length(clusterLogForwarderSpec.pipelines) > 0 then 'pipelines']: [
      { name: name } + clusterLogForwarderSpec.pipelines[name]
      for name in std.objectFields(clusterLogForwarderSpec.pipelines)
    ],
  } + {
    // Import remaining specs as is.
    [key]: clusterLogForwarderSpec[key]
    for key in std.objectFields(clusterLogForwarderSpec)
    if !std.member([ 'inputs', 'outputs', 'pipelines' ], key)
  },
};

// Define outputs below
if params.clusterLogForwarding.enabled then
  {
    '31_cluster_logforwarding': clusterLogForwarder,
  }
else
  std.trace(
    'Log forwarding disabled, not deploying ClusterLogForwarder',
    {}
  )
