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

rm -rf $dir && mkdir -p $dir && chmod 700 $dir || :

# cp/generate CA
if [ -s /secret/ca.key ]; then
  cp /secret/ca.key
  cp /secret/ca.crt
  echo "01" > $dir/ca.serial.txt
else
    openshift admin ca create-signer-cert  \
      --key="${dir}/ca.key" \
      --cert="${dir}/ca.crt" \
      --serial="${dir}/ca.serial.txt" \
      --name="metrics-signer@$(date +%s)"
fi

# Use existing or generate new Hawkular Metrics certificates
if [ -n "${HAWKUKAR_METRICS_PEM}" ]; then
    echo "${HAWKULAR_METRICS_PEM}" | base64 -d > $dir/hawkular-metrics.pem
elif [ -s /secret/hawkular-metrics.pem ]; then
    # use files from secret if present
    cp /secret/hawkular-metrics.pem $dir
    cp /secret/hawkular-metrics-ca.cert $dir
else #fallback to creating one
    openshift admin ca create-server-cert  \
      --key=$dir/hawkular-metrics.key \
      --cert=$dir/hawkular-metrics.crt \
      --hostnames=hawkular-metrics,${hawkular_metrics_hostname} \
      --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
    cat $dir/hawkular-metrics.key $dir/hawkular-metrics.crt > $dir/hawkular-metrics.pem
    cp $dir/ca.crt $dir/hawkular-metrics-ca.cert  
fi

# Use existing or generate new Hawkular Cassandra certificates
if [ -n "${HAWKUKAR_CASSANDRA_PEM}" ]; then
    echo "${HAWKULAR_CASSANDRA_PEM}" | base64 -d > $dir/hawkular-cassandra.pem
elif [ -s /secret/hawkular-cassandra.pem ]; then
    # use files from secret if present
    cp /secret/hawkular-cassandra.pem $dir
    cp /secret/hawkular-cassandra-ca.cert $dir
else #fallback to creating one
    openshift admin ca create-server-cert  \
      --key=$dir/hawkular-cassandra.key \
      --cert=$dir/hawkular-cassandra.crt \
      --hostnames=hawkular-cassandra \
      --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
    cat $dir/hawkular-cassandra.key $dir/hawkular-cassandra.crt > $dir/hawkular-cassandra.pem
    cp $dir/ca.crt $dir/hawkular-cassandra-ca.cert
fi

# Use existing or generate new Heapster certificates
if [ -n "${HEAPSTER_CERT}" ]; then
  echo "${HEAPSTER_CERT}" | base64 -d > $dir/heapster.cert
  echo "${HEAPSTER_KEY}" | base64 -d > $dir/heapster.key
elif  [ -s /secret/heapster.cert ]; then
    # use files from secret if present
    cp /secret/heapster.cert $dir
    cp /secret/heapster.key $dir
else #fallback to creating one
    openshift admin ca create-server-cert  \
      --key=$dir/heapster.key \
      --cert=$dir/heapster.cert \
      --hostnames=heapster \
      --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
fi

# Get the Heapster allowed users
if [ -n "${HEAPSTER_ALLOWED_USERS}" ]; then
  echo "${HEAPSTER_ALLOWED_USERS}" | base64 -d > $dir/heapster_allowed_users
elif [ -s /secret/heapster_allowed_users ]; then
  cp /secret/heapster_allowed_users $dir
else #create an empty allowed users
  echo "" > $dir/heapster_allowed_users
fi

# Get the Heapster Client CA
if [ -n "${HEAPSTER_CLIENT_CA}" ]; then
  echo "${HEAPSTER_CLIENT_CA}" | base64 -d > $dir/heapster_client_ca.cert
elif [ -s /secret/heapster_client_ca.cert ]; then
  cp /secret/heapster_client_ca.cert $dir
else #use the ca we already have for signing our own certificates
  cp $dir/ca.crt $dir/heapster_client_ca.cert
fi
  

echo 03 > $dir/ca.serial.txt  # otherwise openssl chokes on the file

# Convert the *.pem files into java keystores
echo "Generating randomized passwords for the Hawkular Metrics and Cassandra keystores and truststores"
hawkular_metrics_keystore_password=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`
hawkular_metrics_truststore_password=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`
hawkular_cassandra_keystore_password=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`
hawkular_cassandra_truststore_password=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`

echo "Creating the Hawkular Metrics keystore from the PEM file"
openssl pkcs12 -export -in $dir/hawkular-metrics.pem -out $dir/hawkular-metrics.pkcs12 -name $hawkular_metrics_alias -noiter -nomaciter -password pass:$hawkular_metrics_keystore_password
keytool -v -importkeystore -srckeystore $dir/hawkular-metrics.pkcs12 -srcstoretype PKCS12 -destkeystore $dir/hawkular-metrics.keystore -deststoretype JKS -deststorepass $hawkular_metrics_keystore_password -srcstorepass $hawkular_metrics_keystore_password

echo "Creating the Hawkular Cassandra keystore from the PEM file"
openssl pkcs12 -export -in $dir/hawkular-cassandra.pem -out $dir/hawkular-cassandra.pkcs12 -name $hawkular_cassandra_alias -noiter -nomaciter -password pass:$hawkular_cassandra_keystore_password
keytool -v -importkeystore -srckeystore $dir/hawkular-cassandra.pkcs12 -srcstoretype PKCS12 -destkeystore $dir/hawkular-cassandra.keystore -deststoretype JKS -deststorepass $hawkular_cassandra_keystore_password -srcstorepass $hawkular_cassandra_keystore_password

echo "Creating the Hawkular Metrics Certificate"
keytool -noprompt -export -alias $hawkular_metrics_alias -file $dir/hawkular-metrics.cert -keystore $dir/hawkular-metrics.keystore -storepass $hawkular_metrics_keystore_password

echo "Creating the Hawkular Cassandra Certificate"
keytool -noprompt -export -alias $hawkular_cassandra_alias -file $dir/hawkular-cassandra.cert -keystore $dir/hawkular-cassandra.keystore -storepass $hawkular_cassandra_keystore_password

echo "Importing the Hawkular Metrics Certificate into the Cassandra Truststore"
keytool -noprompt -import -v -trustcacerts -alias $hawkular_metrics_alias -file $dir/hawkular-metrics.cert -keystore $dir/hawkular-cassandra.truststore -trustcacerts -storepass $hawkular_cassandra_truststore_password

echo "Importing the Hawkular Cassandra Certificate into the Hawkular Metrics Truststore"
keytool -noprompt -import -v -trustcacerts -alias $hawkular_cassandra_alias -file $dir/hawkular-cassandra.cert -keystore $dir/hawkular-metrics.truststore -trustcacerts -storepass $hawkular_metrics_truststore_password

echo "Importing the Hawkular Cassandra Certificate into the Cassandra Truststore"
keytool -noprompt -import -v -trustcacerts -alias $hawkular_cassandra_alias -file $dir/hawkular-cassandra.cert -keystore $dir/hawkular-cassandra.truststore -trustcacerts -storepass $hawkular_cassandra_truststore_password

echo "Importing the CA Certificate into the Cassandra Truststore"
keytool -noprompt -import -v -trustcacerts -alias ca -file ${dir}/ca.crt -keystore $dir/hawkular-cassandra.truststore -trustcacerts -storepass $hawkular_cassandra_truststore_password
keytool -noprompt -import -v -trustcacerts -alias metricca -file ${dir}/hawkular-metrics-ca.cert -keystore $dir/hawkular-cassandra.truststore -trustcacerts -storepass $hawkular_cassandra_truststore_password
keytool -noprompt -import -v -trustcacerts -alias cassandraca -file ${dir}/hawkular-cassandra-ca.cert -keystore $dir/hawkular-cassandra.truststore -trustcacerts -storepass $hawkular_cassandra_truststore_password

echo "Importing the CA Certificate into the Hawkular Metrics Truststore"
keytool -noprompt -import -v -trustcacerts -alias ca -file ${dir}/ca.crt -keystore $dir/hawkular-metrics.truststore -trustcacerts -storepass $hawkular_metrics_truststore_password
keytool -noprompt -import -v -trustcacerts -alias metricsca -file ${dir}/hawkular-metrics-ca.cert -keystore $dir/hawkular-metrics.truststore -trustcacerts -storepass $hawkular_metrics_truststore_password
keytool -noprompt -import -v -trustcacerts -alias cassandraca -file ${dir}/hawkular-cassandra-ca.cert -keystore $dir/hawkular-metrics.truststore -trustcacerts -storepass $hawkular_metrics_truststore_password

hawkular_metrics_password=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`
htpasswd -cb $dir/hawkular-metrics.htpasswd hawkular $hawkular_metrics_password 

echo
echo "Creating the Hawkular Metrics Secrets configuration json file"
cat > $dir/hawkular-metrics-secrets.json <<EOF
    {
      "apiVersion": "v1",
      "kind": "Secret",
      "metadata":
      { "name": "hawkular-metrics-secrets",
        "labels": {
          "metrics-infra": "hawkular-metrics"
        }
      },
      "data":
      {
        "hawkular-metrics.keystore": "$(base64 -w 0 $dir/hawkular-metrics.keystore)",
        "hawkular-metrics.keystore.password": "$(base64 <<< `echo $hawkular_metrics_keystore_password`)",
        "hawkular-metrics.truststore": "$(base64 -w 0 $dir/hawkular-metrics.truststore)",
        "hawkular-metrics.truststore.password": "$(base64 <<< `echo $hawkular_metrics_truststore_password`)",
        "hawkular-metrics.keystore.alias": "$(base64 <<< `echo $hawkular_metrics_alias`)",
        "hawkular-metrics.htpasswd.file": "$(base64 -w 0 $dir/hawkular-metrics.htpasswd)"
      }
    }
EOF

echo
echo "Creating the Hawkular Metrics Certificate Secrets configuration json file"
cat > $dir/hawkular-metrics-certificate.json <<EOF
    {
      "apiVersion": "v1",
      "kind": "Secret",
      "metadata":
      { "name": "hawkular-metrics-certificate",
        "labels": {
          "metrics-infra": "hawkular-metrics"
        }
      },
      "data":
      {
        "hawkular-metrics.certificate": "$(base64 -w 0 $dir/hawkular-metrics.cert)",
        "hawkular-metrics-ca.certificate": "$(base64 -w 0 $dir/hawkular-metrics-ca.cert)"
      }
    }
EOF

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

echo
echo "Creating the Cassandra Secrets configuration file"
cat > $dir/cassandra-secrets.json <<EOF
    {
      "apiVersion": "v1",
      "kind": "Secret",
      "metadata":
      { "name": "hawkular-cassandra-secrets",
        "labels": {
          "metrics-infra": "hawkular-cassandra"
        }
      },
      "data":
      {
        "cassandra.keystore": "$(base64 -w 0 $dir/hawkular-cassandra.keystore)",
        "cassandra.keystore.password": "$(base64 <<< `echo $hawkular_cassandra_keystore_password`)",
        "cassandra.keystore.alias": "$(base64 <<< `echo $hawkular_cassandra_alias`)",
        "cassandra.truststore": "$(base64 -w 0 $dir/hawkular-cassandra.truststore)",
        "cassandra.truststore.password": "$(base64 <<< `echo $hawkular_cassandra_truststore_password`)",
        "cassandra.pem": "$(base64 -w 0 $dir/hawkular-cassandra.pem)"
      }
    }
EOF

echo
echo "Creating the Cassandra Certificate Secrets configuration json file"
cat > $dir/cassandra-certificate.json <<EOF
    {
      "apiVersion": "v1",
      "kind": "Secret",
      "metadata":
      { "name": "hawkular-cassandra-certificate",
        "labels": {
          "metrics-infra": "hawkular-cassandra"
        }
      },
      "data":
      {
        "cassandra.certificate": "$(base64 -w 0 $dir/hawkular-cassandra.cert)",
        "cassandra-ca.certificate": "$(base64 -w 0 $dir/hawkular-cassandra-ca.cert)"
      }
    }
EOF

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

echo "Creating secrets"
oc create -f $dir/hawkular-metrics-secrets.json
oc create -f $dir/hawkular-metrics-certificate.json
oc create -f $dir/hawkular-metrics-account.json
oc create -f $dir/cassandra-secrets.json
oc create -f $dir/cassandra-certificate.json
oc create -f $dir/heapster-secrets.json

echo "Creating templates"
oc create -f templates/hawkular-metrics.yaml
oc create -f templates/hawkular-cassandra.yaml
oc create -f templates/hawkular-cassandra-node-pv.yaml
oc create -f templates/hawkular-cassandra-node-emptydir.yaml
oc create -f templates/heapster.yaml
oc create -f templates/support.yaml

echo "Deploying components"
oc process hawkular-metrics -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,METRIC_DURATION=$metric_duration,MASTER_URL=$master_url" | oc create -f -
oc process hawkular-cassandra-services | oc create -f -
oc process hawkular-heapster -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,MASTER_URL=$master_url" | oc create -f -
oc process hawkular-support -v "HAWKULAR_METRICS_HOSTNAME=$hawkular_metrics_hostname" | oc create -f -

if [ "${use_persistent_storage}" = true ]; then
  echo "Setting up Cassandra with Persistent Storage"
  # Deploy the main 'master' Cassandra node
  oc process hawkular-cassandra-node-pv -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,NODE=1,PV_SIZE=$cassandra_pv_size,MASTER=true" | oc create -f -
  # Deploy any subsequent Cassandra nodes
  for i in $(seq 2 $cassandra_nodes);
  do
    oc process hawkular-cassandra-node-pv -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,PV_SIZE=$cassandra_pv_size,NODE=$i" | oc create -f -
  done
else 
  echo "Setting up Cassandra with Non Persistent Storage"
  oc process hawkular-cassandra-node-emptydir -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,NODE=1,MASTER=true" | oc create -f -  
fi

echo 'Success!'
