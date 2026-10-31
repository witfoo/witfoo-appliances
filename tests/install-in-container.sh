#!/bin/bash
#
# Run an install script end to end inside a throwaway container and check the result.
#
#   tests/install-in-container.sh <image> <script>
#   tests/install-in-container.sh ubuntu:24.04 ubuntu-install.sh
#   tests/install-in-container.sh almalinux:10 rhel-install.sh
#
# The container has no systemd as PID 1, so systemctl is replaced by a stub that succeeds. That
# makes this a test of the package, repository and file steps, not of services starting: it
# proves the script installs WFA and Docker from the live repositories, survives a second run
# pinned to the installed WFA (the image build's mode), keeps existing Docker data, enforces
# WFA_FLOOR, and refuses to run without root. AlmaLinux 10 stands in for RHEL 10,
# whose repositories need a subscription.
#
# Exits non-zero, naming the failed check, if anything is wrong.
set -Eeuo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <image> <script>" >&2
  exit 2
fi
image="$1"
script="$2"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$repo_root/$script" ] || { echo "no such script: $script" >&2; exit 2; }

# -i is required: without it the container's bash reads an empty stdin, runs no checks at all and
# exits 0. The PASS line is therefore also checked from the outside below, so a run that checked
# nothing cannot pass.
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
docker run --rm -i -v "$repo_root:/src:ro" -e SCRIPT="$script" "$image" bash -s <<'IN_CONTAINER' | tee "$out"
set -uo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }

if command -v dpkg-divert >/dev/null 2>&1; then
  # Package scripts call /usr/bin/systemctl by absolute path. Divert it so a later install of the
  # systemd package lands beside the stub instead of over it.
  dpkg-divert --quiet --local --rename --add /usr/bin/systemctl
  family=deb
else
  dnf -y -q install systemd util-linux shadow-utils >/dev/null
  family=rpm
fi
printf '#!/bin/sh\nexit 0\n' > /usr/bin/systemctl
chmod +x /usr/bin/systemctl

run() { bash "/src/$SCRIPT" > "/tmp/$1.log" 2>&1; echo $?; }
show_tail() { echo "--- last lines of $1:"; tail -25 "/tmp/$1.log"; }

rc=$(run first)
[ "$rc" = 0 ] || { show_tail first; fail "first run exited $rc"; }
grep -q '^Install complete.' /tmp/first.log || { show_tail first; fail "first run did not reach 'Install complete.'"; }

if [ "$family" = deb ]; then
  installed=$(dpkg-query -W -f='${Version}' wfa 2>/dev/null) || fail "wfa is not installed after the first run"
else
  installed=$(rpm -q --qf '%{VERSION}' wfa 2>/dev/null) || fail "wfa is not installed after the first run"
fi

# Second run: as the image build runs it, pinned to the version just installed. It must keep
# existing Docker data, end on exactly that version, and leave no package hold behind.
install -d /docker
echo keep > /docker/existing-data
export WFA_VERSION="$installed" WFA_FLOOR="$installed"
rc=$(run second)
unset WFA_VERSION WFA_FLOOR
[ "$rc" = 0 ] || { show_tail second; fail "pinned second run exited $rc"; }
[ -f /docker/existing-data ] || fail "second run deleted existing Docker data"
if [ "$family" = deb ]; then
  [ -z "$(apt-mark showhold)" ] || fail "the pinned run left packages on hold: $(apt-mark showhold | tr '\n' ' ')"
fi

# Third run: a floor above any real version must stop the install.
rc=$(WFA_FLOOR=999.0 run floor)
[ "$rc" != 0 ] || fail "a WFA_FLOOR above the installed version did not stop the install"
grep -q "below the required floor 999.0" /tmp/floor.log || { show_tail floor; fail "the floor failure did not say why"; }

useradd -m tester
su tester -s /bin/bash -c "bash /src/$SCRIPT" > /tmp/nonroot.log 2>&1
rc=$?
[ "$rc" = 1 ] || fail "non-root run exited $rc, expected 1"

if [ "$family" = deb ]; then
  wfa_version=$(dpkg-query -W -f='${Version}' wfa 2>/dev/null) || fail "wfa is not installed"
  dpkg-query -W docker-ce >/dev/null 2>&1 || fail "docker-ce is not installed"
else
  wfa_version=$(rpm -q --qf '%{VERSION}' wfa 2>/dev/null) || fail "wfa is not installed"
  rpm -q docker-ce >/dev/null 2>&1 || fail "docker-ce is not installed"
fi
command -v growpart >/dev/null || fail "growpart is not installed (expand-disk.sh needs it)"
grep -q '"data-root": "/docker"' /etc/docker/daemon.json || fail "daemon.json does not set data-root /docker"
grep -q '^SystemMaxUse=1G' /etc/systemd/journald.conf.d/10-witfoo.conf || fail "journald is not bounded"

echo "PASS: $SCRIPT on $(. /etc/os-release; echo "$PRETTY_NAME"): wfa $wfa_version"
grep -E '^WARNING' /tmp/first.log | sed 's/^/  first run: /' || true
IN_CONTAINER

if ! grep -q "^PASS: $script on " "$out"; then
  echo "FAIL: the in-container checks did not report PASS for $script" >&2
  exit 1
fi
