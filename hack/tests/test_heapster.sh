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
#  oadm policy remove-role-from-user edit system:serviceaccount:${TEST_PROJECT}:metrics-deployer
#  oadm policy remove-cluster-role-from-user cluster-reader system:serviceaccount:${TEST_PROJECT}:heapster
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
      Fail "Deployer Pod was not deployed. `echo $deployer_pod | awk '{print $3}'`"
    fi

    if [[ $deployer_status == "Terminating" ]] || [[ $deployer_status == "Completed" ]]; then
      Info "The deployer was deployed in $(($(date +%s) - $DEPLOYER_START)) seconds."
      return
    fi

    sleep 1
  done
}

function checkImages {
  heapsterImage=`oc get rc heapster --template='{{with index .spec.template.spec.containers 0}}{{println .image}}{{end}}'`

  expected="${image_prefix}metrics-heapster:${image_version}"
  if [[ $heapsterImage != $expected ]]; then
    Fail "Expected the image version to be '$expected' was instead '$heapsterImage'"
  fi
}

function test.DefaultInstall {
  undeployAll
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null

  oc process -f $heapster_template -v IMAGE_PREFIX=${image_prefix} -v IMAGE_VERSION=${image_version} | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated 
  checkDeployment "Heapster" 1
  checkImages
  checkHeapsterAccess
}

function undeployAll {
  UNDEPLOY_START=$(date +%s) 

  oc delete all --selector=metrics-infra --ignore-not-found=true
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

function checkHeapsterAccess {
  server=`oc status | grep -i "on server" | awk '{print $6}'` #todo: find a better way to do this
  token=`oc whoami -t`
  status=`curl --insecure -L -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" -X GET ${server}/api/v1/proxy/namespaces/${TEST_PROJECT}/services/https:heapster:/api/v1/model/metrics`
  if [[ ! $? -eq 0 ]] || [[ ! $status -eq 200 ]]; then
    Fail "Could not access the Heapster Endpoint. Test failed."
  fi

  CHECK_TIME=$(date +%s)
  while : ; do
     if [[ $(($(date +%s) - $CHECK_START)) -ge $timeout ]]; then
      Fail "Could not get any metrics types from Heapster after $timeout seconds. Test failed."
    fi

    data=`curl --insecure -s -H "Authorization: Bearer $token" -X GET ${server}/api/v1/proxy/namespaces/${TEST_PROJECT}/services/https:heapster:/api/v1/model/metrics`
    if [[ $data != "[]" ]]; then
      Info "Metrics types could be accessed from the Heapster endpoint."
      break
    fi

    Debug "Could not receive metric types from the Heapster endpoint. Will try again"
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
  Info "About to redeploy the components"
  oc process -f $heapster_template -v IMAGE_PREFIX=${image_prefix} -v IMAGE_VERSION=${image_version} -v REDEPLOY=true | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated
  checkDeployment "Heapster" 1
  checkHeapsterAccess
}

function test.RedeployMode {
  undeployAll
  Info "Deploying the Default setup so that we can check if a redeploy works"
  test.DefaultInstall

  Info "Checking Redeployment"

  oc delete pod -l metrics-infra=deployer

  redeployTime=$(date +%s)
  Info "About to redeploy the components"
  oc process -f $heapster_template -v IMAGE_PREFIX=${image_prefix} -v IMAGE_VERSION=${image_version} -v MODE=redeploy | oc create -f - &> /dev/null
  checkDeployer
  checkTerminated
  checkDeployment "Heapster" 1
  checkHeapsterAccess
}

function test.BasicDeploy {
  undeployAll
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null
  oc process -f $heapster_template -v IMAGE_PREFIX=${image_prefix} -v IMAGE_VERSION=${image_version} | oc create -f - &> /dev/null

  checkDeployer
  checkTerminated
  checkDeployment "Heapster" 1
  checkImages
  checkHeapsterAccess
}

function test.DeployMode {
  undeployAll
  oc secrets new metrics-deployer nothing=/dev/null &> /dev/null
  oc process -f $heapster_template -v IMAGE_PREFIX=${image_prefix} -v IMAGE_VERSION=${image_version} -v MODE=deploy | oc create -f - &> /dev/null

  checkDeployer
  checkTerminated
  checkDeployment "Heapster" 1
  checkImages
  checkHeapsterAccess
}

source $TEST_DIR/base.sh
