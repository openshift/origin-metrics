#!/bin/bash
TEST_SOURCE=${BASH_SOURCE}
TEST_DIR=$(dirname "${BASH_SOURCE}")

function tests.setup {
  #initial setup required for all test scenarios
  oc create -f $SOURCE_ROOT/metrics-deployer-setup.yaml &> /dev/null || true
  oadm policy add-role-to-user edit system:serviceaccount:${TEST_PROJECT}:metrics-deployer
  oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:${TEST_PROJECT}:heapster
}

function tests.teardown {
  oc delete -f $SOURCE_ROOT/metrics-deployer-setup.yaml &> /dev/null || true
  #clean up required after the tests have run.
  oadm policy remove-role-from-user edit system:serviceaccount:${TEST_PROJECT}:metrics-deployer
  oadm policy remove-cluster-role-from-user cluster-reader system:serviceaccount:${TEST_PROJECT}:heapster
}

function checkDeployer {
  Info "Checking the deployer."

  DEPLOYER_START=$(date +%s)

  deployer_pod=`oc get pods | grep -i metrics-deployer`

  pods=`oc get pods | grep -i metrics-deployer` || true

  while read -r pod; do
   name=`echo $pod | awk '{print $1}'`
   state=`echo $pod | awk '{print $3}'`
   if [[ $state == "ContainerCreating" ]] || [[ $state == "Pending" ]]; then
     podName=$name
     break
   fi
  done <<< "$pods"

  if [[ -z ${podName-} ]]; then
    Fail "No deployer pod currently being deployed"
  fi

  while : 
  do
    if [[ $(($(date +%s) - $DEPLOYER_START)) -ge $timeout ]]; then
      Fail "Deployer Pod took longer than the timeout of $timeout seconds"
    fi

    deployer_pod=`oc get pods | grep -i metrics-deployer`
    deployer_status=`echo $deployer_pod | awk '{print $3}'`

    Debug "The current status of the deployer:$deployer_status"


    if [ -z "$deployer_pod" ] || [[ $deployer_status == "Failed" ]] || [[ $deployer_status == "Error" ]]; then
      oc logs $deployer_pod
      Fail "Deployer Pod was not deployed. `echo $deployer_pod | awk '{print $3}'`"
    fi

    if [[ $deployer_status == "Terminating" ]] || [[ $deployer_status == "Completed" ]]; then
      Info "The deployer was deployed in $(($(date +%s) - $DEPLOYER_START)) seconds."
      return
    fi

    sleep 1
  done
}


function checkMetrics {
  token=`oc whoami -t`
  if [ -n "${1:-}" ]; then
   hawkularIp=$1
  else 
   hawkularIp=`oc get svc | grep -i hawkular-metrics | awk '{print $2}'`
  fi
  
  CHECK_TIME=$(date +%s)
  while : ; do
    if [[ $(($(date +%s) - $CHECK_TIME)) -ge $timeout ]]; then
      Fail "Could not access the Hawkular Metrics status endpoint after $timeout seconds. Test failed."
    fi

    # Check that we can get the Hawkular Metrics status page at least
    status=`curl --insecure -L -s -o /dev/null -w "%{http_code}" -X GET https://${hawkularIp}/hawkular/metrics/status || true`
    if [[ ! $? -eq 0 ]] || [[ ! $status -eq 200 ]]; then
      Info "Could not access the Hawkular Status Endpoint. Trying again."
    else
      break
    fi
  done

  # Check if we get any metrics
  CHECK_TIME=$(date +%s)
  while : ; do
     if [[ $(($(date +%s) - $CHECK_TIME)) -ge $timeout ]]; then
      Fail "Could not get any metrics after $timeout seconds. Test failed."
    fi

    status=`curl --insecure -L -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" -H "Hawkular-tenant: $TEST_PROJECT" -X GET https://${hawkularIp}/hawkular/metrics/metrics || true`
    if [[ $status -eq 200 ]]; then
      metrics=`curl --insecure -s -H "Authorization: Bearer $token" -H "Hawkular-tenant: $TEST_PROJECT" -X GET https://${hawkularIp}/hawkular/metrics/metrics`
      if [[ ! -z "$metrics" ]]; then
        Info "Could receive metrics from Hawkular Metrics"
        break
      fi
    fi

    Debug "Tried to access metrics for project $TEST_PROJECT but got response of $status. Waiting for metrics to populate"
    sleep 1
  done

  # Check if we get specific metrics data
  CHECK_TIME=$(date +%s)
  while : ; do

     if [[ $(($(date +%s) - $CHECK_TIME)) -ge $timeout ]]; then
      Fail "Could not get any metrics after $timeout seconds. Test failed."
    fi

    data=`curl --insecure -s -H "Authorization: Bearer $token" -H "Hawkular-tenant: $TEST_PROJECT" -X GET https://${hawkularIp}/hawkular/metrics/gauges/data?tags=group_id:heapster/memory/usage\&buckets=1  | python -m json.tool | grep -i empty | awk '{print $2}' || true`

    if [[ $data == "false," ]]; then
      Info "Could resolve metrics data"
      break
    fi

    Debug "Tried to access container metric data for project $TEST_PROJECT but the empty parameter was $data. Waiting for metrics to populate"
    sleep 1
  done
}

function checkMetricsDirectly {
  hawkularIps=`oc describe service hawkular-metrics | grep -i Endpoints | awk '{print $2}' | tr ',' '\n'`
  for ip in $hawkularIps; do
    checkMetrics $ip
  done

}

function checkRoute {
  name=$1
  expectedHost=$2

  host=`oc get route | grep $name | awk '{print $2}'`

  if [[ $host != $expectedHost ]]; then
    Fail "Expected host of $expectedHost, received $host"
  fi
}

function checkImages {
  hawkularMetricsImage=`oc get rc hawkular-metrics --template='{{with index .spec.template.spec.containers 0}}{{println .image}}{{end}}'`
  cassandraImage=`oc get rc hawkular-cassandra-1 --template='{{with index .spec.template.spec.containers 0}}{{println .image}}{{end}}'`
  heapsterImage=`oc get rc heapster --template='{{with index .spec.template.spec.containers 0}}{{println .image}}{{end}}'`

  expected="${image_prefix}metrics-hawkular-metrics:${image_version}"
  if [[ $hawkularMetricsImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$hawkularMetricsImage'"
  fi
  expected="${image_prefix}metrics-cassandra:${image_version}"
  if [[ $cassandraImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$cassandraImage'"
  fi
  expected="${image_prefix}metrics-heapster:${image_version}"
  if [[ $heapsterImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$heapsterImage'"
  fi
}

function test.DefaultInstall {
  undeployAll
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null

  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated 
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1 
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics
  checkImages
}

function undeployAll {
  UNDEPLOY_START=$(date +%s) 

  oc delete all --selector=metrics-infra  --ignore-not-found=true
  oc delete secrets --selector=metrics-infra --ignore-not-found=true
  oc delete sa --selector=metrics-infra --ignore-not-found=true
  oc delete templates --selector=metrics-infra --ignore-not-found=true
  oc delete secrets metrics-deployer --ignore-not-found=true

  while : 
  do
    if [[ $(($(date +%s) - $UNDEPLOY_START)) -ge $timeout ]]; then
      Fail "Undeploy took longer than the timeout of $timeout seconds"
    fi
    
    all=`oc get all --selector=metrics-infra`
    templates=`oc get templates --selector=metrics-infra`    
    sa=`oc get sa --selector=metrics-infra`
    secrets=`oc get secrets --selector=metrics-infra`
    secrets_deployer=`oc get secrets metrics-deployer  &> /dev/null || true`
    
    if [[ -z $all ]] && [[ -z $templates ]] && [[ -z $sa ]] && [[ -z $secrets ]] && [[ -z $secrets_deployer ]]; then
      break
    fi

    Debug "Waiting for all components to be undeployed."

    sleep 1
  done
}

function checkTerminated {
  CHECK_START=$(date +%s)

  while :
  do
    if [[ $(($(date +%s) - $CHECK_START)) -ge $timeout ]]; then
      Fail "Terminating pods took longer than the timeout of $timeout seconds"
    fi

    terminatingPods=`oc get pods | grep -i terminating` || true
    if [[ -z $terminatingPods ]]; then
      break
    fi

    Debug "Waiting for all pods to terminate $terminatingPods"
    sleep 1

  done
}


function test.Redeploy {

  undeployAll
  Info "Deploying the Default setup so that we can check if a redeploy works"
  test.DefaultInstall

  Info "Checking Redeployment"

  oc delete pod -l metrics-infra=deployer

  redeployTime=$(date +%s)
  Info "About to redeploy the components with REDEPLOY=true"
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false,REDEPLOY=true | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics

  local hawkularMetricsPodName=$(oc get pods | grep -i hawkular-metrics | awk '{print $1}')
  local cassandraPodName=$(oc get pods | grep -i cassandra | awk '{print $1}')
  local heapsterPodName=$(oc get pods | grep -i heapster | awk '{print $1}')

  oc delete pod -l metrics-infra=deployer

  Info "About to redeploy the components with MODE=redeploy"
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false,MODE=redeploy | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated

  if [[ $hawkularMetricsPodName == $(oc get pods | grep -i hawkular-metrics | awk '{print $1}') ]] ||
     [[ $cassandraPodName == $(oc get pods | grep -i cassandra | awk '{print $1}') ]] ||
     [[ $heapsterPodName == $(oc get pods | grep -i heapster | awk '{print $1}') ]]; then
     Fail "The pods were not restarted."
  fi

  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics

}

function test.Refresh {
  undeployAll
  Info "Deploying the Default setup so that we can check if a refresh works"
  test.DefaultInstall

  Info "Checking Refresh"

  local hawkularMetricsPodName=$(oc get pods | grep -i hawkular-metrics | awk '{print $1}')
  local cassandraPodName=$(oc get pods | grep -i cassandra | awk '{print $1}')
  local heapsterPodName=$(oc get pods | grep -i heapster | awk '{print $1}')

  oc delete pod -l metrics-infra=deployer 

  Info "About to redeploy the components"
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false,MODE=refresh | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated

  if [[ $hawkularMetricsPodName == $(oc get pods | grep -i hawkular-metrics | awk '{print $1}') ]] ||
     [[ $cassandraPodName == $(oc get pods | grep -i cassandra | awk '{print $1}') ]] ||
     [[ $heapsterPodName == $(oc get pods | grep -i heapster | awk '{print $1}') ]]; then
     Fail "The pods were not restarted."
  fi

  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics

}

function test.Remove {
  undeployAll
  Info "Deploying the Default setup so that we can check that MODE=remove functionality"
  test.DefaultInstall

  oc delete pod -l metrics-infra=deployer

  Info "Checking remove mode"
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false,MODE=remove | oc create -f - &> /dev/null

  CHECK_TIME=$(date +%s)
  while : ; do
    if [[ $(($(date +%s) - $CHECK_TIME)) -ge $timeout ]]; then
      Fail "Not all components were stopped after $timeout seconds. Test failed."
    fi

    deployer_pod=`oc get pods | grep -i metrics-deployer || true`
    deployer_status=`echo $deployer_pod | awk '{print $3}'`

    Debug "The current status of the deployer:$deployer_status"
 
    if [[ $(oc get all,sa,templates,secrets --selector=metrics-infra) == "" ]]; then
     Info "All components were removed after $(($(date +%s) - $CHECK_TIME)) seconds."
      return 
    fi

    sleep 1
  done
}

function checkCassandraState {
  name=$1
  nodes=$2
  
  statuses=`oc exec $(oc get pods | grep -i $name | awk '{print $1}') nodetool status hawkular_metrics | tail -n+6 | awk '{print $1}' | head -n -1`

  count=`echo "$statuses" | wc -l`
  if [[ ! count -eq $nodes ]]; then
      Fail "Expecting only ${nodes} Cassandra nodes to be in the node list, found ${count}."
  fi

  for status in $statuses; do
    if [[ $status != "UN" ]]; then
      Fail "The status of the Cassandra nodes is not UN (up and normal) but was ${status}"
    fi

  done

}

function test.CassandraScale { 
  undeployAll
  Info "Checking if we can start multiple Cassandra Nodes at start and then scale up or down."
  Debug "Creating a new empty secret to be used"
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false,CASSANDRA_NODES=2 | oc create -f - &> /dev/null

  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 2
  checkDeployment "Hawkular-Metrics" 1 true
  checkDeployment "Heapster" 1 true
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkCassandraState "hawkular-cassandra-1" 2
  checkMetrics

  #manually add in a new node using the template
  Info "About to add a new Cassandra node using the hawkular-cassandra-node-emptydir template"
  oc process hawkular-cassandra-node-emptydir -v "IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},NODE=3" | oc create -f - 
  checkDeployment "Cassandra" 3
  checkCassandraState "hawkular-cassandra-1" 3
  checkMetrics

  #remove the second cassandra node
  Info "About to remove a Cassandra node and check that the Cassandra cluster scales down"
  oc exec `oc get pods | grep -i hawkular-cassandra-2 | awk '{print $1}'` nodetool decommission 
  oc delete rc hawkular-cassandra-2 &> /dev/null
  checkDeployment "Cassandra" 2
  checkCassandraState "hawkular-cassandra-1" 2
  checkMetrics 
}

function test.HawkularMetricsScale {
  undeployAll
  Info "Checking if we can start multiple Hawkular Metrics Nodes"
  Debug "Creating a new empty secret to be used"
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null

  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics
  checkMetricsDirectly

  Debug "Scaling up the Hawkular Metrics containers using the ReplicationController"
  oc scale rc hawkular-metrics --replicas=3
  checkDeployment "Hawkular-Metrics" 3
  checkMetrics
  checkMetricsDirectly

  Debug "Scaling down the Hawkular Metrics containers using the ReplicationController" 
  oc scale rc hawkular-metrics --replicas=2
  checkDeployment "Hawkular-Metrics" 2
  checkMetrics
  checkMetricsDirectly
}

function test.HawkularMetricsFailedStart {
  undeployAll
  Info "Checking that Hawkular Metrics can be stopped if started in an invalid state"
  Debug "Creating a new empty secret to be used"
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null
  
  checkDeployer
  checkTerminated
  
  #Deleting all the deployed artifacts
  oc delete all --selector=metrics-infra --ignore-not-found=true 
 
  #Deploying just Hawkular Metrics without Cassandra, this should be a failure condition
  oc process hawkular-metrics -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version}| oc create -f - &> /dev/null

  START=$(date +%s)
  while : ; do
   #Don't use the default timeout, the preset timeout for the failure needs to be this high
   if [[ $(($(date +%s) - $START)) -ge 360 ]]; then
      Fail "The metrics pod took longer than the timeout of 360 seconds"
   fi

   restarts=`oc get pods | grep -i hawkular-metrics| awk '{print $4}'`
 
   if [[ $restarts == "1" ]]; then
      Info "The Hawkular Metrics pod could be restarted."
      break
   fi

   Debug "The Hawkular Metrics pod has not yet been restarted. Waiting. This can take a while"
   sleep 1
  done

  #Delete all the deployed artifacts
  oc delete all --selector=metrics-infra --ignore-not-found=true  
  checkTerminated
}

function testBasicDeploy {
  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null

  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics
  checkImages
}

function test.HawkularMetricsCustomCertificate {
  undeployAll
  
  Info "Checking that everything can be properly started with a custom Hawkular Metrics certificate" 
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/hawkular/hawkular.pem &> /dev/null

  testBasicDeploy
}

function test.HawkularMetricsCustomCertificateWithCA {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate with a custom CA certificate"
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/hawkular/hawkular-noca.pem hawkular-metrics-ca.cert=$SOURCE_ROOT/hack/keys/signer.ca &> /dev/null

  testBasicDeploy
}

function test.hawkularMetricsWildcardCertificate {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate that contains a wildcard"
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/hawkularWildCard/hawkularWildCard.pem &> /dev/null

  testBasicDeploy
}

function test.hawkularMetricsWildcardCertificateWithCA {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate that contains a wildcard"
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/hawkularWildCard/hawkularWildCard.pem hawkular-metrics-ca.cert=$SOURCE_ROOT/hack/keys/signer.ca &> /dev/null

  testBasicDeploy
}

function test.HawkularMetricsInvalidCertificateSkipPreflight {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate that contains a wildcard"
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/hawkularWildCard/hawkularWildCard.pem hawkular-metrics-ca.cert=$SOURCE_ROOT/hack/keys/signer.ca &> /dev/null

  oc process -f $template -v IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version},HAWKULAR_METRICS_HOSTNAME=mymetrics.hawkular.org,USE_PERSISTENT_STORAGE=false,IGNORE_PREFLIGHT=true | oc create -f - &> /dev/null

  # The deployer will throw an error with post-deployment checks (since the certificate is invalid for the hostname)
  #  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "mymetrics.hawkular.org"
  checkMetrics
  checkImages
}

function test.HawkularMetricsCustomCertificateIntermediateCA {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate, when using an intermediary CA."
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/intermediary_ca/hawkular-metrics.pem hawkular-metrics-ca.cert=$SOURCE_ROOT/hack/keys/intermediary_ca/ca-chain.pem &> /dev/null

  testBasicDeploy
}

source $TEST_DIR/base.sh
