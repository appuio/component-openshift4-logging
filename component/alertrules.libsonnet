local alertpatching = import 'lib/alert-patching.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local elasticsearch = inv.parameters.openshift4_logging.components.elasticsearch;
local loki = inv.parameters.openshift4_logging.components.lokistack;


local runbook(alertname) =
  'https://hub.syn.tools/openshift4-logging/runbooks/%s.html' % alertname;

assert
  std.member(inv.applications, 'openshift4-monitoring')
  : 'Component `openshift4-monitoring` not enabled';

// Keep config backwards compatible
local predict_storage_alert = elasticsearch.predict_elasticsearch_storage_alert + (
  if std.objectHas(params, 'predict_elasticsearch_storage_alert') then
    std.trace(
      'parameter predict_elasticsearch_storage_alert is deprecated, please use parameter `components.elasticsearch.predict_elasticsearch_storage_alert instead`',
      com.makeMergeable(params.predict_elasticsearch_storage_alert)
    )
  else {}
);

// Keep only alerts from params.ignore_alerts for which the last
// array entry wasn't prefixed with `~`.
local user_ignore_alerts = com.renderArray(params.ignore_alerts);

// Upstream alerts to ignore
local ignore_alerts = std.set(
  // Add set of upstream alerts that should be ignored from processed value of
  // `params.ignore_alerts`
  user_ignore_alerts
);

// Alert rule patches.
// Provide partial objects for alert rules that need to be tuned compared to
// upstream. The keys in this object correspond to the `alert` field of the
// rule for which the patch is intended.
local patch_alerts = {
  FluentdQueueLengthIncreasing: {
    'for': '12h',
  },
};

local loadFile(file) =
  local fpath = 'openshift4-logging/component/extracted_alerts/%s/%s' % [ params.alerts, file ];
  std.parseJson(kap.yaml_load_stream(fpath));


// This will be processed by filter_patch_rules() as well
local predictESStorage = {
  local alertName = 'ElasticsearchExpectNodeToReachDiskWatermark',
  local hoursFromNow = predict_storage_alert.predict_hours_from_now,
  local secondsFromNow = hoursFromNow * 3600,
  alert: alertName,
  annotations: {
    message: (
      'Expecting to reach disk low watermark at {{ $labels.node }} node in {{ $labels.cluster }} cluster in %s hours.'
      + ' When reaching the watermark no new shards will be allocated to this node anymore. You should consider adding more disk to the node.'
    ) % std.toString(hoursFromNow),
    runbook_url: runbook('SYN_' + alertName),
    summary: 'Expecting to Reach Disk Low Watermark in %s Hours' % std.toString(hoursFromNow),
  },
  expr: |||
    sum by(cluster, instance, node) (
      (1 - (predict_linear(es_fs_path_available_bytes[%s], %s) / es_fs_path_total_bytes)) * 100
    ) > %s
  ||| % [ predict_storage_alert.lookback_range, std.toString(secondsFromNow), std.toString(predict_storage_alert.threshold) ],
  'for': predict_storage_alert['for'],
  labels: {
    severity: predict_storage_alert.severity,
  },
};

local esStorageGroup = {
  name: 'elasticsearch_node_storage.alerts',
  rules: [ predictESStorage ],
};

local esGroups =
  loadFile('elasticsearch_operator_prometheus_alerts.yaml')[0].groups +
  loadFile('fluentd_prometheus_alerts.yaml')[0].groups +
  [
    if predict_storage_alert.enabled then esStorageGroup,
  ];

local lokiGroups = loadFile('lokistack_prometheus_alerts.yaml')[0].groups;

local es_prometheus_rules = kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'syn-elasticsearch-logging-rules') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    groups: std.filter(
      function(it) it != null,
      [
        local r = alertpatching.filterPatchRules(
          g, ignore_alerts, patch_alerts
        );
        if std.length(r.rules) > 0 then r
        for g in esGroups
      ],
    ),
  },
};

local loki_prometheus_rules = kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'syn-loki-logging-rules') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    groups: std.filter(
      function(it) it != null,
      [
        local r = alertpatching.filterPatchRules(
          g, ignore_alerts, patch_alerts
        );
        if std.length(r.rules) > 0 then r
        for g in lokiGroups
      ],
    ),
  },
};

{
  [if elasticsearch.enabled then '60_elasticsearch_alerts']: es_prometheus_rules,
  [if loki.enabled then '60_lokistack_alerts']: loki_prometheus_rules,
}
