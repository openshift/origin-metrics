#!/bin/bash/

set -o errexit
set -o nounset
set -o pipefail

SOURCE_ROOT=$(dirname "${BASH_SOURCE}")/../..

TESTSUITE_STARTTIME=$(date +%s)
STARTTIME=$(date +%s)
SEPARATOR="================================================================================"


red=`tput setaf 1`
green=`tput setaf 2`
orange=`tput setaf 166`
reset=`tput sgr0`

debug=${debug:-false}
for args in "$@"
do
  case $args in
    --debug)
      debug=true
      ;;
  esac
done

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
