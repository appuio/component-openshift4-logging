local alertpatching = import 'lib/alert-patching.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local lokiEnabled = params.components.lokistack.enabled;


local runbook(alertname) = 'https://hub.syn.tools/openshift4-logging/runbooks/%s.html' % alertname;

assert
  std.member(inv.applications, 'openshift4-monitoring')
  : 'Component `openshift4-monitoring` not enabled';

// Upstream alerts to ignore
// Keep only alerts from params.ignore_alerts for which the last
// array entry wasn't prefixed with `~`.
local ignore_alerts = std.set(
  // Add set of upstream alerts that should be ignored from processed value of
  // `params.ignore_alerts`
  com.renderArray(std.get(params, 'ignore_alerts', []))
  + com.renderArray(std.get(params, 'ignore_alerts', []))
);

// Alert rule patches.
// Provide partial objects for alert rules that need to be tuned compared to
// upstream. The keys in this object correspond to the `alert` field of the
// rule for which the patch is intended.
local patch_alerts = params.alerts.patch + std.get(params, 'patch_alerts', {});

local loadFile(file) =
  local fpath = 'openshift4-logging/component/extracted_alerts/%s/%s' % [ params.alerts.release, file ];
  std.parseJson(kap.yaml_load_stream(fpath));

local renderRunbookBaseURL(group, baseURL) = {
  name: group.name,
  rules: std.map(
    function(rule)
      if (
        std.objectHas(rule, 'annotations') &&
        std.objectHas(rule.annotations, 'runbook_url') && (
          std.length(std.findSubstr('[[.RunbookBaseURL]]', rule.annotations.runbook_url)) > 0 ||
          std.length(std.findSubstr('[[ .RunbookURL ]]', rule.annotations.runbook_url)) > 0
        )
      ) then rule {
        annotations+: {
          local round1 = std.strReplace(rule.annotations.runbook_url, '[[.RunbookBaseURL]]', baseURL),
          local round2 = std.strReplace(round1, '[[ .RunbookURL ]]', baseURL),
          runbook_url: round2,
        },
      } else rule,
    group.rules
  ),
};

local dropInfoRules =
  local drop(rule) =
    local rlbls = std.get(rule, 'labels', {});
    std.get(rlbls, 'severity', '') == 'info';
  {
    rules: std.filter(function(rule) !drop(rule), super.rules),
  };

local prometheus_rules(name, groups, baseURL) = kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', name) {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    groups: std.filter(
      function(it) it != null,
      [
        local r = alertpatching.filterPatchRules(g + dropInfoRules, ignore_alerts, patch_alerts);
        local s = renderRunbookBaseURL(r, baseURL);
        if std.length(s.rules) > 0 then s
        for g in groups
      ],
    ),
  },
};

// Lokistack alerts

local lokiGroups = loadFile('lokistack_prometheus_alerts.yaml')[0].groups;
local lokiBaseURL = 'https://github.com/grafana/loki/blob/main/operator/docs/lokistack/sop.md';

// Collector alerts

local collectorGroups = loadFile('collector_prometheus_alerts.yaml')[0].spec.groups;

{
  [if lokiEnabled then '60_lokistack_alerts']: prometheus_rules('syn-loki-logging-rules', lokiGroups, lokiBaseURL),
  '60_collector_alerts': prometheus_rules('syn-collector-rules', collectorGroups, ''),
}
