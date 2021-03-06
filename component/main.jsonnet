local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local group = 'operators.coreos.com/';
local clusterLoggingGroupVersion = 'logging.openshift.io/v1';

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
  '10_operator_group': kube._Object(group + 'v1', 'OperatorGroup', 'cluster-logging') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      targetNamespaces: [
        params.namespace,
      ],
    },
  },
  '20_subscriptions': [kube._Object(group + 'v1alpha1', 'Subscription', name) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      channel: params.channel,
      installPlanApproval: 'Automatic',
      name: name,
      source: 'redhat-operators',
      sourceNamespace: 'openshift-marketplace',
    },
  } for name in ['elasticsearch-operator', 'cluster-logging']],
  '30_cluster_logging': kube._Object(clusterLoggingGroupVersion, 'ClusterLogging', 'instance') {
    metadata+: {
      namespace: params.namespace,
      annotations+: {
        'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
      },
    },
    spec: params.clusterLogging,
  },
  '40_journald_configs': [kube._Object('machineconfiguration.openshift.io/v1', 'MachineConfig', '40-' + role + '-journald') {
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
  } for role in ['master', 'worker']],
}
