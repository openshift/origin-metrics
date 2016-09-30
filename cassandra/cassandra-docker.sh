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
    --keystore_file=*)
      KEYSTORE_FILE="${args#*=}"
    ;;
    --keystore_password=*)
      KEYSTORE_PASSWORD="${args#*=}"
    ;;
    --keystore_password_file=*)
      KEYSTORE_PASSWORD_FILE="${args#*=}"
    ;;
    --truststore_file=*)
      TRUSTSTORE_FILE="${args#*=}"
    ;;
    --trustsotre_password=*)
      TRUSTSTORE_PASSWORD="${args#*=}"
    ;;
    --truststore_password_file=*)
      TRUSTSTORE_PASSWORD_FILE="${args#*=}"
    ;;
    --cassandra_pem_file=*)
      CASSANDRA_PEM_FILE="${args#*=}"
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
  echo "  --keystore_file=KEYSTORE_FILE_LOCATION"
  echo "        the path to where the keystore is located"
  echo
  echo "  --keystore_password=KEYSTORE_PASSWORD"
  echo "        the password to use for the keystore"
  echo
  echo "  --keystore_password_file=KEYSTORE_PASSWORD"
  echo "        a file containing only the keystore password"
  echo
  echo "  --truststore_file=TRUSTSTORE_FILE_LOCATION"
  echo "        the path to where the truststore is located"
  echo
  echo "  --truststore_password=TRUSTSTORE_PASSWORD"
  echo "        the password to use for the truststore"
  echo
  echo "  --truststore_password_file=TRUSTSTORE_PASSWORD"
  echo "        a file containing only the truststore password"
  echo
  exit 0
fi

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

if [ -z "${HEAP_NEWSIZE}" ] && [ -z "${CPU_LIMIT}" ]; then
  echo "The HEAP_NEWSIZE and CPU_LIMIT envars are not set. Defaulting the HEAP_NEWSIZE to 100M"
  export HEAP_NEWSIZE=100M
elif [ -z "${HEAP_NEWSIZE}" ]; then
  export HEAP_NEWSIZE=$((CPU_LIMIT/10))M
  echo "THE HEAP_NEWSIZE envar is not set. Setting to ${HEAP_NEWSIZE} based on the CPU_LIMIT of ${CPU_LIMIT}. [100M per CPU core]"
else
  echo "The HEAP_NEWSIZE envar is set to ${HEAP_NEWSIZE}. Using this value"
fi

#Update the cassandra-env.sh with these new values
cp /opt/apache-cassandra/conf/cassandra-env.sh.template /opt/apache-cassandra/conf/cassandra-env.sh
sed -i 's/${MAX_HEAP_SIZE}/'$MAX_HEAP_SIZE'/g' /opt/apache-cassandra/conf/cassandra-env.sh
sed -i 's/${HEAP_NEWSIZE}/'$HEAP_NEWSIZE'/g' /opt/apache-cassandra/conf/cassandra-env.sh

cp /opt/apache-cassandra/conf/cassandra.yaml.template /opt/apache-cassandra/conf/cassandra.yaml

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
if [ -n "$KEYSTORE_FILE" ]; then
   sed -i 's#${KEYSTORE_FILE}#'$KEYSTORE_FILE'#g' /opt/apache-cassandra/conf/cassandra.yaml
fi
if [ -n "$KEYSTORE_PASSWORD_FILE" ]; then
   KEYSTORE_PASSWORD=$(cat $KEYSTORE_PASSWORD_FILE)
fi
if [ -n "$KEYSTORE_PASSWORD" ]; then
   sed -i 's#${KEYSTORE_PASSWORD}#'$KEYSTORE_PASSWORD'#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

# handle setting up the truststore
if [ -n "$TRUSTSTORE_FILE" ]; then
   sed -i 's#${TRUSTSTORE_FILE}#'$TRUSTSTORE_FILE'#g' /opt/apache-cassandra/conf/cassandra.yaml
fi
if [ -n "$TRUSTSTORE_PASSWORD_FILE" ]; then
   TRUSTSTORE_PASSWORD=$(cat $TRUSTSTORE_PASSWORD_FILE)
fi
if [ -n "$TRUSTSTORE_PASSWORD" ]; then
   sed -i 's#${TRUSTSTORE_PASSWORD}#'$TRUSTSTORE_PASSWORD'#g' /opt/apache-cassandra/conf/cassandra.yaml
fi

# create the cqlshrc file so that cqlsh can be used much more easily from the system
mkdir -p $HOME/.cassandra
cat >> $HOME/.cassandra/cqlshrc << DONE
[connection]
hostname= $HOSTNAME
factory = cqlshlib.ssl.ssl_transport_factory
port = 9042

[ssl]
certfile = ${CASSANDRA_PEM_FILE}
userkey = ${CASSANDRA_PEM_FILE}
usercert = ${CASSANDRA_PEM_FILE}
DONE

if [ -n "$CASSANDRA_HOME" ]; then
  exec ${CASSANDRA_HOME}/bin/cassandra -f
else
  exec /opt/apache-cassandra/bin/cassandra -f
fi

