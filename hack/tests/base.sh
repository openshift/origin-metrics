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

  tests_setup

  functions=$(typeset -f | awk '/ \(\) $/ && !/^main / {print $1}')

  if [[ -n ${test-} ]] && [ `type -t $test`"" == 'function' ]; then
    runTest $test
  else
    for functionName in $functions; do
      if [[ $functionName == test.* ]]; then
        runTest $functionName
      fi
    done
  fi
 
  tests_teardown
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

for args in "$@"
do
  case $args in
    --test=*)
      test="${args#*=}"
      ;;
  esac
done

if [[ -z ${TEST_PROJECT-} ]]; then
  export TEST_PROJECT=`oc project --short`
fi
tests.run
