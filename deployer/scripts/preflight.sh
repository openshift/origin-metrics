#!/bin/bash

set -e

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

function cert_should_have_names() {
  local file="$1"; shift
  local output name cn san sans found count

  if ! output=$(openssl x509 -in "$file" -noout -text 2>&1); then
    echo "Could not extract certificate from $file. The error was:"
    echo "$output"
    return 1
  fi
  if san=$(echo -e "$output" | grep -A 1 "Subject Alternative Name:"); then
    found=0
    sans=$(process_san $san)
    count=${#@}
    for name in $@; do
       for san in $sans; do
         check=$(check_san $san $name)
         if [[ "$check" == "true" ]]; then
          ((found++))
         fi
       done
    done
    if [[ $found != $count ]]; then
      echo "The supplied $file certificate is required to match the following name(s) in the Subject Alternative Name field:"
      echo $@
      echo "Instead the certificate has:"
      echo -e "$sans"
      echo "Please supply a correct certificate or omit it to allow the deployer to generate it."
      return 1
    fi
  elif [[ $# -gt 1 ]]; then
    echo "The supplied $file certificate is required to have a Subject Alternative Name field containing these names:"
    echo $@
    echo "The certificate does not have the Subject Alternative Name field."
    echo "Please supply a correct certificate or omit it to allow the deployer to generate it."
    return 1
  else
    cn=$(echo -e "$output" | grep "Subject:")
    if [[ "$cn" != *CN=$1* ]]; then
      echo "The supplied $file certificate does not contain $1 in the Subject field and lacks a Subject Alternative Name field."
      echo "Please supply a correct certificate or omit it to allow the deployer to generate it."
      return 1
    fi
  fi
  return 0
}

function validate_deployer_secret() {
  local failure=false
  local file
  local output
  pushd ${secret_dir} >& /dev/null
  for file in *; do
    case $file in
      hawkular-metrics.pem)
        cert_should_have_names "$file" "$hawkular_metrics_hostname" || failure=true
       ;;
      heapster.cert)
        cert_should_have_names "$file" heapster || failure=true
        ;;
      hawkular-metrics-ca.cert|heapster.key|heapster_client_ca.cert|heapster_allowed_users)
        # is there a need to validate these?
        ;;
      nothing|none|null|foo|'*')
        # dummy files, ignore
        ;;
      *)
        failure=true
        echo "Unexpected file found in deployer secret: $file"
        echo "This is likely to be a typo; failing validation."
        ;;
    esac
  done
  popd >& /dev/null
  if [ "$failure" = false ]; then
    echo "ok"
    return 0
  fi
  return 1
}

function validate_preflight() {
  set -e
  set +x
  
  local success=()
  local failure=()
  for func in validate_master_accessible validate_hostname validate_deployer_secret; do
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
