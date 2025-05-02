// main template for openshift4-lokistack
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local loki = inv.parameters.openshift4_logging.components.lokistack;

local lokistack_spec = {
  [if loki.spec.size == '1x.demo' then 'limits']: {
    global: {
      ingestion: {
        ingestionBurstSize: 9,
        ingestionRate: 5,
      },
    },
  },
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
      'argocd.argoproj.io/sync-wave': '-50',
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

// Console Log Plugin
local console_plugin = kube._Object('observability.openshift.io/v1alpha1', 'UIPlugin', 'logging') {
  metadata: {
    annotations: {
      'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
    },
    labels: {
      name: 'logging',
    },
    name: 'logging',
  },
  spec: {
    type: 'Logging',
    logging: {
      lokiStack: {
        name: 'loki',
      },
      logsLimit: 50,
      timeout: '30s',
    },
  },
};

// Define outputs below
if loki.enabled then
  {
    '30_loki_stack': lokistack,
    '30_loki_logstore': logstore,
    '30_loki_netpol': [ netpol_viewplugin, netpol_lokigateway ],
    '30_loki_rbac': [ aggregate_loki_log_access ],
    '30_loki_plugin': console_plugin,
  }
else
  std.trace(
    'Lokistack disabled, not deploying Lokistack',
    {}
  )
