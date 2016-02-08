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

# Hawkular-Metrics Cassandra Docker Image

# Image based off of the jboss base image with JDK8
FROM jboss/base-jdk:8

# The image is maintained by the Hawkular Metrics team
MAINTAINER Hawkular Metrics <hawkular-dev@lists.jboss.org>

# Cassandra exposed ports: CQL, thrift, tcp, ssl
EXPOSE 9042 9160 7000 7001

# The Cassandra version
ENV CASSANDRA_VERSION="2.2.4" \
    CASSANDRA_HOME="/opt/apache-cassandra" \
    HOME="/home/cassandra" \
    MAX_HEAP_SIZE="512M" \
    HEAP_NEWSIZE="100M" \
    PATH="/opt/apache-cassandra/bin:$PATH" \
    CASSANDRA_NODES_SERVICE_NAME="hawkular-cassandra-nodes"

# Become the root user to be able to install and setup Cassandra under /opt
USER root

#
RUN yum install -y -q bind-utils && \
    yum clean all

COPY apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz.md5 \
     /tmp

# Copy the Cassandra binary to the /opt directory
RUN cd /opt; \
    curl -LO https://archive.apache.org/dist/cassandra/$CASSANDRA_VERSION/apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz && \
    if [ "$(md5sum apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz | awk '{print $1}')" != "$(cat /tmp/apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz.md5)" ]; then echo "The Cassandra binary does not match the expected md5sum"; exit 1; fi && \
    tar xzf apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz && \
    rm apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz && \
    ln -s apache-cassandra-$CASSANDRA_VERSION apache-cassandra

# Copy our version of the cassandra configuration file over to the filesystem
COPY cassandra.yaml.template /opt/apache-cassandra/conf/cassandra.yaml.template

# Copy across the scripts
COPY cassandra-docker.sh \
     cassandra-docker-ready.sh \
     gather-seeds.sh \
     /opt/apache-cassandra/bin/

# Create a 'Cassandra' user to own the directory and set it to be readable & writable by any user
RUN groupadd -r cassandra -g 312 && \
    useradd -u 313 -r -g cassandra -d /opt/apache-cassandra -s /sbin/nologin cassandra && \
    chown -R cassandra:cassandra /opt/apache-cassandra && \
    chmod -R go+rw /opt/apache-cassandra && \
    mkdir $HOME && \
    chown -R cassandra:cassandra $HOME && \
    chmod -R go+rw $HOME

USER 313

CMD /opt/apache-cassandra/bin/cassandra-docker.sh --seeds=${HOSTNAME}
