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

echo "STARTING WRAPPER"
echo "ARGS : %@"

# Set up the parameters to pass to EAP while removing the ones specific to the wrapper
heapster_args=

for args in "$@"
do
  echo "ARG $args"
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

  CHECK_COMMAND='curl --insecure -L -s -o /dev/null -w "%{http_code}" $ENDPOINT_CHECK'

  while : ; do
    STATUS_CODE=`eval $CHECK_COMMAND`
    CURL_STATUS=$?

    if [[ $CURL_STATUS -eq 6 || $CURL_STATUS -eq 7 || $STATUS_CODE -eq 200 ]]; then
      if [ $STATUS_CODE -eq 200 ]; then
        break
      fi
    else 
      echo "An error occured when trying to access $ENDPOINT_CHECK. Curl exit code $CURL_STATUS"
      exit 1
    fi
 
    echo "'$ENDPOINT_CHECK' is not accessible. Retrying."
 
    # Wait a second and then try again
    sleep 1;
    
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

echo HEAPSTER ARGS : $final_args

exec /heapster $final_args
