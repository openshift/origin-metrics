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

# Set up the parameters to pass to EAP while removing the ones specific to the wrapper
as_args=

for args in "$@"
do
  if [[ $args == --hmw\.* ]]; then
    case $args in
      --hmw.keystore=*)
        KEYSTORE="${args#*=}"
        ;;
      --hmw.truststore=*)
        TRUSTSTORE="${args#*=}"
        ;;
      --hmw.keystore_password=*)
        KEYSTORE_PASSWORD="${args#*=}"
        ;;
      --hmw.keystore_password_file=*)
        KEYSTORE_PASSWORD_FILE="${args#*=}"
        ;;
      --hmw.truststore_password=*)
        TRUSTSTORE_PASSWORD="${args#*=}"
        ;;
      --hmw.truststore_password_file=*)
        TRUSTSTORE_PASSWORD_FILE="${args#*=}"
        ;;
      --hmw.jgroups_password=*)
        JGROUPS_PASSWORD="${args#*=}"
        ;;
      --hmw.jgroups_password_file=*)
        JGROUPS_PASSWORD_FILE="${args#*=}"
        ;;
    esac
  else
    as_args="$as_args $args"
  fi
done

# Check Read Permission
token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
url="${MASTER_URL:-https://kubernetes.default.svc:443}/api/${KUBERNETES_API_VERSION:-v1}/namespaces/${POD_NAMESPACE}/replicationcontrollers/hawkular-metrics"
cacrt="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

status_code=$(curl --cacert ${cacrt} --max-time 10 --connect-timeout 10 -L -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${token}" $url)
if [ "$status_code" != 200 ]; then
  echo "Error: the service account for Hawkular Metrics does not have permission to view resources in this namespace. View permissions are required for Hawkular Metrics to function properly."
  echo "       usually this can be resolved by running: oadm policy add-role-to-user view system:serviceaccount:${POD_NAMESPACE}:hawkular"
  exit 1
else
  echo "The service account has read permissions for its project. Proceeding"
fi

if [ -n "$KEYSTORE_PASSWORD_FILE" ]; then
   KEYSTORE_PASSWORD=$(cat $KEYSTORE_PASSWORD_FILE)
fi

if [ -n "$TRUSTSTORE_PASSWORD_FILE" ]; then
   TRUSTSTORE_PASSWORD=$(cat $TRUSTSTORE_PASSWORD_FILE)
fi

if [ -n "$JGROUPS_PASSWORD_FILE" ]; then
   JGROUPS_PASSWORD=$(cat $JGROUPS_PASSWORD_FILE)
fi
sed -i "s|#JGROUPS_PASSWORD#|${JGROUPS_PASSWORD}|g" ${JBOSS_HOME}/standalone/configuration/standalone.xml

# Setup additional logging if the ADDITIONAL_LOGGING variable is set
if [ -z "$ADDITIONAL_LOGGING"]; then
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

# Setup the truststore so that it will accept the OpenShift cert
HAWKULAR_METRICS_AUTH_DIR=$HAWKULAR_METRICS_DIRECTORY/auth
mkdir $HAWKULAR_METRICS_AUTH_DIR
pushd $HAWKULAR_METRICS_AUTH_DIR

cp $KEYSTORE hawkular-metrics.keystore
cp $TRUSTSTORE hawkular-metrics.truststore

chmod a+rw hawkular-metrics.*

KEYTOOL_COMMAND=/usr/lib/jvm/java-1.8.0/jre/bin/keytool
$KEYTOOL_COMMAND -noprompt -import -v -trustcacerts -alias kubernetes-master -file /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -keystore hawkular-metrics.truststore -trustcacerts -storepass $TRUSTSTORE_PASSWORD

popd


exec 2>&1 /opt/jboss/wildfly/bin/standalone.sh \
  -Djavax.net.ssl.keyStore=$HAWKULAR_METRICS_AUTH_DIR/hawkular-metrics.keystore \
  -Djavax.net.ssl.keyStorePassword=$KEYSTORE_PASSWORD \
  -Djavax.net.ssl.trustStore=$HAWKULAR_METRICS_AUTH_DIR/hawkular-metrics.truststore \
  -Djavax.net.ssl.trustStorePassword=$TRUSTSTORE_PASSWORD \
  -Djboss.node.name=$HOSTNAME \
  -b `hostname -i` \
  -bprivate `hostname -i` \
  $as_args
