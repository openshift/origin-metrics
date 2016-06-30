#!/bin/bash
SOURCE_ROOT=$(dirname "${BASH_SOURCE}")/..

source $SOURCE_ROOT/hack/tests/common.sh

parse_args() {
  local tmp long
  long=cacheBuild,continue,selector:,skipBuild,skipTests,test:
  tmp=$(getopt --options x --long "$long" --name "$(basename "$0")" -- "$@") \
    || return 1
  eval set -- "$tmp"
  while :; do
    case "$1" in
      --cacheBuild) buildOpts=; shift;;
      --continue) continue=true; shift;;
      --selector) NODE_SELECTOR=$2; shift 2;;
      --skipBuild) build=false; shift;;
      --skipTests) skipTests=true; shift;;
      --test) test=$2; shift 2;;
      -x) set_x=-x; set -x; shift;;
      --) shift; break;;
    esac
  done
}

continue=
build=true
skipTests=false
buildOpts=--no-cache
test=
set_x=

parse_args "$@" || exit

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
  oc delete project $TEST_PROJECT > /dev/null || exit
  Info
  Info "The tests took $(($(date +%s) - $TEST_STARTTIME)) seconds"
  Info
}

function cleanup {
        out=$?

        trap test.cleanup SIGINT SIGTERM EXIT
        
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

        test.cleanup || exit

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
  for x in default_deploy standalone_docker heapster; do
    "$SOURCE_ROOT/hack/tests/test_$x.sh" \
      $set_x ${test:+--test "$test"} ${continue:+--continue}
  done
fi
