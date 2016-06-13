#!/bin/bash

# determine whether heapster account has correct credentials
# and nodes resolve, can be reached, and have valid certs.
function validate_nodes_accessible() {
  # this gets us node values per row: $name $ip $status
  local node_detailed_template='{{range .items}}{{.metadata.name}} {{range .status.addresses}}{{if eq .type "InternalIP"}}{{.address}}{{end}}{{end}} {{range .status.conditions}}{{if eq .reason "KubeletReady"}}{{.type}}{{end}}{{end}}{{end}}
'
  # there's no good way for oc to filter the list of secrets; and there can be several token secrets per SA.
  # following template prints all tokens for heapster; --sort-by will order them earliest to latest, we will use the last.
  local sa_token_secret_template='{{range .items}}{{if eq .type "kubernetes.io/service-account-token"}}{{if eq "heapster" (index .metadata.annotations "kubernetes.io/service-account.name")}}{{.data.token}}
{{end}}{{end}}{{end}}'
  local failure="false"
  local nodes_active="false"
  local output=""

  # check that the heapster SA exists and we can get its token
  if ! output=$(oc get secret --sort-by=metadata.resourceVersion --template="$sa_token_secret_template" 2>&1); then
    echo "Error getting heapster service account token; is the master running and are credentials working? Error from oc get secrets follows:"
    echo -n "$output"
    return 1
  elif [[ -z "${output:-}" ]]; then
    echo "Could not find heapster service account token in $project; does it exist?"
    return 1
  fi
  local token=$(echo -e "$output" | tail -1 | base64 -d)
  # set up a config context using the heapster account and most recent token
  oc config set-credentials heapster-account \
    --token="$token" >& /dev/null
  oc config set-context heapster-context \
    --cluster=deployer-master \
    --user=heapster-account \
    --namespace="${project}" >& /dev/null

  # get the list of nodes and test access to them
  if ! output=$(oc --context=heapster-context get nodes --template "$node_detailed_template" 2>&1 ); then
    echo "Could not retrieve node list; does the heapster service account have cluster-reader?"
    echo "You can use 'oadm policy add-cluster-role-to-user' to add this role if needed."
    echo "Error from oc get nodes follows:"
    echo -n "$output"
    return 1
  else
    echo -e "$output" | while IFS= read -r node_line; do
      local node=( ${node_line:-} )
      [ "${#node[@]}" -eq 0 ] && continue
      local name="${node[0]}"
      local ip="${node[1]:-}"
      local ready="${node[2]:-}"
      if [ "${ready:-}" != "Ready" ]; then
        echo "Node ${name} is not ready; skipping."
        continue
      fi
      nodes_active="true"
      # expected response from /stats is a 301 to /stats/
      output=$(curl -fsSo /dev/null --stderr - --connect-timeout 2 --cacert "$master_ca" "https://${ip}:10250/stats") || {
        local rc=$?
        failure=true
        echo "FAIL: unable to reach node ${name} for stats. Is the node functional?"
        case $rc in # if curl's message needs interpretation
        51)
	    echo "The node kubelet cert was not valid for ${ip}:10250."
	    echo "Node kubelet certs generated by older versions may not be valid for the node IP."
	    echo "You most likely need to regenerate the node kubelet cert and distribute it to the node."
	    ;;
        60)
	    echo "The master CA cert did not validate the node kubelet cert."
	    echo "You most likely need to regenerate the node kubelet cert and distribute it to the node."
	    ;;
        esac
        echo "See the error from 'curl https://${ip}:10250/stats' below for details:"
        echo -e "$output"
        continue
      }
      local query='{"containerName":"/", "num_stats":1, "subcontainers": true}'
      if ! output=$(curl -fsSo /dev/null --stderr - --connect-timeout 2 --cacert "$master_ca" -H "Authorization: Bearer $token" -X POST -d "$query" https://${ip}:10250/stats/container); then
        failure=true
        echo "FAIL: heapster is unable to collect metrics from node ${name}"
        echo "See the error from 'curl https://${ip}:10250/stats/container' below for details:"
        echo -e "$output"
        continue
      fi
      continue
      # sadly, the following dead code requires cluster-admin and can't be done by the heapster SA at this time
      if ! output=$(curl -fsSo /dev/null --stderr - --connect-timeout 2 --cacert "$master_ca" -H "Authorization: Bearer $token" -X GET ${master_url}/api/v1/proxy/namespaces/${project}/services/https:heapster:/api/v1/model/metrics); then
        failure=true
        echo "FAIL: unable to collect stats via the API proxy for node ${name}; this will prevent horizontal pod autoscaling."
        echo "See the error from 'curl ${master_url}/api/v1/proxy' below for details:"
        echo "$cmd"
        echo -e "$output"
        continue
      fi
    done
  fi
  if [ "$nodes_active" = "true" ]; then
    echo "No nodes are registered; deployment will not be useful without nodes."
    return 1
  fi
  [ "$failure" = "true" ] && return 1
  echo "ok"
  return 0
}

function check_exists() {
  local output object="$1"
  shift
  if ! output=$(oc get "$object" "$@" 2>&1); then
    echo "Error running oc get $object:"
    echo -e "$output"
    echo "The $object API object must exist for a valid deployment."
    return 1
  elif [ -z "${output:-}" ]; then
    echo "oc get $object did not return any of the expected objects."
    echo "The correct $object API object(s) must exist for a valid deployment."
    return 1
  fi
  echo -e "$output"
  return 0
}

function validate_deployed_project() {
  # check the project is openshift-infra
  if [ "$project" != openshift-infra ]; then
    echo "Metrics should be deployed in the openshift-infra project in order to be"
    echo "available to the horizontal pod autoscaler. Metrics can run successfully"
    echo "in project $project but will not enable the autoscaler to work."
  fi
  return 0
}

function test_deployed_accounts() {
  # test that secrets and service accounts exist
  local object missing=false objects=(secret/heapster-secrets serviceaccount/heapster)
  [ -z "${HEAPSTER_STANDALONE:-}" ] && objects+=( secret/{hawkular-metrics-secrets,hawkular-metrics-certificate,hawkular-metrics-account,hawkular-cassandra-secrets,hawkular-cassandra-certificate} serviceaccount/{hawkular,cassandra} )
  for object in "${objects[@]}"; do
    if ! output=$(check_exists "$object"); then
      missing=true
      echo -e "$output"
    fi
  done
  [ "$missing" = true ] && return 1
  return 0
}

function test_deployed_pvcs() {
  # test the PVC(s) exist and are bound; if not, abort tests beyond this as they would be noise; missing PVCs block everything
  if [ -z "${HEAPSTER_STANDALONE:-}" -a "$use_persistent_storage" = "true" ]; then
    local template='{{range .items}}{{println .metadata.name " " .status.phase}}{{end}}'
    # check that the PVCs exist and are bound; if not, retry briefly before failing
    local i line output unbound=()
    for ((i=0; i<=60; i++)); do
      if ! output=$(check_exists persistentvolumeclaim --selector=metrics-infra=hawkular-cassandra --template="$template"); then
        echo -e "$output"
        echo "The metrics deployment requires a PVC for each Cassandra pod and will not run."
        return 1
      fi
      unbound=()
      while IFS= read -r line; do
        line=( ${line:-} ) # name, phase for each pvc
        [ "${#line[@]}" -eq 0 ] && continue
        [ "${line[1]}" != Bound ] && unbound+=( "${line[0]}" )
      done <<< "$output"
      [ "${#unbound[*]}" -eq 0 ] && break
      sleep 1
    done
    if [ "${#unbound[*]}" -ne 0 ]; then
      echo "The following required PVCs have not been bound to a PhysicalVolume:"
      echo "  ${unbound[@]}"
      echo "The corresponding Cassandra instances will not run without a bound PVC."
      echo "Please create satisfying PhysicalVolumes to enable this deployment."
      return 1
    fi
  fi
  return 0
}

# helper function - based on params, which ReplicationControllers are expected to exist
function get_expected_rcs() {
  local i
  echo heapster
  if [ -z "${HEAPSTER_STANDALONE:-}" ]; then
    echo hawkular-metrics
    for i in $(seq 1 $cassandra_nodes); do echo "hawkular-cassandra-$i"; done
  fi
}
 
# test the expected RCs exist and have the right number of replicas.
function test_deployed_rcs() {
  local template='{{range .items}}{{println .metadata.name " " .spec.replicas}}{{end}}'
  local i line output repc rc_broken 
  # get all metrics RCs
  if ! output=$(check_exists replicationcontroller --selector=metrics-infra --template="$template"); then
    echo -e "$output"
    echo "The metrics replication controllers are missing. Please re-deploy metrics."
    return 1
  fi
  # read the RCs found into a hash of name => #replicas
  local -A found_rcs=()
  while IFS=$'\n' read -r line; do
    line=( ${line:-} ) # name, replicas for each RC
    [ "${#line[@]}" -eq 0 ] && continue
    found_rcs["${line[0]}"]="${line[1]}"
  done <<< "$output"
  # compare to what we expect to see.
  for repc in $(get_expected_rcs); do
    if ! test "${found_rcs[$repc]+set}"; then
      rc_broken=true
      echo "ReplicationController $repc should exist but does not. Please re-deploy metrics."
      continue
    fi
    case "${found_rcs[$repc]}" in
      0)
        rc_broken=true
        echo "ReplicationController $repc should have 1 replica but has none. Please scale it up to 1."
        ;;
      1)
        ;; # 1 replica is fine
      *)
        # hawkular-metrics frontend can be scaled as desired; nothing else should be > 1
        if [ "$repc" != "hawkular-metrics" ]; then
          rc_broken=true
          echo "ReplicationController $repc should not have more than 1 replica. Please scale it down to 1."
        fi
        ;;
    esac
  done
  [ "${rc_broken:-}" ] && return 1
  return 0
}

# Test the related pods exist and are running. If they're not running and ready,
# look at events to see if we can figure out why.
function test_deployed_pods() {
  local events_output pods_output line repc
  # first get all pods related to metrics
  local pods_template='{{range .items}}{{print .metadata.name " " .metadata.labels.name " " .status.phase}}{{range .status.conditions}}{{if eq .type "Ready"}} {{.status}}{{end}}{{end}}{{println}}{{end}}'
  local -A expected_rcs=()
  for repc in $(get_expected_rcs); do expected_rcs["$repc"]=1; done
  if ! pods_output=$(check_exists pod --selector=metrics-infra --template="$pods_template"); then
    echo -e "$pods_output"
    echo "The metrics pods are missing. Please re-deploy metrics." # this would be weird
    return 1
  fi
  # now we get available events so that we can refer to them when looking at pods.
  # there is no way to scope our oc get to just events we care about, so get them all.
  # the template only prints out events that are related to a pod.
  local events_template='{{range .items}}{{if and (eq .involvedObject.kind "Pod") (or (eq .reason "Failed") (eq .reason "FailedScheduling")) }}{{.involvedObject.name}} {{.reason}} {{.metadata.name}}
{{end}}{{end}}
'
  if ! events_output=$(oc get events --sort-by=.metadata.resourceVersion --template="$events_template"); then
    echo "Error while getting project events:"
    echo -e "$pods_output"
    return 1
  fi
  local -A failed_event=() failed_schedule=()
  while IFS=$'\n' read -r line; do
    line=( ${line:-} ) # pod, reason, event name for each event
    [ "${#line[@]}" -eq 0 ] && continue
    local pod_name="${line[0]}"
    local reason="${line[1]}"
    local event_name="${line[2]}"
    [ "$reason" = Failed ] && failed_event["$pod_name"]="$event_name"
    [ "$reason" = FailedScheduling ] && failed_schedule["$pod_name"]="$event_name"
  done <<< "$events_output"
  #
  # now process the pods with events as background
  local pending=false broken=false
  while IFS=$'\n' read -r line; do
    line=( ${line:-} ) # name, label, phase for each pod
    [ "${#line[@]}" -eq 0 ] && continue
    local name="${line[0]}"
    local label="${line[1]}"
    local phase="${line[2]}"
    local ready="${line[3]}"
    test "${expected_rcs[$label]+set}" || continue # not from a known rc
    case "$phase" in
      Running)
        [ "$ready" = True ] && continue # doing fine; else:
        echo "Pod $name from ReplicationController $label is running but not marked ready."
        echo "This is most often due to either startup latency or crashing for lack of other services."
        echo "It should resolve over time; if not, check the pod logs to see what is going wrong."
        echo "  * * * * "
        pending=true
        ;;
      Pending)
        # find out why it's pending
        if test "${failed_schedule[$name]+set}"; then
          broken=true
          echo "ERROR: Pod $name from ReplicationController $label could not be scheduled (placed on a node)."
          echo "This is most often due to a faulty nodeSelector or lack of node availability."
          echo "There was an event for this pod with the following message:"
          oc get event/"${failed_schedule[$name]}" --template='{{println .message}}' 2>&1
          echo "  * * * * "
        elif test "${failed_event[$name]+set}"; then
          broken=true
          echo "Pod $name from ReplicationController $label specified an image that cannot be pulled."
          echo "ERROR: This is most often due to the image name being wrong or the docker registry being unavailable."
          echo "Ensure that you used the correct IMAGE_PREFIX and IMAGE_VERSION with the deployment."
          echo "There was an event for this pod with the following message:"
          oc get event/"${failed_event[$name]}" --template='{{println .message}}' 2>&1
          echo "  * * * * "
        else
          echo "Pod $name from ReplicationController $label is in a Pending state."
          echo "This is most often due to waiting for the container image to pull and should eventually resolve."
          echo "  * * * * "
          pending=true
        fi
        ;;
      *)
        broken=true
        echo "ERROR: Pod $name from ReplicationController $label is in a $phase state, which is not normal."
        ;;
    esac
  done <<< "$pods_output"
  [ "$broken" = true ] && return 1
  [ "$pending" = true ] && return 2
  return 0
}

# Test the services exist and have endpoints;
# test the service names are resolvable via DNS
function test_deployed_services() {
  local output line svc rc=0 expected_svcs=(heapster)
  [ -z "${HEAPSTER_STANDALONE:-}" ] && expected_svcs+=(hawkular-metrics hawkular-cassandra hawkular-cassandra-nodes)
  # test the services exist and names resolve
  if ! output=$(check_exists services --selector=metrics-infra --template='{{range .items}}{{println .metadata.name}}{{end}}' 2>&1); then
      echo "There was an error retrieving metrics services:"
      echo -e "$output"
      return 1
  fi
  local -A found_svcs=()
  while IFS=$'\n' read -r line; do found_svcs["$line"]=true; done <<< "$output"
  for svc in "${expected_svcs[@]}"; do
    if [ "${found_svcs[$svc]}" != true ]; then
      echo "'$svc' service does not exist. This is essential for metrics operation. You may need to redeploy metrics."
      rc=1
    elif [ "$svc" = hawkular-cassandra-nodes ]; then :
      # (exclude hawkular-cassandra-nodes from DNS test at this point; if it is broken and has no active endpoints and thus no IPs,
      # the DNS test will fail. Instead we would like to know that it has no active endpoints which we test next.
    elif ! output=$(dig $svc.$project.svc.cluster.local. ${SKYNDS_SERVER:-} +short 2>&1) || [ -z "${output:-}" ]; then
      echo "Could not resolve '$svc' service domain $svc.$project.svc.cluster.local."
      echo "This is essential for metrics operation. Please check that cluster DNS is working in pods."
      rc=1
    fi
  done
  [ "$rc" = 0 ] || return $rc # at least one service non-functional, no need for further testing here

  # now we want to test that the endpoints on services are populated. they should be, because if we got here,
  # then previous tests indicated the pods were running. but it's one more thing that could go wrong.
  local template='{{range .items}}{{.metadata.name}}{{range .subsets}}{{range .addresses}} {{.ip}}{{end}}{{end}}{{println}}{{end}}'
  if ! output=$(check_exists endpoints --selector=metrics-infra --template="$template"); then
    echo "There was an error retrieving metrics service endpoints:"
    echo -e "$output"
    return 1
  fi
  while IFS=$'\n' read -r line; do
    line=( ${line:-} )
    [ "${#line[@]}" -eq 0 ] && continue
    local name="${line[0]}"
    local ips=("${line[@]:1}") # shift name off, IPs remain
    if [ "${#ips[*]}" -eq 0 ]; then
      echo " * * * * *"
      echo "There are no active endpoints for service '$name'. This will prevent metrics operation."
      echo "This is strange because previous validations indicated the pod(s) for this service are running."
      echo "It may help to scale the corresponding ReplicationController(s) down and up again to repopulate endpoints."
      rc=1
    elif [[ $name = *cassandra* ]] && [ "${#ips[*]}" -ne "$cassandra_nodes" ]; then
      echo " * * * * *"
      echo "There are an incorrect number of active endpoints for service '$name'."
      echo "There are ${#ips[*]} and there should be $cassandra_nodes. This may complicate metrics operation."
      echo "This is strange because previous validations indicated the pod(s) for this service are running."
      rc=1
    fi
  done <<< "$output"
  [ "$rc" = 0 ] || return $rc # at least one endpoint set not right, no need for further tests

  # finally, since endpoints came up solid, make sure the cassandra nodes service resolves.
  [ -z "${HEAPSTER_STANDALONE:-}" ] &&  if ! output=$(dig hawkular-cassandra-nodes.$project.svc.cluster.local ${SKYNDS_SERVER:-} +short 2>&1) || [ -z "${output:-}" ]; then
    echo "Could not resolve 'hawkular-cassandra-nodes' service."
    echo "This is essential for metrics operation. Please check that cluster DNS is working in pods."
    rc=1
  fi
  return $rc
}

function bail_on_tls() {
  echo "error on retrieving hawkular-metrics route TLS $1:"
  echo -e "$2"
}

# for reencrypt type external route, test that its values are valid TLS entities, that its cert has the right name, 
# and that it has a CA that validates the backend.
function test_reencrypt_route() {
  local name="$1"
  local rc=0 secret_cert
  # check external cert has right hostname
  local cert=$(oc get route/hawkular-metrics --template='{{.spec.tls.certificate}}' 2>&1) || { bail_on_tls certificate "$cert"; return 1; }
  if [ "$cert" = "" ]; then
    : # TODO if the cert is empty, the fallback is the router cert, which is more complicated to examine
  elif ! output=$(echo -e "$cert" | openssl x509 -noout -text 2>&1); then
    echo ---
    echo "The hawkular-metrics route certificate is not valid; there was an error while processing it:"
    echo -e "$output"
    rc=1
  elif ! $(echo -e "$output" | grep -q "\(Subject: CN=$name\$\|DNS:$name\(,\|\$\)\)"); then
    echo ---
    echo "The hawkular-metrics route certificate does not include the host '$name', so browsers will consider it invalid."
    rc=1
  fi
  # validate server key
  local key=$(oc get route/hawkular-metrics --template='{{.spec.tls.key}}' 2>&1) || { bail_on_tls key "$key"; return 1; }
  if [ "$key" != "" ] && ! output=$(echo -e "$key" | openssl pkey -noout 2>&1); then
    echo ---
    echo "The hawkular-metrics route key is not valid; there was an error while processing it:"
    echo -e "$output"
    rc=1
  fi
  # test that the dest ca cert validates the internal hawkular-metrics cert from its secret.
  # dest ca is required for reencrypt, and we assume the secret exists from previous tests.
  local dest_ca=$(oc get route/hawkular-metrics --template='{{.spec.tls.destinationCACertificate}}' 2>&1) ||  { bail_on_tls destinationCACertificate "$dest_ca"; return 1; }
  # note: following mess is because we want the error output from the first failure, not a pipeline
  if secret_cert=$(oc get secret/hawkular-metrics-certificate --template='{{index .data "hawkular-metrics.certificate"}}' 2>&1) && \
    [[ $secret_cert != "" ]] && \
    secret_cert=$(echo -e "$secret_cert" | base64 -d | keytool -printcert -rfc 2>&1); then :
  else
    echo ---
    echo "There was an error while retrieving the hawkular-metrics internal server certificate:"
    [ -n "${secret_cert:-}" ] && echo -e "$secret_cert" || echo "The certificate is empty."
    echo "Cannot test this certificate for validity."
    return 1
  fi
  echo -e "$dest_ca" > $dir/test-hawkular-metrics.ca
  echo -e "$secret_cert" > $dir/test-hawkular-metrics.crt
  if ! output=$(echo -e "$secret_cert" | openssl verify -CAfile $dir/test-hawkular-metrics.ca 2>&1); then
    echo ---
    echo "There was an error while validating the internal hawkular-metrics certificate against the route destination CA:"
    echo -e "$output"
    echo "This will prevent proper functioning of the route."
    rc=1
  fi
  return $rc
}

# test the route exists and is properly configured
function test_deployed_route() {
  [ -n "${HEAPSTER_STANDALONE:-}" ] && return 0 # no hawkular, no need for route
  # note: template cycles through all ingress statuses looking for any that are admitted. one active ingress is enough.
  local rc=0 output template='{{.spec.host}} {{.spec.tls.termination}} {{range .status.ingress}}{{range .conditions}}{{if and (eq .type "Admitted") (eq .status "True")}}True {{end}}{{end}}{{end}}'
  if ! output=$(check_exists route/hawkular-metrics --template="$template"); then
    echo -e "$output"
    echo "The hawkular-metrics route is missing or broken. This should have been deployed with metrics."
    return 1
  fi
  output=($output) # hostname, tls termination type, admission condition
  local name="${output[0]}"
  local tls="${output[1]}"
  local admitted="${output[2]:-False}"
  # if the route doesn't have the right condition, complain
  if [ "$admitted" != True ]; then
    echo "The hawkular-metrics route is not active."
    echo "This often means that the route has already been created (likely in another project) and this one is newer."
    echo "It can also mean that no router has been deployed."
    oc get route/hawkular-metrics --template='{{range .status.ingress}}{{range .conditions}}{{println .reason ":" .message}}{{end}}{{end}}' 2>&1
    rc=1
  fi
  case "$tls" in
    passthrough) # nothing to check
      ;;
    reencrypt)
      test_reencrypt_route "$name" || rc=1
      ;;
    *)
      echo "Invalid TLS termination type for hawkular-metrics route: $tls"
      echo "You may need to re-create the route or redeploy metrics."
      rc=1
      ;;
  esac
  return $rc
}

function validate_deployment_artifacts() {
  local func rc=0 output
  for func in test_deployed_accounts test_deployed_pvcs test_deployed_rcs test_deployed_pods test_deployed_services test_deployed_route; do
    output=$($func) || {
      rc=$?
      echo -e "$output"
      break # each test is a precondition for the next to have much meaning
    }
  done
  [ "$rc" -eq 0 ] && echo "ok"
  return $rc
}

function validate_deployment() {
  set -e
  set +x

  echo =========================
  echo VALIDATING THE DEPLOYMENT
  local success=() failure=false output func rc
  for func in validate_nodes_accessible validate_deployment_artifacts validate_deployed_project; do
    while echo "--- $func ---"; do
      if output="$($func 2>&1)"; then
        success+=("$func: $output")
        break
      else
        rc=$?
        case $rc in
          1) # invalid
            echo ======== ERROR =========
            echo "$func: "
            echo -e "$output"
            echo ========================
            failure=true
            break
            ;;
          2) # retry
            echo ======== RETRY =========
            echo "$func: "
            echo -e "$output"
            echo "Will retry in 5 seconds."
            sleep 5
            echo ========================
            ;;
          *)
            echo ======== ERROR =========
            echo "$func: "
            echo -e "$output"'\n'"unexpected return code: $rc"
            echo ========================
            failure=true
            break
            ;;
        esac
      fi
    done
  done

  echo
  if [[ $failure = true ]]; then
    echo "VALIDATION FAILED"
    exit 255
  fi

  echo "VALIDATION SUCCEEDED"
  for win in "${success[@]}"; do echo $win; done
}
