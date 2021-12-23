local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local resourceLocker = import 'lib/resource-locker.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_logging;

local routeToPatch = kube._Object('route.openshift.io/v1', 'Route', 'kibana') {
  metadata+: {
    namespace: params.namespace,
  },
};

{
  [if params.kibana_host != null then '32_kibana_host']:
    resourceLocker.Patch(routeToPatch, {
      spec: {
        host: params.kibana_host,
      },
    }),
}
