local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';
local utils = import 'utils.libsonnet';

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
    [if !params.namespaceLogForwarderEnabled then 'targetNamespaces']: [
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

// With version 5.9 of the logging stack, elasticsearch is deprecated,
// this will clamp elasticsearch-operator subscription to stable-5.8.
local esChannel = if utils.isVersion59 then 'stable-5.8' else params.channel;
local elasticsearch = if deployElasticsearch then operatorlib.managedSubscription(
  'openshift-operators-redhat',
  'elasticsearch-operator',
  esChannel
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
+ (import 'logmetrics.libsonnet')
