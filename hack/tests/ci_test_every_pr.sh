#!/bin/bash
#
# This script is run in conjunction with origin automated testing.
# It is intended to run from the openshift/origin/test/extended
# directory, and launched by `vagrant test-origin -e metrics`
#
# This scripts starts the OpenShift server with a default configuration.
# The OpenShift Docker registry and router are installed.
# It will run the metrics tests

set -o errexit
set -o nounset
set -o pipefail

STARTTIME=$(date +%s)
# assume this script is being run from openshift/origin-metrics/hack/tests, and
# origin is checked out in openshift/origin
OS_ROOT=${OS_ROOT:-$(dirname "${BASH_SOURCE}")/../../../origin}
# use absolute path
pushd $OS_ROOT
OS_ROOT=`pwd`
popd
GIT_URL=${GIT_URL:-https://github.com/openshift/origin-metrics}
GIT_BRANCH=${GIT_BRANCH:-master}
# assume this script is being run from openshift/origin-metrics/hack/tests
ORIGIN_METRICS_DIR=${ORIGIN_METRICS_DIR:-$(dirname "${BASH_SOURCE}")/../..}
# use absolute path
pushd $ORIGIN_METRICS_DIR
ORIGIN_METRICS_DIR=`pwd`
popd
USE_DEPLOYER=
USE_DEPLOYER_SCRIPT=
DEBUG_FAILURES=${DEBUG_FAILURES:-false}
USE_LOCAL_SOURCE=${USE_LOCAL_SOURCE:-false}
TEST_PERF=${TEST_PERF:-false}

# include all the origin test libs we need
for lib in "${OS_ROOT}"/hack/{util.sh,text.sh} \
           "${OS_ROOT}"/hack/lib/*.sh "${OS_ROOT}"/hack/lib/**/*.sh
do source "$lib"; done
os::log::stacktrace::install

os::util::environment::setup_time_vars

cd "${OS_ROOT}"

os::build::setup_env

os::test::junit::declare_suite_start 'origin-metrics'

function cleanup()
{
   echo ">>>>>>>>>>>> ENV VARIABLES <<<<<<<<<<<<<<<<<<"
   env | sort
   echo ">>>>>>>>>>>> END ENV VARIABLES <<<<<<<<<<<<<<"

    out=$?
    echo
    if [ $out -ne 0 ]; then echo "[FAIL] !!!!! Test Failed !!!!"
    else
        echo "[INFO] Test Succeeded"
    fi
    echo

    os::test::junit::declare_suite_end
    os::test::junit::reconcile_output
    if [ "$DEBUG_FAILURES" = "true" ] ; then
        echo debug failures
        sleep 54321 || echo debugging done - continuing
    fi
    cleanup_openshift
    echo "[INFO] Exiting at " `date`
    ENDTIME=$(date +%s); echo "$0 took $(($ENDTIME - $STARTTIME)) seconds"
    exit $out
}

trap "exit" INT TERM
trap "cleanup" EXIT

echo "[INFO] Starting metrics tests at " `date`

ensure_iptables_or_die
# override LOG_DIR and ARTIFACTS_DIR
export LOG_DIR=${LOG_DIR:-${TMPDIR:-/tmp}/origin-metrics/logs}
export ARTIFACT_DIR=${ARTIFACT_DIR:-${TMPDIR:-/tmp}/origin-metrics/artifacts}
os::util::environment::setup_all_server_vars "origin-metrics/"
os::util::environment::use_sudo
reset_tmp_dir

os::log::start_system_logger

configure_os_server
start_os_server

export KUBECONFIG="${ADMIN_KUBECONFIG}"

install_registry
wait_for_registry

######### metric specific code starts here ####################

os::cmd::expect_success 'oadm policy add-cluster-role-to-user cluster-admin metrics-admin'
os::cmd::expect_success 'oadm policy add-cluster-role-to-user cluster-admin metrics-admin'
os::cmd::expect_success 'oc login -u metrics-admin -p g1b315H'

"${ORIGIN_METRICS_DIR}/hack/e2e-tests.sh -x --test=test.DefaultInstall"

### finished tests ###


### END ###
