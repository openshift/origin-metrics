# origin-metrics

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

