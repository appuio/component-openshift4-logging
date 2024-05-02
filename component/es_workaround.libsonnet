local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local po = import 'lib/patch-operator.libsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;


// Generate missing metrics SA token for Elasticsearch Operator.
//
// The ServiceMonitor for the Elasticsearch Operator references a SA token secret
// called `elasticsearch-operator-controller-manager-metrics-token` which doesn't exist
// on the cluster after the operator is installed or upgraded to 5.8.6 via
// OLM.
local missing_metrics_token =
  kube.Secret('elasticsearch-operator-controller-manager-metrics-token') {
    metadata+: {
      // Loki operator is deployed in openshift-operators-redhat
      namespace: 'openshift-operators-redhat',
      annotations+: {
        'kubernetes.io/service-account.name': 'elasticsearch-operator-controller-manager-metrics-reader',
        // disable argocd prune/delete so removing the workaround should be
        // fairly easy in case the Elasticsearch Operator OLM install fixes the issue.
        'argocd.argoproj.io/sync-options': 'Prune=false,Delete=false',
      },
    },
    data:: {},
    type: 'kubernetes.io/service-account-token',
  };

{
  missing_metrics_token: [ missing_metrics_token ],
}
