#!/bin/bash

# $1: name (eg [hawkular-metrics|hawkular-cassandra])
# $2: hostnames to use
# $3: environment variable containing base64 pem 
function setup_certificate {
  local name="${1:-}"
  local hostnames="${2:-}"
  local envVar="${3:-}"

  # Use existing or generate new Hawkular Metrics certificates
  if [ -n "${envVar:-}" ]; then
      echo "${envVar}" | base64 -d > $dir/${name}.pem
  elif [ -s ${secret_dir}/${name}.pem ]; then
      # use files from secret if present
      cp ${secret_dir}/${name}.pem $dir
      cp ${secret_dir}/${name}-ca.cert $dir
  else #fallback to creating one
      openshift admin ca create-server-cert  \
        --key=$dir/${name}.key \
        --cert=$dir/${name}.crt \
        --hostnames=${hostnames} \
        --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
      cat $dir/${name}.key $dir/${name}.crt > $dir/${name}.pem
      cp $dir/ca.crt $dir/${name}-ca.cert
  fi

}

function handle_previous_deployment() {
  if [ "$mode" = "refresh" ]; then
    echo "Deleting any previous deployment (leaving route and PVCs)"
    oc delete rc,svc,pod,sa,templates,secrets --selector="metrics-infra"
  elif [ "$redeploy" = true ] || [ "$mode" = remove ]; then
    echo "Deleting any previous deployment"
    oc delete all,sa,templates,secrets,pvc --selector="metrics-infra"
  fi
}


function create_signer_cert() {
  local dir=$1

  openshift admin ca create-signer-cert  \
    --key="${dir}/ca.key" \
    --cert="${dir}/ca.crt" \
    --serial="${dir}/ca.serial.txt" \
    --name="metrics-signer@$(date +%s)"
}

