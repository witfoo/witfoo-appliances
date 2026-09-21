#!/bin/bash
#
# Install Docker, WFA and related tools on a RHEL-based appliance.
#
# Run as root:  sudo ./rhel-install.sh
#
# set -E/-e/-u/-o pipefail: this script previously ran without any error handling, and three
# defects survived in it unnoticed for that reason — a non-root run that exited SUCCESS, a
# `yum remove` with no -y that would hang an unattended install, and a Debian package name that
# can never resolve on RHEL. A failing install must now stop and say so.
set -Eeuo pipefail

fail() { echo "ERROR on line $1 — install aborted" >&2; }
trap 'fail $LINENO' ERR

echo "Verifying that the script is running with root privileges"
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo" >&2
  # Was a bare `exit`, i.e. status 0 — a non-root run reported SUCCESS to whatever called it.
  exit 1
fi

# Update the system and install prerequisite packages
echo "Updating system and installing prerequisite packages"
dnf update -y

# Remove old versions of Docker and related tools.
# -y is required: without it this prompts, and an unattended install hangs here forever.
# `|| true` because under `set -e` a remove of packages that are not installed is not an error.
echo "Removing old versions of Docker and related tools"
yum remove -y docker \
              docker-client \
              docker-client-latest \
              docker-common \
              docker-latest \
              docker-latest-logrotate \
              docker-logrotate \
              docker-engine \
              podman \
              runc || true

# Yum Utils is required for adding repositories and managing packages
echo "Installing yum-utils"
yum install -y yum-utils

# Install Docker CE and related tools
echo "Installing Docker CE and related tools"
yum-config-manager -y --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
install -d -m 0755 /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
	"data-root": "/docker",
	"storage-driver": "overlay2"
}
JSON
systemctl enable docker
systemctl start docker

# Install prerequisite packages
echo "Installing prerequisite packages"
dnf install -y curl jq tcpdump wget nano zip unzip

# NOTE: `setenforce 0` was removed here. It only changed the RUNTIME mode and did not persist, so
# every appliance came back SELinux-Enforcing on its first reboot regardless — measured on the
# fishlab RHEL 10 nodes, which run Enforcing with SELINUX=enforcing in /etc/selinux/config and work
# correctly. The line therefore did nothing durable while implying the opposite. If a genuine
# SELinux exception is ever needed, it belongs in a policy module, not a non-persistent toggle.

# Cloud/VM Tools
echo "Installing Cloud/VM Tools"
dnf install -y cloud-utils-growpart
# NOTE: `linux-cloud-tools-$(uname -r)` was removed. That is a Debian/Ubuntu package name and has
# never existed in any RHEL repository — verified against a live RHEL 10.1 appliance. Without
# `set -e` it failed silently on every run since the script was written.

# Bound the log footprint BEFORE anything starts writing.
#
# A fishlab RHEL 10 appliance filled a dedicated 5.0 G /var/log to 100%: two rotated
# /var/log/messages archives of 2700 MB and 1996 MB, still uncompressed two months later, because
# RHEL ships `compress` commented out in /etc/logrotate.conf and `dateext` makes a second same-day
# rotation collide and skip. A full /var/log then broke dnf ("Failed to open log file:
# /var/log/hawkey.log"), which blocked the WFA upgrade that would have fixed the service wedge
# generating the log spam — the failure prevented its own remedy, and that node sat stuck for
# two months. See witfoo-dev/analytics#1195.
#
# WFA >= 2.4.16 reconciles this itself on every start; this sets a floor from first boot, before
# WFA is installed, and is idempotent with what WFA writes.
echo "Bounding the journal so /var/log cannot fill before WFA takes over"
install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/10-witfoo.conf <<'JOURNAL'
# Managed by WitFoo Agent (wfad).
[Journal]
SystemMaxUse=1G
SystemKeepFree=1G
MaxFileSec=1day
Compress=yes
JOURNAL
systemctl restart systemd-journald

# WitFoo Appliance Manager
echo "Installing WitFoo Appliance Manager"
dnf config-manager --add-repo https://witfoo-dev.github.io/rpm/witfoo.repo
dnf install -y wfa

# Update CA Trust with WitFoo CA
echo "Updating CA Trust with WitFoo CA"
curl -fsSL https://objectstorage.us-chicago-1.oraclecloud.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo_2024_ca.crt \
  | base64 -d > /witfoo/witfoo_ca_2024.crt
cp /witfoo/witfoo_ca_2024.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust

echo
echo "Install complete."
echo "  wfa version: $(rpm -q --qf '%{VERSION}' wfa 2>/dev/null || echo unknown)"
echo "  Next: run \`sudo wfa configure\` to register this appliance."
