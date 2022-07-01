local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local runbook(alertname) =
  'https://hub.syn.tools/openshift4-logging/runbooks/%s.html' % alertname;

assert
  std.member(inv.applications, 'openshift4-monitoring') ||
  std.member(inv.applications, 'prometheus')
  : 'neither component `openshift4-monitoring` nor `prometheus` enabled';

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

/* FROM HERE: should be provided as library function by
 * rancher-/openshift4-monitoring */
// We shouldn't be expected to care how rancher-/openshift4-monitoring
// implement alert managmement and patching, instead we should be able to
// reuse their functionality as a black box to make sure our alerts work
// correctly in the environment into which we're deploying.

// XXX: We'll figure out how we do alert management, when we start working on
// alerting for the vendor-independent monitoring stack based on component
// prometheus.
local global_alert_params =
  com.getValueOrDefault(
    inv.parameters,
    'openshift4_monitoring',
    { alerts: { ignoreNames: [] } }
  ).alerts;

local filter_patch_rules(g) =
  // combine our set of alerts to ignore with the monitoring component's
  // set of ignoreNames.
  local ignore_set = std.set(global_alert_params.ignoreNames + ignore_alerts);
  g {
    rules: std.map(
      // Patch rules to make sure they match the requirements.
      function(rule)
        local rulepatch = com.getValueOrDefault(patch_alerts, rule.alert, {});
        rule {
          // Change alert names so we don't get multiple alerts with the same
          // name, as the logging operator deploys its own copy of these
          // rules.
          alert: 'SYN_%s' % super.alert,
          labels+: {
            syn: 'true',
            // mark alert as belonging to openshift4-logging
            // can be used for inhibition rules
            syn_component: 'openshift4-logging',
          },
        } + rulepatch,
      std.filter(
        // Filter out unwanted rules
        function(rule)
          // only create duplicates of alert rules, we can use the recording
          // rules which are deployed anyway when we enable monitoring on the
          // CephCluster resource.
          std.objectHas(rule, 'alert') &&
          // Drop rules which are in the ignore_set
          !std.member(ignore_set, rule.alert),
        super.rules
      ),
    ),
  };

/* TO HERE */

local predictESStorage = {
  local alertName = 'SYN_ElasticsearchExpectNodeToReachDiskWatermark',
  local hoursFromNow = params.predict_elasticsearch_storage_alert.predict_hours_from_now,
  local secondsFromNow = hoursFromNow * 3600,
  alert: alertName,
  annotations: {
    message: (
      'Expecting to reach disk low watermark at {{ $labels.node }} node in {{ $labels.cluster }} cluster in %s hours.'
      + ' When reaching the watermark no new shards will be allocated to this node anymore. You should consider adding more disk to the node.'
    ) % std.toString(hoursFromNow),
    runbook_url: runbook(alertName),
    summary: 'Expecting to Reach Disk Low Watermark in %s Hours' % std.toString(hoursFromNow),
  },
  expr: |||
    sum by(cluster, instance, node) (
      (1 - (predict_linear(es_fs_path_available_bytes[%s], %s) / es_fs_path_total_bytes)) * 100
    ) > %s
  ||| % [ params.predict_elasticsearch_storage_alert.lookback_range, std.toString(secondsFromNow), std.toString(params.predict_elasticsearch_storage_alert.threshold) ],
  'for': params.predict_elasticsearch_storage_alert['for'],
  labels: {
    severity: params.predict_elasticsearch_storage_alert.severity,
  },
};

local esStorageGroup = {
  name: 'elasticsearch_node_storage.alerts',
  rules: [ predictESStorage ],
};

{
  rules: kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'syn-logging-rules') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      groups: std.filter(
        function(it) it != null,
        [
          local r = filter_patch_rules(g);
          if std.length(r.rules) > 0 then r
          for g in std.parseJson(kap.yaml_load_stream('openshift4-logging/manifests/%s/fluentd_prometheus_alerts.yaml' % [ params.alerts ]))[0].groups
        ] + [
          if params.predict_elasticsearch_storage_alert.enabled then esStorageGroup,
        ],
      ),
    },
  },
}
