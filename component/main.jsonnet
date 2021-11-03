local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local group = 'operators.coreos.com/';
local clusterLoggingGroupVersion = 'logging.openshift.io/v1';

local alert_rules = import 'alertrules.libsonnet';

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
    operatorlib.managedSubscription(
      'openshift-operators-redhat',
      'elasticsearch-operator',
      params.channel
    ),
    operatorlib.namespacedSubscription(
      params.namespace,
      'cluster-logging',
      params.channel,
      'redhat-operators'
    ),
  ],
  '30_cluster_logging': kube._Object(clusterLoggingGroupVersion, 'ClusterLogging', 'instance') {
    metadata+: {
      namespace: params.namespace,
      annotations+: {
        'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
      },
    },
    spec: params.clusterLogging,
  },
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
      [if std.length(params.clusterLogForwarding.namespace_groups) > 0 then 'inputs']: [
        {
          name: group,
          application: {
            namespaces: params.clusterLogForwarding.namespace_groups[group].namespaces,
          },
        }
        for group in std.objectFields(params.clusterLogForwarding.namespace_groups)
      ],
      [if std.length(params.clusterLogForwarding.namespace_groups) > 0 then 'pipelines']: [
        local enable_json = com.getValueOrDefault(params.clusterLogForwarding.namespace_groups[group], 'json', false);
        local patch_json = { outputRefs: [ 'default' ], parse: 'json' };
        {
          name: group,
          inputRefs: params.clusterLogForwarding.namespace_groups[group].namespaces,
          outputRefs: com.getValueOrDefault(params.clusterLogForwarding.namespace_groups[group], 'forwarders', []),
        } + com.makeMergeable(if enable_json then patch_json else {})
        for group in std.objectFields(params.clusterLogForwarding.namespace_groups)
      ],
    } + com.makeMergeable(
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'json', false);
      {
        pipelines: [
          {
            name: 'infrastructure-logs',
            inputRefs: [ 'infrastructure' ],
            outputRefs: [ 'default' ],
          },
          {
            name: 'application-logs',
            inputRefs: [ 'application' ],
            outputRefs: com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'forwarders', []) + [ 'default' ],
            [if enable_json then 'parse']: 'json',
          },
        ],
      }
    ),
  },
  '40_journald_configs': [ kube._Object('machineconfiguration.openshift.io/v1', 'MachineConfig', '40-' + role + '-journald') {
    metadata+: {
      labels+: {
        'machineconfiguration.openshift.io/role': role,
      },
    },
    spec: {
      config: {
        ignition: {
          version: '2.2.0',
        },
        storage: {
          files: [
            {
              contents: {
                // See https://docs.openshift.com/container-platform/latest/logging/config/cluster-logging-systemd.html
                source: 'data:text/plain;charset=utf-8;base64,' + std.base64(|||
                  MaxRetentionSec=1month
                  RateLimitBurst=10000
                  RateLimitInterval=1s
                  Storage=persistent
                  SyncIntervalSec=1s
                |||),
              },
              filesystem: 'root',
              mode: 420,
              path: '/etc/systemd/journald.conf',
            },
          ],
        },
      },
    },
  } for role in [ 'master', 'worker' ] ],
  '50_networkpolicy':
    // Allow cluster-scoped ES operator to access ES pods in openshift-logging
    kube._Object('networking.k8s.io/v1', 'NetworkPolicy', 'allow-from-openshift-operators-redhat')
    {
      metadata+: {
        namespace: params.namespace,
      },
      spec: {
        ingress: [
          {
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    name: 'openshift-operators-redhat',
                  },
                },
              },
              {
                podSelector: {
                  matchLabels: {
                    name: 'elasticsearch-operator',
                  },
                },
              },
            ],
          },
        ],
        podSelector: {},
        policyTypes: [ 'Ingress' ],
      },
    },
  '60_prometheus_rules': alert_rules.rules,
}
