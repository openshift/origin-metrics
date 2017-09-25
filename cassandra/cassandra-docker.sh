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

for args in "$@"
do
  case $args in
    --seeds=*)
      SEEDS="${args#*=}"
    ;;
    --cluster_name=*)
      CLUSTER_NAME="${args#*=}"
    ;;
    --data_volume=*)
      DATA_VOLUME="${args#*=}"
    ;;
    --commitlog_volume=*)
      COMMITLOG_VOLUME="${args#*=}"
    ;;
    --seed_provider_classname=*)
      SEED_PROVIDER_CLASSNAME="${args#*=}"
    ;;
    --internode_encryption=*)
      INTERNODE_ENCRYPTION="${args#*=}"
    ;;
    --require_node_auth=*)
      REQUIRE_NODE_AUTH="${args#*=}"
    ;;
    --enable_client_encryption=*)
      ENABLE_CLIENT_ENCRYPTION="${args#*=}"
    ;;
    --require_client_auth=*)
      REQUIRE_CLIENT_AUTH="${args#*=}"
    ;;
    --truststore_nodes_authorities=*)
      TRUSTSTORE_NODES_AUTHORITIES="${args#*=}"
    ;;
    --truststore_client_authorities=*)
      TRUSTSTORE_CLIENT_AUTHORITIES="${args#*=}"
    ;;
    --tls_certificate=*)
      SERVICE_CERT="${args#*=}"
    ;;
    --tls_certificate_key=*)
      SERVICE_CERT_KEY="${args#*=}"
    ;;
    --help)
      HELP=true
    ;;
  esac
done

if [ -n "$HELP" ]; then
  echo
  echo Starts up a Cassandra Docker image
  echo
  echo Usage: [OPTIONS]...
  echo
  echo Options:
  echo "  --seeds=SEEDS"
  echo "        comma separated list of hosts to use as a seed list"
  echo "        default: \$HOSTNAME"
  echo
  echo "  --cluster_name=NAME"
  echo "        the name to use for the cluster"
  echo "        default: test_cluster"
  echo
  echo "  --data_volume=VOLUME_PATH"
  echo "        the path to where the data volume should be located"
  echo "        default: \$CASSANDRA_HOME/data"
  echo
  echo "  --seed_provider_classname"
  echo "        the classname to use as the seed provider"
  echo "        default: org.apache.cassandra.locator.SimpleSeedProvider"
  echo
  echo "  --internode_encryption=[all|none|dc|rack]"
  echo "        what type of internode encryption should be used"
  echo "        default: none"
  echo
  echo "  --enable_client_encryption=[true|false]"
  echo "        if client encryption should be enabled"
  echo "        default: false"
  echo
  echo "  --require_node_auth=[true|false]"
  echo "        if certificate based authentication should be required between nodes"
  echo "        default: false"
  echo
  echo "  --require_client_auth=[true|false]"
  echo "        if certificate based authentication should be required for client"
  echo "        default: false"
  echo
  echo "  --truststore_nodes_authorities=TRUSTSTORE_NODES_AUTHORITIES"
  echo "        a file containing all certificate authorities to trust as peers"
  echo
  echo "  --truststore_client_authorities=TRUSTSTORE_CLIENT_AUTHORITIES"
  echo "        a file containing all certificate authorities to trust as clients"
  echo
  echo "  --tls_certificate=SERVICE_CERT"
  echo "        the path to the certificate file to be used as the service certificate"
  echo
  echo "  --tls_certificate_key=SERVICE_CERT_KEY"
  echo "        the path to the certificate private key part to the SERVICE_CERT"
  echo
  exit 0
fi

CASSANDRA_HOME=${CASSANDRA_HOME:-"/opt/apache-cassandra"}
CASSANDRA_CONF=${CASSANDRA_CONF:-"${CASSANDRA_HOME}/conf"}
CASSANDRA_CONF_FILE=${CASSANDRA_CONF_FILE:-"${CASSANDRA_CONF}/cassandra.yaml"}
KEYSTORE_DIR=${KEYSTORE_DIR:-"${CASSANDRA_CONF}"}

SERVICE_ALIAS=${SERVICE_ALIAS:-"cassandra"}
SERVICE_CERT=${SERVICE_CERT:-"/hawkular-cassandra-certs/tls.crt"}
SERVICE_CERT_KEY=${SERVICE_CERT_KEY:-"/hawkular-cassandra-certs/tls.key"}

if [ -z "${TRUSTSTORE_NODES_AUTHORITIES}" ]; then
 echo "The --truststore_node_authorities value is not specified. Aborting"
 exit 1
fi

if [ -z "${TRUSTSTORE_CLIENT_AUTHORITIES}" ]; then
 echo "The --truststore_client_authorities value is not specified. Aborting"
 exit 1
fi


PKCS12_FILE=${PKCS12_FILE:-"${KEYSTORE_DIR}/cassandra.pkcs12"}
KEYTOOL_COMMAND="/usr/lib/jvm/java-1.8.0/jre/bin/keytool"

if [ -z "${MAX_HEAP_SIZE}" ]; then
  if [ -z "${MEMORY_LIMIT}" ]; then
    MEMORY_LIMIT=`cat /sys/fs/cgroup/memory/memory.limit_in_bytes`
    echo "The MEMORY_LIMIT envar was not set. Reading value from /sys/fs/cgroup/memory/memory.limit_in_bytes."
  fi
  echo "The MAX_HEAP_SIZE envar is not set. Basing the MAX_HEAP_SIZE on the available memory limit for the pod (${MEMORY_LIMIT})."
  BYTES_MEGABYTE=1048576
  BYTES_GIGABYTE=1073741824
  # Based on the Cassandra memory limit recommendations. See http://docs.datastax.com/en/cassandra/2.2/cassandra/operations/opsTuneJVM.html
  if (( ${MEMORY_LIMIT} <= (2 * ${BYTES_GIGABYTE}) )); then
    # If less than 2GB, set the heap to be 1/2 of available ram
    echo "The memory limit is less than 2GB. Using 1/2 of available memory for the max_heap_size."
    export MAX_HEAP_SIZE="$((${MEMORY_LIMIT} / ${BYTES_MEGABYTE} / 2 ))M"
  elif (( ${MEMORY_LIMIT} <= (4 * ${BYTES_GIGABYTE}) )); then
    echo "The memory limit is between 2 and 4GB. Setting max_heap_size to 1GB."
    # If between 2 and 4GB, set the heap to 1GB
    export MAX_HEAP_SIZE="1024M"
  elif (( ${MEMORY_LIMIT} <= (32 * ${BYTES_GIGABYTE}) )); then
    echo "The memory limit is between 4 and 32GB. Using 1/4 of the available memory for the max_heap_size."
    # If between 4 and 32GB, use 1/4 of the available ram
    export MAX_HEAP_SIZE="$(( ${MEMORY_LIMIT} / ${BYTES_MEGABYTE} / 4 ))M"
  else
    echo "The memory limit is above 32GB. Using 8GB for the max_heap_size"
    # If above 32GB, set the heap size to 8GB
    export MAX_HEAP_SIZE="8192M"
  fi
  echo "The MAX_HEAP_SIZE has been set to ${MAX_HEAP_SIZE}"
else
  echo "The MAX_HEAP_SIZE envar is set to ${MAX_HEAP_SIZE}. Using this value"
fi

if [ -z "${HEAP_NEWSIZE}" ]; then
  export HEAP_NEWSIZE="$(( ${MAX_HEAP_SIZE::-1} / 3 ))M"
  echo "The HEAP_NEWSIZE envar is not set. Setting the HEAP_NEWSIZE to one third the MAX_HEAP_SIZE: ${HEAP_NEWSIZE}"
else
  echo "The HEAP_NEWSIZE envar is set to ${HEAP_NEWSIZE}. Using this value"
fi

#Update the cassandra-env.sh with these new values
cp /opt/apache-cassandra/conf/cassandra-env.sh.template /opt/apache-cassandra/conf/cassandra-env.sh
sed -i 's/${MAX_HEAP_SIZE}/'$MAX_HEAP_SIZE'/g' /opt/apache-cassandra/conf/cassandra-env.sh
sed -i 's/${HEAP_NEWSIZE}/'$HEAP_NEWSIZE'/g' /opt/apache-cassandra/conf/cassandra-env.sh

cp /opt/apache-cassandra/conf/cassandra.yaml.template /opt/apache-cassandra/conf/cassandra.yaml

if [ "x$DISABLE_PROMETHEUS_ENDPOINT" != "xtrue" ]; then
  export JVM_OPTS="$JVM_OPTS -javaagent:/opt/apache-cassandra/lib/jmx_prometheus_javaagent.jar=localhost:7575:/opt/hawkular/prometheus_agent/prometheus.yaml"
fi

# set the hostname in the cassandra configuration file
sed -i 's/${HOSTNAME}/'$HOSTNAME'/g' /opt/apache-cassandra/conf/cassandra.yaml

# if the seed list is not set, try and get it from the gather-seeds script
if [ -z "$SEEDS" ]; then
  source /opt/apache-cassandra/bin/gather-seeds.sh
fi

echo "Setting seeds to be ${SEEDS}"
sed -i 's/${SEEDS}/'$SEEDS'/g' /opt/apache-cassandra/conf/cassandra.yaml

# set the cluster name if set, default to "test_cluster" if not set
if [ -n "$CLUSTER_NAME" ]; then
    sed -i 's/${CLUSTER_NAME}/'$CLUSTER_NAME'/g' /opt/apache-cassandra/conf/cassandra.yaml
else
    sed -i 's/${CLUSTER_NAME}/test_cluster/g' /opt/apache-cassandra/conf/cassandra.yaml
fi

# set the data volume if set, otherwise use the CASSANDRA_HOME location, otherwise default to '/cassandra_data'
if [ -n "$DATA_VOLUME" ]; then
    sed -i 's#${DATA_VOLUME}#'$DATA_VOLUME'#g' /opt/apache-cassandra/conf/cassandra.yaml
elif [ -n "$CASSANDRA_HOME" ]; then
    DATA_VOLUME="$CASSANDRA_HOME/data"
    sed -i 's#${DATA_VOLUME}#'$CASSANDRA_HOME'/data#g' /opt/apache-cassandra/conf/cassandra.yaml
else
    DATA_VOLUME="/cassandra_data"
    sed -i 's#${DATA_VOLUME}#/cassandra_data#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

# set the commitlog volume if set, otherwise use the DATA_VOLUME value instead
if [ -n "$COMMITLOG_VOLUME" ]; then
  sed -i 's#${COMMITLOG_VOLUME}#'$COMMITLOG_VOLUME'#g' /opt/apache-cassandra/conf/cassandra.yaml
else
  sed -i 's#${COMMITLOG_VOLUME}#'$DATA_VOLUME'#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

# set the seed provider class name, otherwise default to the SimpleSeedProvider
if [ -n "$SEED_PROVIDER_CLASSNAME" ]; then
    sed -i 's#${SEED_PROVIDER_CLASSNAME}#'$SEED_PROVIDER_CLASSNAME'#g' /opt/apache-cassandra/conf/cassandra.yaml
else
    sed -i 's#${SEED_PROVIDER_CLASSNAME}#org.apache.cassandra.locator.SimpleSeedProvider#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

# setup and configure the security setting
if [ -n "$INTERNODE_ENCRYPTION" ]; then
   sed -i 's#${INTERNODE_ENCRYPTION}#'$INTERNODE_ENCRYPTION'#g' /opt/apache-cassandra/conf/cassandra.yaml
else
   sed -i 's#${INTERNODE_ENCRYPTION}#none#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

if [ -n "$ENABLE_CLIENT_ENCRYPTION" ]; then
   sed -i 's#${ENABLE_CLIENT_ENCRYPTION}#'$ENABLE_CLIENT_ENCRYPTION'#g' /opt/apache-cassandra/conf/cassandra.yaml
else
   sed -i 's#${ENABLE_CLIENT_ENCRYPTION}#false#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

if [ -n "$REQUIRE_NODE_AUTH" ]; then
   sed -i 's#${REQUIRE_NODE_AUTH}#'$REQUIRE_NODE_AUTH'#g' /opt/apache-cassandra/conf/cassandra.yaml
else
   sed -i 's#${REQUIRE_NODE_AUTH}#false#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

if [ -n "$REQUIRE_CLIENT_AUTH" ]; then
   sed -i 's#${REQUIRE_CLIENT_AUTH}#'$REQUIRE_CLIENT_AUTH'#g' /opt/apache-cassandra/conf/cassandra.yaml
else
   sed -i 's#${REQUIRE_CLIENT_AUTH}#false#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

# handle setting up the keystore
KEYSTORE_FILE="${KEYSTORE_DIR}/.keystore"
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-$(openssl rand -base64 512 | tr -dc A-Z-a-z-0-9 | head -c 17)}

echo "Creating the Cassandra keystore from the Secret's cert data"
openssl pkcs12 -export -in ${SERVICE_CERT} -inkey ${SERVICE_CERT_KEY} -out ${PKCS12_FILE} -name ${SERVICE_ALIAS} -noiter -nomaciter -password pass:${KEYSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to create a PKCS12 certificate file with the service-specific certificate. Aborting."
    exit 1
fi
echo "Converting the PKCS12 keystore into a Java Keystore"
${KEYTOOL_COMMAND} -v -importkeystore -srckeystore ${PKCS12_FILE} -srcstoretype PKCS12 -destkeystore ${KEYSTORE_FILE} -deststoretype JKS -deststorepass ${KEYSTORE_PASSWORD} -srcstorepass ${KEYSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to create a Java Keystore file with the service-specific certificate. Aborting."
    exit 1
fi
sed -i 's#${KEYSTORE_PASSWORD}#'$KEYSTORE_PASSWORD'#g' /opt/apache-cassandra/conf/cassandra.yaml
sed -i 's#${KEYSTORE_FILE}#'$KEYSTORE_FILE'#g' /opt/apache-cassandra/conf/cassandra.yaml

# handle setting up the trust store for the inter node communication
TRUSTSTORE_NODES_FILE=${TRUSTSTORE_NODES_FILE:-"${KEYSTORE_DIR}/.nodes.truststore"}
TRUSTSTORE_NODES_PASSWORD=${TRUSTSTORE_NODES_PASSWORD:-$(openssl rand -base64 512 | tr -dc A-Z-a-z-0-9 | head -c 17)}

# The next few lines deserve an explantion: the TRUSTSTORE_NODES_AUTHORITIES may contain the root CA and the certificates
# in a single file. Java's keytool can't handle this, it seems, and ends up importing only
# the first one. So, we split the file, having one cert per resulting file. The next lines are for that, and
# will only work properly on the scenario described. If the scenario ever changes, the next lines will probably
# need to be adapted accordingly. The best solution would be to have one cert per file.
PREV_DIR=${PWD}
cd ${KEYSTORE_DIR}
csplit -z -f cas-to-import ${TRUSTSTORE_NODES_AUTHORITIES} '/-----BEGIN CERTIFICATE-----/' '{*}' > /dev/null
if [ $? != 0 ]; then
    echo "Failed to split the trustore_nodes_authorities into individual cert files. Aborting."
    exit 1
fi

echo "Building the trust store for inter node communication"
for file in $(ls cas-to-import*);
do
    ${KEYTOOL_COMMAND} -noprompt -import -alias ${file} -file ${file} -keystore ${TRUSTSTORE_NODES_FILE} -trustcacerts -storepass ${TRUSTSTORE_NODES_PASSWORD}
    if [ $? != 0 ]; then
        echo "Failed to import the authority from '${file}' into the node communication trust store. Aborting."
        exit 1
    fi
done

rm cas-to-import*
cd ${PREV_DIR}
sed -i 's#${TRUSTSTORE_NODES_FILE}#'$TRUSTSTORE_NODES_FILE'#g' /opt/apache-cassandra/conf/cassandra.yaml
sed -i 's#${TRUSTSTORE_NODES_PASSWORD}#'$TRUSTSTORE_NODES_PASSWORD'#g' /opt/apache-cassandra/conf/cassandra.yaml

# handle setting up the trust store for the client communication
TRUSTSTORE_CLIENT_FILE=${TRUSTSTORE_CLIENT_FILE:-"${KEYSTORE_DIR}/.clients.truststore"}
TRUSTSTORE_CLIENT_PASSWORD=${TRUSTSTORE_CLIENT_PASSWORD:-$(openssl rand -base64 512 | tr -dc A-Z-a-z-0-9 | head -c 17)}

# see comment on a similar code for inter-node communication
PREV_DIR=${PWD}
cd ${KEYSTORE_DIR}
csplit -z -f cas-to-import ${TRUSTSTORE_CLIENT_AUTHORITIES} '/-----BEGIN CERTIFICATE-----/' '{*}' > /dev/null
if [ $? != 0 ]; then
    echo "Failed to split the truststore_client_authorities into individual cert files. Aborting."
    exit 1
fi

echo "Building the trust store for client communication"
for file in $(ls cas-to-import*);
do
    ${KEYTOOL_COMMAND} -noprompt -import -alias ${file} -file ${file} -keystore ${TRUSTSTORE_CLIENT_FILE} -trustcacerts -storepass ${TRUSTSTORE_CLIENT_PASSWORD}
    if [ $? != 0 ]; then
        echo "Failed to import the authority from '${file}' into the client communication trust store. Aborting."
        exit 1
    fi
done

rm cas-to-import*

echo "Generating self signed certificates for the local client for cqlsh"
openssl req -new -newkey rsa:4096 -x509 -keyout .cassandra.local.client.key -out .cassandra.local.client.cert -subj "/CN=local.cassandra" -nodes -days 1825
${KEYTOOL_COMMAND} -noprompt -import -alias .cassandra.local.client.cert -file .cassandra.local.client.cert -keystore ${TRUSTSTORE_CLIENT_FILE} -trustcacerts -storepass ${TRUSTSTORE_CLIENT_PASSWORD}

cd ${PREV_DIR}
sed -i 's#${TRUSTSTORE_CLIENT_FILE}#'$TRUSTSTORE_CLIENT_FILE'#g' /opt/apache-cassandra/conf/cassandra.yaml
sed -i 's#${TRUSTSTORE_CLIENT_PASSWORD}#'$TRUSTSTORE_CLIENT_PASSWORD'#g' /opt/apache-cassandra/conf/cassandra.yaml

# create the cqlshrc file so that cqlsh can be used much more easily from the system
mkdir -p $HOME/.cassandra
cat >> $HOME/.cassandra/cqlshrc << DONE
[connection]
hostname= $HOSTNAME
port = 9042
factory = cqlshlib.ssl.ssl_transport_factory
[ssl]
certfile = ${SERVICE_CERT}
userkey = ${KEYSTORE_DIR}/.cassandra.local.client.key
usercert = ${KEYSTORE_DIR}/.cassandra.local.client.cert
DONE

# verify that we are not trying to run an older version of Cassandra which has been configured for a newer version.
if [ -f ${CASSANDRA_DATA_VOLUME}/.cassandra.version ]; then
    previousVersion=$(cat ${CASSANDRA_DATA_VOLUME}/.cassandra.version)
    echo "The previous version of Cassandra was $previousVersion. The current version is $CASSANDRA_VERSION"
    previousMajor=$(cut -d "." -f 1 <<< "$previousVersion")
    previousMinor=$(cut -d "." -f 2 <<< "$previousVersion")

    currentMajor=$(cut -d "." -f 1 <<< "$CASSANDRA_VERSION")
    currentMinor=$(cut -d "." -f 2 <<< "$CASSANDRA_VERSION")

    if (( ($currentMajor < $previousMajor) || (($currentMajor == $previousMajor) && ($currentMinor < $previousMinor)) )); then
       echo "Error: the data volume associated with this pod is configured to be used with Cassandra version $previousVersion"
       echo "       or higher. This pod is using Cassandra version $CASSANDRA_VERSION which does not meet this requirement."
       echo "       This pod will not be started."
       exit 1
    fi
fi

exec ${CASSANDRA_HOME}/bin/cassandra -f -R
