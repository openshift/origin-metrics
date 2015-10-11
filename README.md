# origin-metrics

**This document and its corresponding contianers are meant to run on [OpenShift Origin](https://github.com/openshift/origin), built from its current master branch. Metric gathering will not function properly on any currently released version, up to and including the latest v1.0.6.**

The following document will describe how to build, configure and install metric components for OpenShift.

The metric components will gather metrics for all containers and nodes across an entire OpenShift cluster. As such it needs to be performed by a cluster administrator.

## Overview

There are three main components to the metrics gathering:

#### Heapster

[Heapster](https://github.com/kubernetes/heapster) is the component which gathers the various metrics from the OpenShift cluster. It connects to each node in an OpenShift cluster and reads the kubelet's `/stats` endpoint to retrieve metrics.

It retrieves cpu and memory metrics for every container running in the cluster, across all namespaces. It also retrieves metrics for the node itself, the kubelet, and the docker daemon.

Heapster does not store metrics itself and requires sending the metrics to another component for storage. For this setup, the component which deals with historically saved metrics is Hawkular Metrics.

For more information about Heapster, please see https://github.com/kubernetes/heapster

#### Hawkular Metrics
[Hawkular Metrics](https://github.com/hawkular/hawkular-metrics/) is the metric storage engine from the [Hawkular](http://www.hawkular.org/) project. It provides means of creating, accessing and managing historically stored metrics via an easy to use json based REST interface.

Heapster sends the metrics it receives to Hawkular Metrics over the Hawkular Metric REST interface. Hawkular Metrics then stores the metrics into a Cassandra database.

For more information about Hawkular Metrics, please see https://github.com/hawkular/hawkular-metrics/

#### Cassandra

[Cassandra](http://cassandra.apache.org/) is the database used to store the gathered metrics.

For more information about Cassandra, please visit its website: http://cassandra.apache.org/

## Building the Docker Containers

The docker containers can be built using the `hack/build-images.sh` script.

	cd hack
	./build-images.sh --prefix=openshift/origin- --version=devel

Where the `--prefix` value is used to specify a prefix to the docker image and the `--version` value is used to specify the version tag for the resulting docker images.

For instance, as with the above command, a prefix of `openshift/origin-` and version `devel` will create the following docker images:

	openshift/origin-metrics-deployer
	openshift/origin-metrics-heapster
	openshift/origin-metrics-cassandra
	openshift/origin-metrics-hawkular-metrics
	
## Setting up your System

The Metrics components requires that OpenShift is properly installed and configured. How to properly install and configure OpenShift is beyond the scope of this document. Please see the [OpenShift documentation](https://docs.openshift.org/latest/welcome/index.html) on how to properly install and setup your system.

Please be aware of things such as firewall and selinux permission issues, as well as things like making sure that Openshift's dns server starts properly.

## Deploying

### Create a Metrics Project

To prevent unwanted components from accessing the metric's persistent volume claim, it is highly recommended to deploy all the metric components within their own project (eg metrics-infra). Management of the metric components is also easier if they are separated in their own project as well.

For the instructions presented here we are going to do so in a project named `metrics`.

To create a new project called `metrics` you will need to run the following command:

	oc new-project metrics

### Create the Deployer Service Account

A pod is used to setup, configure and deploy all the various metric components. This deployer pod is run under the `metrics-deployer` service account.

The `metrics-deployer` can be created from the `metrics-deployer-setup.yaml` configuration file. The following command will create the service account for you:

	oc create -f metrics-deployer-setup.yaml

### Service Account Permissions

Note: the following commands assumes you are running in the 'metric' project, if you are running in another project, your service account will need to be updated the service account accordingly. The format follows the following format  `system:serviceaccount:$PROJECT_NAME:$SERVICE_ACCOUNT_NAME`

#### Metrics Deployer Service Account

In order to deploy components within the project, the `metrics-deployer` service account needs to be granted the 'edit' permission.

This can be accomplished by running the following command:

	oadm policy add-role-to-user edit \
          system:serviceaccount:metrics:metrics-deployer


#### Heapster Service Account

The heapster component requires accessing the kubernetes node to find all the available nodes as well as accessing the `/stats` endpoint on each of those nodes. This means that the `heapster` service account which requires having the `cluster-reader` permission.

The following command will give the `heapster` service account the required permission:

	oadm policy add-cluster-role-to-user cluster-reader \
          system:serviceaccount:metrics:heapster


### Create the Hawkular Deployer Secret

In order to deploy the Hawkular deployer pod, a secret must first be created. These secrets allow an admin to specify their own ssl certificates instead of letting the deployer autogenerate self-signed ones. 

If you wish to let the deployer generate all the certificates for you, you will just need to create an empty secret:

	oc secrets new metrics-deployer nothing=/dev/null
	
If you wish to provide any of your own certificates, then you will need to specify the certificates that you wish to provide. Please see the [advanced configuration](docs/advanced_configuration.md#configuring-the-deployer) document for instructions in how to accomplish this.

### Deploying the Metrics Components

#### Persistent Storage

You can deploy the metrics components with or without persistent storage.

Running with persistent storage means that your metrics will be stored to a [persistent volume](https://docs.openshift.org/latest/architecture/additional_concepts/storage.html) and be able to survive a pod being restarted or recreated. This requires an admin to have setup and made available a persistent volume of sufficient size. Running with persistent storage is highly recommended if you require metric data to be guarded against data loss. Please see the [advanced configuration](docs/advanced_configuration.md#creating-persistent-storage) page for more information.

Running with non-persistent storage means that any stored metrics will be deleted when the pod is deleted or restarted. Metrics will still survive a container being restarted. It is much easier to run with non-persistent data, but with the tradeoff of potentially losing this metric data. Running with non-persistent data should only be done when data loss under certain situations is acceptable.

#### Deployer Template

To deploy the metric components, you will need to deploy the 'metrics' template.

You will need to use the same IMAGE_PREFIX and IMAGE_VERSION used to build the containers.

The only requires template parameter is `HAWKULAR_METRICS_HOSTNAME`. This specifies the hostname that hawkular metrics is going to be hosted under. This is used to generate the Hawkular Metrics certificate and is used for the host in the route configuration.

For the full list of deployer template options, please see the [advanced configuration](docs/advanced_configuration.md#deployer-template-options) page.

If you are using non-persistent data, the following command will deploy the metric components without requiring a persistent volume to be created before hand:

	oc process -f metrics.yaml -v \
	HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,IMAGE_PREFIX=openshift/origin-,IMAGE_VERSION=devel,USE_PERSISTENT_STORAGE=false \
	| oc create -f -
	
If you are using persistent data, the following command will deploy the metric components but requires a storage volume of sufficient size to be available:

	oc process -f metrics.yaml -v \
	HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,IMAGE_PREFIX=openshift/origin-,IMAGE_VERSION=devel,USE_PERSISTENT_STORAGE=true \
	| oc create -f -

### Cleanup

If you wish to undeploy and remove everything deployed by the deployer, the follow commands can be used:

	oc delete all --selector=metrics-infra
	oc delete secrets --selector=metrics-infra
	oc delete sa --selector=metrics-infra
	
Note: the persistent volume claim will not be deleted by the above command. If you wish to permanently delete the data in persistent storage you can run `oc delete pvc --selector=metrics-infa`

