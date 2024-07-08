local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local deployLokistack = params.components.lokistack.enabled;
local deployElasticsearch = params.components.elasticsearch.enabled;

local group = 'operators.coreos.com/';
local clusterLoggingGroupVersion = 'logging.openshift.io/v1';

local forwardingOnly = !params.components.elasticsearch.enabled && !params.components.lokistack.enabled;

local namespace_groups = (
  if std.objectHas(params.clusterLogForwarding, 'namespaces') then
    {
      [ns]: {
        namespaces: [ ns ],
        forwarders: [ params.clusterLogForwarding.namespaces[ns].forwarder ],
      }
      for ns in std.objectFields(params.clusterLogForwarding.namespaces)
    }
  else
    {}
) + params.clusterLogForwarding.namespace_groups;

// --- Patch deprecated logging resource
local legacyCollectionConfig = std.get(params.clusterLogging.collection, 'logs', {});
local legacyCollectionPatch = if std.length(legacyCollectionConfig) > 0 then std.trace(
  'Parameter `clusterLogging.collector.logs` is deprecated. Please update your config to use `clusterLogging.collector`',
  {
    local type = std.get(legacyCollectionConfig, 'type', ''),
    local fluentd = std.get(legacyCollectionConfig, 'fluentd', {}),
    collection+: {
      [if type != '' then 'type']: type,
    } + if std.length(fluentd) > 0 then fluentd,
  }
) else {};

local clusterLogging = std.mergePatch(
  params.clusterLogging {
    collection: {
      [it]: params.clusterLogging.collection[it]
      for it in std.objectFields(params.clusterLogging.collection)
      if it != 'logs'
    },
  } + legacyCollectionPatch,
  {
    // Patch to remove certain keys, as the ClusterLogging operator would just
    // deploy elasticsearch or kibana if they are configured
    [if forwardingOnly then 'logStore']: null,
  }
);
// --- End patch

local pipelineOutputRefs(pipeline) =
  local default = if forwardingOnly then [] else [ 'default' ];
  std.get(pipeline, 'forwarders', []) + default;

// Namespace

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    annotations+: {
      'openshift.io/node-selector': '',
    },
    labels+: {
      'openshift.io/cluster-monitoring': 'true',
    },
  },
};

// OperatorGroup

local operatorGroup = operatorlib.OperatorGroup('cluster-logging') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    targetNamespaces: [
      params.namespace,
    ],
  },
};

// Subscriptions

local logging = operatorlib.namespacedSubscription(
  params.namespace,
  'cluster-logging',
  params.channel,
  'redhat-operators'
) {
  spec+: {
    config+: {
      resources: params.operatorResources.clusterLogging,
    },
  },
};

local lokistack = if deployLokistack then operatorlib.managedSubscription(
  'openshift-operators-redhat',
  'loki-operator',
  params.channel
) {
  spec+: {
    config+: {
      resources: params.operatorResources.lokistack,
    },
  },
};

local elasticsearch = if deployElasticsearch then operatorlib.managedSubscription(
  'openshift-operators-redhat',
  'elasticsearch-operator',
  params.channel
) {
  spec+: {
    config+: {
      resources: params.operatorResources.elasticsearch,
    },
  },
};

local subscriptions = std.filter(function(it) it != null, [
  logging,
  lokistack,
  elasticsearch,
]);

// Define outputs below
{
  '00_namespace': namespace,
  '10_operator_group': operatorGroup,
  '20_subscriptions': subscriptions,
  '30_cluster_logging': std.mergePatch(
    // ClusterLogging resource from inventory
    kube._Object(clusterLoggingGroupVersion, 'ClusterLogging', 'instance') {
      metadata+: {
        namespace: params.namespace,
        annotations+: {
          'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
        },
      },
      spec: clusterLogging,
    }, {
      // Patch to remove certain keys, as the ClusterLogging operator would just
      // deploy elasticsearch or kibana if they are configured
      spec: {
        logStore: {
          [if !params.components.elasticsearch.enabled then 'elasticsearch']: null,
          [if !params.components.lokistack.enabled then 'lokistack']: null,
        },
        [if !params.components.elasticsearch.enabled then 'visualization']: null,
      },
    }
  ),
  [if params.clusterLogForwarding.enabled then '31_cluster_logforwarding']: kube._Object(clusterLoggingGroupVersion, 'ClusterLogForwarder', 'instance') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      [if params.clusterLogForwarding.json.enabled then 'outputDefaults']: {
        elasticsearch: {
          structuredTypeKey: params.clusterLogForwarding.json.typekey,
          structuredTypeName: params.clusterLogForwarding.json.typename,
        },
      },
      [if std.length(params.clusterLogForwarding.forwarders) > 0 then 'outputs']: [
        params.clusterLogForwarding.forwarders[fw] { name: fw }
        for fw in std.objectFields(params.clusterLogForwarding.forwarders)
      ],
      [if std.length(namespace_groups) > 0 then 'inputs']: [
        {
          name: group,
          application: {
            namespaces: namespace_groups[group].namespaces,
          },
        }
        for group in std.objectFields(namespace_groups)
      ],
      [if std.length(namespace_groups) > 0 then 'pipelines']: [
        local enable_json = com.getValueOrDefault(namespace_groups[group], 'json', false);
        local enable_multilineErrors = com.getValueOrDefault(namespace_groups[group], 'detectMultilineErrors', false);
        local patch_json = { outputRefs: [ 'default' ], parse: 'json' };
        {
          name: group,
          inputRefs: [ group ],
          outputRefs: com.getValueOrDefault(namespace_groups[group], 'forwarders', []),
        } + com.makeMergeable(if enable_json then patch_json else {})
        + com.makeMergeable(if enable_multilineErrors then { detectMultilineErrors: true } else {})
        for group in std.objectFields(namespace_groups)
      ],
    } + com.makeMergeable(
      local enable_pipeline = std.length(pipelineOutputRefs(params.clusterLogForwarding.application_logs)) > 0;
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'json', false);
      local enable_multilineErrors = com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'detectMultilineErrors', false);
      {
        [if enable_pipeline then 'pipelines']: [
          {
            name: 'application-logs',
            inputRefs: [ 'application' ],
            outputRefs: pipelineOutputRefs(params.clusterLogForwarding.application_logs),
            [if enable_json then 'parse']: 'json',
            [if enable_multilineErrors then 'detectMultilineErrors']: true,
          },
        ],
      }
    ) + com.makeMergeable(
      local enable_pipeline = params.clusterLogForwarding.infrastructure_logs.enabled && std.length(pipelineOutputRefs(params.clusterLogForwarding.infrastructure_logs)) > 0;
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.infrastructure_logs, 'json', false);
      local enable_multilineErrors = com.getValueOrDefault(params.clusterLogForwarding.infrastructure_logs, 'detectMultilineErrors', false);
      {
        [if enable_pipeline then 'pipelines']: [
          {
            name: 'infrastructure-logs',
            inputRefs: [ 'infrastructure' ],
            outputRefs: pipelineOutputRefs(params.clusterLogForwarding.infrastructure_logs),
            [if enable_json then 'parse']: 'json',
            [if enable_multilineErrors then 'detectMultilineErrors']: true,
          },
        ],
      }
    ) + com.makeMergeable(
      local enable_pipeline = params.clusterLogForwarding.audit_logs.enabled && std.length(pipelineOutputRefs(params.clusterLogForwarding.application_logs)) > 0;
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.audit_logs, 'json', false);
      {
        [if params.clusterLogForwarding.audit_logs.enabled then 'pipelines']: [
          {
            name: 'audit-logs',
            inputRefs: [ 'audit' ],
            outputRefs: pipelineOutputRefs(params.clusterLogForwarding.audit_logs),
          },
        ],
      }
    ),
  },
}
+ (import 'loki.libsonnet')
+ (import 'elasticsearch.libsonnet')
+ (import 'alertrules.libsonnet')
