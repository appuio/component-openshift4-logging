local kap = import 'lib/kapitan.libjsonnet';
local lib = import 'lib/openshift4-logging.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_logging;

local deployLokistack = params.components.lokistack.enabled;
local deployElasticsearch = params.components.elasticsearch.enabled;

// Apply defaults for Lokistack.
local patchLokistackDefaults = {
  [if deployLokistack then 'spec']: {
    logStore: {
      type: 'lokistack',
      lokistack: {
        name: 'loki',
      },
    },
  },
};

// Apply defaults for Elasticsearch.
local patchElasticsearchDefaults = {
  [if deployElasticsearch then 'spec']: {
    logStore: {
      elasticsearch: {
        nodeCount: 3,
        storage: {
          size: '200Gi',
        },
        redundancyPolicy: 'SingleRedundancy',
        nodeSelector: {
          'node-role.kubernetes.io/infra': '',
        },
      },
      retentionPolicy: {
        application: {
          maxAge: '7d',
          pruneNamespacesInterval: '15m',
        },
        infra: {
          maxAge: '30d',
          pruneNamespacesInterval: '15m',
        },
        audit: {
          maxAge: '30d',
          pruneNamespacesInterval: '15m',
        },
      },
    },
    visualization: {
      type: 'kibana',
      kibana: {
        replicas: 2,
        nodeSelector: {
          'node-role.kubernetes.io/infra': '',
        },
      },
    },
  },
};

// Apply customisations from params.clusterLogging.
local patchLoggingConfig = {
  spec: params.clusterLogging {
    collection: {
      // Don't include legacy config key 'collection.logs'.
      [it]: params.clusterLogging.collection[it]
      for it in std.objectFields(std.get(params.clusterLogging, 'collection', {}))
      if it != 'logs'
    },
  },
};

// --- patch deprecated logging resource
local patchLegacyConfig = {
  local legacyConfig = std.get(std.get(params.clusterLogging, 'collection', { collection: {} }), 'logs', {}),
  local legacyType = std.get(legacyConfig, 'type', ''),
  local legacyFluentd = std.get(legacyConfig, 'fluentd', {}),

  spec: {
    collection: if std.length(legacyConfig) > 0 then std.trace(
      'Parameter `clusterLogging.collector.logs` is deprecated. Please update your config to use `clusterLogging.collector`',
      {
        [if legacyType != '' then 'type']: legacyType,
      } + legacyFluentd,
    ) else {},
  },
};
// --- patch end


// ClusterLogging specs:
// Consecutively apply patches to result of previous apply.
local clusterLogging = std.foldl(
  // we use std.mergePatch here, because this way we don't need
  // to make each patch object mergeable by suffixing all keys with a +.
  function(manifest, patch) std.mergePatch(manifest, patch),
  [
    patchLokistackDefaults,
    patchElasticsearchDefaults,
    patchLoggingConfig,
    patchLegacyConfig,
  ],
  lib.ClusterLogging(params.namespace, 'instance') {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
      },
    },
    spec: {
      managementState: 'Managed',
      collection: {
        type: 'vector',
      },
    },
  }
);

// Define outputs below
{
  '30_cluster_logging': clusterLogging,
}
