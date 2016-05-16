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
    # We don't want to delete ourselves, but we do want to remove old deployers
    # Remove our label so that we are not deleted.
    echo "POD_NAME ${POD_NAME:-}"
    [ -n "${POD_NAME:-}" ] && oc label pod ${POD_NAME} metrics-infra-

    oc delete rc,svc,pod,sa,templates,secrets --selector="metrics-infra" --ignore-not-found=true

    # Add back our label so that the next time the deployer is run this will be deleted
    [ -n "${POD_NAME:-}" ] && oc label pod ${POD_NAME} metrics-infra=deployer

  elif [ "$redeploy" = true ] || [ "$mode" = remove ]; then
    echo "Deleting any previous deployment"
    # We don't want to delete ourselves, but we do want to remove old deployers
    # Remove our label so that we are not immediately deleted.
    echo "POD_NAME ${POD_NAME:-}"
    [ -n "${POD_NAME:-}" ] && oc label pod ${POD_NAME} metrics-infra-

    oc delete --grace-period=0 all,sa,templates,secrets --selector="metrics-infra" --ignore-not-found=true
    oc delete pvc --selector="metrics-infra" --ignore-not-found=true

    # Add back our label so that the next time the deployer is run this will be deleted
    [ -n "${POD_NAME:-}" ] && oc label pod ${POD_NAME} metrics-infra=deployer
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

