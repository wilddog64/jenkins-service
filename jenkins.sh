#!/usr/bin/env bash

docker network ls | grep jenkins 2>&1 > /dev/null
if [[ $? != 0 ]]; then
    docker network create jenkins
    echo create a docker network jenkins
fi

docker volume ls | grep jenkins-coker-certs 2>&1 > /dev/null
if [[ $? != 0 ]]; then
    docker volume create jenkins-docker-certs
    echo create a docker volume jenkins-docker-certs
fi

docker volume ls | grep jenkins-data 2>&1 > /dev/null
if [[ $? != 0 ]]; then
    docker volume create jenkins-data
    echo create a docker volume jenkins-data
fi

docker container ls | grep jenkins-docker 2>&1
if [[ $? != 0 ]]; then
    docker container run --name jenkins-docker --rm --detach \
      --privileged --network jenkins --network-alias docker \
      --env DOCKER_TLS_CERTDIR=/certs \
      --volume jenkins-docker-certs:/certs/client \
      --volume jenkins-data:/var/jenkins_home \
      docker:dind
    if [[ $? != 0 ]]; then
        echo unable to download docker:dind image
        exit -1
    fi
fi

docker container ls | grep jenkins-blueocean 2>&1 > /dev/null
if [[ $? != 0 ]]; then
    docker container run --name jenkins-blueocean --rm --detach \
      --network jenkins --env DOCKER_HOST=tcp://docker:2376 \
      --env DOCKER_CERT_PATH=/certs/client --env DOCKER_TLS_VERIFY=1 \
      --volume jenkins-data:/var/jenkins_home \
      --volume jenkins-docker-certs:/certs/client:ro \
      --publish 8080:8080 --publish 50000:50000 jenkinsci/blueocean
    if [[ $? != 0 ]]; then
        echo unable to download and run jenkinsci/blueocean image
        exit -1
    fi
fi
