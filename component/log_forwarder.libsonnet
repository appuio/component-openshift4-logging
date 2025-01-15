local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local lokiEnabled = params.components.lokistack.enabled;
local forwarderEnabled = lokiEnabled || std.length(params.clusterLogForwarder) > 0;

// clusterLogForwarderSpec:
// Consecutively apply patches to result of previous apply.
local clusterLogForwarderSpec = {
  managementState: 'Managed',
  collector: {
    resources: {
      requests: {
        cpu: '20m',
        memory: '400M',
      },
    },
    tolerations: [ {
      key: 'storagenode',
      operator: 'Exists',
    } ],
  },
  serviceAccount: {
    name: 'logcollector',
  },
  filters: {},
  inputs: {},
  outputs: {
    [if lokiEnabled then 'default-lokistack']: {
      type: 'lokiStack',
      lokiStack: {
        target: {
          name: 'loki',
          namespace: params.namespace,
        },
        authentication: {
          token: {
            from: 'serviceAccount',
          },
        },
      },
      tls: {
        ca: {
          key: 'service-ca.crt',
          configMapName: 'openshift-service-ca.crt',
        },
      },
    },
  },
  pipelines: {
    [if lokiEnabled then 'default-lokistack']: {
      outputRefs: [ 'default-lokistack' ],
      inputRefs: [ 'application', 'infrastructure' ],
    },
  },
} + com.makeMergeable(params.clusterLogForwarder);

// Unfold objects into array for ClusterLogForwarder resource.
local unfoldSpecs(specs) = {
  // Unfold objects into array.
  [if std.length(specs.filters) > 0 then 'filters']: [
    { name: name } + specs.filters[name]
    for name in std.objectFields(specs.filters)
  ],
  [if std.length(specs.inputs) > 0 then 'inputs']: [
    { name: name } + specs.inputs[name]
    for name in std.objectFields(specs.inputs)
  ],
  [if std.length(specs.outputs) > 0 then 'outputs']: [
    { name: name } + specs.outputs[name]
    for name in std.objectFields(specs.outputs)
  ],
  [if std.length(specs.pipelines) > 0 then 'pipelines']: [
    { name: name } + specs.pipelines[name]
    for name in std.objectFields(specs.pipelines)
  ],
} + {
  // Import remaining specs as is.
  [key]: specs[key]
  for key in std.objectFields(specs)
  if !std.member([ 'filters', 'inputs', 'outputs', 'pipelines' ], key)
};

// ClusterLogForwarder:
// Create definitive ClusterLogForwarder resource from specs.
local clusterLogForwarder = kube._Object('observability.openshift.io/v1', 'ClusterLogForwarder', 'instance') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
    },
    namespace: params.namespace,
  },
  spec: unfoldSpecs(clusterLogForwarderSpec),
};

// Collector ServiceAccount
// Create a ServiceAccount and ClusterRoleBindings for collector pods.
local rbac = [
  kube.ServiceAccount('logcollector') {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-wave': '-50',
      },
      namespace: params.namespace,
    },
  },
  kube._Object('rbac.authorization.k8s.io/v1', 'ClusterRoleBinding', 'logcollector-application-logs') {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-wave': '-50',
      },
      namespace: params.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'collect-application-logs',
    },
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'logcollector',
      namespace: params.namespace,
    } ],
  },
  kube._Object('rbac.authorization.k8s.io/v1', 'ClusterRoleBinding', 'logcollector-infrastructure-logs') {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-wave': '-50',
      },
      namespace: params.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'collect-infrastructure-logs',
    },
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'logcollector',
      namespace: params.namespace,
    } ],
  },
  kube._Object('rbac.authorization.k8s.io/v1', 'ClusterRoleBinding', 'logcollector-audit-logs') {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-wave': '-50',
      },
      namespace: params.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'collect-audit-logs',
    },
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'logcollector',
      namespace: params.namespace,
    } ],
  },
  if lokiEnabled then kube._Object('rbac.authorization.k8s.io/v1', 'ClusterRoleBinding', 'logcollector-log-writer') {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-wave': '-50',
      },
      namespace: params.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'logging-collector-logs-writer',
    },
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'logcollector',
      namespace: params.namespace,
    } ],
  },
];

// Define outputs below
if forwarderEnabled then
  {
    '40_log_forwarder': clusterLogForwarder,
    '40_log_forwarder_rbac': rbac,
  }
else
  std.trace(
    'Log forwarding disabled, not deploying ClusterLogForwarder',
    {}
  )
