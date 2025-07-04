local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local oplib = import 'lib/operator-rules.libsonnet';
local syn_teams = import 'syn/syn-teams.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local global_name = 'openshift4-monitoring-rules';
local global_namespace = inv.parameters.espejote.namespace;

local jsonnetLibrary(ns) = esp.jsonnetLibrary(global_name, ns) {
  spec: {
    data: {
      'config.json': std.manifestJson({
        ignoreNames: params.alerts.ignore,
        patchRules: params.alerts.patch,
        teamLabel: syn_teams.teamForApplication(inv.parameters._instance),
      }),
    },
  },
};


// Define outputs below
{
  '60_rules_operator': [
    oplib.serviceAccount(params.namespace),
    oplib.role(params.namespace),
    oplib.roleBinding(params.namespace),
    oplib.roleBindingGlobal(params.namespace),
    oplib.managedResourceV1(params.namespace),
    jsonnetLibrary(params.namespace),
  ],
}
