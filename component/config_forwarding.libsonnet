local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local lib = import 'lib/openshift4-logging.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local deployLokistack = params.components.lokistack.enabled;
local deployElasticsearch = params.components.elasticsearch.enabled;
local forwardingOnly = !deployLokistack && !deployElasticsearch;

// Make sure the default output is added to the pipelines `outputRefs`,
// if the logging stack is not disabled.
local pipelineOutputRefs(pipeline) =
  local default = if forwardingOnly then [] else [ 'default' ];
  std.get(pipeline, 'forwarders', []) + default;

// -----------------------------------------------------------------------------
//   Legacy Rendering
// -----------------------------------------------------------------------------

local legacyConfig = std.get(params, 'clusterLogForwarding', {});
local hasLegacyConfig = if std.length(legacyConfig) > 0 then std.trace(
  'Parameter `clusterLogForwarding` is deprecated. Please update your config to use `clusterLogForwarder`',
  true
) else false;

// Apply default config for application logs.
local patchLegacyAppLogDefaults = {
  local pipeline = std.get(legacyConfig, 'application_logs', { enabled: true }),
  local pipelineOutputs = pipelineOutputRefs(pipeline),
  local pipelineEnabled = std.length(pipelineOutputs) > 0,

  [if hasLegacyConfig then 'pipelines']: {
    [if pipelineEnabled then 'application-logs']: {
      inputRefs: [ 'application' ],
      outputRefs: pipelineOutputs,
    },
  },
};

// Apply default config for infra logs.
local patchLegacyInfraLogDefaults = {
  local pipeline = { enabled: true } + std.get(legacyConfig, 'infrastructure_logs', {}),
  local pipelineOutputs = pipelineOutputRefs(pipeline),
  local pipelineEnabled = pipeline.enabled && std.length(pipelineOutputs) > 0,

  [if hasLegacyConfig then 'pipelines']: {
    [if pipelineEnabled then 'infrastructure-logs']: {
      inputRefs: [ 'infrastructure' ],
      outputRefs: pipelineOutputs,
    },
  },
};

// Apply default config for audit logs.
local patchLegacyAuditLogDefaults = {
  local pipeline = std.get(legacyConfig, 'audit_logs', { enabled: false }),
  local pipelineOutputs = pipelineOutputRefs(pipeline),
  local pipelineEnabled = pipeline.enabled && std.length(pipelineOutputs) > 0,

  [if hasLegacyConfig then 'pipelines']: {
    [if pipelineEnabled then 'audit-logs']: {
      inputRefs: [ 'audit' ],
      outputRefs: pipelineOutputs,
    },
  },
};

// Enable json parsing for default pipelines if configured.
local legacyEnableJson = std.get(std.get(legacyConfig, 'json', {}), 'enabled', false);
local patchLegacyJsonLogging = {
  local enableAppLogs = std.get(std.get(legacyConfig, 'application_logs', {}), 'json', false),
  local enableInfraLogs = std.get(std.get(legacyConfig, 'infrastructure_logs', {}), 'json', false),

  [if hasLegacyConfig then 'pipelines']: {
    [if enableAppLogs then 'application-logs']: { parse: 'json' },
    [if enableInfraLogs then 'infrastructure-logs']: { parse: 'json' },
  },
  [if deployElasticsearch && legacyEnableJson then 'outputDefaults']: {
    elasticsearch: {
      structuredTypeKey: std.get(legacyConfig.json, 'typekey', 'kubernetes.labels.logFormat'),
      structuredTypeName: std.get(legacyConfig.json, 'typename', 'nologformat'),
    },
  },
};

// Enable detectMultilineErrors for default pipelines if configured.
local patchLegacyMultilineErrors = {
  local enableAppLogs = std.get(std.get(legacyConfig, 'application_logs', {}), 'detectMultilineErrors', false),
  local enableInfraLogs = std.get(std.get(legacyConfig, 'infrastructure_logs', {}), 'detectMultilineErrors', false),

  [if hasLegacyConfig then 'pipelines']: {
    [if enableAppLogs then 'application-logs']: { detectMultilineErrors: true },
    [if enableInfraLogs then 'infrastructure-logs']: { detectMultilineErrors: true },
  },
};

// --- patch deprecated `clusterLogForwarding.namespace` config
local namespaceGroups = (
  if std.objectHas(legacyConfig, 'namespaces') then
    {
      [ns]: {
        namespaces: [ ns ],
        forwarders: [ legacyConfig.namespaces[ns].forwarder ],
      }
      for ns in std.objectFields(legacyConfig.namespaces)
    } else {}
) + std.get(legacyConfig, 'namespace_groups', {});
// --- patch end

// Add inputs entry for every namespace_group defined in `clusterLogForwarding.namespace_groups`.
local patchLegacyCustomInputs = {
  [if std.length(namespaceGroups) > 0 then 'inputs']: {
    [group]: {
      application: {
        namespaces: namespaceGroups[group].namespaces,
      },
    }
    for group in std.objectFields(namespaceGroups)
    if hasLegacyConfig
  },
};

// Add pipelines entry for every namespace_group defined in `clusterLogForwarding.namespace_groups`.
local patchLegacyCustomPipelines = {
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
    if hasLegacyConfig
  },
};

// Add outputs entry for every forwarder defined in `clusterLogForwarding.forwarders`.
local patchLegacyCustomOutputs = {
  [if std.length(std.get(legacyConfig, 'forwarders', {})) > 0 then 'outputs']: {
    [name]: legacyConfig.forwarders[name]
    for name in std.objectFields(legacyConfig.forwarders)
    if hasLegacyConfig
  },
};

// -----------------------------------------------------------------------------
//   End Legacy Rendering
// -----------------------------------------------------------------------------

// Add defaults to pipelines config
local patchPipelineDefaults = {
  local appsPipeline = std.get(std.get(params.clusterLogForwarder, 'pipelines', {}), 'application-logs', {}),
  local infraPipeline = std.get(std.get(params.clusterLogForwarder, 'pipelines', {}), 'infrastructure-logs', {}),
  local auditPipeline = std.get(std.get(params.clusterLogForwarder, 'pipelines', {}), 'audit-logs', {}),

  pipelines: {
    'application-logs': {
      inputRefs: [ 'application' ],
      outputRefs: pipelineOutputRefs(appsPipeline),
    },
    'infrastructure-logs': {
      inputRefs: [ 'infrastructure' ],
      outputRefs: pipelineOutputRefs(infraPipeline),
    },
    [if std.length(auditPipeline) > 0 then 'audit-logs']: {
      inputRefs: [ 'audit' ],
    },
  },
};

// clusterLogForwarderSpec:
// Consecutively apply patches to result of previous apply.
local clusterLogForwarderSpec = std.foldl(
  // we use std.mergePatch here, because this way we don't need
  // to make each patch object mergeable by suffixing all keys with a +.
  function(manifest, patch) std.mergePatch(manifest, patch),
  [
    patchPipelineDefaults,
    // Apply legacy patches / defaults
    patchLegacyAppLogDefaults,
    patchLegacyInfraLogDefaults,
    patchLegacyAuditLogDefaults,
    patchLegacyJsonLogging,
    patchLegacyMultilineErrors,
    patchLegacyCustomInputs,
    patchLegacyCustomOutputs,
    patchLegacyCustomPipelines,
  ],
  {
    inputs: {},
    outputs: {},
    pipelines: {},
  },
) + com.makeMergeable(params.clusterLogForwarder);

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

local enableLogForwarder = std.length(params.clusterLogForwarder) > 0 || std.get(legacyConfig, 'enabled', false);

// Define outputs below
if enableLogForwarder then
  {
    '31_cluster_logforwarding': clusterLogForwarder,
  }
else
  std.trace(
    'Log forwarding disabled, not deploying ClusterLogForwarder',
    {}
  )
