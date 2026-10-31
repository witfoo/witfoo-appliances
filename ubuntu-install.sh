#!/bin/bash
#
# Install Docker, WFA and related tools on an Ubuntu 24.04 system (bare metal, or a VM you built
# yourself). The WitFoo appliance images already contain everything this script installs.
#
# Run as root:  sudo ./ubuntu-install.sh
#
# Before running it, create the partition layout in README.md ("Disk Partition Layout"):
# /docker, /var/log, /var/log/audit, /cassandra_commit and /data must each be their own volume.
#
# The script is safe to run again on a system it has already installed: it changes package and
# repository configuration only, and never deletes Docker data.
set -Eeuo pipefail

fail() { echo "ERROR on line $1 — install aborted" >&2; }
trap 'fail $LINENO' ERR

warn() { echo "WARNING: $*" >&2; }

echo "Verifying that the script is running with root privileges"
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo" >&2
  # A bare `exit` here returned status 0, so a non-root run reported success to its caller.
  exit 1
fi

# shellcheck source=/dev/null
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  echo "This script is for Ubuntu; this system is ${PRETTY_NAME:-unknown}. On RHEL use rhel-install.sh." >&2
  exit 1
fi
if [ "${VERSION_ID:-}" != "24.04" ]; then
  warn "WitFoo appliances are built and tested on Ubuntu 24.04; this system is ${PRETTY_NAME}."
fi

# Optional pins, set by the WitFoo image build so every image carries a known WFA. Leave them
# unset on a normal install, which gets the latest WFA.
#   WFA_VERSION  install exactly this WFA version, and keep it through the system upgrade below
#   WFA_FLOOR    stop with an error if the installed WFA is older than this
WFA_VERSION="${WFA_VERSION:-}"
WFA_FLOOR="${WFA_FLOOR:-}"

# Every apt call is non-interactive, so an unattended run cannot stop at a prompt. Configuration
# files changed locally are kept on upgrade (--force-confold) rather than prompting.
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo "Checking the partition layout"
missing_mounts=()
for m in /docker /var/log /var/log/audit /cassandra_commit /data; do
  mountpoint -q "$m" || missing_mounts+=("$m")
done
if [ "${#missing_mounts[@]}" -gt 0 ]; then
  warn "these paths are not separate volumes: ${missing_mounts[*]}"
  warn "WitFoo services will run, but one volume filling up can starve the others."
  warn "See \"Disk Partition Layout\" in README.md."
fi

echo "Updating apt repository"
apt-get update -y

echo "Installing prerequisite packages"
apt-get install "${APT_OPTS[@]}" apt-transport-https ca-certificates curl gnupg-agent gnupg lsb-release \
  software-properties-common iotop htop jq update-motd tcpdump wget nano zip unzip net-tools openssl

# Bound the log footprint BEFORE anything starts writing. A dedicated 5 GB /var/log can fill up
# before WFA is configured; WFA 2.4.16 and later writes this same file on every start, so this
# only sets the floor from first boot and agrees with what WFA writes.
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

# Docker's settings are written BEFORE Docker is installed, so its first start already uses
# /docker and nothing is initialised under /var/lib/docker on the root volume. WFA writes the same
# content when it configures a role.
#
# This script used to stop Docker and run `rm -rf /docker/*` at this point. On a system that was
# already running WitFoo, that deleted every container, image and volume. It is gone: existing
# Docker data is left alone.
echo "Writing Docker daemon settings"
install -d -m 0755 /etc/docker /docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "data-root": "/docker",
  "storage-driver": "overlay2"
}
JSON

echo "Adding Docker repository and trusted gpg key"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod 0644 /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

echo "Adding WitFoo repository and trusted gpg key"
curl -fsSL --compressed https://witfoo-dev.github.io/apt/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/witfoo.gpg
chmod 0644 /etc/apt/keyrings/witfoo.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/witfoo.gpg] https://witfoo-dev.github.io/apt/ ./" \
  > /etc/apt/sources.list.d/witfoo.list

echo "Updating apt repository"
apt-get update -y

echo "Installing Docker, Docker Compose, and WFA${WFA_VERSION:+ $WFA_VERSION}"
wfa_pkgs=(wfa wfa-helper)
if [ -n "$WFA_VERSION" ]; then
  wfa_pkgs=("wfa=$WFA_VERSION" "wfa-helper=$WFA_VERSION")
fi
apt-get install "${APT_OPTS[@]}" docker-ce docker-ce-cli containerd.io docker-compose-plugin "${wfa_pkgs[@]}"

# Guest tools for the platform this system runs on. growpart (cloud-guest-utils) is used by
# expand-disk.sh everywhere. The rest depends on the hypervisor:
#   Hyper-V : Hyper-V KVP/VSS daemons. linux-cloud-tools-virtual follows kernel updates; the
#             previous `linux-cloud-tools-$(uname -r)` only matched the kernel running at install
#             time and was installed on every platform, including bare metal.
#   VMware  : open-vm-tools.
#   KVM     : qemu-guest-agent.
# These calls previously had no -y, so an unattended install stopped at a prompt.
echo "Adding VM/cloud tools"
guest_pkgs=(cloud-guest-utils)
virt="$(systemd-detect-virt 2>/dev/null || true)"
case "$virt" in
  microsoft)
    guest_pkgs+=(linux-cloud-tools-virtual)
    if apt-cache show "linux-cloud-tools-$(uname -r)" >/dev/null 2>&1; then
      guest_pkgs+=("linux-cloud-tools-$(uname -r)")
    fi
    ;;
  vmware) guest_pkgs+=(open-vm-tools) ;;
  kvm | qemu) guest_pkgs+=(qemu-guest-agent) ;;
esac
echo "  platform: ${virt:-unknown}; installing: ${guest_pkgs[*]}"
apt-get install "${APT_OPTS[@]}" "${guest_pkgs[@]}"

echo "Upgrading system packages"
if [ -n "$WFA_VERSION" ]; then
  # Without the hold, the upgrade would replace the pinned WFA with the latest one.
  apt-mark hold wfa wfa-helper
fi
apt-get upgrade "${APT_OPTS[@]}"
if [ -n "$WFA_VERSION" ]; then
  apt-mark unhold wfa wfa-helper
fi

wfa_installed="$(dpkg-query -W -f='${Version}' wfa)"
if [ -n "$WFA_VERSION" ] && [ "$wfa_installed" != "$WFA_VERSION" ]; then
  echo "ERROR: WFA $WFA_VERSION was requested but $wfa_installed is installed" >&2
  exit 1
fi
if [ -n "$WFA_FLOOR" ] && ! dpkg --compare-versions "$wfa_installed" ge "$WFA_FLOOR"; then
  echo "ERROR: installed WFA $wfa_installed is below the required floor $WFA_FLOOR" >&2
  exit 1
fi

echo "Restarting Docker"
systemctl enable docker
systemctl restart docker

# WitFoo CA certificate.
#
# WFA keeps its own CA bundle in /witfoo/certs for WitFoo-to-WitFoo TLS. This step also adds the
# 2024 WitFoo CA to the system trust store. It was downloaded with `curl -k`, i.e. with TLS
# verification off, for a file that then became a trusted root on this system. It is now
# fetched over verified TLS and installed only if it decodes to an X.509 CA certificate.
# If it cannot be fetched, the install continues without it and says so, rather than installing
# whatever came back.
WITFOO_CA_URL="https://objectstorage.us-chicago-1.oraclecloud.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo_2024_ca.crt"
echo "Installing the WitFoo CA certificate"
ca_tmp="$(mktemp -d)"
if curl -fsSL --retry 3 --max-time 60 "$WITFOO_CA_URL" -o "$ca_tmp/ca.b64" &&
  base64 -d "$ca_tmp/ca.b64" > "$ca_tmp/ca.crt" 2>/dev/null &&
  ca_text="$(openssl x509 -in "$ca_tmp/ca.crt" -noout -text 2>/dev/null)" &&
  [[ "$ca_text" == *"CA:TRUE"* ]]; then
  install -d -m 0755 /witfoo
  install -m 0644 "$ca_tmp/ca.crt" /witfoo/witfoo_ca_2024.crt
  install -m 0644 "$ca_tmp/ca.crt" /usr/local/share/ca-certificates/witfoo_ca_2024.crt
  update-ca-certificates
else
  warn "the WitFoo CA certificate could not be downloaded or is not a valid CA certificate;"
  warn "it was NOT added to the system trust store. WFA's own CA bundle is not affected."
fi
rm -rf "$ca_tmp"

echo
echo "Install complete."
echo "  wfa version: $(dpkg-query -W -f='${Version}' wfa 2>/dev/null || echo unknown)"
echo "  Next: run \`sudo wfa configure\` to register this appliance."
