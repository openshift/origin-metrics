#!/bin/bash
SOURCE_ROOT=$(dirname "${BASH_SOURCE}")/..

source $SOURCE_ROOT/hack/tests/common.sh

continue=false
build=true
skipTests=false
for args in "$@"
do
  case $args in
    --skipBuild)
      build=false
      ;;
    --skipTests)
      skipTests=true
      ;;
    --continue)
      continue=true
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
  oc new-project $TEST_PROJECT > /dev/null
  Info
}

function test.build {
  Info
  Info "Building new images"
  sh $SOURCE_ROOT/hack/build-images.sh --no-cache
  Info "finished building images"
}

function test.testBuild {
  Info
  Info "Building new test images"
  sh $SOURCE_ROOT/hack/build-images.sh --prefix=testing/ --version=test
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
        out=$?

        test.cleanup

        if [ $out -ne 0 ]; then
                Error "Test failed"
        else
                Info "Test Succeeded"
        fi
        echo

        ENDTIME=$(date +%s)

        Info "Exiting. Origin-Metrics tests took took $(($ENDTIME - $STARTTIME)) seconds"
        exit $out
}


trap cleanup SIGINT SIGTERM EXIT

#Build the components
if [ "$build" = true ]; then
  test.build
  test.testBuild
fi

test.setup

#Run the tests
if [ "$skipTests" = false ]; then
  $SOURCE_ROOT/hack/tests/test_default_deploy.sh $@
fi

if [ "$continue" = true ]; then
  Info "The tests are completed. Press ctrl-c to end the tests and perform a clean-up."
  while : 
  do
    sleep 10
  done
fi

test.cleanup
