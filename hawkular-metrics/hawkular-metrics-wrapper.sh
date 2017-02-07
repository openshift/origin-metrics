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

echo $(date "+%Y-%m-%d %H:%M:%S") Starting Hawkular Metrics

KUBERNETES_API_VERSION=${KUBERNETES_API_VERSION:-v1}
POD_NAMESPACE=${POD_NAMESPACE:-openshift-infra}
MASTER_URL=${MASTER_URL:-https://kubernetes.default.svc:443}

JBOSS_HOME=${JBOSS_HOME:-/opt/jboss/wildfly}
HAWKULAR_METRICS_DIRECTORY=${HAWKULAR_METRICS_DIRECTORY:-/opt/hawkular}
KEYSTORE_DIR=${KEYSTORE_DIR:-"${HAWKULAR_METRICS_DIRECTORY}"}

KEYSTORE_FILE=${KEYSTORE_FILE:-"${KEYSTORE_DIR}/hawkular-metrics.keystore"}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-$(head /dev/urandom -c 512 | tr -dc A-Z-a-z-0-9 | head -c 17)}

TRUSTSTORE_FILE=${TRUSTSTORE_FILE:-"${KEYSTORE_DIR}/hawkular-metrics.truststore"}
TRUSTSTORE_PASSWORD=${TRUSTSTORE_PASSWORD:-$(head /dev/urandom -c 512 | tr -dc A-Z-a-z-0-9 | head -c 17)}

SERVICE_ALIAS=${SERVICE_ALIAS:-"hawkular-metrics"}
SERVICE_CERT=${SERVICE_CERT:-"/secrets/tls.crt"}
SERVICE_CERT_KEY=${SERVICE_CERT_KEY:-"/secrets/tls.key"}

CA=${CA:-"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"}
CA_ALIAS=${CA_ALIAS:-"openshift-ca"}

SERVICE_CA=${SERVICE_CA:-"${KEYSTORE_DIR}/cas-to-import01"}
SERVICE_CA_ORIGINAL=${SERVICE_CA_ORIGINAL:-"/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt"}
SERVICE_CA_ALIAS=${SERVICE_CA_ALIAS:-"services-ca"}

PKCS12_FILE=${PKCS12_FILE:-"${KEYSTORE_DIR}/hawkular-metrics.pkcs12"}
KEYTOOL_COMMAND="/usr/lib/jvm/java-1.8.0/jre/bin/keytool"

# Check Read Permission
token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
url="${MASTER_URL}/api/${KUBERNETES_API_VERSION}/namespaces/${POD_NAMESPACE}/replicationcontrollers/hawkular-metrics"

status_code=$(curl --cacert ${SERVICE_CA_ORIGINAL} --max-time 10 --connect-timeout 10 -L -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${token}" $url)
if [ "$status_code" != 200 ]; then
  echo "Error: the service account for Hawkular Metrics does not have permission to view resources in this namespace. View permissions are required for Hawkular Metrics to function properly."
  echo "Usually this can be resolved by running: oc adm policy add-role-to-user view system:serviceaccount:${POD_NAMESPACE}:hawkular -n ${POD_NAMESPACE}"
  exit 1
else
  echo "The service account has read permissions for its project. Proceeding"
fi

echo "Creating the Hawkular Metrics PKCS12 keystore"
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

# the next few lines deserve an explanation: the service-ca.crt provided by OpenShift contains the root CA and the
# service-ca certificates in a single file. Java's keytool can't handle this, it seems, and ends up importing only
# the first one. So, we split the file, having one cert per resulting file. The next lines are for that, and
# will only work properly on the scenario described. If the scenario ever changes, the next lines will probably
# need to be adapted accordingly. The best solution would be to have one cert per file.
PREV_DIR=${PWD}
cd ${KEYSTORE_DIR}
csplit -z -f cas-to-import ${SERVICE_CA_ORIGINAL} '/-----BEGIN CERTIFICATE-----/' '{*}' > /dev/null
if [ $? != 0 ]; then
    echo "Failed to split the original service-ca into individual cert files. Aborting."
    exit 1
fi
cd ${PREV_DIR}

echo "Importing the Service CA into the trust store"
${KEYTOOL_COMMAND} -noprompt -import -alias ${SERVICE_CA_ALIAS} -file ${SERVICE_CA} -keystore ${TRUSTSTORE_FILE} -trustcacerts -storepass ${TRUSTSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to import the Service CA into the trust store. Aborting."
    exit 1
fi

# Setup additional logging if the ADDITIONAL_LOGGING variable is set
if [ -z "$ADDITIONAL_LOGGING" ]; then
  additional_loggers="            <!-- no additional logging configured -->"
else
  entries=$(echo ${ADDITIONAL_LOGGING} | tr "," "\n")
  for entry in ${entries}; do
    component=${entry%=*}
    debug_level=${entry##*=}

    debug_config="\
            <logger category=\"${component}\"> \n\
              <level name=\"${debug_level}\"/> \n\
            </logger> \n"

    additional_loggers+=${debug_config}
  done
fi
sed -i "s|<!-- ##ADDITIONAL LOGGERS## -->|$additional_loggers|g" ${JBOSS_HOME}/standalone/configuration/standalone.xml

if [ "x${JGROUPS_PASSWORD}" == "x" ]; then
    echo "ATTENTION ATTENTION ATTENTION ATTENTION"
    echo "The environment variable JGROUPS_PASSWORD was not set and we are generating one."
    echo "This means that each Hawkular instance will have its own password and won't be able to form a cluster."
    JGROUPS_PASSWORD=$(head /dev/urandom -c 512 | tr -dc A-Z-a-z-0-9 | head -c 17)
fi

cat > ${HAWKULAR_METRICS_DIRECTORY}/server.properties << EOL
javax.net.ssl.keyStorePassword=${KEYSTORE_PASSWORD}
javax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}
EOL

exec 2>&1 /opt/jboss/wildfly/bin/standalone.sh \
  -Djboss.node.name=$HOSTNAME \
  -Djgroups.password=${JGROUPS_PASSWORD} \
  -Djavax.net.ssl.keyStore=${KEYSTORE_FILE} \
  -Djavax.net.ssl.trustStore=${TRUSTSTORE_FILE} \
  -P ${HAWKULAR_METRICS_DIRECTORY}/server.properties \
  -b `hostname -i` \
  -bprivate `hostname -i` \
  $@
