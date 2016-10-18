#!/bin/bash
#
# Copyright 2014-2015 Red Hat, Inc. and/or its affiliates
# and other contributors as indicated by the @author tags.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Check to see if we need to perform an upgrade on the data or not
if [ "$(ls -A ${CASSANDRA_DATA_VOLUME})" ]; then
  echo "The Cassandra datavolume (${CASSANDRA_DATA_VOLUME}) is not empty. Checking if an update is required."
  
  if [ -f ${CASSANDRA_DATA_VOLUME}/.cassandra.version ]; then
    previousVersion=$(cat ${CASSANDRA_DATA_VOLUME}/.cassandra.version)
    echo "The previous version of Cassandra was $previousVersion. The current version is $CASSANDRA_VERSION"
    previousMajor=$(cut -d "." -f 1 <<< "$previousVersion")
    previousMinor=$(cut -d "." -f 2 <<< "$previousVersion")

    currentMajor=$(cut -d "." -f 1 <<< "$CASSANDRA_VERSION")
    currentMinor=$(cut -d "." -f 2 <<< "$CASSANDRA_VERSION")

    if (( ($currentMajor < $previousMajor) || (($currentMajor == $previousMajor) && ($currentMinor < $previousMinor)) )); then
       echo "Error: the current cassandra version ($CASSANDRA_VERSION) is older than the version last used ($previousVersion). Cannot preform update."
       exit 1
    fi

    if [ "${previousMajor}.${previousMinor}" == "${currentMajor}.${currentMinor}" ]; then
      echo "The major and minor versions match. No extra update steps required"
      update=false
    else
      echo "We are currently running a newer version of Cassandra, an extra update step is required."
      update=true
    fi
  else
    # if no ${CASSANDRA_DATA_VOLUME}/.cassandra.version exists, then its an update from an old version, most likely 2.2.7
    echo "We are running a newer version of Cassandra and need to upgrade the existing data."
    update=true
  fi

  if $update; then
    echo "Waiting for Cassandra to enter the up and normal state"
    while : ;do
      # Get the machines IP address from hosts
      HOSTIP=`cat /etc/hosts | grep $HOSTNAME | awk '{print $1}' | head -n 1`

      # Get the status of this machine from the Cassandra nodetool
      STATUS=`nodetool status | grep $HOSTIP | awk '{print $1}'`

      if [ ${STATUS:-""} = "" ]; then
        echo "Could not get the Cassandra status. This may mean that the Cassandra instance is not up yet. Will try again"
      fi

      # Once the status is Up and Normal, then we are ready
      if [ ${STATUS} = "UN" ]; then
        echo "Cassandra is in the up and normal state. It is now ready."
        break
      else
        echo "Cassandra not in the up and normal state. Current state is $STATUS"
      fi

      #wait 1 second and try again
      sleep 1
    done
    
    echo "About to upgrade Cassandra's data"
    output=$(nodetool upgradesstables 2>&1)
    if [ "$?" == 0 ]; then
      echo "Started : $(date)" > ${CASSANDRA_DATA_VOLUME}/.upgrade.upgradesstables
      echo $output >> ${CASSANDRA_DATA_VOLUME}/.upgrade.upgradesstables
      echo "Finished : $(date)" >> ${CASSANDRA_DATA_VOLUME}/.upgrade.upgradesstables
      echo "'nodetool upgradesstables' completed successfully"
    else
      echo "Started : $(date)" > ${CASSANDRA_DATA_VOLUME}/.update.error.upgradesstables
      echo $output >> ${CASSANDRA_DATA_VOLUME}/.update.error.upgradesstables
      echo "Finished : $(date)" >> ${CASSANDRA_DATA_VOLUME}/.update.error.upgradesstables
      echo "'nodetool upgradesstables' failed: $output"
    fi
    echo "Upgrade completed"
  fi
else
  echo "There is no existing data to upgrade. Skipping upgrade process."
fi

# set the version flag to the current version of Cassandra
echo ${CASSANDRA_VERSION} > ${CASSANDRA_DATA_VOLUME}/.cassandra.version
