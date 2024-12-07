#!/usr/bin/env bash

# refer to https://www.jenkins.io/doc/book/installing/ for how to
# install jenkins container. This script is basedd on that document

# check if given command exists
function command_exist() {
   command -v $1 "$1" 2 >&1 > /dev/null
}

# alias podman as docker
function docker() {
  if ! command_exist podman; then
     echo podman not installed
     exit -1
  fi

  podman "$@"
  if [[ $? != 0 ]]; then
     echo error executing podman command
     exit -1
  fi
}

# Function to check if a docker machine exists
function docker_machine_exists() {
   docker machine list --format "{{.Name}}" | grep -q "^$1\$"
}

# Function to check if a docker machine is running
function docker_machine_running() {
   docker machine list --format "{{.Name}} {{.Running}}" | awk '{print $2}' | grep -q "true"
}

# start docker machine
function start_docker_machine() {
   if ! docker_machine_exists; then
      docker machine init
   fi

   if ! docker_machine_running; then
      docker machine start
   fi
}

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
            --publish 8080:8080 --publish 50000:50000 --publish 10022:10022 jenkinsci/blueocean
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

function in_jenkins_container() {
    docker exec -it jenkins-blueocean bash
}

function start_jenkins() {

    # start docker machine
    start_docker_machine

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

    docker ps -a | grep -v CONTAINER | grep $container_name | awk '{print $1}' | xargs docker container stop
    if [[ $? != 0 ]]; then
        echo unable to stop container $container_name
        exit 1
    fi
    echo successfully stop container $container_name
}

function stop_all_jenkins_container() {
    stop_jenkins_container dind
    stop_jenkins_container blueocean
}

# --- main ---

case "$1" in
    start)
        start_jenkins
        ;;
    stop-all)
        stop_all_jenkins_container
        ;;
    into-container)
        in_jenkins_container
esac
