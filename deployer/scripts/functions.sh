#!/bin/bash

function parse_bool {
  local v=${1,,}
  if [ "$v" != true -a "$v" != false ]; then
    printf >&2 'Invalid boolean value for %s: %s\n' "$2" "$1"
    return 1
  fi
  echo "$v"
}

function handle_previous_deployment() {
  if [ "$mode" = "refresh" ]; then
    echo "Deleting any previous deployment (leaving route and PVCs)"
    # We don't want to delete ourselves, but we do want to remove old deployers
    # Remove our label so that we are not deleted.
    [ -n "${POD_NAME:-}" ] && oc label pod ${POD_NAME} metrics-infra-

    oc delete rc,svc,pod,sa,templates,secrets --selector="metrics-infra" --ignore-not-found=true

    # Add back our label so that the next time the deployer is run this will be deleted
    [ -n "${POD_NAME:-}" ] && oc label pod ${POD_NAME} metrics-infra=deployer

  elif [ "$redeploy" = true ] || [ "$mode" = remove ]; then
    echo "Deleting any previous deployment"
    # We don't want to delete ourselves, but we do want to remove old deployers
    # Remove our label so that we are not immediately deleted.
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

function process_san() {
  local host
  local san=$*
  local sans=()
  for value in $san; do
    if [[ $value == "DNS:"* ]]; then
      host=${value:4}
      if [[ ${host: -1} == "," ]]; then
        host=${host:0:${#host} -1}
      fi
      sans=("${sans[@]-}" "$host")
    fi
  done
  echo ${sans[@]}
}

function check_san() {
  local san=$1
  local hostname=$2
  #we need to handle the wildcard situation
  if [[ ${san:0:2} == "*." ]]; then
    san=${san:2}
    if [[ $hostname =~ ^.*".${san}"$ ]] || [[ $hostname =~ ^"${san}"$   ]]; then
      echo true
      return
    fi
  else
    if [[ $hostname == ${san} ]]; then
      echo true
      return
    fi
  fi
  echo false
}

