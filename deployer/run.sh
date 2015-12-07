#!/bin/bash
#
# Copyright 2014-2015 Red Hat, Inc. and/or its affiliates
# and other contributors as indicated by the @author tags.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -ex

# The version of everything to deploy
image_prefix=${IMAGE_PREFIX:-openshift/origin-}
image_version=${IMAGE_VERSION:-latest}

master_url=${MASTER_URL:-https://kubernetes.default.svc:8443}

# Set to true to undeploy everything before deploying
redeploy=${REDEPLOY:-false}

# The number of initial Cassandra Nodes to Deploy
cassandra_nodes=${CASSANDRA_NODES:-1}
# If we should use persistent storage or not
use_persistent_storage=${USE_PERSISTENT_STORAGE:-true}
# The size of each Cassandra Node
cassandra_pv_size=${CASSANDRA_PV_SIZE-10Gi}

# How long metrics should be stored in days
metric_duration=${METRIC_DURATION:-7}

# The project we are deployed in
project=${PROJECT:-default}

# the master certificate and service account tokens
master_ca=${MASTER_CA:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}
token_file=${TOKEN_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}

# directory to perform all the processing
dir=${PROCESSING_DIR:-_output} #directory used to write files which generating certificates

hawkular_metrics_hostname=${HAWKULAR_METRICS_HOSTNAME:-hawkular-metrics.example.com}
hawkular_metrics_alias=${HAWKULAR_METRICS_ALIAS:-hawkular-metrics}
hawkular_cassandra_alias=${HAWKULAR_CASSANDRA_ALIAS:-hawkular-cassandra}

# $1: name (eg [hawkular-metrics|hawkular-cassandra])
# $2: hostnames to use
# $3: environment variable containing base64 pem 
function setupCertificate {
  name=$1
  hostnames=$2
  envVar=$3

  # Use existing or generate new Hawkular Metrics certificates
  if [ -n "${!envVar}" ]; then
      echo "${envVar}" | base64 -d > $dir/${name}.pem
  elif [ -s /secret/${name}.pem ]; then
      # use files from secret if present
      cp /secret/${name}.pem $dir
      cp /secret/${name}-ca.cert $dir
  else #fallback to creating one
      openshift admin ca create-server-cert  \
        --key=$dir/${name}.key \
        --cert=$dir/${name}.crt \
        --hostnames=${hostnames} \
        --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
      cat $dir/${name}.key $dir/${name}.crt > $dir/${name}.pem
      cp $dir/ca.crt $dir/${name}-ca.cert
  fi

}

rm -rf $dir && mkdir -p $dir && chmod 700 $dir || :

openshift admin ca create-signer-cert  \
  --key="${dir}/ca.key" \
  --cert="${dir}/ca.crt" \
  --serial="${dir}/ca.serial.txt" \
  --name="metrics-signer@$(date +%s)"

# set up configuration for client
if [ -n "${WRITE_KUBECONFIG}" ]; then
    # craft a kubeconfig, usually at $KUBECONFIG location
    oc config set-cluster master \
      --api-version='v1' \
      --certificate-authority="${master_ca}" \
      --server="${master_url}"
    oc config set-credentials account \
      --token="$(cat ${token_file})"
    oc config set-context current \
      --cluster=master \
      --user=account \
      --namespace="${PROJECT}"
    oc config use-context current
fi

if [ "$redeploy" = true  ]; then
  echo "Deleting any previous deployment"
  oc delete all --selector="metrics-infra"

  echo "Deleting any exisiting service account"
  oc delete sa --selector="metrics-infra"

  echo "Deleting the templates"
  oc delete templates --selector="metrics-infra"

  echo "Deleting the secrets"
  oc delete secrets --selector="metrics-infra"

  echo "Deleting any pvc"
  oc delete pvc --selector="metrics-infra"
fi

if [ -z "${HEAPSTER_STANDALONE}" ]; then 
  . ./run-hawkular.sh
fi
. ./run-heapster.sh

echo 'Success!'
