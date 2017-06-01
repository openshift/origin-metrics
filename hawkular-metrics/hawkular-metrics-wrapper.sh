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

# Set up the parameters to pass to EAP while removing the ones specific to the wrapper
as_args=

for args in "$@"
do
  if [[ $args == --hmw\.* ]]; then
    case $args in
        --hmw.tls_certificate=*)
          SERVICE_CERT="${args#*=}"
        ;;
        --hmw.tls_certificate_key=*)
          SERVICE_CERT_KEY="${args#*=}"
        ;;
        --hmw.truststore_authorities=*)
          TRUSTSTORE_AUTHORITIES="${args#*=}"
        ;;
    esac
  else
    as_args="$as_args $args"
  fi
done

HAWKULAR_METRICS_DIRECTORY=${HAWKULAR_METRICS_DIRECTORY:-"/opt/hawkular"}
KEYTOOL_COMMAND=/usr/lib/jvm/java-1.8.0/jre/bin/keytool
HAWKULAR_METRICS_AUTH_DIR=${HAWKULAR_METRICS_DIRECTORY}/auth

KEYSTORE_DIR=${KEYSTORE_DIR:-"${HAWKULAR_METRICS_AUTH_DIR}"}
KEYSTORE=${KEYSTORE:-"${KEYSTORE_DIR}/hawkular-metrics.keystore"}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-$(openssl rand -base64 512 | tr -dc A-Z-a-z-0-9 | head -c 17)}

TRUSTSTORE_DIR=${TRUSTSTORE_DIR:-"${HAWKULAR_METRICS_AUTH_DIR}"}
TRUSTSTORE=${TRUSTSTORE:-"${KEYSTORE_DIR}/hawkular-metrics.truststore"}
TRUSTSTORE_PASSWORD=${TRUSTSTORE_PASSWORD:-$(openssl rand -base64 512 | tr -dc A-Z-a-z-0-9 | head -c 17)}

SERVICE_ALIAS=${SERVICE_ALIAS:-"hawkular-metrics"}
SERVICE_CERT=${SERVICE_CERT:-"/hawkular-metrics-certs/tls.crt"}
SERVICE_CERT_KEY=${SERVICE_CERT_KEY:-"/hawkular-metrics-certs/tls.key"}

PKCS12_FILE=${PKCS12_FILE:-"${KEYSTORE_DIR}/hawkular-metrics.pkcs12"}

if [ -z "${TRUSTSTORE_AUTHORITIES}" ]; then
 echo "The --truststore_authorities value is not specified. Aborting"
 exit 1
fi

# Check Read Permission
token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
url="${MASTER_URL:-https://kubernetes.default.svc:443}/api/${KUBERNETES_API_VERSION:-v1}/namespaces/${POD_NAMESPACE}/replicationcontrollers/hawkular-metrics"
cacrt="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

status_code=$(curl --cacert ${cacrt} --max-time 10 --connect-timeout 10 -L -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${token}" $url)
if [ "$status_code" != 200 ]; then
  if [ "$status_code" == "403" ]; then
    echo "Error: the service account for Hawkular Metrics does not have permission to view resources in this namespace. View permissions are required for Hawkular Metrics to function properly."
    echo "Usually this can be resolved by running: oc adm policy add-role-to-user view system:serviceaccount:${POD_NAMESPACE}:hawkular -n ${POD_NAMESPACE}"
  elif [ "$status_code" == "401" ]; then
    echo "Error: the credentials for Hawkular Metrics are not valid."
  else
    echo "Error: An error was encountered fetching ${url} (status code ${status_code})."
  fi
  exit 1
else
  echo "The service account has read permissions for its project. Proceeding"
fi

# Setup additional logging if the ADDITIONAL_LOGGING variable is set
if [ -z "$ADDITIONAL_LOGGING" ]; then
  additional_loggers="            <!-- no additional logging configured -->"
else
  entries=$(echo $ADDITIONAL_LOGGING | tr "," "\n")
  for entry in $entries; do
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

if [ ! -d ${KEYSTORE_DIR} ]; then
    mkdir -p "${KEYSTORE_DIR}"
fi

if [ -f ${PKCS12_FILE} ]; then
    echo "Removing the existing PKCS12 certificate file"
    rm ${PKCS12_FILE}
fi
if [ -f ${KEYSTORE} ]; then
    echo "Removing the existing keystore"
    rm ${KEYSTORE}
fi
if [ -f ${TRUSTSTORE} ]; then
    echo "Removing the existing trust store"
    rm ${TRUSTSTORE}
fi

echo "Creating the Hawkular Metrics keystore from the Secret's cert data"
openssl pkcs12 -export -in ${SERVICE_CERT} -inkey ${SERVICE_CERT_KEY} -out ${PKCS12_FILE} -name ${SERVICE_ALIAS} -noiter -nomaciter -password pass:${KEYSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to create a PKCS12 certificate file with the service-specific certificate. Aborting."
    exit 1
fi
echo "Converting the PKCS12 keystore into a Java Keystore"
${KEYTOOL_COMMAND} -v -importkeystore -srckeystore ${PKCS12_FILE} -srcstoretype PKCS12 -destkeystore ${KEYSTORE} -deststoretype JKS -deststorepass ${KEYSTORE_PASSWORD} -srcstorepass ${KEYSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to create a Java Keystore file with the service-specific certificate. Aborting."
    exit 1
fi

PREV_DIR=${PWD}
cd ${KEYSTORE_DIR}
csplit -z -f cas-to-import ${TRUSTSTORE_AUTHORITIES} '/-----BEGIN CERTIFICATE-----/' '{*}' > /dev/null
if [ $? != 0 ]; then
    echo "Failed to split the trust store input file into individual cert files. Aborting."
    exit 1
fi

echo "Building the trust store"
for file in $(ls cas-to-import*);
do
    ${KEYTOOL_COMMAND} -noprompt -import -alias ${file} -file ${file} -keystore ${TRUSTSTORE} -trustcacerts -storepass ${TRUSTSTORE_PASSWORD}
    if [ $? != 0 ]; then
        echo "Failed to import the authority from '${file}' into the trust store. Aborting."
        exit 1
    fi
done

echo "Splitting up the Kubernetes CA into individual certificates"
csplit -z -f kubernetes-cas-to-import /var/run/secrets/kubernetes.io/serviceaccount/ca.crt '/-----BEGIN CERTIFICATE-----/' '{*}' > /dev/null
if [ $? != 0 ]; then
    echo "Failed to split the kubernetes CA file into individual cert files. Aborting."
    exit 1
fi

echo "Adding the Kubernetes CAs into the trust store"
for file in $(ls kubernetes-cas-to-import*);
do
    ${KEYTOOL_COMMAND} -noprompt -import -alias ${file} -file ${file} -keystore ${TRUSTSTORE} -trustcacerts -storepass ${TRUSTSTORE_PASSWORD}
    if [ $? != 0 ]; then
        echo "Failed to import the authority from '${file}' into the trust store. Aborting."
        exit 1
    fi
done

rm cas-to-import*
cd ${PREV_DIR}

if [ "x${JGROUPS_PASSWORD}" == "x" ]; then
    echo "Could not determine the JGroups password. Without it, we cannot get a cluster lock, which could lead to unpredictable results."
    echo "Set the JGROUPS_PASSWORD environment variable and try again."
    exit 1
fi

cat > ${HAWKULAR_METRICS_DIRECTORY}/server.properties << EOL
javax.net.ssl.keyStorePassword=${KEYSTORE_PASSWORD}
javax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD}
jgroups.password=${JGROUPS_PASSWORD}
EOL

exec 2>&1 /opt/jboss/wildfly/bin/standalone.sh \
  -Djavax.net.ssl.keyStore=${KEYSTORE} \
  -Djavax.net.ssl.trustStore=${TRUSTSTORE} \
  -Djboss.node.name=$HOSTNAME \
  -b `hostname -i` \
  -bprivate `hostname -i` \
  -P ${HAWKULAR_METRICS_DIRECTORY}/server.properties \
  $as_args
