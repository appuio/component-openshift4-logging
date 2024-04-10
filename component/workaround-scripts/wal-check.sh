#!/bin/bash

set -e -o pipefail

# Check if pod is in stuck state.
function check_pod() {
  POD_NAME="loki-ingester-${1}"
  echo "checking POD ${POD_NAME}"
  PHASE=$(kubectl -n openshift-logging get po ${POD_NAME} -oyaml | yq '.status.phase')
  if [ ${PHASE} != "Running" ]; then
    return 0
  fi
  READY=$(kubectl -n openshift-logging get po ${POD_NAME} -oyaml | yq '.status.conditions[] | select(.type == "ContainersReady") | .status')
  if [ ${READY} == "True" ]; then
    return 0
  fi
  return 1
}

# Check directories of pod and remove non-existing checkpoint if present.
function check_dir() {
  shopt -s extglob
  POD_NAME="loki-ingester-${1}"
  echo "checking DIR ${POD_NAME}"
  DIR_CHP=$(kubectl -n openshift-logging exec -i ${POD_NAME} -- ls /tmp/wal | grep -o "^checkpoint\.[0-9]*$")
  PATTERN=$(echo ${DIR_CHP} | sed 's/[^0-9]*//g')
  DIR_WAL=$(kubectl -n openshift-logging exec -i ${POD_NAME} -- ls /tmp/wal | grep -o "^0*${PATTERN}$" || exit 0)
  if [ -z $DIR_WAL ]; then
    kubectl -n openshift-logging exec -i ${POD_NAME} -- rm -rf /tmp/wal/${DIR_CHP}
    kubectl -n openshift-logging delete po ${POD_NAME}
  fi
}

# Check if pods are in stuck state for longer than ${SLEEP_TIME}.
# Only fix 1 pod at a time and immediatly exit if it is fixed.
function fix_pod() {
  if ! check_pod $1; then
    echo "stuck POD, waiting ${SLEEP_TIME}"
    sleep ${SLEEP_TIME}
    if ! check_pod $1; then
      check_dir $1
      exit 0
    fi
  fi
}

fix_pod 0
fix_pod 1

exit 0
