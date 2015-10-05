# origin-metrics

TODO: write brief introduction here.

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

The Metrics components require a properly running OpenShift instances. How to properly install and configure OpenShift is beyond the scope of this document. Please see the OpenShift documentation on how to properly install and setup your system.

### Enabling the Read Only Kubelet Endpoint

Currently the kubelet endpoints are secured with certificate authentication and are not accessible to metric contianers. This is a known issue which is currently being worked on: https://github.com/openshift/origin/pull/4873 

Until this is properly fix in OpenShift, you will need to enable the RO endpoint for each of your nodes.

For each of your node's `node-config.yaml` you will need to run the following command to enable read only access:

	cat >> node-config.yaml << DONE
	kubeletArguments:
 	read-only-port:
 	- "10266"
	DONE

### Creating Persistent Storage

The Cassandra database stores its data to persistent storage. For each Cassandra node you deploy, you will need a persistent volume with sufficient data available. You do not need to directly manage peristent volume claims as the deployer and templates will take care of that for you.

Please see the [OpenShift documentation](https://docs.openshift.org/latest/architecture/additional_concepts/storage.html) for how to setup and configure persistent volumes.

For example, if you are using NFS as a persistent storage backend, the following command will generate the persistent volume for use in OpenShift:

oc create -f - <<API
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv01
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Recycle
  nfs:
    server: localhost
    path: /persistent_storage/pv01


## Deploying


### Create a Metrics Project

Although you can deploy the metrics components to any project, it is recommended to keep and manage all metric related entities in their own project.

For the instructions presented here we are going to do so in a project named 'metrics'

	oc new-project metrics

### Create the Deployer Service Account

We use a pod to setup and deploy the various components. This component is run under the 'metrics-deployer' service account.

	oc create -f - <<API
	apiVersion: v1
	kind: ServiceAccount
	metadata:
	  name: metrics-deployer
	secrets:
	- name: metrics-deployer
	API

### Granting the Deployer Service Account Permissions

In order to deploy components within the project, the 'metrics-deployer' service account needs to be granted the 'edit' permission

	openshift admin policy add-role-to-user edit \
          system:serviceaccount:metrics:metrics-deployer

Note: the above command assumes you are running in the 'metric' project, if you are running in another project, your service account will need to be updated to the right format: 'system:serviceaccount:$PROJECT_NAME:metrics-deployer'

### Create the Hawkular Deployer Secret

The Hawkular deployer pod can use a few optional secrets to configure how it deploys.

A secret is required to exist, even if its empty and is using defaults. To create the empty default secret:

	oc secrets new metrics-deployer nothing=/dev/null

TODO: add the other secret options here.

### Create the Heapster Service Account

The heapster component needs to with a 'hawkular' service account. 

        oc create -f - <<API
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: hawkular
        secrets:
        - name: hawkular
        API

### Granting the Heapster Service Account Permissions

The heapster service account needs to have cluster-reader permission in order to fetch and read the metrics coming from the OpenShift server.

TODO: currently we require cluster-admin for the hawkular service account. This will be changing to the cluster-reader permission.

	openshift admin policy add-cluster-role-to-user cluster-admin \
          system:serviceaccount:metrics:hawkular

### Deploying the Metrics Components

	oc process -f metrics.yaml -v HAWKULAR_METRICS_HOSTNAME=metrics.example.com,IMAGE_PREFIX=mwringe/,IMAGE_VERSION=0.1-devel | oc create -f -

### Cleanup

	oc delete all --selector=metrics-infra
	oc delete secrets --selector=metrics-infra

