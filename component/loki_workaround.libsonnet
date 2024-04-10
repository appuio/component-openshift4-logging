local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local po = import 'lib/patch-operator.libsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;


// Generate missing metrics SA token for Loki Operator.
//
// The ServiceMonitor for the Loki Operator references a SA token secret
// called `loki-operator-controller-manager-metrics-token` which doesn't exist
// on the cluster after the operator is installed or upgraded to 5.8.5 via
// OLM.
local missing_metrics_token =
  kube.Secret('loki-operator-controller-manager-metrics-token') {
    metadata+: {
      // Loki operator is deployed in openshift-operators-redhat
      namespace: 'openshift-operators-redhat',
      annotations+: {
        'kubernetes.io/service-account.name': 'loki-operator-controller-manager-metrics-reader',
        // disable argocd prune/delete so removing the workaround should be
        // fairly easy in case the Loki Operator OLM install fixes the issue.
        'argocd.argoproj.io/sync-options': 'Prune=false,Delete=false',
      },
    },
    data:: {},
    type: 'kubernetes.io/service-account-token',
  };


// Workaround for stuck loki-ingester.
// To be removed, once upstream is fixed.

local ingester_stuck = [
  kube.ServiceAccount('loki-ingester-check') {
    metadata+: {
      namespace: params.namespace,
    },
  },
  kube.Role('loki-ingester-check') {
    metadata+: {
      namespace: params.namespace,
    },
    rules: [ {
      apiGroups: [ '' ],
      resources: [ 'pods', 'pods/exec' ],
      verbs: [
        'get',
        'list',
        'watch',
        'create',
        'delete',
        'patch',
        'update',
      ],
    } ],
  },
  kube.RoleBinding('loki-ingester-check') {
    metadata+: {
      namespace: params.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: 'loki-ingester-check',
    },
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'loki-ingester-check',
    } ],
  },
  kube.ConfigMap('loki-ingester-check') {
    metadata+: {
      namespace: params.namespace,
    },
    data: {
      'wal-check.sh': importstr 'workaround-scripts/wal-check.sh',
    },
  },
  kube.CronJob('loki-ingester-check') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      schedule: params.workaround.ingester_fix.schedule,
      concurrencyPolicy: 'Forbid',
      failedJobsHistoryLimit: 0,
      jobTemplate: {
        spec: {
          activeDeadlineSeconds: 360,
          backoffLimit: 1,
          template: {
            spec: {
              containers: [ {
                name: 'check-pod',
                image: '%(registry)s/%(repository)s:%(tag)s' % params.images.kubectl,
                imagePullPolicy: 'IfNotPresent',
                command: [ '/usr/local/bin/wal-check.sh' ],
                env: [ {
                  name: 'SLEEP_TIME',
                  value: params.workaround.ingester_fix.sleep_time,
                } ],
                ports: [],
                stdin: false,
                tty: false,
                volumeMounts: [ {
                  mountPath: '/usr/local/bin/wal-check.sh',
                  name: 'wal-check',
                  readOnly: true,
                  subPath: 'wal-check.sh',
                } ],
              } ],
              nodeSelector: { 'node-role.kubernetes.io/infra': '' },
              restartPolicy: 'Never',
              serviceAccountName: 'loki-ingester-check',
              volumes: [ {
                name: 'wal-check',
                configMap: {
                  defaultMode: 364,
                  name: 'loki-ingester-check',
                },
              } ],
            },
          },
        },
      },
    },
  },
];

{
  missing_metrics_token: [ missing_metrics_token ],
  ingester_stuck: ingester_stuck,
}
