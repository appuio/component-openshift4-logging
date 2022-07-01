/*
- apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    creationTimestamp: "2022-04-18T10:03:18Z"
    generation: 1
    labels:
      control-plane: controller-manager
    name: cluster-logging-operator-metrics-monitor
    namespace: openshift-logging
    ownerReferences:
    - apiVersion: operators.coreos.com/v1alpha1
      blockOwnerDeletion: false
      controller: false
      kind: ClusterServiceVersion
      name: cluster-logging.5.2.11
      uid: 836f800d-82ab-444c-9d67-1e33028a91d0
    resourceVersion: "466758226"
    uid: 34c85cf9-c513-42fe-aeb9-c4d59d31810e
  spec:
    endpoints:
    - port: http-metrics
    namespaceSelector: {}
    selector:
      matchLabels:
        control-plane: cluster-logging-operator
- apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    creationTimestamp: "2021-10-14T07:57:45Z"
    generation: 1
    name: fluentd
    namespace: openshift-logging
    ownerReferences:
    - apiVersion: logging.openshift.io/v1
      controller: true
      kind: ClusterLogging
      name: instance
      uid: 4cb4fcdd-7284-4781-9ede-0b250d6a99e6
    resourceVersion: "406788"
    uid: f1158c9f-e5f8-4a33-bd4b-840428035887
  spec:
    endpoints:
    - bearerTokenSecret:
        key: ""
      path: /metrics
      port: metrics
      scheme: https
      tlsConfig:
        ca: {}
        caFile: /etc/prometheus/configmaps/serving-certs-ca-bundle/service-ca.crt
        cert: {}
        serverName: fluentd.openshift-logging.svc
    - bearerTokenSecret:
        key: ""
      path: /metrics
      port: logfile-metrics
      scheme: https
      tlsConfig:
        ca: {}
        caFile: /etc/prometheus/configmaps/serving-certs-ca-bundle/service-ca.crt
        cert: {}
        serverName: fluentd.openshift-logging.svc
    jobLabel: monitor-fluentd
    namespaceSelector:
      matchNames:
      - openshift-logging
    selector:
      matchLabels:
        logging-infra: support
- apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    creationTimestamp: "2021-10-14T07:58:18Z"
    generation: 1
    labels:
      cluster-name: elasticsearch
      scrape-metrics: enabled
    name: monitor-elasticsearch-cluster
    namespace: openshift-logging
    ownerReferences:
    - apiVersion: logging.openshift.io/v1
      controller: true
      kind: Elasticsearch
      name: elasticsearch
      uid: 34fc08a0-d069-4a78-8ae7-71ae915513df
    resourceVersion: "73826551"
    uid: c3a18817-425a-410c-9789-6ecec603172e
  spec:
    endpoints:
    - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
      bearerTokenSecret:
        key: ""
      path: /metrics
      port: elasticsearch
      scheme: https
      tlsConfig:
        ca: {}
        caFile: /etc/prometheus/configmaps/serving-certs-ca-bundle/service-ca.crt
        cert: {}
        serverName: elasticsearch-metrics.openshift-logging.svc
    - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
      bearerTokenSecret:
        key: ""
      path: /_prometheus/metrics
      port: elasticsearch
      scheme: https
      tlsConfig:
        ca: {}
        caFile: /etc/prometheus/configmaps/serving-certs-ca-bundle/service-ca.crt
        cert: {}
        serverName: elasticsearch-metrics.openshift-logging.svc
    jobLabel: monitor-elasticsearch
    namespaceSelector:
      matchNames:
      - openshift-logging
    selector:
      matchLabels:
        cluster-name: elasticsearch
        scrape-metrics: enabled

*/

{
  service_monitors: [],
}
