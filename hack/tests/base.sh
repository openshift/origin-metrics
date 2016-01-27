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

  for functionName in $functions; do
    if [[ $functionName == test.* ]]; then
      Info 
      Info "Starting Test Function $functionName"
      Info $SEPARATOR
      STARTTIME=$(date +%s)
      $functionName
      ENDTIME=$(date +%s)
      Info
      Success "Test $functionName took $(($ENDTIME - $STARTTIME)) seconds"
      Info 
    fi
  done
 
  tests_teardown
}

for args in "$@"
do
  case $args in
    --test=*)
      test="${args#*=}"
      ;;
  esac
done
if [[ -z ${test-} ]]; then
 tests.run
else
 export TEST_PROJECT=`oc project --short` 
 $test
fi
