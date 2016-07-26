#!/bin/bash/

set -o errexit
set -o nounset
set -o pipefail

SOURCE_ROOT=$(dirname "${BASH_SOURCE}")/../..

TESTSUITE_STARTTIME=$(date +%s)
STARTTIME=$(date +%s)
SEPARATOR="================================================================================"


[ ! -t 1 -o ! "$TERM" ] && TERM=dumb
export TERM
red=`tput setaf 1 || true`
green=`tput setaf 2 || true`
orange=`tput setaf 166 || true`
reset=`tput sgr0 || true`

function Error {
  echo ${red}[ERROR] $@${reset}
}

function Fail {
  echo ${red}[ERROR] $@${reset}
  exit 1
}

function Warn {
  echo ${orange}[WARN] $@${reset}
}

function Success {
  echo ${green}[INFO] $@${reset}
}

function Info {
  echo ${reset}[INFO] $@${reset}
}

function Debug {
  if [ "$debug" = true ]; then
    echo ${reset}[DEBUG] $1${reset}
  fi
}
