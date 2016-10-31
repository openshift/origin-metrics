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
  
  setup_certificate "hawkular-metrics" "hawkular-metrics,${hawkular_metrics_hostname}" "${HAWKULAR_METRICS_PEM:-}"
  setup_certificate "hawkular-cassandra" "hawkular-cassandra" "${HAWKULAR_CASSANDRA_PEM:-}"
 
  echo "Generating randomized passwords for Hawkular Metrics JGroups"
  hawkular_metrics_jgroups_password=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`
  
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
          "hawkular-metrics.htpasswd.file": "$(base64 -w 0 $dir/hawkular-metrics.htpasswd)",
          "hawkular-metrics.jgroups.password": "$(base64 <<< `echo $hawkular_metrics_jgroups_password`)"
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
  
  echo "Creating Hawkular Metrics & Cassandra Secrets"
  oc create -f $dir/hawkular-metrics-secrets.json
  oc create -f $dir/hawkular-metrics-certificate.json
  oc create -f $dir/hawkular-metrics-account.json
  oc create -f $dir/cassandra-secrets.json
  oc create -f $dir/cassandra-certificate.json
  
  echo "Creating Hawkular Metrics & Cassandra Templates"
  oc create -f templates/hawkular-metrics.yaml
  oc create -f templates/hawkular-metrics-service.yaml
  oc create -f templates/hawkular-cassandra.yaml
  oc create -f templates/hawkular-cassandra-node-pv.yaml
  oc create -f templates/hawkular-cassandra-node-dynamic-pv.yaml
  oc create -f templates/hawkular-cassandra-node-emptydir.yaml
  oc create -f templates/support.yaml

  echo "Deploying Hawkular Metrics & Cassandra Components"
  oc process hawkular-metrics -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,METRIC_DURATION=$metric_duration,MASTER_URL=$master_url,USER_WRITE_ACCESS=$user_write_access,HAWKULAR_METRICS_MASTER=true,HAWKULAR_METRICS_REPLICATION_CONTROLLER_NAME=hawkular-master" | oc create -f -
  oc process hawkular-metrics -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,METRIC_DURATION=$metric_duration,MASTER_URL=$master_url,USER_WRITE_ACCESS=$user_write_access,REPLICAS=0" | oc create -f -
  oc process hawkular-metrics-service | oc create -f -
  oc process hawkular-cassandra-services | oc create -f -
  oc process hawkular-support | oc create -f -

  echo "Creating the Hawkular Metrics Route"
  # We need to create the route after the service has been created so that its labels get applied to the route itself
  route_params="--hostname=$hawkular_metrics_hostname --service=hawkular-metrics --dest-ca-cert=$dir/hawkular-metrics-ca.cert"
  if [ -s ${secret_dir}/hawkular-metrics.pem ]; then
    `openssl rsa -in  ${secret_dir}/hawkular-metrics.pem > $dir/custom-certificate.key`
    # We want to get all the certificates in the pem which is a bit tricky. The more simple 'openssl x509 ...' command will not work since it only returns the first certificate
    `openssl crl2pkcs7 -nocrl -certfile ${secret_dir}/hawkular-metrics.pem | openssl pkcs7 -print_certs | grep -v "^subject=*\|^issuer=*\|^$" > $dir/custom-certificate.crt`
     route_params="${route_params} --cert=$dir/custom-certificate.crt --key=$dir/custom-certificate.key"
     if [ -s ${secret_dir}/hawkular-metrics-ca.cert ]; then
       route_params="${route_params} --ca-cert=${secret_dir}/hawkular-metrics-ca.cert"
     fi
  fi
  # this may return an error code if the route already exists, this is to be expect with a refresh and is why we have the || true here
  oc create route reencrypt hawkular-metrics ${route_params} || true

  # if we are dealing with a refresh, then we need to update the router's CACertificate for the Hawkular Metric's internal certificate
  if [ "$mode" = "refresh" ]; then
   type=$(oc get route hawkular-metrics --template='{{.spec.tls.termination}}') || true
   if [ "$type" = "reencrypt" ]; then
      oc patch route hawkular-metrics -p "$(python <<-EOF
				import json
				ca = open("$dir/hawkular-metrics-ca.cert").read()
				print json.dumps({"spec": {"tls": {"destinationCACertificate": ca}}})
				EOF
      )"
   fi
  fi
 
  if [ "${use_persistent_storage}" = true ]; then
    if [ "${dynamically_provision_storage}" = true ]; then
      echo "Setting up Cassandra with Dynamically Provisioned Storage"
      # Deploy the main 'master' Cassandra node
      # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
      oc process hawkular-cassandra-node-dynamic-pv -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,NODE=1,PV_SIZE=$cassandra_pv_size,MASTER=true" | oc create -f - || true
      # Deploy any subsequent Cassandra nodes
      for i in $(seq 2 $cassandra_nodes);
      do
        # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
        oc process hawkular-cassandra-node-dynamic-pv -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,PV_SIZE=$cassandra_pv_size,NODE=$i" | oc create -f - || true
      done
    else
      echo "Setting up Cassandra with Persistent Storage"
      # Deploy the main 'master' Cassandra node
      # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
      oc process hawkular-cassandra-node-pv -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,NODE=1,PV_SIZE=$cassandra_pv_size,MASTER=true" | oc create -f - || true
      # Deploy any subsequent Cassandra nodes
      for i in $(seq 2 $cassandra_nodes);
      do
        # Note that this may return an error code if the pvc already exists, this is to be expected and why we have the || true here
        oc process hawkular-cassandra-node-pv -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,PV_SIZE=$cassandra_pv_size,NODE=$i" | oc create -f - || true
      done
    fi
  else 
    echo "Setting up Cassandra with Non Persistent Storage"
    oc process hawkular-cassandra-node-emptydir -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,NODE=1,MASTER=true" | oc create -f -  
    for i in $(seq 2 $cassandra_nodes);
    do
      oc process hawkular-cassandra-node-emptydir -v "IMAGE_PREFIX=$image_prefix,IMAGE_VERSION=$image_version,NODE=$i" | oc create -f -
    done
  fi
}
