local kube = import 'lib/kube.libjsonnet';

local ClusterLogging(namespace, name) = kube._Object('logging.openshift.io/v1', 'ClusterLogging', name) {
  metadata+: {
    namespace: namespace,
  },
};

local ClusterLogForwarder(namespace, name) = kube._Object('logging.openshift.io/v1', 'ClusterLogForwarder', name) {
  metadata+: {
    namespace: namespace,
  },
};

{
  ClusterLogging: ClusterLogging,
  ClusterLogForwarder: ClusterLogForwarder,
}
