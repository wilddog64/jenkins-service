#!/usr/bin/env bash

# refer to https://www.jenkins.io/doc/book/installing/ for how to
# install jenkins container. This script is basedd on that document

function create_network() {
    docker network ls | grep jenkins 2>&1 > /dev/null
    if [[ $? != 0 ]]; then
        docker network create jenkins
        echo create a docker network jenkins
    fi
}

function create_volumes() {
    docker volume ls | grep jenkins-docker-certs 2>&1 > /dev/null
    if [[ $? != 0 ]]; then
        docker volume create jenkins-docker-certs
        echo create a docker volume jenkins-docker-certs
    fi

    docker volume ls | grep jenkins-data 2>&1 > /dev/null
    if [[ $? != 0 ]]; then
        docker volume create jenkins-data
        echo create a docker volume jenkins-data
    fi
}

function start_docker_dind_container() {
    # in order to execute docker commands within a Jenkins node, we
    # download and run the docker:dind image
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
}

function run_docker_jenkins_blueocean() {
    # download and run jenkins blueocean
    docker container ls | grep jenkins-blueocean 2>&1 > /dev/null
    if [[ $? != 0 ]]; then
        docker container run --name jenkins-blueocean --rm --detach \
            --network jenkins \
            --env DOCKER_HOST=tcp://docker:2376 \
            --env DOCKER_CERT_PATH=/certs/client \
            --env DOCKER_TLS_VERIFY=1 \
            --volume jenkins-data:/var/jenkins_home \
            --volume jenkins-docker-certs:/certs/client:ro \
            --publish 8080:8080 --publish 50000:50000 jenkinsci/blueocean
                if [[ $? != 0 ]]; then
                    echo unable to download and run jenkinsci/blueocean image
                    exit -1
                fi
    fi
}

function download_and_run_containers() {

    # run docker dind conainter
    start_docker_dind_container

    # run docker jenkins/blueocean image
    run_docker_jenkins_blueocean

}

function start_jenkins() {

    # create a bridge network
    create_network

    # create volumes to share the Docker client TLS certificates that needed to
    # connect to the Docker daemon and persist the Jenkins data
    create_volumes

    # download and run the containers
    download_and_run_containers
}

# stop_jenkins_container function will stop a given container that user provides
function stop_jenkins_container() {
    container_name=$1

    docker ps -a | grep -v CONTAINER | awk '$2 ~ /$container_name/ {print $1}' | xargs docker container stop
    if [[ $? != 0 ]]; then
        echo unable to stop container $container_name
        exit -1
    fi
    echo successfully stop container $container_name
}

# --- main ---

case "$1" in
    start)
        start_jenkins
        ;;
    stop)
esac
