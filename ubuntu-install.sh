#!/bin/bash
# This script is intended to be run on an Ubuntu-based system to install Docker, WFA, and related tools.

echo "Verifying that the script is running with root privileges"
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit
fi

echo "Updating apt repository"
apt-get update -y

echo "Installing prerequisite packages"
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent gnupg lsb-release \
 software-properties-common iotop htop jq update-motd tcpdump wget nano zip unzip net-tools

echo "Cleaning up docker artifacts"
service docker stop || true
rm -rf /docker/* || true

echo "Adding Docker repository and trusted gpg key"
mkdir -p /etc/apt/keyrings
chmod -R 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Adding WitFoo repository and trusted gpg key"
curl -fsSL --compressed https://witfoo-dev.github.io/apt/gpg | gpg --dearmor > /etc/apt/keyrings/witfoo.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/witfoo.gpg] https://witfoo-dev.github.io/apt/ ./" | \
tee /etc/apt/sources.list.d/witfoo.list > /dev/null

echo "Updating apt repository"
apt-get update -y

echo "Installing Docker, Docker Compose, and WFA"
apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin wfa wfa-helper

echo "Adding vm/cloud tools"
apt install linux-cloud-tools-$(uname -r)
apt install cloud-guest-utils

echo "Upgrading system packages"
apt-get upgrade -y

echo "Updating Docker daemon settings"
mkdir -p /etc/docker

cat << 'EOF' > /etc/docker/daemon.json
{
  "data-root": "/docker",
  "storage-driver": "overlay2"
}
EOF

echo "Restarting Docker"
service docker restart

# Download and decode the cert
echo "Downloading and decoding WitFoo CA certificate"
curl https://objectstorage.us-chicago-1.oraclecloud.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo_2024_ca.crt -k | base64 -d > /witfoo/witfoo_ca_2024.crt
cp /witfoo/witfoo_ca_2024.crt /usr/local/share/ca-certificates/witfoo_ca_2024.crt
update-ca-certificates
