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
  # Get the Heapster allowed users
  if [ -n "${HEAPSTER_ALLOWED_USERS:-}" ]; then
    echo "${HEAPSTER_ALLOWED_USERS:-}" | base64 -d > $dir/heapster_allowed_users
  elif [ -s ${secret_dir}/heapster-allowed-users ]; then
    cp ${secret_dir}/heapster-allowed-users $dir/heapster_allowed_users
  else #by default accept access from the api proxy
    echo "system:master-proxy" > $dir/heapster_allowed_users
  fi

  echo
  echo "Creating the Heapster Secrets configuration json file"
  heapster_tls_truststore=$(base64 -w 0 ${dir}/hawkular-metrics-ca.cert)
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
          "heapster.allowed-users":"$(base64 -w 0 $dir/heapster_allowed_users)",
          "heapster.tls.truststore":"${heapster_tls_truststore}"
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
    echo "Processing sinks for Heapster"
    if [ -n "${ADDITIONAL_HEAPSTER_SINKS:-}"  ]; then
        cp templates/heapster.yaml /tmp/heapster.yaml
        for SINK in $(echo -e "$ADDITIONAL_HEAPSTER_SINKS");do
          sed -i "/--source/a \
              \ \ \ \ \ \ \ \ \ \ - \"--sink=${SINK}\" /tmp/heapster.yaml"
        done
        oc create -f /tmp/heapster.yaml
        rm -f /tmp/heapster.yaml
    else
        oc create -f templates/heapster.yaml
    fi
  fi
  
  echo "Deploying the Heapster component"
  if [ -n "${HEAPSTER_STANDALONE:-}" ]; then
    oc process heapster-standalone -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v MASTER_URL=$master_url -v METRIC_RESOLUTION=$metric_resolution -v STARTUP_TIMEOUT=$startup_timeout | oc create -f -
  else
    oc process hawkular-heapster -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v MASTER_URL=$master_url -v NODE_ID=$heapster_node_id -v METRIC_RESOLUTION=$metric_resolution -v STARTUP_TIMEOUT=$startup_timeout | oc create -f -
  fi
}
