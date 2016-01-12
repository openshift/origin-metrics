#!/bin/bash

START_TIME=$(date +%s)

#the timeout in seconds
TIMEOUT=120

#the name of the heapster process
HEAPSTER_PROCESS="heapster"

while : ;do

  if [[ $(($(date +%s) - $START_TIME)) -ge $TIMEOUT ]]; then
    echo "Heapster post-start check could not be completed after $TIMEOUT seconds, aborting."
    exit 1
  fi

  pgrep -x $HEAPSTER_PROCESS
  response=$?
  if [[ $response -eq 0 ]]; then
    exit 0
  fi

done
