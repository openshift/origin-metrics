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

function createCertificate {
  name=$1
  hostnames=$2
  mkdir -p $name
  oadm ca create-server-cert --cert=$name/$name.cert --key=$name/$name.key --hostnames=$hostnames --signer-cert=${SIGNER_CERT} --signer-key=${SIGNER_KEY} --signer-serial=${SIGNER_SERIAL}
  cat $name/$name.cert $name/$name.key > $name/$name.pem

  (openssl x509 -in $name/$name.cert; cat $name/$name.key) > $name/$name-noca.pem
}

#copy the signer certificate into this directory
cp ${SIGNER_CERT} signer.ca

#create the Hawkular certificate and key from the OpenShift instance
createCertificate hawkular hawkular-metrics.example.com

#create the Hawkular certificate and key from the OpenShift instance with a wildcard
createCertificate hawkularWildCard *.example.com 
