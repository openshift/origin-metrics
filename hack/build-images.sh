#!/bin/bash

set -e

prefix="docker.io/openshift/origin-"
version="latest"
push=false
verbose=false

for args in "$@"
do
  case $args in
    --prefix=*)
      prefix="${args#*=}"
      ;;
    --version=*)
      version="${args#*=}"
      ;;
    --push)
      push=true
    ;;
    --verbose)
      verbose=true
    ;;
    --help)
      help=true
    ;;
  esac
done

if [ "$help" = true ]; then
  echo "Builds the docker images for metrics and optionally pushes them to a registry"
  echo
  echo "Options: "
  echo "  --prefix=PREFIX"
  echo "  The prefix to use for the image names."
  echo "  default: docker.io/openshift/origin-"
  echo
  echo "  --version=VERSION"
  echo "  The version used to tag the image"
  echo "  default: latest"
  echo
  echo "  --push"
  echo "  If set will call 'docker push' on the images"
  echo
  echo "  --verbose"
  echo "  Enables printing of the commands as they run."
  echo
  echo "  --help"
  echo "  Prints this help message"
  echo

  exit 0
fi

if [ "$verbose" = true ]; then
  set -x
fi

echo "Building image ${prefix}metrics-hawkular-metrics:${version}"
docker build -t "${prefix}metrics-hawkular-metrics:${version}"       ../hawkular-metrics/
docker build -t "${prefix}metrics-cassandra:${version}" ../cassandra/
docker build -t "${prefix}metrics-heapster:${version}"        ../heapster/
docker build -t "${prefix}metrics-deployer:${version}"    ../deployer/

if [ "$push" = true ]; then
  echo "Pushing Docker Images"
  docker push "${prefix}metrics-hawkular-metrics:${version}"
  docker push "${prefix}metrics-cassandra:${version}"
  docker push "${prefix}metrics-heapster:${version}"
  docker push "${prefix}metrics-deployer:${version}"
fi
