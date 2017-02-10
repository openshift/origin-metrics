#!/bin/bash

# determine whether DNS resolves the master successfully
function validate_master_accessible() {
  local output
  if output=$(curl -sSI --stderr - --connect-timeout 2 --cacert "$master_ca" "$master_url"); then
    echo "ok"
    return 0
  fi
  local rc=$?
  echo "unable to access master url $master_url"
  case $rc in # if curl's message needs interpretation
  51)
	  echo "The master server cert was not valid for $master_url."
	  echo "You most likely need to regenerate the master server cert;"
	  echo "or you may need to address the master differently."
	  ;;
  60)
	  echo "The master CA cert did not validate the master."
	  echo "If you have multiple masters, confirm their certs have the same CA."
	  ;;
  esac
  echo "See the error from 'curl ${master_url}' below for details:"
  echo -e "$output"
  return 1
}

function validate_hostname() {
  #The route will only accept RFC 952 based hostnames
  if [[ $hawkular_metrics_hostname =~ ^[a-zA-Z][a-zA-Z0-9.-]?+[a-zA-Z0-9]$ ]]; then
    echo "The HAWKULAR_METRICS_HOSTNAME value is deemed acceptable."
    return 0  
  else 
    echo "The HAWKULAR_METRICS_HOSTNAME value must be a valid hostname (RFC 952)"
    echo "The value which was specified is invalid:"
    echo "  $hawkular_metrics_hostname"
    echo "Hostnames must start with a letter, may only contain letters, numbers, '.' and '-'."
    return 1
  fi
}

function validate_preflight() {
  set +x
  
  local success=()
  local failure=()
  for func in validate_master_accessible validate_hostname; do
    func_output="$($func 2>&1)" && \
      success+=("$func: $func_output") || \
      failure+=("$func: "$'\n'"$func_output")
  done

  echo
  if [[ "${#failure[*]}" -gt 0 ]]; then
    echo "PREFLIGHT CHECK FAILED"
    for fail in "${failure[@]}"; do
      echo ========================
      echo -e "$fail"
    done
    echo
    echo "Deployment has been aborted prior to starting, as these failures often indicate fatal problems."
    echo "Please evaluate any error messages above and determine how they can be addressed."
    echo "To ignore this validation failure and continue, specify IGNORE_PREFLIGHT=true."
    echo
    echo "PREFLIGHT CHECK FAILED"
    exit 255
  fi
  
  echo "PREFLIGHT CHECK SUCCEEDED"
  for win in "${success[@]}"; do echo $win; done
}
