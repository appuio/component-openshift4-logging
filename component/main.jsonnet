local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local deployLokistack = params.components.lokistack.enabled;
local deployElasticsearch = params.components.elasticsearch.enabled;

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
}
+ (import 'config_logging.libsonnet')
+ (import 'config_forwarding.libsonnet')
+ (import 'loki.libsonnet')
+ (import 'elasticsearch.libsonnet')
+ (import 'alertrules.libsonnet')
