#!/bin/bash
SOURCE_ROOT=$(dirname "${BASH_SOURCE}")/..

source $SOURCE_ROOT/hack/tests/common.sh

continue=false
build=true
skipTests=false
buildOpts=--no-cache

for args in "$@"
do
  case $args in
    --skipBuild)
      build=false
      ;;
    --cacheBuild)
      buildOpts=""
      ;;
    --skipTests)
      skipTests=true
      ;;
    --continue)
      continue=true
      ;;
    --selector=*)
      NODE_SELECTOR="${args#*=}"

      ;;
    -x)
      set -x
      ;;
  esac
done


Info $SEPARATOR
Info "Starting Origin-Metric end-to-end test"
Info
Info "Settings:"
Info "Base Directory: `realpath $SOURCE_ROOT`"
Info $SEPARATOR
Info

TEST_STARTTIME=$(date +%s)
export TEST_PROJECT=test-$(date +%s)

function test.setup {
  Info 
  Info "Creating test project $TEST_PROJECT"
  oadm new-project $TEST_PROJECT --node-selector="${NODE_SELECTOR:-}" > /dev/null
  oc project $TEST_PROJECT > /dev/null
  Info
}

function test.build {
  Info
  Info "Building new images"
  sh $SOURCE_ROOT/hack/build-images.sh $buildOpts
  Info "finished building images"
}

function test.cleanup {
  Info
  Info "Deleting test project $TEST_PROJECT"
  oc delete project $TEST_PROJECT > /dev/null
  Info
  Info "The tests took $(($(date +%s) - $TEST_STARTTIME)) seconds"
  Info
}

function cleanup {
        trap test.cleanup SIGINT SIGTERM EXIT
        out=$?
        
        if [ $out -ne 0 ]; then
                Error "Test failed"
        else
                Info "Test Succeeded"
        fi
        echo

        ENDTIME=$(date +%s)

        if [ "$continue" = true ]; then
          Info "The tests are completed. Press ctrl-c to end the tests and perform a clean-up."
          while : 
          do
            sleep 10
          done
        fi

        test.cleanup

        Info "Exiting. Origin-Metrics tests took took $(($ENDTIME - $STARTTIME)) seconds"
        exit $out
}


trap cleanup SIGINT SIGTERM EXIT

#Build the components
if [ "$build" = true ]; then
  test.build
fi

test.setup

#Run the tests
if [ "$skipTests" = false ]; then
  $SOURCE_ROOT/hack/tests/test_default_deploy.sh $@
  $SOURCE_ROOT/hack/tests/test_standalone_docker.sh $@
fi

cleanup
