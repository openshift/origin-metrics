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
ENV HAWKULAR_METRICS_ENDPOINT_PORT="8080" \
    HAWKULAR_METRICS_VERSION="0.15.0.Final" \
    HAWKULAR_METRICS_DIRECTORY="/opt/hawkular" \
    HAWKULAR_METRICS_SCRIPT_DIRECTORY="/opt/hawkular/scripts/"

# The http and https ports
EXPOSE 8080 8444

# Get and copy the hawkular metrics war to the deployment directory
#COPY hawkular-metrics-api-rest-openshift.war $JBOSS_HOME/standalone/deployments/hawkular-metrics-api-jaxrs.war
RUN cd $JBOSS_HOME/standalone/deployments/ && \
    curl -Lo hawkular-metrics-api-jaxrs.war https://origin-repository.jboss.org/nexus/service/local/artifact/maven/content?r=public\&g=org.hawkular.metrics\&a=hawkular-metrics-api-jaxrs-openshift\&e=war\&v=${HAWKULAR_METRICS_VERSION}

# Copy the scripts
COPY hawkular-metrics-readiness.py \
     hawkular-metrics-liveness.py \
     hawkular-metrics-wrapper.sh \
     $HAWKULAR_METRICS_SCRIPT_DIRECTORY

# Overwrite the welcome-content to display a more appropriate status page
COPY welcome-content $JBOSS_HOME/welcome-content/

# Overwrite the default Standalone.xml file with one that activates the HTTPS endpoint
COPY standalone.xml $JBOSS_HOME/standalone/configuration/standalone.xml

# Change the permissions so that the user running the image can start up Hawkular Metrics
USER root
RUN chmod -R 777 /opt
USER jboss

CMD $HAWKULAR_METRICS_SCRIPT_DIRECTORY/hawkular-metrics-wrapper.sh -b 0.0.0.0 -bmanagement 0.0.0.0 -Dhawkular-metrics.cassandra-nodes=hawkular-cassandra
