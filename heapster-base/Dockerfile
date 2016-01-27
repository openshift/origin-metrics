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

# Heapster Docker Base Image
FROM centos:centos7

# The image is maintained by the Hawkular Metrics team
MAINTAINER Hawkular Metrics <hawkular-dev@lists.jboss.org>

EXPOSE 8082

ENV HEAPSTER_COMMIT=af4752e

COPY 0001-Fix-nil-pointer-reference-panic-in-kube_nodes.patch /tmp/

RUN yum install -y -q go git wget make patch && \
    yum clean all && \
    export GOPATH=/tmp/gopath && \
    export PATH=$PATH:$GOPATH/bin && \
    mkdir -p $GOPATH && \
    cd $GOPATH && \
    go get -d k8s.io/heapster && \
    cd src/k8s.io/heapster && \
    git checkout $HEAPSTER_COMMIT && \
    patch sources/kube_nodes.go < /tmp/0001-Fix-nil-pointer-reference-panic-in-kube_nodes.patch && \
    make && \
    cp heapster /opt && \
    rm -rf $GOPATH && \
    yum remove -y -q go git wget make
    
ENV PATH=$PATH:/opt

ENTRYPOINT ["/opt/heapster"]
