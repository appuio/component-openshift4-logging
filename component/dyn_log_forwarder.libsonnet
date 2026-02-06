local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local utils = import 'utils.libsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local espNamespace = inv.parameters.espejote.namespace;
local mrName = 'espejote-dyn-log-forwarder';
local rbacName = 'espejote-managedresource-dyn-log-forwarder';

// RBAC for dynamic log forwarder
local espejoteRBAC = [
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'openshift4-logging',
        'app.kubernetes.io/name': mrName,
      },
      name: mrName,
      namespace: espNamespace,
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'openshift4-logging',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
    },
    rules: [
      {
        apiGroups: [ '' ],
        resources: [ 'namespaces' ],
        verbs: [ 'get', 'list', 'watch' ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'openshift4-logging',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: rbacName,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: mrName,
        namespace: espNamespace,
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'openshift4-logging',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
      namespace: espNamespace,
    },
    rules: [
      {
        apiGroups: [ 'espejote.io' ],
        resources: [ 'jsonnetlibraries' ],
        resourceNames: [ mrName ],
        verbs: [ 'get', 'list', 'watch' ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'openshift4-logging',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
      namespace: espNamespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: rbacName,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: mrName,
        namespace: espNamespace,
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'openshift4-logging',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
      namespace: params.namespace,
    },
    rules: [
      {
        apiGroups: [ 'observability.openshift.io' ],
        resources: [ 'clusterlogforwarders' ],
        resourceNames: [ 'instance' ],
        verbs: [ 'get', 'list', 'watch', 'patch', 'create', 'delete' ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'openshift4-logging',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
      namespace: params.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: rbacName,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: mrName,
        namespace: espNamespace,
      },
    ],
  },
];

// Espejote resources
local jsonnetLibrary = esp.jsonnetLibrary(mrName, espNamespace) {
  spec: {
    data: {
      'config.json': std.manifestJson({
        // Ignore namespaces by name or prefix
        ignoreNamespaces: com.renderArray(params.dynamicLogForwarder.ignoreNamespaces),
        ignoreNamespacePrefixes: com.renderArray(params.dynamicLogForwarder.ignoreNamespacePrefixes),
        // Label prefix for inputs
        inputLabelPrefix: params.dynamicLogForwarder.inputLabelPrefix,
      }),
    },
  },
};

local managedResource = esp.managedResource(mrName, espNamespace) {
  metadata+: {
    annotations: {
      'syn.tools/description': |||
        Manages OpenShift ClusterLogForwarder inputs based on namespace labels.

        This component allows to dynamically add namespaces to the  `inputs.<NAME>.application.includes`
        field of a ClusterLogForwarder by using labels on namespaces.
        See https://hub.syn.tools/openshift4-logging/index.html for details.
      |||,
    },
  },
  spec: {
    context: [
      {
        name: 'namespaces',
        resource: {
          apiVersion: 'v1',
          kind: 'Namespace',
        },
      },
    ],
    triggers: [
      {
        name: 'jslib',
        watchResource: {
          apiVersion: jsonnetLibrary.apiVersion,
          kind: 'JsonnetLibrary',
          name: jsonnetLibrary.metadata.name,
          namespace: jsonnetLibrary.metadata.namespace,
        },
      },
      {
        name: 'namespace',
        watchContextResource: {
          name: 'namespaces',
        },
      },
      {
        name: 'clusterlogforwarder',
        watchResource: {
          apiVersion: 'observability.openshift.io/v1',
          kind: 'ClusterLogForwarder',
          name: 'instance',
          namespace: 'openshift-logging',
        },
      },
    ],
    serviceAccountRef: {
      name: espejoteRBAC[0].metadata.name,
    },
    template: importstr 'espejote-templates/log-forwarder.jsonnet',
  },
};

// Check if espejote is installed and resources are configured
local hasEspejote = std.member(inv.applications, 'espejote');

// Define outputs below
if params.dynamicLogForwarder.enabled && hasEspejote then
  {
    '50_dyn_log_forwarder_rbac': espejoteRBAC,
    '50_dyn_log_forwarder_lib': jsonnetLibrary,
    '50_dyn_log_forwarder_mr': managedResource,
  }
else if params.dynamicLogForwarder.enabled then
  std.trace(
    'espejote must be installed',
    {}
  )
else {}
