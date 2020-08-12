local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('openshift4-logging', params.namespace, secrets=false);

{
  'openshift4-logging': app,
}
