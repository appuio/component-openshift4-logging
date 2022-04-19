local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local resourceLocker = import 'lib/resource-locker.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_logging;

local deploymentToPatch = kube._Object('apps/v1', 'Deployment', 'elasticsearch-operator') {
  metadata+: {
    namespace: params.namespace,
  },
};

local patch = resourceLocker.Patch(deploymentToPatch, {
  spec: {
    template: {
      spec: {
        nodeSelector: params.elasticsearch_operator.nodeSelector,
      },
    },
  },
});


{
  '40_deployment_patch': patch,
}
