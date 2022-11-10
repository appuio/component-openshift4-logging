local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local group = 'operators.coreos.com/';
local clusterLoggingGroupVersion = 'logging.openshift.io/v1';

local alert_rules = import 'alertrules.libsonnet';
local metrics = import 'metrics.libsonnet';

// Boolean flag to determine if the provided logging channel is >= <channel>-5.5
//
// The implementation is able to parse arbitrary channel specifications which
// have the format <channel-name>-<maj>.<min>, channel-name can contain
// dashes.
//
// IMPORTANT: Channel specifications which don't contain a recognizable
// version are treated as >= 5.5.
local channel_ge_55 =
  local parts = std.split(params.channel, '-');

  local genericErr = {
    parseErr:
      'Unable to parse channel version from "%s", assuming version >= 5.5' % [ params.channel ],
    result: true,
  };
  local minorErr(maj) = {
    parseErr:
      'Unable to parse minor version from "%s", treating any 5.x as >= 5.5' % [ params.channel ],
    result: maj >= 5,
  };
  local veridx = std.length(parts) - 1;
  local verparts = std.split(parts[veridx], '.');
  // Version is a object with fields result and parseErr.
  // If parseErr is not '', `result` may not be accurate. If we can't
  // accurately determine whether the provided channel is >= 5.5 we fall back
  // to assuming >= 5.5 (e.g. if we can parse the major version but not the
  // minor version, we assume that any 5.x is >= 5.5).
  local result =
    if std.length(parts) < 2 then
      genericErr
    else
      // we assume the version is the last part
      local veridx = std.length(parts) - 1;
      local verparts = std.split(parts[veridx], '.');
      // ver contains maj, min, and parseErr
      // we use std.parseJson instead of std.parseInt here, so that we can
      // gracefully degrade if the value is not a number.
      local ver = {
        maj: std.parseJson(verparts[0]),
        min: if std.length(verparts) > 1 then std.parseJson(verparts[1]) else 5,
      };
      if std.isNumber(ver.maj) && std.isNumber(ver.min) then
        {
          result: ver.maj > 5 || (ver.maj == 5 && ver.min >= 5),
          parseErr: '',
        }
      else if std.isNumber(ver.maj) then
        minorErr(ver.maj)
      else
        genericErr;

  if result.parseErr != '' then
    std.trace(result.parseErr, result.result)
  else
    result.result;

local namespace_groups = (
  if std.objectHas(params.clusterLogForwarding, 'namespaces') then
    {
      [ns]: {
        namespaces: [ ns ],
        forwarders: [ params.clusterLogForwarding.namespaces[ns].forwarder ],
      }
      for ns in std.objectFields(params.clusterLogForwarding.namespaces)
    }
  else
    {}
) + params.clusterLogForwarding.namespace_groups;

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
  '10_operator_group': operatorlib.OperatorGroup('cluster-logging') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      targetNamespaces: [
        params.namespace,
      ],
    },
  },
  '20_subscriptions': [
    operatorlib.managedSubscription(
      'openshift-operators-redhat',
      'elasticsearch-operator',
      params.channel
    ),
    operatorlib.namespacedSubscription(
      params.namespace,
      'cluster-logging',
      params.channel,
      'redhat-operators'
    ),
  ],
  '30_cluster_logging': kube._Object(clusterLoggingGroupVersion, 'ClusterLogging', 'instance') {
    metadata+: {
      namespace: params.namespace,
      annotations+: {
        'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
      },
    },
    spec: params.clusterLogging {
      [if channel_ge_55 then 'collection']+: {
        type: super.logs.type,
      },
    },
  },
  [if params.clusterLogForwarding.enabled then '31_cluster_logforwarding']: kube._Object(clusterLoggingGroupVersion, 'ClusterLogForwarder', 'instance') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      [if params.clusterLogForwarding.json.enabled then 'outputDefaults']: {
        elasticsearch: {
          structuredTypeKey: params.clusterLogForwarding.json.typekey,
          structuredTypeName: params.clusterLogForwarding.json.typename,
        },
      },
      [if std.length(params.clusterLogForwarding.forwarders) > 0 then 'outputs']: [
        params.clusterLogForwarding.forwarders[fw] { name: fw }
        for fw in std.objectFields(params.clusterLogForwarding.forwarders)
      ],
      [if std.length(namespace_groups) > 0 then 'inputs']: [
        {
          name: group,
          application: {
            namespaces: namespace_groups[group].namespaces,
          },
        }
        for group in std.objectFields(namespace_groups)
      ],
      [if std.length(namespace_groups) > 0 then 'pipelines']: [
        local enable_json = com.getValueOrDefault(namespace_groups[group], 'json', false);
        local patch_json = { outputRefs: [ 'default' ], parse: 'json' };
        {
          name: group,
          inputRefs: [ group ],
          outputRefs: com.getValueOrDefault(namespace_groups[group], 'forwarders', []),
        } + com.makeMergeable(if enable_json then patch_json else {})
        for group in std.objectFields(namespace_groups)
      ],
    } + com.makeMergeable(
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'json', false);
      {
        pipelines: [
          {
            name: 'application-logs',
            inputRefs: [ 'application' ],
            outputRefs: com.getValueOrDefault(params.clusterLogForwarding.application_logs, 'forwarders', []) + [ 'default' ],
            [if enable_json then 'parse']: 'json',
          },
        ],
      }
    ) + com.makeMergeable(
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.infrastructure_logs, 'json', false);
      {
        [if params.clusterLogForwarding.infrastructure_logs.enabled then 'pipelines']: [
          {
            name: 'infrastructure-logs',
            inputRefs: [ 'infrastructure' ],
            outputRefs: com.getValueOrDefault(params.clusterLogForwarding.infrastructure_logs, 'forwarders', []) + [ 'default' ],
            [if enable_json then 'parse']: 'json',
          },
        ],
      }
    ) + com.makeMergeable(
      local enable_json = com.getValueOrDefault(params.clusterLogForwarding.audit_logs, 'json', false);
      {
        [if params.clusterLogForwarding.audit_logs.enabled then 'pipelines']: [
          {
            name: 'audit-logs',
            inputRefs: [ 'audit' ],
            outputRefs: com.getValueOrDefault(params.clusterLogForwarding.audit_logs, 'forwarders', []) + [ 'default' ],
          },
        ],
      }
    ),
  },
  '40_journald_configs': [ kube._Object('machineconfiguration.openshift.io/v1', 'MachineConfig', '40-' + role + '-journald') {
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
  } for role in [ 'master', 'worker' ] ],
  '50_networkpolicy':
    // Allow cluster-scoped ES operator to access ES pods in openshift-logging
    kube._Object('networking.k8s.io/v1', 'NetworkPolicy', 'allow-from-openshift-operators-redhat')
    {
      metadata+: {
        namespace: params.namespace,
      },
      spec: {
        ingress: [
          {
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    name: 'openshift-operators-redhat',
                  },
                },
              },
              {
                podSelector: {
                  matchLabels: {
                    name: 'elasticsearch-operator',
                  },
                },
              },
            ],
          },
        ],
        podSelector: {},
        policyTypes: [ 'Ingress' ],
      },
    },
  '60_prometheus_rules': alert_rules.rules,
} + (import 'kibana-host.libsonnet')
+ (import 'metrics.libsonnet')
