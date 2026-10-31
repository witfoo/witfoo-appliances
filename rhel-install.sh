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

warn() { echo "WARNING: $*" >&2; }

# Optional pins, set by the WitFoo image build so every image carries a known WFA. Leave them
# unset on a normal install, which gets the latest WFA.
#   WFA_VERSION  install exactly this WFA version
#   WFA_FLOOR    stop with an error if the installed WFA is older than this
WFA_VERSION="${WFA_VERSION:-}"
WFA_FLOOR="${WFA_FLOOR:-}"

# version_ge A B: true when version A >= version B (numeric, dot-separated).
version_ge() {
  local sorted
  mapfile -t sorted < <(printf '%s\n' "$1" "$2" | sort -V)
  [ "${sorted[0]}" = "$2" ]
}

# shellcheck source=/dev/null
. /etc/os-release
case "${ID:-}" in
  rhel) ;;
  *) warn "this script is written for RHEL 10; this system is ${PRETTY_NAME:-unknown}." ;;
esac

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

# Cloud/VM Tools. growpart (cloud-utils-growpart) is used by expand-disk.sh everywhere; the
# rest depends on the hypervisor: Hyper-V KVP/VSS daemons, open-vm-tools, or qemu-guest-agent.
# NOTE: `linux-cloud-tools-$(uname -r)` was removed earlier. That is a Debian/Ubuntu package name
# and has never existed in any RHEL repository; hyperv-daemons is the RHEL equivalent.
echo "Installing Cloud/VM Tools"
guest_pkgs=(cloud-utils-growpart)
virt="$(systemd-detect-virt 2>/dev/null || true)"
case "$virt" in
  microsoft) guest_pkgs+=(hyperv-daemons) ;;
  vmware) guest_pkgs+=(open-vm-tools) ;;
  kvm | qemu) guest_pkgs+=(qemu-guest-agent) ;;
esac
echo "  platform: ${virt:-unknown}; installing: ${guest_pkgs[*]}"
dnf install -y "${guest_pkgs[@]}"

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
echo "Installing WitFoo Appliance Manager${WFA_VERSION:+ $WFA_VERSION}"
dnf config-manager --add-repo https://witfoo-dev.github.io/rpm/witfoo.repo
dnf install -y "wfa${WFA_VERSION:+-$WFA_VERSION}"
wfa_installed="$(rpm -q --qf '%{VERSION}' wfa)"
if [ -n "$WFA_VERSION" ] && [ "$wfa_installed" != "$WFA_VERSION" ]; then
  echo "ERROR: WFA $WFA_VERSION was requested but $wfa_installed is installed" >&2
  exit 1
fi
if [ -n "$WFA_FLOOR" ] && ! version_ge "$wfa_installed" "$WFA_FLOOR"; then
  echo "ERROR: installed WFA $wfa_installed is below the required floor $WFA_FLOOR" >&2
  exit 1
fi

echo
echo "Install complete."
echo "  wfa version: $(rpm -q --qf '%{VERSION}' wfa 2>/dev/null || echo unknown)"
echo "  Next: run \`sudo wfa configure\` to register this appliance."
