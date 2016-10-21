#!/bin/python
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

import os
import json
import urllib2

hawkularEndpointPort = os.environ.get("HAWKULAR_METRICS_ENDPOINT_PORT")
statusURL = "http://localhost:" + hawkularEndpointPort  + "/hawkular/metrics/status"

uptime = os.popen("ps -eo comm,etimes | grep -i standalone.sh | awk '{print $2}'").read()

try:
  # need to set a timeout, the default is to never timeout.
  response = urllib2.urlopen(statusURL, timeout=5)
  statusCode = response.getcode();
  # if the status is 200, then continue
  if (statusCode == 200):
    responseHTML = response.read() 
    jsonResponse = json.loads(responseHTML)
    # if the metrics service is started then we are good
    if (jsonResponse["MetricsService"] == "STARTED"):
      print "The MetricsService is in the STARTED state and is available."
      exit(0)
    elif (jsonResponse["MetricsService"] == "FAILED"):
      print "The MetricsService is in a FAILED state. Aborting"
      exit(1)
except Exception as e:
  print "Failed to access the status endpoint : %s." % e

if int(uptime) < 300:
  print "Hawkular metrics has only been running for " + uptime + " seconds not aborting yet."
  exit(0)
else:
  print "Hawkular metrics has been running for " + uptime + " seconds. Aborting"
  exit(1)
