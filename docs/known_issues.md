# Known Issues

## 'RejectedExecutionException' in Hawkular Metrics Logs

Hawkular Metrics requires a connection to Cassandra and will poll for this connection at startup. If you are starting both Hawkular Metrics and cassandra at the same time, then there is an issue where you may see 'RejectedExecutionExceptions' in the logs when a connection could not be established.

This warning can be safely ignored. It is being tracked in [Hawkular Metrics](https://issues.jboss.org/browse/HWKMETRICS-275) as well as with the [Cassandra Java Driver](https://datastax-oss.atlassian.net/browse/JAVA-914)

## x509: cannot validate certificate for ... because it doesn't contain any IP SANs
This is a [known issue](https://github.com/openshift/origin/issues/5294) when starting the all-in-one server.  The issue can be resolved by supplying the
hostname flag and setting it to the IP address of master host.
```
openshift start --write-config=openshift.local.config --hostname=<IP_ADDRESS> --public-master=<IP_ADDRESS> --master=<IP_ADDRESS>
```

