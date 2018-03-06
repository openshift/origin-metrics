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

echo $(date "+%Y-%m-%d %H:%M:%S") Starting Hawkular Metrics Schema Installer

HAWKULAR_METRICS_DIRECTORY=${HAWKULAR_METRICS_DIRECTORY:-"/opt"}
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

echo "CREATED HAWKULAR METRICS KEYSTORE"

echo "Converting the PKCS12 keystore into a Java Keystore"
${KEYTOOL_COMMAND} -v -importkeystore -srckeystore ${PKCS12_FILE} -srcstoretype PKCS12 -destkeystore ${KEYSTORE} -deststoretype JKS -deststorepass ${KEYSTORE_PASSWORD} -srcstorepass ${KEYSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to create a Java Keystore file with the service-specific certificate. Aborting."
    exit 1
fi

echo "CONVERTED THE PKCS12 KEYSTORE"

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
    sed -i 's/\s$//gi' ${file} # See BZ 1471251: remove trailing spaces, as the Java Keytool hates whitespace.
    sed -i '/^\s*$/d' ${file} # Let's also remove empty lines
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
    sed -i 's/\s$//gi' ${file}
    sed -i '/^\s*$/d' ${file}
    ${KEYTOOL_COMMAND} -noprompt -import -alias ${file} -file ${file} -keystore ${TRUSTSTORE} -trustcacerts -storepass ${TRUSTSTORE_PASSWORD}
    if [ $? != 0 ]; then
        echo "Failed to import the authority from '${file}' into the trust store. Aborting."
        exit 1
    fi
done

rm cas-to-import*
cd ${PREV_DIR}

java -Dhawkular.metrics.cassandra.nodes=hawkular-cassandra \
     -Dhawkular.metrics.cassandra.use-ssl=true \
     -Djavax.net.ssl.keyStore=${KEYSTORE} \
     -Djavax.net.ssl.trustStore=${TRUSTSTORE} \
     -Djavax.net.ssl.keyStorePassword=${KEYSTORE_PASSWORD} \
     -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD} \
     -jar /opt/hawkular-metrics-schema-installer.jar 
