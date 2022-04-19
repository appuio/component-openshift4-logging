local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local resourceLocker = import 'lib/resource-locker.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_logging;

local deploymentToPatch = kube._Object('apps/v1', 'Deployment', params.elasticsearchOperator.patchTarget.name) {
  metadata+: {
    namespace: params.elasticsearchOperator.patchTarget.namespace,
  },
};

local patch = resourceLocker.Patch(deploymentToPatch, {
  spec: {
    template: {
      spec: params.elasticsearchOperator.patch,
    },
  },
});

{
  '40_deployment_patch': patch,
}
