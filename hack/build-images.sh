#!/bin/bash

set -e

prefix="openshift/origin-"
version="latest"
push=false
verbose=false
options=""

source_root=$(dirname "${BASH_SOURCE}")/..

for args in "$@"
do
  case $args in
    --prefix=*)
      prefix="${args#*=}"
      ;;
    --version=*)
      version="${args#*=}"
      ;;
    --no-cache)
      options="${options} --no-cache"
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
  echo "  --no-cache"
  echo "  If set will perform the build without a cache."
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

echo "Building image ${prefix}metrics-deployer:${version}"
docker build ${options} -t "${prefix}metrics-deployer:${version}"    		${source_root}/deployer/
echo
echo "Building image ${prefix}metrics-hawkular-metrics:${version}"
docker build ${options} -t "${prefix}metrics-hawkular-metrics:${version}"       ${source_root}/hawkular-metrics/
echo
echo "Building image ${prefix}metrics-cassandra:${version}"
docker build ${options} -t "${prefix}metrics-cassandra:${version}" 		${source_root}/cassandra/
echo
echo "Building image ${prefix}metrics-heapster:${version}"
docker build ${options} -t "${prefix}metrics-heapster:${version}"        	${source_root}/heapster/

if [ "$push" = true ]; then
  echo "Pushing Docker Images"
  docker push "${prefix}metrics-deployer:${version}"
  docker push "${prefix}metrics-hawkular-metrics:${version}"
  docker push "${prefix}metrics-cassandra:${version}"
  docker push "${prefix}metrics-heapster:${version}"
fi
