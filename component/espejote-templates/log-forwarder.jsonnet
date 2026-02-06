local esp = import 'espejote.libsonnet';
local config = import 'lib/espejote-dyn-log-forwarder/config.json';

local context = esp.context();

// Extracts labels starting with 'config.inputLabelPrefix' from a namespace object
local getPrefixedLabels(ns) = std.filter(
  // Filter label keys starting with `config.inputLabelPrefix`.
  function(key) std.startsWith(key, config.inputLabelPrefix),
  // Array of label keys in the namespace object
  std.objectFields(std.get(ns.metadata, 'labels', {}))
);

// Filter namespaces based on `config.ignoreNamespaces` and `config.ignoreNamespacesPrefix`
local filteredNamespaces = std.filter(
  function(ns) if std.member(config.ignoreNamespaces, ns.metadata.name) then
    false
  else if std.length(std.filter(
    function(prefix) std.startsWith(ns.metadata.name, prefix),
    config.ignoreNamespacePrefixes
  )) > 0 then
    false
  else true,
  context.namespaces
);

// Filter all labels from namespaces starting with `config.inputLabelPrefix`.
local filteredLabels = std.set(
  std.flatMap(
    function(ns) [
      label
      for label in getPrefixedLabels(ns)
    ],
    filteredNamespaces
  )
);

// Get the namespaces for a given input label
local namespacePerInput(label) = std.filterMap(
  function(ns) std.member(getPrefixedLabels(ns), label),
  function(ns) ns.metadata.name,
  filteredNamespaces
);

// Do the thing
{
  apiVersion: 'observability.openshift.io/v1',
  kind: 'ClusterLogForwarder',
  metadata: {
    name: 'instance',
    namespace: 'openshift-logging',
  },
  spec: {
    inputs: [
      {
        name: std.split(label, '/')[1],
        type: 'application',
        application: {
          includes: [
            { namespace: name }
            for name in namespacePerInput(label)
          ],
        },
      }
      for label in filteredLabels
    ],
  },
}
