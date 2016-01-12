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
ENV CASSANDRA_VERSION="2.2.1" \
    HAWKULAR_METRICS_VERSION="0.8.0.Final" \
    CASSANDRA_HOME="/opt/apache-cassandra" \
    HOME="/home/cassandra" \
    MAX_HEAP_SIZE="512M" \
    HEAP_NEWSIZE="100M" \
    PATH="/opt/apache-cassandra/bin:$PATH" \
    CASSANDRA_NODES_SERVICE_NAME="hawkular-cassandra-nodes"

# Become the root user to be able to install and setup Cassandra under /opt
USER root

# Copy the Cassandra binary to the /opt directory
RUN cd /opt; \
    curl -LO https://archive.apache.org/dist/cassandra/$CASSANDRA_VERSION/apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz && \
    tar xzf apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz && \
    rm apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz && \
    ln -s apache-cassandra-$CASSANDRA_VERSION apache-cassandra

# Copy our version of the cassandra configuration file over to the filesystem
COPY cassandra.yaml /opt/apache-cassandra/conf/cassandra.yaml

# Copy the jar containing the kubernetes away jar
#COPY cassandra-seed-provider.jar /opt/apache-cassandra/lib/
RUN cd $CASSANDRA_HOME/lib/ && \
    curl -Lo cassandra-seed-provider.jar https://origin-repository.jboss.org/nexus/service/local/artifact/maven/content?r=public\&g=org.hawkular.metrics\&a=cassandra-seed-provider\&e=jar\&v=${HAWKULAR_METRICS_VERSION}

# Copy across the scripts
COPY cassandra-docker.sh \
     cassandra-docker-ready.sh \
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

CMD ["/opt/apache-cassandra/bin/cassandra-docker.sh", "--seed_provider_classname=org.hawkular.openshift.cassandra.OpenshiftSeedProvider" ,"--cluster_name=hawkular-metrics"]
