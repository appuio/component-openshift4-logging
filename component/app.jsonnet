local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local argocd = import 'lib/argocd.libjsonnet';

{
  'openshift4-logging': argocd.App('openshift4-logging', params.namespace) {
    spec+: {
      syncPolicy+: {
        syncOptions+: [
          'ServerSideApply=true',
        ],
      },
    },
  },
}
