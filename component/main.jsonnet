local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local group = 'operators.coreos.com/';
local clusterLoggingGroupVersion = 'logging.openshift.io/v1';

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


{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      annotations+: {
        'openshift.io/node-selector': '',
      },
      labels+: {
        'openshift.io/cluster-monitoring': 'true',
      },
    },
  },
  '10_operator_group': operatorlib.OperatorGroup('cluster-logging') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      targetNamespaces: [
        params.namespace,
      ],
    },
  },
  '20_subscriptions': [
    operatorlib.namespacedSubscription(
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
    },
  ] + (
    if params.components.lokistack.enabled then [
      operatorlib.managedSubscription(
        'openshift-operators-redhat',
        'loki-operator',
        params.channel
      ) {
        spec+: {
          config+: {
            resources: params.operatorResources.lokistack,
          },
        },
      },
    ] else []
  ) + (
    if params.components.elasticsearch.enabled then [
      operatorlib.managedSubscription(
        'openshift-operators-redhat',
        'elasticsearch-operator',
        params.channel
      ) {
        spec+: {
          config+: {
            resources: params.operatorResources.elasticsearch,
          },
        },
      },
    ] else []
  ),
  '30_cluster_logging': std.mergePatch(
    // ClusterLogging resource from inventory
    kube._Object(clusterLoggingGroupVersion, 'ClusterLogging', 'instance') {
      metadata+: {
        namespace: params.namespace,
        annotations+: {
          'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
        },
      },
      spec: params.clusterLogging,
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
        local patch_json = { outputRefs: [ 'default' ], parse: 'json' };
        {
          name: group,
          inputRefs: [ group ],
          outputRefs: com.getValueOrDefault(namespace_groups[group], 'forwarders', []),
        } + com.makeMergeable(if enable_json then patch_json else {})
        for group in std.objectFields(namespace_groups)
      ],
    } + com.makeMergeable(
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'json', false);
      {
        pipelines: [
          {
            name: 'application-logs',
            inputRefs: [ 'application' ],
            outputRefs: com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'forwarders', []) + [ 'default' ],
            [if enable_json then 'parse']: 'json',
          },
        ],
      }
    ) + com.makeMergeable(
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.infrastructure_logs, 'json', false);
      {
        [if params.clusterLogForwarding.infrastructure_logs.enabled then 'pipelines']: [
          {
            name: 'infrastructure-logs',
            inputRefs: [ 'infrastructure' ],
            outputRefs: com.getValueOrDefault(params.clusterLogForwarding.infrastructure_logs, 'forwarders', []) + [ 'default' ],
            [if enable_json then 'parse']: 'json',
          },
        ],
      }
    ) + com.makeMergeable(
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.audit_logs, 'json', false);
      {
        [if params.clusterLogForwarding.audit_logs.enabled then 'pipelines']: [
          {
            name: 'audit-logs',
            inputRefs: [ 'audit' ],
            outputRefs: com.getValueOrDefault(params.clusterLogForwarding.audit_logs, 'forwarders', []) + [ 'default' ],
          },
        ],
      }
    ),
  },
}
+ (import 'loki.libsonnet')
+ (import 'elasticsearch.libsonnet')
+ (import 'alertrules.libsonnet')
