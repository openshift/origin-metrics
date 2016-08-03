#!/bin/bash/

source $(dirname "${BASH_SOURCE}")/common.sh
source $(dirname "${BASH_SOURCE}")/test-base.sh

function cleanup {
        out=$?

        if [ $out -ne 0 ]; then
                Info
                Error $SEPARATOR
                Error "Test failed"
                Error $SEPARATOR
                Info
                tests_teardown
        else
                Info
                Success $SEPARATOR
                Success "Tests Succeeded"
                Success $SEPARATOR
                Info
        fi

        ENDTIME=$(date +%s)

        Info "Exiting. The tests took took $(($ENDTIME - $TESTSUITE_STARTTIME)) seconds"
        exit $out
}

function tests_setup {
  if functionExists tests.setup; then
    setupStart=$(date +%s) 
    Info "Performing test setup"
    Info $SEPARATOR
    tests.setup
    Info "Setup took $(($(date +%s) - $setupStart)) seconds"
  fi
}

function tests_teardown {
  if functionExists tests.teardown; then
    if [ "$continue" = true ]; then
      trap tests.teardown SIGINT SIGTERM EXIT
      Info "The tests are completed. Press ctrl-c to end the tests and perform a clean-up.."
      while : 
        do
          sleep 10
        done
    fi

      teardownStart=$(date +%s)
      Info "Performing test shutdown"
      Info $SEPARATOR
      tests.teardown
      Info "Teardown took $(($(date +%s) - $teardownStart)) seconds"
  fi
}

function functionExists {
  declare -f -F $1 > /dev/null
  return $?
}

trap cleanup SIGINT SIGTERM EXIT

function tests.run {
  Info $SEPARATOR
  Info "Running tests from $TEST_SOURCE" 
  Info $SEPARATOR
  Info

  if [[ -n ${test-} ]]; then
    if [ `type -t $test`"" == 'function' ]; then
      tests_setup
      runTest $test
      tests_teardown
    else
      Info "No tests named $test within the current test script. Skipping"
    fi
  else
    tests_setup

    functions=$(typeset -f | awk '/ \(\) $/ && !/^main / {print $1}')
    for functionName in $functions; do
      if [[ $functionName == test.* ]]; then
        runTest $functionName
      fi
    done
    tests_teardown
  fi
}

function runTest {
  functionName=$1
  
  Info
  Info "Starting Test Function $functionName"
  Info $SEPARATOR
  STARTTIME=$(date +%s)
  $functionName
  ENDTIME=$(date +%s)
  Info
  Success "Test $functionName took $(($ENDTIME - $STARTTIME)) seconds"
  Info
}

parse_args() {
  local tmp long
  long=continue,debug,heapster_template:,image_prefix:,image_version:,template:
  long=$long,test:,timeout:
  tmp=$(getopt --options x --long "$long" --name "$(basename "$0")" -- "$@") \
    || return 1
  eval set -- "$tmp"
  while :; do
    case "$1" in
      --continue) continue=true; shift;;
      --debug) debug=true; shift;;
      --heapster_template) heapster_template=$2; shift 2;;
      --image_prefix) image_prefix=$2; shift 2;;
      --image_version) image_version=$2; shift 2;;
      --template) template=$2; shift 2;;
      --test) test=$2; shift 2;;
      --timeout) timeout=$2; shift 2;;
      -x) set -x; shift;;
      --) shift; break;;
    esac
  done
}

continue=false
debug=false
timeout=240
template=$SOURCE_ROOT/metrics.yaml
heapster_template=$SOURCE_ROOT/metrics-heapster.yaml
image_prefix=openshift/origin-
image_version=latest
test=

parse_args "$@" || exit

if [[ -z ${TEST_PROJECT:-} ]]; then
  export TEST_PROJECT=`oc project --short`
fi
tests.run
