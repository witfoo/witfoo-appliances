#!/bin/bash

# This script is intended to be run on a RHEL-based system to install Docker, WFA, and related tools.

echo "Verifying that the script is running with root privileges"
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit
fi

# Update the system and install prerequisite packages
echo "Updating system and installing prerequisite packages"
dnf update -y

# Remove old versions of Docker and related tools
echo "Removing old versions of Docker and related tools"
yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine \
                  podman \
                  runc
# Yum Utils is required for adding repositories and managing packages
echo "Installing yum-utils"
yum install -y yum-utils

# Install Docker CE and related tools
echo "Installing Docker CE and related tools"
yum-config-manager -y --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
echo '{' > /etc/docker/daemon.json
echo '	"data-root": "/docker",' >> /etc/docker/daemon.json
echo '	"storage-driver": "overlay2"' >> /etc/docker/daemon.json
echo '}' >> /etc/docker/daemon.json
systemctl enable docker
systemctl start docker

# Install prerequisite packages
echo "Installing prerequisite packages"
dnf install -y curl jq tcpdump wget nano zip unzip
setenforce 0

# Cloud/VM Tools
echo "Installing Cloud/VM Tools"
yum install -y cloud-utils-growpart
yum install -y linux-cloud-tools-$(uname -r)

# WitFoo Appliance Manager
echo "Installing WitFoo Appliance Manager"
dnf config-manager --add-repo https://witfoo-dev.github.io/rpm/witfoo.repo
dnf install -y wfa wfa-helper

# Update CA Trust with WitFoo CA
echo "Updating CA Trust with WitFoo CA"
curl https://objectstorage.us-chicago-1.oraclecloud.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo_2024_ca.crt -k | base64 -d > /witfooprecinct/witfoo_ca_2024.crt
cp /witfooprecinct/witfoo_ca_2024.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust