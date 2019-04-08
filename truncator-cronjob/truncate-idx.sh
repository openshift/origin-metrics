#!/usr/bin/env bash
set -e

# We will see if we required to truncate tables, if we found a large partition (larger than the threshold)
# proceeed to truncate tables and recreate indices.

# Get one cassandra pod so we can execute nodetool
CASSANDRA_POD=$(oc get pods -n ${HAWKULAR_NAMESPACE} | grep hawkular-cassandra | head -n 1 |  awk '{print $1}')


# Get largest partition of metrics_idx and metrics_tags_idx
MAX_PARTIITON_TAGS_IDX=$(oc -n ${HAWKULAR_NAMESPACE} exec ${CASSANDRA_POD} -- nodetool tablehistograms hawkular_metrics metrics_tags_idx | grep Max | awk '{print $5}')
MAX_PARTIITON_IDX=$(oc -n ${HAWKULAR_NAMESPACE} exec ${CASSANDRA_POD} -- nodetool tablehistograms hawkular_metrics metrics_idx | grep Max | awk '{print $5}')

# Do we need to truncate the tables???? (if the largest partition is big enough, yes!)

if ([ "$MAX_PARTIITON_TAGS_IDX" != "NaN" ] && [ $MAX_PARTIITON_TAGS_IDX -gt $PARTITION_THRESHOLD ]) || ([ "$MAX_PARTIITON_IDX" != "NaN" ] && [ $MAX_PARTIITON_IDX -gt $PARTITION_THRESHOLD ]); then
  echo "Scalling down Heapster and Hawkular pods"
  oc -n ${HAWKULAR_NAMESPACE} scale rc heapster --replicas=0
  oc -n ${HAWKULAR_NAMESPACE} scale rc hawkular-metrics --replicas=0
  echo "Cassandra pod is ${CASSANDRA_POD}. Truncating tables"
  oc -n ${HAWKULAR_NAMESPACE} exec ${CASSANDRA_POD} -- cqlsh --ssl -e "truncate table hawkular_metrics.metrics_tags_idx"
  oc -n ${HAWKULAR_NAMESPACE} exec ${CASSANDRA_POD} -- cqlsh --ssl -e "truncate table hawkular_metrics.metrics_idx"
  echo "Scalling up Hawkular and Heapster pods"
  oc -n ${HAWKULAR_NAMESPACE} scale rc hawkular-metrics --replicas=1
  oc -n ${HAWKULAR_NAMESPACE} scale rc heapster --replicas=1
else
  echo "No need to truncate/clean index tables"
fi
