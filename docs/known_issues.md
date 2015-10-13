# Known Issues

## 'RejectedExecutionException' in Hawkular Metrics Logs

Hawkular Metrics requires a connection to Cassandra and will poll for this connection at startup. If you are starting both Hawkular Metrics and cassandra at the same time, then there is an issue where you may see 'RejectedExecutionExceptions' in the logs when a connection could not be established.

This warning can be safely ignored. It is being tracked in [Hawkular Metrics](https://issues.jboss.org/browse/HWKMETRICS-275) as well as with the [Cassandra Java Driver](https://datastax-oss.atlassian.net/browse/JAVA-914)
