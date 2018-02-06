#!/bin/bash

####################################
# BASH options

set -e


####################################
# Defaults

container_name=${PWD##*/}
container_tags=`date '+%Y-%m-%d--%H:%M:%S'`
ecs_host="834579172960.dkr.ecr.eu-west-2.amazonaws.com"


###################################
# Get/set options

usage() {
  echo
  echo "Usage: $0 [-t container_tags] [-v package_version] [-n container_name]";
  echo
  echo "   -t : the container tags to build/push (comma-separated),  Default:  $container_tags"
  echo "   -v : the OTRL package version to install in the container.   Default:  unset"
  echo "   -n : the name to give the container.  Default: $container_name"
  echo "   -l : tag this container as 'latest'"
  echo
  exit 1;
}

while getopts ":t:v:n:lh" opt; do
  case $opt in
    t)
      container_tags=(${OPTARG//,/ })
      ;;
    l)
      is_latest="true"
      ;;
    v)
      package_version="=${OPTARG}"
      ;;
    n)
      container_name=$OPTARG
      ;;
    h)
      usage
      ;;
    \?)
      usage
      ;;
    : )
      echo "Invalid Option: -$OPTARG requires an argument" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))


###################################
# Entrypoint script

if [ ! -f "bin/entrypoint" ]; then
 mkdir bin
 wget -q https://raw.githubusercontent.com/otrl/aws-rail-deployment-scripts/docker/entrypoint -O bin/entrypoint
 downloaded_entrypoint="true"
fi


## info

echo
echo "Building container..."
echo "Container tag:  $container_tags"
echo "Container name: $container_name"
echo "OTRL package version: $package_version"
echo


###################################
# Build

docker build --build-arg package_version="$package_version" -t ${ecs_host}/${container_name} .

if [ "$downloaded_entrypoint" == "true" ]; then
 rm -f bin/entrypoint
fi


###################################
# Tag

for this_tag in "${container_tags[@]}" ; do

 docker tag ${ecs_host}/${container_name} ${ecs_host}/${container_name}:${this_tag}

done

if [ "$is_latest" == "true" ]; then

 docker tag ${ecs_host}/${container_name} ${ecs_host}/${container_name}:latest

fi


###################################
# Push


for this_tag in "${container_tags[@]}" ; do

 docker push ${ecs_host}/${container_name}:${this_tag}

done


if [ "$is_latest" == "true" ]; then

 docker push ${ecs_host}/${container_name}:latest

fi

