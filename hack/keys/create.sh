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
    *)
      echo "invalid argument $args"
      exit 1
    ;;
  esac
done

if [ -n ${OS_ROOT} ]; then
  SIGNER_CERT=${OS_ROOT}/master/ca.crt
  SIGNER_KEY=${OS_ROOT}/master/ca.key
  SIGNER_SERIAL=${OS_ROOT}/master/ca.serial.txt
fi

#copy the signer certificate into this directory
cp ${SIGNER_CERT} signer.ca

#create the Hawkular certificate and key from the OpenShift instance
oadm ca create-server-cert --cert=hawkular.crt --key=hawkular.key --hostnames=hawkular-metrics,hawkular-metrics.example.com --signer-cert=${SIGNER_CERT} --signer-key=${SIGNER_KEY} --signer-serial=${SIGNER_SERIAL}
cat hawkular.crt hawkular.key > hawkular.pem

#create the Hawkular certificate and key from the OpenShift instance with a wildcard
oadm ca create-server-cert --cert=hawkular-wc.crt --key=hawkular-wc.key --hostnames=hawkular-metrics,*.example.com --signer-cert=${SIGNER_CERT} --signer-key=${SIGNER_KEY} --signer-serial=${SIGNER_SERIAL}
cat hawkular-wc.crt hawkular-wc.key > hawkular-wc.pem

#create the Cassandra certificate and key from the OpenShift instance
oadm ca create-server-cert --cert=cassandra.crt --key=cassandra.key --hostnames=hawkular-cassandra --signer-cert=${SIGNER_CERT} --signer-key=${SIGNER_KEY} --signer-serial=${SIGNER_SERIAL}
cat cassandra.crt cassandra.key > cassandra.pem

