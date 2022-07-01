local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prometheus.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local syn_metrics =
  params.monitoring.enabled &&
  std.member(inv.applications, 'prometheus');

local nsName = 'syn-monitoring-openshift4-logging';
local endpointDefaults = {
  interval: '30s',
  relabelings: [
    prom.DropRuntimeMetrics,
  ],
};

local promInstance =
  if params.monitoring.instance != '' then
    params.monitoring.instance
  else
    inv.parameters.prometheus.defaultInstance;

local serviceMonitors = [
  prom.ServiceMonitor('cluster-logging-operator',) {
    metadata+: {
      namespace: nsName,
    },
    endpoints: {
      operator: {
        interval: '30s',
        relabelings: [
          prom.DropRuntimeMetrics,
        ],
        port: 'http-metrics',
      },
    },
    selector: {
      matchLabels: {
        'control-plane': 'cluster-logging-operator',
      },
    },
    targetNamespace: params.namespace,
  },
  prom.ServiceMonitor('fluentd') {
    metadata+: {
      namespace: nsName,
    },
    endpoints: {
      fluentd:
        prom.ServiceMonitorHttpsEndpoint('fluentd.openshift-logging.svc') {
          // Fluentd doesn't need bearer token
          bearerTokenFile:: '',
          port: 'logfile-metrics',
          relabelings: [
            prom.DropRuntimeMetrics,
          ],
        },
    },
    targetNamespace: params.namespace,
    selector: {
      matchLabels: {
        'logging-infra': 'support',
      },
    },
  },
  prom.ServiceMonitor('elasticsearch-cluster') {
    metadata+: {
      namespace: nsName,
    },
    endpoints: {
      elasticsearch:
        prom.ServiceMonitorHttpsEndpoint('elasticsearch-metrics.openshift-logging.svc')
        {
          path: '/_prometheus/metrics',
          port: 'elasticsearch',
          relabelings: [
            prom.DropRuntimeMetrics,
          ],
        },
    },
    targetNamespace: params.namespace,
    selector: {
      matchLabels: {
        'cluster-name': 'elasticsearch',
        'scrape-metrics': 'enabled',
      },
    },
  },
];

if syn_metrics then
  {
    '70_monitoring_namespace': prom.RegisterNamespace(
      kube.Namespace(nsName),
      instance=promInstance,
    ),
    '70_monitoring_servicemonitors': serviceMonitors,
    '70_monitoring_networkpolicy': prom.NetworkPolicy(instance=promInstance) {
      metadata+: {
        // The networkpolicy needs to be in the namespace in which OpenShift
        // logging is deployed.
        namespace: params.namespace,
      },
    },
  }
else
  {}
