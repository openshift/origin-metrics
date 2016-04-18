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

function deploy_heapster() {
  set -ex
  
  # Use existing or generate new Heapster certificates
  if [ -n "${HEAPSTER_CERT:-}" ]; then
    echo "${HEAPSTER_CERT:-}" | base64 -d > $dir/heapster.cert
    echo "${HEAPSTER_KEY:-}" | base64 -d > $dir/heapster.key
  elif  [ -s ${secret_dir}/heapster.cert ]; then
      # use files from secret if present
      cp ${secret_dir}/heapster.cert $dir
      cp ${secret_dir}/heapster.key $dir
  else #fallback to creating one
      openshift admin ca create-server-cert  \
        --key=$dir/heapster.key \
        --cert=$dir/heapster.cert \
        --hostnames=heapster \
        --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
  fi
  
  # Get the Heapster allowed users
  if [ -n "${HEAPSTER_ALLOWED_USERS:-}" ]; then
    echo "${HEAPSTER_ALLOWED_USERS:-}" | base64 -d > $dir/heapster_allowed_users
  elif [ -s ${secret_dir}/heapster-allowed-users ]; then
    cp ${secret_dir}/heapster-allowed-users $dir/heapster_allowed_users
  else #by default accept access from the api proxy
    echo "system:master-proxy" > $dir/heapster_allowed_users
  fi
  
  # Get the Heapster Client CA
  if [ -n "${HEAPSTER_CLIENT_CA:-}" ]; then
    echo "${HEAPSTER_CLIENT_CA:-}" | base64 -d > $dir/heapster_client_ca.cert
  elif [ -s ${secret_dir}/heapster-client-ca.cert ]; then
    cp ${secret_dir}/heapster-client-ca.cert $dir/heapster_client_ca.cert
  else #use the service account ca by default
    cp ${master_ca} $dir/heapster_client_ca.cert
  fi
  
  echo
  echo "Creating the Heapster Secrets configuration json file"
  cat > $dir/heapster-secrets.json <<EOF
      {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata":
        { "name": "heapster-secrets",
          "labels": {
            "metrics-infra": "heapster"
          }
        },
        "data":
        {
          "heapster.cert": "$(base64 -w 0 $dir/heapster.cert)",
          "heapster.key": "$(base64 -w 0 $dir/heapster.key)",
          "heapster.client-ca": "$(base64 -w 0 $dir/heapster_client_ca.cert)",
          "heapster.allowed-users":"$(base64 -w 0 $dir/heapster_allowed_users)"
        }
      }
EOF
  
  echo "Installing the Heapster Component."
     
  echo "Creating the Heapster secret"
  oc create -f $dir/heapster-secrets.json
  
  echo "Creating the Heapster template"
  if [ -n "${HEAPSTER_STANDALONE:-}" ]; then
    oc create -f templates/heapster-standalone.yaml
  else
    oc create -f templates/heapster.yaml
  fi
  
  echo "Deploying the Heapster component"
  if [ -n "${HEAPSTER_STANDALONE:-}" ]; then
    oc process heapster-standalone -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,MASTER_URL=$master_url,METRIC_RESOLUTION=$metric_resolution" | oc create -f -
  else
    oc process hawkular-heapster -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,MASTER_URL=$master_url,NODE_ID=$heapster_node_id,METRIC_RESOLUTION=$metric_resolution" | oc create -f -
  fi
}
