#
# Copyright 2014-2017 Red Hat, Inc. and/or its affiliates
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

# Hawkular-Metrics Cassandra Cleaner Job Docker Image

FROM openshift/origin:latest

# The image is maintained by the Hawkular Metrics team
MAINTAINER Hawkular Metrics <hawkular-dev@lists.jboss.org>

# Environment variables exposed.
ENV PATH=$PATH:/usr/local/bin \
    HAWKULAR_NAMESPACE="openshift-infra" \
    CASSANDRA_CONTAINER_PREFIX="hawkular-cassandra" \
    PARTITION_THRESHOLD=157286400


ADD truncate-idx.sh /usr/local/bin/
# Become the root user to be able to install and setup Cassandra under /opt
USER root
RUN chmod +x /usr/local/bin/truncate-idx.sh

USER 1000

ENTRYPOINT [ "/usr/local/bin/truncate-idx.sh" ]
