#!/bin/bash

####################################
# Defaults

container_name=${PWD##*/}
container_tag="latest"
ecs_host="834579172960.dkr.ecr.eu-west-2.amazonaws.com"


###################################
# Get/set options

# -t The container tag to build/push.   Default:  latest
# -v The OTRL package version to install in the container.   Default:  unset
# -n The name to give the container.  Default: the directory name

usage() {
  echo
  echo "Usage: $0 [-t container_tag] [-v package_version] [-n container_name]";
  echo
  echo "   -t : the container tag to build/push.   Default:  $container_tag"
  echo "   -v : the OTRL package version to install in the container.   Default:  unset"
  echo "   -n : the name to give the container.  Default: $container_name"
  echo
  exit 1;
}

while getopts ":t:v:n:h" opt; do
  case $opt in
    t)
      container_tag=$OPTARG
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

if [ ! -f "entrypoint" ]; then
 wget -q https://raw.githubusercontent.com/otrl/aws-rail-deployment-scripts/docker/entrypoint entrypoint.tmp
fi


## info

echo
echo "Building container..."
echo "Container tag:  $container_tag"
echo "Container name: $container_name"
echo "OTRL package version: $package_version"
echo


###################################
# Build

docker build --build-arg package_version="$package_version" -t ${ecs_host}/${container_name}:${container_tag} .

rm -f entrypoint.tmp


###################################
# Push

if [ "$?" -eq "0" ]; then
 docker push ${ecs_host}/${container_name}:${container_tag}
fi

if [ "$?" -ne "0" ]; then
 echo
 echo "Unable to push the image to the repository. Either the repository doesn't"
 echo "exist yet or perhaps you might need to log into the repository again."
 echo "Run: \$(aws ecr get-login --no-include-email --region eu-west-2)"
 echo "to automatically log in."
 echo
 exit 1
fi
