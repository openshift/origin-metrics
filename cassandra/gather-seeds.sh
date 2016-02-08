#!/bin/bash

#How many retries before giving up
RETRIES=30

#How long to wait inbetween retries
WAIT_TIME_SECONDS=2

#The service hostname used to look up the seed addresses
SERVICE="hawkular-cassandra-nodes"

#Get the default seed from the hostname of this machine
default_seed=${HOSTNAME}

echo "About to generate seeds"

for i in `seq 1 ${RETRIES}`; do
  echo "Trying to access the Seed list [try #${i}]"

  seeds=$(dig +time=5 +tries=1 +short +search ${SERVICE} | paste -sd "," -)
  if [ -n "${seeds}" ]; then
    break
  fi

  if [[ ${i} -ge 3 ]] && [[ $CASSANDRA_MASTER == "true" ]]; then
    seeds=${default_seed}
    break
  fi

  sleep ${WAIT_TIME_SECONDS}
done

if [ -z "${seeds}" ]; then
  echo "ERROR. Could not determine seeds from a headless service named ${SERVICE}"
  exit 1
else
  SEEDS=${seeds}
fi

