#!/usr/bin/env bash

MACHINE_NAME='podman-machine-default'

# refer to https://www.jenkins.io/doc/book/installing/ for how to
# install jenkins container. This script is basedd on that document

# check if given command exists

function command_exist() {
   command -v "$1" > /dev/null 2>&1
}

# alias podman as docker
function _docker() {
  if ! command_exist podman; then
     echo podman not installed
     exit 1
  fi

  podman "$@"
  if ! command_exist podman; then
     echo error executing podman command
     exit 1
  fi
}

# Function to check if a _docker machine exists
function docker_machine_exists() {
   _docker machine list --format "{{.Name}}" | grep -qFx -- "$1"
}

# Function to check if a _docker machine is running
function docker_machine_running() {
   _docker machine list --format "{{.Name}} {{.Running}}" | grep -qFx -- "$MACHINE_NAME"
}

# start _docker machine
function start_docker_machine() {
   if docker_machine_exists $MACHINE_NAME; then
      _docker machine init
   else
      echo "Docker machine $MACHINE_NAME already exists."
   fi

   if docker_machine_running; then
      _docker machine start
   else
      echo "Docker machine $MACHINE_NAME is already running."
   fi
}

function create_network() {
    _docker network ls > /dev/null 2>&1 | grep jenkins
    if _docker network ls > /dev/null 2>&1 | grep jenkins; then
        _docker network create jenkins
        echo create a _docker network jenkins
    fi
}

function create_volumes() {
    if _docker volume ls > /dev/null 2>&1 | grep jenkins-docker-certs; then
        _docker volume create jenkins-docker-certs
        echo create a docker volume jenkins-docker-certs
    fi

    _docker volume ls > /dev/null 2>&1 | grep jenkins-data
    if [[ $? != 0 ]]; then
        _docker volume create jenkins-data
        echo create a docker volume jenkins-data
    fi
}

function start_docker_dind_container() {
    # in order to execute docker commands within a Jenkins node, we
    # download and run the docker:dind image
    if _docker container ls | grep jenkins-docker > /dev/null 2>&1; then
        _docker container run --name jenkins-docker --rm --detach \
            --privileged --network jenkins --network-alias docker \
            --env DOCKER_TLS_CERTDIR=/certs \
            --volume jenkins-docker-certs:/certs/client \
            --volume jenkins-data:/var/jenkins_home \
            docker:dind
        if [[ $? != 0 ]]; then
            echo unable to download docker:dind image
            exit 1
        fi
    fi
}


# new
: "${PLUGIN_FILE=/usr/share/jenkins/ref/plugins.txt}"
: "${PLUGIN_TEXT=$(pwd)/SOURCES/plugins.txt}"

function install_jenkins_plugins() {
   jenkins_version="${1:?Jenkins version is required}"
   echo ">>> install/update jenkins plugins"

   jenkins_core="${jenkins_version%%-*}"
   update_center_url="https://updates.jenkins.io/update-center.actual.json?version=${jenkins_core}"
   _docker run --rm -u jenkins \
      -v "${PLUGIN_TEXT}:/usr/share/jenkins/ref/plugins.txt:Z" \
      --volume jenkins-data:/var/jenkins_home:Z,U \
      "jenkins/jenkins:${jenkins_version}" \
      jenkins-plugin-cli --plugin-file "${PLUGIN_FILE}" \
        --verbose \
        --jenkins-update-center "${update_center_url}" \
        --latest false \
        --plugin-download-directory /var/jenkins_home/plugins
   if [[ $? == 0 ]]; then
      echo ">>> plugins install complete"
   else
      echo "warning: fail to install plugins"
      exit 1
   fi
}

: "${ADMIN_SSH_KEY_PATH:=/run/secrets/jenkins_admin_ssh_key.pub}"
: "${SSH_KEY_PATH:=$HOME/.ssh/jenkins_admin_ssh_key.pub}"
# Function to start Jenkins container
function start_jenkins_container() {
    local jenkins_version="${1:?Jenkins version is required}"
    local jenkins_admin_ssh_key_path=${ADMIN_SSH_KEY_PATH}
    local jenkins_key_path=${SSH_KEY_PATH}

    # Check if jenkins-lts container is running
    if _docker ps | grep -q jenkins-lts; then
        # Container is running, check version
        current_version=$(_docker inspect --format='{{.Config.Image}}' jenkins-lts | sed 's/.*://')
        if [[ "$current_version" == "$jenkins_version" ]]; then
            echo "Jenkins container version $jenkins_version is already running."
            return 0
        else
            echo "Stopping Jenkins container with version $current_version to start version $jenkins_version..."
            _docker stop jenkins-lts
        fi
    fi

    echo "Starting Jenkins container version $jenkins_version..."
    _docker run -u jenkins --name jenkins-lts --rm --detach \
        -e JAVA_OPTS=-Djenkins.install.runSetupWizard=false \
        --network jenkins \
        --volume jenkins-data:/var/jenkins_home:Z,U \
        --publish 8080:8080 --publish 50000:50000 \
        --publish 2233:2233 \
        -v "$(pwd)":/mnt/workdir:Z \
        -v "$(pwd)"/init.groovy.d/:/var/jenkins_home/init.groovy.d/ \
        -v "$jenkins_key_path:$jenkins_admin_ssh_key_path:Z" \
        -v "$(pwd)"/SOURCES/secret.txt:/var/run/secrets/ADMIN_PASS:Z,ro \
        -w /mnt/workdir \
        jenkins/jenkins:"${jenkins_version}"
    echo "Jenkins container started. Access it at http://localhost:8080"
}


function download_and_run_containers() {

    # run _docker dind conainter
    start_docker_dind_container

    # run docker jenkins/lts image
    run_docker_jenkins_blueocean

}

function show_jenkins_init_admin_password() {
   _docker logs jenkins-lts | grep -C 2 "Please use the following password"
}

function in_jenkins_container() {
    _docker exec -it jenkins-lts bash
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
    install_jenkins_plugins "${version}"
    start_jenkins_container "${version}"
}

function stop_jenkins_container() {
    # stop_jenkins_container dind
    # docker ps -a --format "{{ .Image }} {{ .ID }}" | grep -E jenkins | awk '{print $2}' | xargs podman container stop
    ids=$(_docker ps -a --filter name=jenkins -q)
    [[ -n "$ids" ]] && _docker stop "$ids"
 }

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

    # 1  Check that the SSHD port answers
    if nc -vzw3 "$port" "$host" &>/dev/null; then
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
        exit 1
    fi
}

# --- main ---
case "$1" in
    start)
       VERSION=${2:?Jenkins version is required as the second argument}
       start_jenkins "${VERSION}"
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
       start_jenkins "${VERSION}"
       ;;
    reload)
       reload_jenkins
       ;;
esac
