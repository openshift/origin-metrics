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

function deploy_hawkular() {
  hawkular_metrics_password=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`
  htpasswd -cb $dir/hawkular-metrics.htpasswd hawkular $hawkular_metrics_password 

  echo
  echo "Creating the Hawkular Metrics User Account Secrets"
  cat > $dir/hawkular-metrics-account.json <<EOF
      {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata":
        { "name": "hawkular-metrics-account",
          "labels": {
            "metrics-infra": "hawkular-metrics"
          }
        },
        "data":
        {
          "hawkular-metrics.username": "$(base64 <<< `echo hawkular`)",
          "hawkular-metrics.password": "$(base64 <<< `echo $hawkular_metrics_password`)"
        }
      }
EOF

  echo "Creating the Hawkular Metrics User Account Secret"
  oc create -f $dir/hawkular-metrics-account.json

  echo "Creating Hawkular Metrics & Cassandra Templates"
  oc create -f templates/hawkular-metrics.yaml
  oc create -f templates/hawkular-cassandra.yaml
  oc create -f templates/hawkular-cassandra-node-pv.yaml
  oc create -f templates/hawkular-cassandra-node-dynamic-pv.yaml
  oc create -f templates/hawkular-cassandra-node-emptydir.yaml
  oc create -f templates/support.yaml

  echo "Deploying Hawkular Metrics & Cassandra Components"
  oc process hawkular-metrics -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v METRIC_DURATION=$metric_duration -v MASTER_URL=$master_url -v USER_WRITE_ACCESS=$user_write_access -v STARTUP_TIMEOUT=$startup_timeout | oc create -f -
  oc process hawkular-cassandra-services | oc create -f -
  oc process hawkular-support | oc create -f -

  # this may return an error code if the route already exists, this is to be expect with a refresh and is why we have the || true here
  ## once BZ 1401081 is done, the Route specified on `hawkular-metrics.yaml` should work and this command here should be removed.
  oc create route hawkular-metrics || true

  if [ "${use_persistent_storage}" = true ]; then
    if [ "${dynamically_provision_storage}" = true ]; then
      echo "Setting up Cassandra with Dynamically Provisioned Storage"
      # Deploy the main 'master' Cassandra node
      # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
      oc process hawkular-cassandra-node-dynamic-pv -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v NODE=1 -v PV_SIZE=$cassandra_pv_size -v MASTER=true | oc create -f - || true
      # Deploy any subsequent Cassandra nodes
      for i in $(seq 2 $cassandra_nodes);
      do
        # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
        oc process hawkular-cassandra-node-dynamic-pv -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v PV_SIZE=$cassandra_pv_size -v NODE=$i | oc create -f - || true
      done
    else
      echo "Setting up Cassandra with Persistent Storage"
      # Deploy the main 'master' Cassandra node
      # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
      oc process hawkular-cassandra-node-pv -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v NODE=1 -v PV_SIZE=$cassandra_pv_size -v MASTER=true | oc create -f - || true
      # Deploy any subsequent Cassandra nodes
      for i in $(seq 2 $cassandra_nodes);
      do
        # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
        oc process hawkular-cassandra-node-pv -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v PV_SIZE=$cassandra_pv_size -v NODE=$i | oc create -f - || true
      done
    fi
  else 
    echo "Setting up Cassandra with Non Persistent Storage"
    oc process hawkular-cassandra-node-emptydir -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v NODE=1 -v MASTER=true | oc create -f -  
    for i in $(seq 2 $cassandra_nodes);
    do
      oc process hawkular-cassandra-node-emptydir -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v NODE=$i | oc create -f -
    done
  fi
}
