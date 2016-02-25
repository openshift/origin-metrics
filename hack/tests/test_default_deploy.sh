#!/bin/bash
TEST_SOURCE=${BASH_SOURCE}
TEST_DIR=$(dirname "${BASH_SOURCE}")

function tests.setup {
  #initial setup required for all test scenarios
  oc create -f $SOURCE_ROOT/metrics-deployer-setup.yaml &> /dev/null
  oadm policy add-role-to-user edit system:serviceaccount:${TEST_PROJECT}:metrics-deployer
  oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:${TEST_PROJECT}:heapster
}

function tests.teardown {
  #clean up required after the tests have run.
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
   if [[ $state == "Pending" ]]; then
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
  
  # Check that we can get the Hawkular Metrics status page at least
  status=`curl --insecure -L -s -o /dev/null -w "%{http_code}" -X GET https://${hawkularIp}/hawkular/metrics/status`
  if [[ ! $? -eq 0 ]] || [[ ! $status -eq 200 ]]; then
    Fail "Could not access the Hawkular Status Endpoint. Test failed."
  fi

  # Check if we get any metrics
  CHECK_TIME=$(date +%s)
  while : ; do
     if [[ $(($(date +%s) - $CHECK_START)) -ge $timeout ]]; then
      Fail "Could not get any metrics after $timeout seconds. Test failed."
    fi

    status=`curl --insecure -L -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" -H "Hawkular-tenant: $TEST_PROJECT" -X GET https://${hawkularIp}/hawkular/metrics/metrics`
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

     if [[ $(($(date +%s) - $CHECK_START)) -ge $timeout ]]; then
      Fail "Could not get any metrics after $timeout seconds. Test failed."
    fi

    data=`curl --insecure -s -H "Authorization: Bearer $token" -H "Hawkular-tenant: $TEST_PROJECT" -X GET https://${hawkularIp}/hawkular/metrics/gauges/data?tags=group_id:heapster/memory/usage\&buckets=1  | python -m json.tool | grep -i empty | awk '{print $2}'`

    if [[ $data == "false," ]]; then
      Info "Could resolve metrics data"
      break
    fi

    Debug "Tried to access metric data for project $TEST_PROJECT but got response of $data. Waiting for metrics to populate"
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

function test.DefaultInstall {
  undeployAll
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null

  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated 
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1 
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics

  hawkularMetricsImage=`oc get rc | grep -i Hawkular-Metrics | awk '{print $3}'`
  cassandraImage=`oc get rc | grep -i Cassandra | awk '{print $3}'`
  heapsterImage=`oc get rc | grep -i Heapster| awk '{print $3}'`

  expected="openshift/origin-metrics-hawkular-metrics:latest"
  if [[ $hawkularMetricsImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$hawkularMetricsImage'"
  fi
  expected="openshift/origin-metrics-cassandra:latest"
  if [[ $cassandraImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$cassandraImage'"
  fi
  expected="openshift/origin-metrics-heapster:latest"
  if [[ $heapsterImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$heapsterImage'"
  fi

}

function undeployAll {
  UNDEPLOY_START=$(date +%s) 

  oc delete all --selector=metrics-infra       &> /dev/null
  oc delete secrets --selector=metrics-infra   &> /dev/null
  oc delete sa --selector=metrics-infra        &> /dev/null
  oc delete templates --selector=metrics-infra &> /dev/null
  oc delete secrets metrics-deployer &> /dev/null || true

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

function checkTerminating {
  CHECK_START=$(date +%s)

  while :
  do
    if [[ $(($(date +%s) - $CHECK_START)) -ge 120 ]]; then
      Fail "No pods entered the terminating state when expected"
    fi

    terminatingPods=`oc get pods | grep -i terminating` || true
    if [[ -n $terminatingPods ]]; then
      break
    fi

    Debug "Waiting for all pods to start terminating $terminatingPods"
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

  redeployTime=$(date +%s)
  Info "About to redeploy the components"
  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false,REDEPLOY=true | oc create -f - &> /dev/null
  checkDeployer
  checkTerminating
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics
}

function test.Image {
  undeployAll
  Info "Checking the IMAGE_PREFIX and IMAGE_VERSION deployment parameters"
  Debug "Creating a new empty secret to be used"
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null
  Debug "Testing a deployment with the test tagged docker images"
  oc process -f $SOURCE_ROOT/metrics.yaml -v IMAGE_PREFIX=testing/,IMAGE_VERSION=test,HAWKULAR_METRICS_HOSTNAME=hm.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null

  checkDeployer
  checkTerminated 
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hm.example.com"
  checkMetrics

  hawkularMetricsImage=`oc get rc | grep -i Hawkular-Metrics | awk '{print $3}'`
  cassandraImage=`oc get rc | grep -i Cassandra | awk '{print $3}'`
  heapsterImage=`oc get rc | grep -i Heapster| awk '{print $3}'`

  expected="testing/metrics-hawkular-metrics:test"
  if [[ $hawkularMetricsImage != "testing/metrics-hawkular-metrics:test" ]]; then
    Fail "Expected the image version to be '$expected' was instead '$hawkularMetricsImage'"
  fi 
  expected="testing/metrics-cassandra:test"
  if [[ $cassandraImage != "testing/metrics-cassandra:test" ]]; then
    Fail "Expected the image version to be '$expected' was instead '$cassandraImage'"
  fi
  expected="testing/metrics-heapster:test"
  if [[ $heapsterImage != "testing/metrics-heapster:test" ]]; then
    Fail "Expected the image version to be '$expected' was instead '$heapsterImage'"
  fi
 
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
      Fail "The status of the Cassandra nodes is not UN (up and normal) but awas ${status}"
    fi

  done

}

function test.CassandraScale { 
  undeployAll
  Info "Checking if we can start multiple Cassandra Nodes at start and then scale up or down."
  Debug "Creating a new empty secret to be used"
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null
  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false,CASSANDRA_NODES=2 | oc create -f - &> /dev/null

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
  oc process hawkular-cassandra-node-emptydir -v "NODE=3" | oc create -f - &> /dev/null
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
  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null

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
  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null
  
  checkDeployer
  checkTerminated
  
  #Deleting all the deployed artifacts
  oc delete all --selector=metrics-infra &> /dev/null 
 
  #Deploying just Hawkular Metrics without Cassandra, this should be a failure condition
  oc process hawkular-metrics | oc create -f - &> /dev/null

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
  oc delete all --selector=metrics-infra &> /dev/null  
  checkTerminated
}

function testBasicDeploy {
  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null

  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics

  hawkularMetricsImage=`oc get rc | grep -i Hawkular-Metrics | awk '{print $3}'`
  cassandraImage=`oc get rc | grep -i Cassandra | awk '{print $3}'`
  heapsterImage=`oc get rc | grep -i Heapster| awk '{print $3}'`

  expected="openshift/origin-metrics-hawkular-metrics:latest"
  if [[ $hawkularMetricsImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$hawkularMetricsImage'"
  fi
  expected="openshift/origin-metrics-cassandra:latest"
  if [[ $cassandraImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$cassandraImage'"
  fi
  expected="openshift/origin-metrics-heapster:latest"
  if [[ $heapsterImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$heapsterImage'"
  fi
}

function test.HawkularMetricsCustomCertificate {
  undeployAll
  
  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate" 
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/hawkular.pem hawkular-metrics-ca.cert=$SOURCE_ROOT/hack/keys/signer.ca &> /dev/null

  testBasicDeploy
}

function test.HawkularMetricsCustomCertificateIntermediateCA {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate, when using an intermediary CA."
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/intermediary_ca/hawkular-metrics.pem hawkular-metrics-ca.cert=$SOURCE_ROOT/hack/keys/intermediary_ca/ca-chain.pem &> /dev/null

  testBasicDeploy
}

function test.CassandraCustomCertificate {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate"
  oc secrets new metrics-deployer hawkular-cassandra.pem=$SOURCE_ROOT/hack/keys/cassandra.pem hawkular-cassandra-ca.cert=$SOURCE_ROOT/hack/keys/signer.ca &> /dev/null
 
  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics

  hawkularMetricsImage=`oc get rc | grep -i Hawkular-Metrics | awk '{print $3}'`
  cassandraImage=`oc get rc | grep -i Cassandra | awk '{print $3}'`
  heapsterImage=`oc get rc | grep -i Heapster| awk '{print $3}'`

  expected="openshift/origin-metrics-hawkular-metrics:latest"
  if [[ $hawkularMetricsImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$hawkularMetricsImage'"
  fi
  expected="openshift/origin-metrics-cassandra:latest"
  if [[ $cassandraImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$cassandraImage'"
  fi
  expected="openshift/origin-metrics-heapster:latest"
  if [[ $heapsterImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$heapsterImage'"
  fi
}

function test.CustomCertificates {
  undeployAll

  Info "Checking that everything can be properly start with a custom Hawkular Metrics certificate"
  oc secrets new metrics-deployer hawkular-metrics.pem=$SOURCE_ROOT/hack/keys/hawkular.pem hawkular-metrics-ca.cert=$SOURCE_ROOT/hack/keys/signer.ca \
                                  hawkular-cassandra.pem=$SOURCE_ROOT/hack/keys/cassandra.pem hawkular-cassandra-ca.cert=$SOURCE_ROOT/hack/keys/signer.ca &> /dev/null

  oc process -f $SOURCE_ROOT/metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,USE_PERSISTENT_STORAGE=false | oc create -f -
  checkDeployer
  checkTerminated
  checkDeployment "Cassandra" 1
  checkDeployment "Hawkular-Metrics" 1
  checkDeployment "Heapster" 1
  checkCassandraState "hawkular-cassandra-1" 1
  checkRoute "hawkular-metrics" "hawkular-metrics.example.com"
  checkMetrics

  hawkularMetricsImage=`oc get rc | grep -i Hawkular-Metrics | awk '{print $3}'`
  cassandraImage=`oc get rc | grep -i Cassandra | awk '{print $3}'`
  heapsterImage=`oc get rc | grep -i Heapster | awk '{print $3}'`

  expected="openshift/origin-metrics-hawkular-metrics:latest"
  if [[ $hawkularMetricsImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$hawkularMetricsImage'"
  fi
  expected="openshift/origin-metrics-cassandra:latest"
  if [[ $cassandraImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$cassandraImage'"
  fi
  expected="openshift/origin-metrics-heapster:latest"
  if [[ $heapsterImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$heapsterImage'"
  fi
}


source $TEST_DIR/base.sh
