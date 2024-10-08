local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local isVersion58 =
  local major = std.split(params.version, '.')[0];
  local minor = std.split(params.version, '.')[1];
  if major == 'master' then true
  else if std.parseInt(major) >= 6 then true
  else if std.parseInt(major) == 5 && std.parseInt(minor) >= 8 then true
  else false;

local isVersion59 =
  local major = std.split(params.version, '.')[0];
  local minor = std.split(params.version, '.')[1];
  if major == 'master' then true
  else if std.parseInt(major) >= 6 then true
  else if std.parseInt(major) == 5 && std.parseInt(minor) >= 9 then true
  else false;

local namespacedName(name) = {
  local namespaced = std.splitLimit(name, '/', 1),
  namespace: if std.length(namespaced) > 1 then namespaced[0] else params.namespace,
  name: if std.length(namespaced) > 1 then namespaced[1] else namespaced[0],
};

{
  isVersion58: isVersion58,
  isVersion59: isVersion59,
  namespacedName: namespacedName,
}
