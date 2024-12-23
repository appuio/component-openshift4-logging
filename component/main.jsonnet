local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local lokiEnabled = params.components.lokistack.enabled;

// Namespace

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    annotations+: {
      'openshift.io/node-selector': '',
      'argocd.argoproj.io/sync-wave': '-100',
    },
    labels+: {
      'openshift.io/cluster-monitoring': 'true',
    },
  },
};

// OperatorGroup

local operatorGroup = operatorlib.OperatorGroup('cluster-logging') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-90',
    },
    namespace: params.namespace,
  },
};

// Subscriptions

local logging = operatorlib.namespacedSubscription(
  params.namespace,
  'cluster-logging',
  params.channel,
  'redhat-operators'
) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-80',
    },
  },
  spec+: {
    config+: {
      resources: params.operatorResources.clusterLogging,
    },
  },
};

local lokistack = if lokiEnabled then operatorlib.managedSubscription(
  'openshift-operators-redhat',
  'loki-operator',
  params.channel
) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-80',
    },
  },
  spec+: {
    config+: {
      resources: params.operatorResources.lokistack,
    },
  },
};

local observability = if lokiEnabled then operatorlib.managedSubscription(
  'openshift-operators-redhat',
  'cluster-observability-operator',
  'development'
) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-80',
    },
  },
};

local subscriptions = std.filter(function(it) it != null, [
  logging,
  lokistack,
  observability,
]);

local secrets = com.generateResources(params.secrets, kube.Secret);

// Define outputs below
{
  '00_namespace': namespace,
  '10_operator_group': operatorGroup,
  '20_subscriptions': subscriptions,
  [if std.length(params.secrets) > 0 then '99_secrets']: secrets,
}
+ (import 'log_lokistack.libsonnet')
+ (import 'log_forwarder.libsonnet')
+ (import 'log_metricsexporter.libsonnet')
+ (import 'log_workaround.libsonnet')
+ (import 'alertrules.libsonnet')
