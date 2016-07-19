#!/bin/python
#
# Copyright 2016 Red Hat, Inc. and/or its affiliates
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
from hawkular import *

hwkpass = open('/client-secrets/hawkular-metrics.password').read().rstrip()
hwkuser = open('/client-secrets/hawkular-metrics.username').read().rstrip()

hawkularEndpointPort = os.environ.get("HAWKULAR_METRICS_ENDPOINT_PORT")

c = HawkularMetricsClient(tenant_id='default', username=hwkuser, password=hwkpass, port=hawkularEndpointPort)
