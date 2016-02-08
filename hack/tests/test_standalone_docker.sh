#!/bin/bash
TEST_SOURCE=${BASH_SOURCE}
TEST_DIR=$(dirname "${BASH_SOURCE}")

function tests.setup {
  #initial setup required for all test scenarios
  :
}

function tests.teardown {
  #clean up required after the tests have run.
  :
}

function test.Cassandra {
  undeploy "pod" "test-cassandra"

  oc create -f $TEST_DIR/default_cassandra_pod.yaml

  checkDeployment "test-cassandra" 1

  startTime=$(date +%s)

  while : ; do
    if [[ $(($(date +%s) - $startTime)) -ge $timeout ]]; then
      Fail "The test cassandra pod did not enter a UN state in $timeout seconds. Test failed."
    fi

    status=`oc exec test-cassandra nodetool status 2> /dev/null | tail -n+6 | awk '{print $1}' | head -n -1 || true` &> /dev/null

    if [[ $status == "UN" ]]; then
        break
    fi

    Debug "The current status is $status, waiting for a status of UN"
    sleep 1
  done

  oc delete pod test-cassandra
}

source $TEST_DIR/base.sh
