# origin-metrics

TODO: write brief introduction here.
TODO: specify the role needed to perform the following operations

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

The Metrics components require a properly running OpenShift instances. How to properly install and configure OpenShift is beyond the scope of this document. Please see the [OpenShift documentation](https://docs.openshift.org/latest/welcome/index.html) on how to properly install and setup your system.

### Enabling the Read Only Kubelet Endpoint

Currently the kubelet endpoints are secured with certificate authentication and are not accessible to metric containers. This is a known issue which is currently being worked on: https://github.com/openshift/origin/pull/4873 

Until this is properly fix in OpenShift, you will need to enable the RO endpoint for each of your nodes.

For each node, you will need to update its `node-config.yaml` to enable read only access:

	cat >> node-config.yaml << DONE
	kubeletArguments:
 	read-only-port:
 	- "10266"
	DONE

### Creating Persistent Storage

The Cassandra database stores its data to persistent storage. For each Cassandra node you deploy, you will need a persistent volume with sufficient data available. You do not need to directly manage peristent volume claims as the deployer and templates will take care of that for you.

Please see the [OpenShift documentation](https://docs.openshift.org/latest/architecture/additional_concepts/storage.html) for how to setup and configure persistent volumes.

For example if you have a NFS server running on localhost with an exposed directory at `/persistent_storage/pv01`, the following command will generate a 10 gigabyte persistent volume:

	oc create -f - <<API
	apiVersion: v1
	kind: PersistentVolume
	metadata:
	  name: my_pv
	spec:
	  capacity:
	    storage: 10Gi
	  accessModes:
	    - ReadWriteOnce
	    - ReadWriteMany
	  persistentVolumeReclaimPolicy: Recycle
	  nfs:
	    server: localhost
	    path: /persistent_storage/pv01
	API


## Deploying


### Create a Metrics Project

To prevent unwanted components from accessing the metric's persistent volume claim, it is highly recommended to deploy all the metric components within their own project (eg metrics-infra). Management of the metric components is also easier if they are separated in their own project as well.

For the instructions presented here we are going to do so in a project named `metrics`.

To create a new project called `metrics` you will need to run the following command:

	oc new-project metrics

### Create the Deployer Service Account

A pod is used to setup, configure and deploy all the various metric components. This deployer pod is run under the `metrics-deployer` service account.

To create the metrics deployer service account, the following command can be run:

	oc create -f - <<API
	apiVersion: v1
	kind: ServiceAccount
	metadata:
	  name: metrics-deployer
	secrets:
	- name: metrics-deployer
	API

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

	openshift admin policy add-cluster-role-to-user cluster-reader \
          system:serviceaccount:metrics:heapster


### Create the Hawkular Deployer Secret

In order to deploy the Hawkular deployer pod, a secret must first be created. These secrets allow an admin to specify their own ssl certificates instead of letting the deployer autogenerate self-signed ones. 

If you wish to let the deployer generate all the certificates for you, you will just need to create an empty secret:


	oc secrets new metrics-deployer nothing=/dev/null

If you wish to provide any of your own certificates, then you will need to specify the certifcate that you wish to provide.

The following is a list of configuration options which can be specifed as a secret for the deployer:

* hawkular-metrics.pem
	* The pem file used for the Hawkular Metrics certificate
	* if not specified: autogenerated
* hawkular-metrics-ca.cert
	* The certificate for the CA used to sign the hawkular-metrics.pem
	* required if hawkular-metrics.pem is specified, ignored otherwise
* hawkular-cassandra.pem
	* The pem file used for the Cassandra certificate
	* if not specified: autogenerated
* hawkular-cassandra-ca.cert
	* The certificate for the CA used to sign the hawkular-cassandra.pem
	* required if hawkular-cassandra-ca.cert is specified, ignored otherwise
* heapster.cert
	* The certificate used by Heapster
	* if not specified: autogenerated
* heapster.key
	* The key to be used with the heapster certificate
	* only required if heapster.cert is specified, ignored otherwise
* heapster_client_ca.cert
	* The certificate authority certificate used to generate heapster.cert
	* required if heapster.cert is specified, otherwise set to an autogenerated ca certificate
* heapster_allowed_users
	* A file containing a comma separated list of CN to accept from certificates signed with the specified CA
	* required if heapster.cert is specified, otherwise set to no allowed users
	
If the secrets to be used are placed all within a single directory, the following command will create the secret for you:

	oc secrets new metrics-deployer path/to/dir
	
If the secrets are not all located within a single directory, the following command can be used to specify the location of the files:

	oc secrets new metric-deployer hawkular-metrics.pem=/my/dir/hm.pem \
	                               hawkular-metrics-ca.cert=/my/dir/hm-ca.cert


### Deploying the Metrics Components

To deploy the metric components, you will need to deploy the 'metrics' template.

You will need to use the same IMAGE_PREFIX and IMAGE_VERSION used to build the containers:

	oc process -f metrics.yaml -v \
	HAWKULAR_METRICS_HOSTNAME=hawkular-metrics.example.com,IMAGE_PREFIX=openshift/origin-,IMAGE_VERSION=devel \
	| oc create -f -
	
#### Template Parameters

The following are the various parameters the template will accept

#####IMAGE_PREFX
The prefix selected when the containers were built.

#####IMAGE_VERSION
The version selected when the containers were built.

##### HAWKULAR_METRICS_HOSTNAME
The hostname that hawkular metrics is going to be hosted under. This is used to generate the Hawkular Metrics certificate and is used for the host in the route configuration.

##### REDEPLOY
If the redeploy parameter is set to `true` it will delete all the components, service accounts, secrets and persistent volume claim. This will permanently delete any metrics which are stored.

##### MASTER_URL
The url to used for components to access the kubernetes master. Defaults to `https://kubernetes.default.svc.cluster.local:443`

##### CASSANDRA_NODES
How many initial Cassandra nodes should be deployed. This defaults to a single node cluster.

##### CASSANDRA_PV_SIZE
The requested size that each Cassandra node is requesting. This defaults to 1gi

##### METRIC_DURATION
How many days that metrics should be stored for. This defaults to 7 days.

	
### Cassandra Scaling

Since the Cassandra nodes use persistent storage, we cannot currently scale up or down using replication controllers.

In a subsequent release, nominal services will allow replication controllers to handle this type of scaling and these extra steps will not be needed. But for now a few extra steps are required.

In order to scale up a Cassandra cluster, you will need to use the `hawkular-cassandra-node` template.

By default, the Cassandra cluster is a single node cluster. To add a second node with 1Gi of storage, you would need to call the following command:

	oc process hawkular-cassandra-node -v \
	"IMAGE_PREFIX=openshift/origin-,IMAGE_VERSION=devel,PV_SIZE=1Gi,NODE=2"
	
To deploy more nodes, you would need to just increase the `NODE` value.

Note: when you add a new node to a Cassandra cluster, the data stored in the cluster will rebalance across the cluster. The same thing will happen when you remove a node from the Cluster. Adding and removing Cassandra nodes can be an expensive operation.

### Cleanup

If you wish to undeploy and remove everything deployed by the deployer, the follow commands can be used:

	oc delete all --selector=metrics-infra
	oc delete secrets --selector=metrics-infra
	oc delete sa --selector=metrics-infra
	
Note: the persistent volume claim will not be deleted by the above command. If you wish to permanently delete the data in persistent storage you can run `oc delete pvc --selector=metrics-infa`

