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

# Set up the parameters to pass to EAP while removing the ones specific to the wrapper
heapster_args=

for args in "$@"
do
  if [[ $args == --wrapper\.* ]]; then
    case $args in
      --wrapper.username_file=*)
        USERNAME_FILE="${args#*=}"
        ;;
      --wrapper.password_file=*)
        PASSWORD_FILE="${args#*=}"
        ;;
      --wrapper.allowed_users_file=*)
        ALLOWED_USERS_FILE="${args#*=}"
        ;;
      --wrapper.endpoint_check=*)
        ENDPOINT_CHECK="${args#*=}"
        ;;
    esac
  else
    heapster_args="$heapster_args $args"
  fi
done

if [ -n "$USERNAME_FILE" ]; then
   HEAPSTER_USERNAME=$(cat $USERNAME_FILE)
fi

if [ -n "$PASSWORD_FILE" ]; then
   HEAPSTER_PASSWORD=$(cat $PASSWORD_FILE)
fi

if [ -n "$ALLOWED_USERS_FILE" ]; then
   HEAPSTER_ALLOWED_USERS=$(cat $ALLOWED_USERS_FILE)
fi

if [ -n "$ENDPOINT_CHECK" ]; then
  echo "Endpoint Check in effect. Checking $ENDPOINT_CHECK";

  START_TIME=$(date +%s)
  
  CHECK_COMMAND='curl --insecure --max-time 10 --connect-timeout 10 -L -s -o /dev/null -w "%{http_code}" $ENDPOINT_CHECK'

  TIMEOUT=${STARTUP_TIMEOUT:-500}

  while : ; do
    if [[ $(($(date +%s) - $START_TIME)) -ge $TIMEOUT ]]; then
      echo "Endpoint check for '$ENDPOINT_CHECK' could not be established after $TIMEOUT seconds. Aborting"
      exit 1
    fi

    STATUS_CODE=`eval $CHECK_COMMAND`
    CURL_STATUS=$?

    if [ $STATUS_CODE -eq 200 ]; then
        echo "The endpoint check has successfully completed."
        break
    else 
      echo "Could not connect to $ENDPOINT_CHECK. Curl exit code: $CURL_STATUS. Status Code $STATUS_CODE"
    fi
 
    echo "'$ENDPOINT_CHECK' is not accessible [HTTP status code: $STATUS_CODE. Curl exit code $CURL_STATUS]. Retrying."
 
    # Wait a second and then try again
    sleep 1
    
  done

fi

final_args=

for arg in "$heapster_args"
do
  arg=${arg//\%username\%/$HEAPSTER_USERNAME}
  arg=${arg//\%password\%/$HEAPSTER_PASSWORD}
  arg=${arg//\%allowed_users\%/$HEAPSTER_ALLOWED_USERS}
  final_args="$final_args $arg"
done

echo Starting Heapster with the following arguments: $final_args

exec heapster $final_args
