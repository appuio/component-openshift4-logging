// main template for openshift4-lokistack
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local resourceLocker = import 'lib/resource-locker.libjsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local elasticsearch = inv.parameters.openshift4_logging.components.elasticsearch;


local machineconfig_journald = [
  kube._Object('machineconfiguration.openshift.io/v1', 'MachineConfig', '40-' + role + '-journald') {
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
  }
  for role in [ 'master', 'worker' ]
];

// Allow cluster-scoped ES operator to access ES pods in openshift-logging
local netpol_operator = kube.NetworkPolicy('allow-from-openshift-operators-redhat') {
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
};

// Keep config backwards compatible
local kibana_host =
  if std.objectHas(params, 'kibana_host') then
    std.trace(
      'parameter kibana_host is deprecated, please use parameter `components.elasticsearch.kibana_host instead`',
      params.kibana_host
    )
  else elasticsearch.kibana_host;

local kibana_routeToPatch = kube._Object('route.openshift.io/v1', 'Route', 'kibana') {
  metadata+: {
    namespace: inv.parameters.openshift4_logging.namespace,
  },
};

local kibana_patch = resourceLocker.Patch(kibana_routeToPatch, {
  spec: {
    host: kibana_host,
  },
});

// OpenShift has custom RBAC permissions on routes if you want to set a host ┻━┻︵ヽ(`Д´)ﾉ︵ ┻━┻
local kibana_patchWithAdditionalPermissions = std.map(
  function(obj)
    if obj.apiVersion == 'rbac.authorization.k8s.io/v1' && obj.kind == 'Role' then
      obj {
        rules+: [
          {
            apiGroups: [
              'route.openshift.io',
            ],
            resources: [
              'routes/custom-host',
            ],
            verbs: [
              '*',
            ],
          },
        ],
      }
    else
      obj
  , kibana_patch
);

// Define outputs below
if elasticsearch.enabled then
  {
    '40_es_machineconfig': machineconfig_journald,
    '40_es_netpol': netpol_operator,
    [if kibana_host != null then '40_es_kibana_host']: kibana_patchWithAdditionalPermissions,
  }
else
  std.trace(
    'Elasticsearch disabled, not deploying Elasticsearch stack',
    {}
  )
