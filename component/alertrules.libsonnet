local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

assert
  std.member(inv.applications, 'openshift4-monitoring')
  : 'openshift4-monitoring is not available';

// Function to process an array which supports removing previously added
// elements by prefixing them with ~
local render_array(arr) =
  // extract real value of array entry
  local realval(v) = std.lstripChars(v, '~');
  // Compute whether each element should be included by keeping track of
  // whether its last occurrence in the input array was prefixed with ~ or
  // not.
  local val_state = std.foldl(
    function(a, it) a + it,
    [
      { [realval(v)]: !std.startsWith(v, '~') }
      for v in arr
    ],
    {}
  );
  // Return filtered array containing only elements whose last occurrence
  // wasn't prefixed by ~.
  std.filter(
    function(val) val_state[val],
    std.objectFields(val_state)
  );

// Keep only alerts from params.ignore_alerts for which the last
// array entry wasn't prefixed with `~`.
local user_ignore_alerts = render_array(params.ignore_alerts);

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

local global_alert_params = inv.parameters.openshift4_monitoring.alerts;

local filter_patch_rules(g) =
  // combine our set of alerts to ignore with the monitoring component's
  // set of ignoreNames.
  local ignore_set = std.set(global_alert_params.ignoreNames + ignore_alerts);
  g {
    rules: std.map(
      // Patch rules to make sure they match the requirements.
      function(rule)
        local rulepatch = com.getValueOrDefault(patch_alerts, rule.alert, {});
        //        local runbook_url = runbook(rule.alert);
        rule {
          // Change alert names so we don't get multiple alerts with the same
          // name, as the logging operator deploys its own copy of these
          // rules.
          alert: 'SYN_%s' % super.alert,
          labels+: {
            // ensure the alerts are not silenced on OCP4
            // TODO: figure out how to ensure we don't get duplicate alerts on
            // not-OCP4
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

local additional_rules = [];

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
        ]
      ) + additional_rules,
    },
  },
}
