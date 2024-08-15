// main template for openshift4-lokistack
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local po = import 'lib/patch-operator.libsonnet';
local workaround = import 'loki_workaround.libsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local loki = inv.parameters.openshift4_logging.components.lokistack;


local lokistack_spec = {
  template: {
    compactor: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 1,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
    distributor: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 2,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
    gateway: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 2,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
    indexGateway: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 2,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
    ingester: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 2,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
    querier: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 2,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
    queryFrontend: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 2,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
    ruler: {
      [if loki.spec.size == '1x.demo' then 'replicas']: 1,
      nodeSelector: { 'node-role.kubernetes.io/infra': '' },
    },
  },
};

local lokistack = kube._Object('loki.grafana.com/v1', 'LokiStack', 'loki') {
  metadata+: {
    annotations+: {
      // Allow ArgoCD to do the dry run when the CRD doesn't exist yet
      'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
    },
  },
  spec: lokistack_spec + com.makeMergeable(loki.spec),
};

local logstore = kube.Secret('loki-logstore') {
  stringData: loki.logStore,
};

local netpol_viewplugin = kube.NetworkPolicy('allow-console-logging-view-plugin') {
  spec: {
    ingress: [ {
      from: [
        { podSelector: { matchLabels: { app: 'console', component: 'ui' } } },
        { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'openshift-console' } } },
      ],
      ports: [ { port: 9443, protocol: 'TCP' } ],
    } ],
    podSelector: {
      matchLabels: {
        'app.kubernetes.io/created-by': 'openshift-logging_instance',
        'app.kubernetes.io/name': 'logging-view-plugin',
      },
    },
    policyTypes: [ 'Ingress' ],
  },
};

local netpol_lokigateway = kube.NetworkPolicy('allow-console-logging-lokistack-gateway') {
  spec: {
    ingress: [ {
      from: [
        { podSelector: { matchLabels: { app: 'console', component: 'ui' } } },
        { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'openshift-console' } } },
      ],
      ports: [ { port: 8080, protocol: 'TCP' } ],
    } ],
    podSelector: {
      matchLabels: {
        'app.kubernetes.io/component': 'lokistack-gateway',
        'app.kubernetes.io/instance': 'loki',
        'app.kubernetes.io/name': 'lokistack',
      },
    },
    policyTypes: [ 'Ingress' ],
  },
};

// Aggregate permission to view all logs to `cluster-reader` role
local aggregate_loki_log_access = kube.ClusterRole('syn:loki:cluster-reader') {
  metadata+: {
    labels+: {
      'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
    },
  },
  rules: [
    {
      apiGroups: [ 'loki.grafana.com' ],
      resources: com.renderArray(loki.clusterReaderLogAccess),
      resourceNames: [ 'logs' ],
      verbs: [ 'get' ],
    },
  ],
};

// Define outputs below
if loki.enabled then
  {
    '50_loki_stack': lokistack,
    '50_loki_logstore': logstore,
    '50_loki_netpol': [ netpol_viewplugin, netpol_lokigateway ],
    '50_loki_rbac': [ aggregate_loki_log_access ],
    '50_loki_operator_metrics_token': workaround.missing_metrics_token,
    '50_loki_ingester_fix': workaround.ingester_stuck,
    '50_loki_logreader_fix': workaround.app_logs_reader,
  }
else
  std.trace(
    'Lokistack disabled, not deploying Lokistack',
    {}
  )
