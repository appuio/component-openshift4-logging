local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local logmetrics = inv.parameters.openshift4_logging.components.logmetrics;

local logMetricExporter = kube._Object('logging.openshift.io/v1alpha1', 'LogFileMetricExporter', 'instance') {
  spec: logmetrics.spec,
};


// Define outputs below
if logmetrics.enabled then
  {
    '70_logmetricsexporter': logMetricExporter,
  }
else
  std.trace(
    'Logmetrics disabled, not deploying LogFileMetricExporter',
    {}
  )
