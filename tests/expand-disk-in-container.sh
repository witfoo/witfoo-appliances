#!/bin/bash
#
# Test expand-disk.sh on real LVM volumes and filesystems, inside a throwaway container.
#
#   tests/expand-disk-in-container.sh <image>
#   tests/expand-disk-in-container.sh ubuntu:24.04
#   tests/expand-disk-in-container.sh almalinux:10
#
# The cases are in tests/expand-disk-cases.sh. Each builds a layout on loop devices backed by
# sparse files, mounts it at /data, grows the files to imitate a disk grown at the hypervisor (or
# attaches a new one), runs expand-disk.sh and checks the result.
#
# Cases:
#   LVM on a partition (the appliance images' layout), xfs and ext4; LVM on a whole disk (how
#     cloud data disks are used); LVM on a device-mapper device; LVM over two disks, one
#     partitioned and one whole, with a second logical volume. Each is then run again with
#     nothing to grow into
#   a growpart failure: the other disk is still used and the script exits 1
#   without growpart and offline: a whole-disk volume needs no growpart; a partition with space
#     after it is reported and the rest is still grown; a partition without space needs no
#     growpart. With growpart removed and the network up, the script installs it
#   two volume groups with /data's group name, a missing physical volume, and /data on a
#     device-mapper device that is not LVM: refused, nothing changes
#   a plain partition (xfs and ext4, and ext4 on an MBR disk) and a filesystem on a whole disk,
#     each run again; a plain partition beside another volume group with an LV named "data",
#     which must not be touched
#   --add-disk: a blank disk is added. A disk with a filesystem, swap, an empty partition table,
#     a partition, a mount, an existing physical volume, a logical volume and a missing device
#     are refused, and nothing changes. When vgextend fails, the label pvcreate wrote is removed.
#     --add-disk on a plain partition is refused
#   /data not mounted; usage errors; not root
#
# Not covered:
#   - name parsing: loop devices are named loopN, so these cases cannot show a defect in handling
#     names such as /dev/sdb or /dev/nvme1n1 (the script finds disks and partitions through sysfs
#     by device number);
#   - the refusal of a cloud's local (ephemeral) disk, which the script recognises by a model
#     string or a /dev/disk/by-id name that a loop device does not have;
#   - md RAID devices, and the SCSI and NVMe rescans (the rig hides the SCSI hosts; loop devices
#     have neither);
#   - choosing physical volumes by volume group UUID rather than name: with duplicate names
#     refused first, the two choose the same volumes.
#
# The container is privileged and shares the host's /dev, because loop partitions and
# device-mapper nodes appear there, and the kernel. Inside it:
#   - LVM sees only the devices the rig holds: a device filter in lvmlocal.conf, rewritten as
#     they change, lists them (on RHEL, while LVM's devices file exists, that file, which lists
#     only devices the rig added). So neither the rig nor the script under test can find a volume
#     group on the host's disks or on another rig's loop devices;
#   - every destructive step the rig takes checks that its device is one it created: a loop
#     device, a partition of one, a device-mapper device, or a logical volume in one of its
#     volume groups;
#   - empty mounts hide /sys/class/scsi_host and scsi_device, so the script's SCSI rescan cannot
#     rescan the host's disks; the rig resizes its loop devices with losetup instead;
#   - volume groups have autoactivation off, so a host running LVM leaves them alone.
# When it exits, by passing or failing, it removes its volume groups, device-mapper devices, loop
# devices and files, and fails if any are left. On SIGTERM or SIGINT it does the same once the
# command in progress ends, which can take longer than docker stop's default 10 s: use
# `docker stop -t 120`. Further signals during the cleanup are ignored. A SIGKILL (docker kill)
# leaves them. To remove them, find the run's tag (edt<id>) with `dmsetup ls | grep edt`, and
# remove every device-mapper device carrying it with `dmsetup remove`, the logical volumes
# (vg_edt<id>_*) before the edt<id>-* devices; then `losetup -d` each loop device whose backing
# file `losetup -l` shows as /rig-edt<id>/disk*.img.
#
# Exits non-zero, naming the failed check, if anything is wrong.
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <image>" >&2
  exit 2
fi
image="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# The container gets a copy of the script and the cases, so editing them during a run cannot
# change what it tests.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/src"
cp -r "$repo_root/expand-disk.sh" "$repo_root/tests" "$work/src/"
chmod -R a+rX "$work/src"

# No -i: the cases run with no stdin, so no command they start can read the script or a prompt's
# answer from it. Their output (stderr too) is checked from the outside: the PASS line with the
# count of cases must be there and no FAIL line, so a run that checked nothing cannot pass.
docker run --rm --privileged -v /dev:/dev -v "$work/src:/src:ro" -e EXPAND_DISK_RIG=1 "$image" \
  bash /src/tests/expand-disk-cases.sh 2>&1 | tee "$work/out"

if grep -q '^FAIL' "$work/out" || ! grep -qE '^PASS: expand-disk on .+: [0-9]+ cases$' "$work/out"; then
  echo "FAIL: the in-container checks did not report PASS" >&2
  exit 1
fi
