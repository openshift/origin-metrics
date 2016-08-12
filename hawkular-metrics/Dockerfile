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

# Hawkular-Metrics DockerFile
#
# This dockerfile can be used to create a Hawkular-Metrics docker
# image to be run on Openshift.

FROM jboss/wildfly:10.0.0.Final

# The image is maintained by the Hawkular Metrics team
MAINTAINER Hawkular Metrics <hawkular-dev@lists.jboss.org>

#
# Version 0.17.0-20160602.155443-1 has a fix for https://github.com/openshift/origin-metrics/issues/134
ENV HAWKULAR_METRICS_ENDPOINT_PORT="8080" \
    HAWKULAR_METRICS_VERSION="0.18.2.Final" \
    HAWKULAR_METRICS_DIRECTORY="/opt/hawkular" \
    HAWKULAR_METRICS_SCRIPT_DIRECTORY="/opt/hawkular/scripts/"

ENV PATH=$PATH:$HAWKULAR_METRICS_SCRIPT_DIRECTORY

# The http and https ports
EXPOSE 8080 8444

# Get and copy the hawkular metrics war to the deployment directory
RUN cd $JBOSS_HOME/standalone/deployments/ && \
    curl -Lo hawkular-metrics-api-jaxrs.war https://origin-repository.jboss.org/nexus/service/local/artifact/maven/content?r=public\&g=org.hawkular.metrics\&a=hawkular-metrics-api-jaxrs-openshift\&e=war\&v=${HAWKULAR_METRICS_VERSION}

# Enable http2/spdy
# TODO: remove when we are running on JDK9 which will already have this support added
ENV ALPN_VERSION="8.1.7.v20160121" 
RUN curl -Lo $JBOSS_HOME/bin/alpn-boot-$ALPN_VERSION.jar http://central.maven.org/maven2/org/mortbay/jetty/alpn/alpn-boot/$ALPN_VERSION/alpn-boot-$ALPN_VERSION.jar && \
    echo 'JAVA_OPTS="$JAVA_OPTS' " -Xbootclasspath/p:$JBOSS_HOME/bin/alpn-boot-$ALPN_VERSION.jar" '"' >> $JBOSS_HOME/bin/standalone.conf

# Copy the scripts
COPY hawkular-metrics-readiness.py \
     hawkular-metrics-liveness.py \
     hawkular-metrics-wrapper.sh \
     hawkular-client-initialization.py \
     client \
     $HAWKULAR_METRICS_SCRIPT_DIRECTORY

# Overwrite the welcome-content to display a more appropriate status page
COPY welcome-content $JBOSS_HOME/welcome-content/

# Overwrite the default Standalone.xml file with one that activates the HTTPS endpoint
COPY standalone.xml $JBOSS_HOME/standalone/configuration/standalone.xml

# Overwrite the default logging.properties file
COPY logging.properties $JBOSS_HOME/standalone/configuration/logging.properties

# Install Hawkular-Metrics Python client, only available on EPEL
USER root
RUN yum -y install epel-release \
    && yum -y install python-pip \
    && yum clean all \
    && pip install --no-cache-dir 'hawkular-client==0.4.4'

# Change the permissions so that the user running the image can start up Hawkular Metrics
RUN chmod -R 777 /opt
USER 1000

CMD $HAWKULAR_METRICS_SCRIPT_DIRECTORY/hawkular-metrics-wrapper.sh -b 0.0.0.0 -bmanagement 0.0.0.0 -Dhawkular-metrics.cassandra-nodes=hawkular-cassandra
