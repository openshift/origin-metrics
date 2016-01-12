#!/bin/bash

set -e

for args in "$@"
do
  case $args in
    --OS_ROOT=*)
      OS_ROOT="${args#*=}"
    ;;
    --signer-cert=*)
      SIGNER_CERT="${args#*=}"
    ;;
    --signer-key=*)
      SIGNER_KEY="${args#*=}"
    ;;
    --signer-serial=*)
      SIGNER_SERIAL="${args#*=}"
    ;;
  esac
done

if [ -n ${OS_ROOT} ]; then
  SIGNER_CERT=${OS_ROOT}/openshift.local.config/master/ca.crt
  SIGNER_KEY=${OS_ROOT}/openshift.local.config/master/ca.key
  SIGNER_SERIAL=${OS_ROOT}/openshift.local.config/master/ca.serial.txt
fi

#copy the signer certificate into this directory
cp ${SIGNER_CERT} signer.ca

#create the Hawkular certificate and key from the OpenShift instance
oadm ca create-server-cert --cert=hawkular.crt --key=hawkular.key --hostnames=hawkular-metrics --signer-cert=${SIGNER_CERT} --signer-key=${SIGNER_KEY} --signer-serial=${SIGNER_SERIAL}
cat hawkular.crt hawkular.key > hawkular.pem

#create the Cassandra certificate and key from the OpenShift instance
oadm ca create-server-cert --cert=cassandra.crt --key=cassandra.key --hostnames=cassandra --signer-cert=${SIGNER_CERT} --signer-key=${SIGNER_KEY} --signer-serial=${SIGNER_SERIAL}
cat cassandra.crt cassandra.key > cassandra.pem

