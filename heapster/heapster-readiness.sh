#!/bin/bash

#the name of the heapster process
HEAPSTER_PROCESS="heapster"

pgrep -x $HEAPSTER_PROCESS
response=$?
if [[ $response -eq 0 ]]; then
  echo "The heapster process has started and is now ready."
  exit 0
else
  echo "The heapster process is not yet started, it is waiting for the Hawkular Metrics to start."
  exit 1
fi
