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

local patch = resourceLocker.Patch(routeToPatch, {
  spec: {
    host: params.kibana_host,
  },
});

// OpenShift has custom RBAC permissions on routes if you want to set a host ┻━┻︵ヽ(`Д´)ﾉ︵ ┻━┻
local patchWithAdditionalPermissions = std.map(
  function(obj)
    if obj.apiVersion == 'rbac.authorization.k8s.io/v1' && obj.kind == 'Role' then
      obj {
        rules+: [
          {
            apiGroups: [
              'route.openshift.io',
            ],
            resources: [
              'routes/custom-host',
            ],
            verbs: [
              '*',
            ],
          },
        ],
      }
    else
      obj
  , patch
);

{
  [if params.kibana_host != null then '32_kibana_host']: patchWithAdditionalPermissions,
}
