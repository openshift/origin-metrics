#!/bin/bash
echo "About to call the nodetool drain command"
output=$(nodetool drain 2>&1)
if [ "$?" == 0 ]; then
  echo "Started : $(date)" > ${CASSANDRA_DATA_VOLUME}/.shutdown.drain
  echo $output >> ${CASSANDRA_DATA_VOLUME}/.shutdown.drain
  echo "Finished : $(date)" >> ${CASSANDRA_DATA_VOLUME}/.shutdown.drain
  echo "'nodetool drain' completed succesfully"
else
  echo "Started : $(date)" > ${CASSANDRA_DATA_VOLUME}/.shutdown.error.drain
  echo $output >> ${CASSANDRA_DATA_VOLUME}/.shutdown.error.drain
  echo "Finished : $(date)" >> ${CASSANDRA_DATA_VOLUME}/.shutdown.error.drain
  echo "'nodetool drain' failed: $output"
fi
