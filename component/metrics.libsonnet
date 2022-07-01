local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prometheus.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local syn_metrics =
  params.monitoring.enabled &&
  std.member(inv.applications, 'prometheus');

local nsName = 'syn-monitoring-openshift4-logging';

local promInstance =
  if params.monitoring.instance != '' then
    params.monitoring.instance
  else
    inv.parameters.prometheus.defaultInstance;

local serviceMonitors = [
  prom.ServiceMonitor('cluster-logging-operator',) {
    endpoints: {
      operator: {
        interval: '30s',
        metricRelabelings: [
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
    endpoints: {
      fluentd:
        prom.ServiceMonitorHttpsEndpoint('fluentd.openshift-logging.svc') {
          // Fluentd doesn't need bearer token
          bearerTokenFile:: '',
          port: 'logfile-metrics',
          metricRelabelings: [
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
    endpoints: {
      elasticsearch:
        prom.ServiceMonitorHttpsEndpoint('elasticsearch-metrics.openshift-logging.svc')
        {
          path: '/_prometheus/metrics',
          port: 'elasticsearch',
          metricRelabelings: [
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
    '70_monitoring_servicemonitors': std.filter(
      function(it) it != null,
      [
        if params.monitoring.enableServiceMonitors[sm.metadata.name] then
          sm {
            metadata+: {
              namespace: nsName,
            },
          }
        for sm in serviceMonitors
      ]
    ),
    '70_monitoring_networkpolicy': prom.NetworkPolicy(instance=promInstance) {
      metadata+: {
        // The networkpolicy needs to be in the namespace in which OpenShift
        // logging is deployed.
        namespace: params.namespace,
      },
    },
  }
else
  std.trace(
    'Monitoring disabled or component `prometheus` not present, '
    + 'not deploying ServiceMonitors',
    {}
  )
