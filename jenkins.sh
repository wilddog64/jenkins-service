#!/usr/bin/env bash

MACHINE_NAME='podman-machine-default'

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
   return  [[ $? != 0 ]]
}

# Function to check if a docker machine is running
function docker_machine_running() {
   docker machine list --format "{{.Name}} {{.Running}}" | grep -q "^$MACHINE_NAME$"
   return  [[ $? != 0 ]]
}

# start docker machine
function start_docker_machine() {
   if docker_machine_exists $MACHINE_NAME; then
      docker machine init
   else
      echo "Docker machine $MACHINE_NAME already exists."
   fi

   if docker_machine_running; then
      docker machine start
   else
      echo "Docker machine $MACHINE_NAME is already running."
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


function install_jenkins_plugins() {
   jenkins_version=$1
   echo ">>> install/update jenkins plugins"

   if [[ -z $jenkins_version ]]; then
      echo "jenkins version missing!"
      exit -1
   fi

   PLUGIN_TEXT=$(pwd)/plugins.txt
   PLUGIN_FILE=/usr/share/jenkins/ref/plugins.txt
   docker run --rm -u jenkins \
      -v "${PLUGIN_TEXT}:/usr/share/jenkins/ref/plugins.txt:Z" \
      --volume jenkins-data:/var/jenkins_home:Z,U \
      "jenkins:${jenkins_version}" \
      jenkins-plugin-cli --plugin-file "${PLUGIN_FILE}" --latest --verbose --plugin-download-directory /var/jenkins_home/plugins
   if [[ $? == 0 ]]; then
      echo ">>> plugins install complete"
   else
      echo "warning: fail to install plugins"
      exit -1
   fi
}

# Function to start Jenkins container
function start_jenkins_container() {
    local jenkins_version=${1:-2.440.3}

    # Check if jenkins-lts container is running
    docker ps | grep -q jenkins-lts
    if [[ $? == 0 ]]; then
        # Container is running, check version
        current_version=$(docker inspect --format='{{.Config.Image}}' jenkins-lts | sed 's/.*://')
        if [[ "$current_version" == "$jenkins_version" ]]; then
            echo "Jenkins container version $jenkins_version is already running."
            return 0
        else
            echo "Stopping Jenkins container with version $current_version to start version $jenkins_version..."
            docker stop jenkins-lts
        fi
    fi

    echo "Starting Jenkins container version $jenkins_version..."
    docker run -u jenkins --name jenkins-lts --rm --detach \
        -e JAVA_OPTS=-Djenkins.install.runSetupWizard=false \
        --network jenkins \
        --volume jenkins-data:/var/jenkins_home:Z,U \
        --publish 8080:8080 --publish 50000:50000 \
        --publish 2233:2233 \
        -v $(pwd):/mnt/workdir:Z \
        -v $(pwd)/init.groovy.d/:/var/jenkins_home/init.groovy.d/ \
        -w /mnt/workdir \
        jenkins/jenkins:${jenkins_version}
    echo "Jenkins container started. Access it at http://localhost:8080"
}


function download_and_run_containers() {

    # run docker dind conainter
    start_docker_dind_container

    # run docker jenkins/lts image
    run_docker_jenkins_blueocean

}

function show_jenkins_init_admin_password() {
   docker logs jenkins-lts | grep -C 2 "Please use the following password"
}

function in_jenkins_container() {
    docker exec -it jenkins-lts bash
}

function start_jenkins() {
   version=$1

    # start docker machine
    start_docker_machine

    # create a bridge network
    create_network

    # create volumes to share the Docker client TLS certificates that needed to
    # connect to the Docker daemon and persist the Jenkins data
    create_volumes

    # download and run the containers
    # download_and_run_containers
    install_jenkins_plugins "$version"
    start_jenkins_container "$version"
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

function stop_jenkins_container() {
    # stop_jenkins_container dind
    docker ps -a --format "{{ .Image }} {{ .ID }}" | grep -E jenkins | awk '{print $2}' | xargs podman container stop
}

##############################################
# Hot-reload Jenkins system & job config
# Requires:
#   • SSHD plugin enabled on <port> inside Jenkins
#   • Public key for $JENKINS_USER uploaded in
#     “Account ▸ Security ▸ SSH Public Keys”
#   • The user has the Overall › Reload permission
##############################################
function reload_jenkins() {
    local host="${JENKINS_HOST:-localhost}"
    local port="${JENKINS_SSH_PORT:-2233}"
    local user="${JENKINS_USER:-admin}"
    local key="${JENKINS_KEY:-$HOME/.ssh/id_ed25519}"

    # 1  Check that the SSHD port answers
    nc -vzw3 "$port" "$host" &>/dev/null
    if [[ $? == 0 ]]; then
        echo "ERROR: SSHD port $port on host $host is not listening - return code $?"
        return 1
    fi

    # 2  Invoke the Jenkins CLI ‘reload’ command via SSH
    ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -p "$port" "${user}@${host}" reload-configuration

    if [[ $? == 0 ]]; then
        echo "Jenkins configuration reloaded successfully."
    else
        echo "ERROR: reload failed – check key, user permissions, or SSHD port."
        exit -1
    fi
}

# --- main ---

case "$1" in
    start)
        start_jenkins "${VERSION:-2.516.1}"
        ;;
    stop)
        stop_jenkins_container
        ;;
    show-admin-passwd)
        show_jenkins_init_admin_password
        ;;
    into-container)
        in_jenkins_container
         ;;
    restart)
        stop_jenkins_container
        start_jenkins "${VERSION:-2.516.1}"
         ;;
    reload)
       reload_jenkins
         ;;
esac
