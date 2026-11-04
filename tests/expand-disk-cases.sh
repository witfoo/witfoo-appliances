#!/bin/bash
#
# The cases tests/expand-disk-in-container.sh runs inside its container. Do not run this file
# directly: it creates loop devices, volume groups and filesystems, and refuses to start outside
# that container.
#
# Each case builds a layout on loop devices backed by sparse files, mounts it at /data, grows the
# files to imitate a disk grown at the hypervisor (or attaches a new one), runs expand-disk.sh
# and checks the result: every physical volume fills its device, no extent is left free, the
# filesystem fills the logical volume, and a file written beforehand is still there.
set -uo pipefail
exec </dev/null

if [ "${EXPAND_DISK_RIG:-}" != 1 ] || [ ! -f /.dockerenv ]; then
  echo "refusing to run: this file is run by tests/expand-disk-in-container.sh in a container" >&2
  exit 2
fi

# Every case calls start, and must reach finish (end_case calls it). A case that stops early, for
# example on a shell error inside a check, therefore fails the run instead of disappearing.
EXPECTED_CASES=34

MiB=$((1024 * 1024))
SMALL=512M
LARGE=1G
LOOPS=()
FILES=()
VGS=()
DMS=()
CASES=0
DONE=0
CASE=setup

MAIN_PID=$$
FAILED_FILE=/tmp/expand-disk-rig.failed
rm -f "$FAILED_FILE"

# fail <message>: report the failed check and stop the run. In a command substitution (a
# measurement such as d=$(size ...)), exit ends only that subshell, so fail also signals the main
# shell, whose TERM trap ends the run; the run also checks FAILED_FILE before reporting PASS.
fail() {
  echo "FAIL: $CASE: $*" >&2
  echo "FAIL: $CASE: $*" >> "$FAILED_FILE"
  if [ "$BASHPID" != "$MAIN_PID" ]; then
    kill -TERM "$MAIN_PID"
  fi
  exit 1
}
note() { echo "== $*"; }

# Device-mapper names are global on the host, so every name carries the container's ID (its
# hostname): rigs running side by side cannot collide.
host_id=$(tr -cd 'a-z0-9' < /proc/sys/kernel/hostname | cut -c1-12)
[ -n "$host_id" ] || fail "no container hostname to tag devices with"
TAG="edt${host_id}${RANDOM}"
# The disk images' paths are unique too: RHEL's LVM devices file names a loop device by the path
# of its backing file, and a rig running beside this one has the same paths in its container.
RIG="/rig-$TAG"

retry() {
  local i
  for i in 1 2 3 4 5; do
    "$@" >/dev/null 2>&1 && return 0
    sleep "$i"
  done
  "$@"
}

remove_vgs() {
  local vg uuid
  for vg in "${VGS[@]}"; do
    vgreduce --removemissing --force "$vg" >/dev/null 2>&1
    for uuid in $(vgs --noheadings -o vg_uuid -S "vg_name=$vg" 2>/dev/null); do
      retry vgremove -ff -y -S "vg_uuid=$uuid" || return 1
    done
  done
}

remove_all() {
  local dm dev rc=0
  mountpoint -q /data && { retry umount /data || rc=1; }
  mountpoint -q /mnt/other && { retry umount /mnt/other || rc=1; }
  remove_vgs || rc=1
  for dm in "${DMS[@]}"; do
    retry dmsetup remove "$dm" || rc=1
  done
  for dev in "${LOOPS[@]}"; do
    retry losetup -d "$dev" || rc=1
  done
  return $rc
}

# What of this run is still on the host: device-mapper devices with its tag, and loop devices
# backed by its files (losetup -j matches the file itself).
leftovers() {
  local f list
  if list=$(dmsetup ls 2>&1); then
    grep -F "$TAG" <<< "$list"
  else
    echo "could not list device-mapper devices: $list"
  fi
  for f in "${FILES[@]}"; do
    if [ -e "$f" ] && ! losetup -j "$f" 2>&1; then
      echo "could not list the loop devices of $f"
    fi
  done
  return 0
}

cleanup() {
  local left
  # A second signal must not cut the cleanup short.
  trap '' TERM INT HUP
  set +u
  remove_all >/dev/null 2>&1
  left=$(leftovers)
  if [ -n "$left" ]; then
    echo "LEFTOVER on the host from this run (remove with dmsetup remove / losetup -d):" >&2
    echo "$left" >&2
    exit 1
  fi
}
trap cleanup EXIT
trap 'exit 143' TERM INT HUP

# ---- Tools and LVM isolation ------------------------------------------------

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if ! { apt-get update -qq >/dev/null &&
    apt-get install -y -qq lvm2 xfsprogs e2fsprogs cloud-guest-utils fdisk parted util-linux \
      >/dev/null 2>&1; }; then
    fail "could not install the tools"
  fi
  GROWPART_PACKAGE=cloud-guest-utils
else
  dnf -y -q install lvm2 xfsprogs e2fsprogs cloud-utils-growpart parted util-linux shadow-utils \
    >/dev/null 2>&1 || fail "could not install the tools"
  GROWPART_PACKAGE=cloud-utils-growpart
fi

# No udev in the container: libdevmapper creates the device nodes itself and does not wait for
# udev events that never come.
export DM_DISABLE_UDEV=1

# LVM in the container sees only this rig's devices: update_filter rewrites its device filter to
# accept exactly the loop devices (and their partitions) and device-mapper devices the rig holds,
# whenever that set changes. So neither the rig nor the script under test can find, grow or extend
# a volume group on the host's disks, or on the loop devices of another rig running beside it.
# Where the filter does not apply, on RHEL's LVM while its devices file exists, that file lists
# only devices the rig added.
update_filter() {
  local x accept=""
  for x in "${LOOPS[@]}"; do
    accept+="\"a|^${x}(p[0-9]+)?\$|\", "
  done
  for x in "${DMS[@]}"; do
    accept+="\"a|^/dev/mapper/${x}\$|\", "
  done
  printf 'devices {\n  global_filter = [ %s"r|.*|" ]\n}\n' "$accept" > /etc/lvm/lvmlocal.conf ||
    fail "could not write the LVM device filter"
}
update_filter
lvmconfig devices/global_filter 2>/dev/null | grep -qF '"r|.*|"' ||
  fail "LVM did not take the rig's device filter"

# Hide the SCSI hosts and devices from the script's rescan, which would otherwise rescan the
# host's disks. (A read-only /sys would also stop the kernel reading the rig's partition tables.)
for d in /sys/class/scsi_host /sys/class/scsi_device; do
  if [ -d "$d" ]; then
    mount -t tmpfs -o size=1m tmpfs "$d" || fail "could not hide $d"
  fi
done

mkdir -p "$RIG" /data /mnt/other /rigbin /rigbin-offline
mount -t tmpfs -o size=8g tmpfs "$RIG" || fail "could not mount a tmpfs for the disk images"

# Stubs that fail like a package manager with no network, for the offline cases.
for pm in apt-get dnf yum; do
  printf '#!/bin/sh\necho "%s: no network (rig stub)" >&2\nexit 1\n' "$pm" > "/rigbin-offline/$pm"
  chmod +x "/rigbin-offline/$pm"
done

# ---- Helpers ----------------------------------------------------------------

# owned <device>: fail unless the device is one this rig created: one of its loop devices, a
# partition of one, one of its device-mapper devices, or a logical volume in one of its volume
# groups.
owned() {
  local dev="$1" x
  if [[ "$dev" =~ ^(/dev/loop[0-9]+)(p[0-9]+)?$ ]]; then
    for x in "${LOOPS[@]}"; do
      [ "$x" = "${BASH_REMATCH[1]}" ] && return 0
    done
  elif [[ "$dev" == /dev/mapper/* ]]; then
    for x in "${DMS[@]}"; do
      [ "$dev" = "/dev/mapper/$x" ] && return 0
    done
  elif [[ "$dev" == /dev/vg_"${TAG}"_?/* ]]; then
    # A logical volume in one of the rig's volume groups.
    return 0
  fi
  fail "refusing to touch $dev: not a device this rig created"
}

# num <value> <what>: fail unless the value is a whole number, so that a measurement that
# failed can never pass a comparison.
num() {
  [[ "$1" =~ ^[0-9]+$ ]] || fail "could not read $2 (got '$1')"
}

size() {
  local s
  s=$(blockdev --getsize64 "$1" 2>/dev/null)
  num "$s" "the size of $1"
  echo "$s"
}
fs_bytes() { df -B1 --output=size /data | tail -1 | tr -d ' '; }
lv_bytes() { lvs --noheadings --units b --nosuffix -o lv_size "$1/lv_data" 2>/dev/null | tr -d ' '; }
pv_bytes() { pvs --noheadings --units b --nosuffix -o pv_size "$1" 2>/dev/null | tr -d ' '; }
vg_free() { vgs --noheadings -o vg_free_count "$1" 2>/dev/null | tr -d ' '; }
vg_pvs() { pvs --noheadings -o pv_name -S "vg_name=$1" 2>/dev/null | tr -d ' ' | sort | tr '\n' ' '; }

wait_node() {
  local i
  for i in $(seq 50); do
    [ -b "$1" ] && return 0
    sleep 0.1
  done
  fail "$1 did not appear"
}

GPT_LINUX=0FC63DAF-8483-4772-8E79-3D69D8477DE4
GPT_LVM=E6D6D379-F507-44C2-A23C-238F2A3DF928
GPT_BIOS_BOOT=21686148-6449-6E6F-744E-656564454649

# table <line>...: write an sfdisk script to $DISK_FILE, and check a table is there.
table() {
  printf '%s\n' "$@" | sfdisk -q "$DISK_FILE" >/dev/null || fail "sfdisk $DISK_FILE"
  [ -n "$(wipefs --no-act --noheadings "$DISK_FILE")" ] || fail "sfdisk wrote no table to $DISK_FILE"
}

# new_disk <size> [layout]: a new loop device on a sparse file; sets DISK and DISK_FILE, and PART
# to the last partition. The layout is written to the file before the loop device is attached,
# so the kernel reads the partition table as it attaches; a re-read afterwards can fail while
# the host's udev has the new device open.
#   (none)  no partition table
#   one     GPT, one partition over the whole disk
#   boot    GPT, a 1 MiB BIOS boot partition and an LVM partition after it (the images' layout)
#   empty   GPT with no partitions
#   mbr     MBR (dos), one partition over the whole disk
# The tables are written with sfdisk (util-linux): AlmaLinux 10 has no gdisk package.
new_disk() {
  local n=${#FILES[@]}
  DISK_FILE="$RIG/disk$n.img"
  PART=""
  truncate -s "$1" "$DISK_FILE" || fail "truncate $DISK_FILE"
  case "${2:-}" in
    "") ;;
    one) table "label: gpt" "start=2048, type=$GPT_LINUX" ;;
    boot) table "label: gpt" "start=2048, size=2048, type=$GPT_BIOS_BOOT" "type=$GPT_LVM" ;;
    empty) table "label: gpt" ;;
    mbr) table "label: dos" "start=2048, type=83" ;;
    *) fail "unknown layout $2" ;;
  esac
  attach "$DISK_FILE"
  FILES+=("$DISK_FILE")
  case "${2:-}" in
    one|mbr) PART="${DISK}p1" ;;
    boot) PART="${DISK}p2" ;;
  esac
  [ -z "$PART" ] || wait_node "$PART"
}

# attach <file>: a loop device for the file; sets DISK.
attach() {
  DISK=$(losetup -f --show -P "$1") || fail "losetup $1"
  LOOPS+=("$DISK")
  update_filter
}

# detach <device>: detach one of the rig's loop devices and forget it.
detach() {
  local x keep=()
  owned "$1"
  retry losetup -d "$1" || fail "losetup -d $1"
  for x in "${LOOPS[@]}"; do
    [ "$x" = "$1" ] || keep+=("$x")
  done
  LOOPS=("${keep[@]}")
  update_filter
}

# grow_disk <device> <file> <size>: what growing a disk at the hypervisor looks like to the guest.
grow_disk() {
  owned "$1"
  truncate -s "$3" "$2" || fail "truncate $2"
  losetup -c "$1" || fail "losetup -c $1"
  [ "$(size "$1")" -ge $((900 * MiB)) ] || fail "$1 did not grow"
}

# make_vg <vg> <pv>...: autoactivation off, so a host running LVM does not activate it.
make_vg() {
  local vg="$1" pv
  shift
  for pv in "$@"; do
    owned "$pv"
    pvcreate -q -y "$pv" >/dev/null || fail "pvcreate $pv"
  done
  vgcreate -q --setautoactivation n "$vg" "$@" >/dev/null || fail "vgcreate $vg"
  VGS+=("$vg")
}

make_lv() {
  lvcreate -q -y -n lv_data -l 100%FREE "$@" >/dev/null || fail "lvcreate in $1"
}

# mkfs_mount <fs> <device>: make the filesystem, mount it at /data and write a marker file.
mkfs_mount() {
  owned "$2"
  case "$1" in
    xfs) mkfs.xfs -q -f "$2" >/dev/null || fail "mkfs.xfs $2" ;;
    ext4) mkfs.ext4 -q -F "$2" >/dev/null || fail "mkfs.ext4 $2" ;;
  esac
  mount "$2" /data || fail "mount $2"
  echo "$CASE" > /data/marker || fail "write /data/marker"
  MARKER="$CASE"
  sync
}

start() {
  [ "$CASES" = "$DONE" ] || fail "the previous case did not finish"
  CASE="$1"
  CASES=$((CASES + 1))
  CASE_FINISHED=no
  LOG="$RIG/case$CASES.log"
  note "$CASE"
}

# finish: the current case reached its end (once, however often it is called).
finish() {
  if [ "$CASE_FINISHED" = no ]; then
    DONE=$((DONE + 1))
    CASE_FINISHED=yes
  fi
}

# expand [args...]: run the script under test; sets RC.
expand() {
  bash /src/expand-disk.sh "$@" > "$LOG" 2>&1
  RC=$?
}

show() { echo "--- expand-disk.sh output:"; tail -40 "$LOG"; }
expect_rc() { [ "$RC" = "$1" ] || { show; fail "exited $RC, expected $1"; }; }
expect_log() { grep -qF -e "$1" "$LOG" || { show; fail "the output does not say: $1"; }; }
expect_no_log() { ! grep -qF -e "$1" "$LOG" || { show; fail "the output says: $1"; }; }
expect_marker() { [ "$(cat /data/marker 2>/dev/null)" = "$MARKER" ] || fail "the marker file in /data is gone"; }

# before_growth: record the filesystem size. check_filled requires it to grow, and to end at
# 85% of a device about twice its size, so a script that does nothing cannot pass.
before_growth() {
  FS_BEFORE=$(fs_bytes)
  num "$FS_BEFORE" "the size of /data"
}

# check_filled <device size>: the filesystem grew and now fills the device under it.
check_filled() {
  local target="$1" after
  num "$target" "the size under /data"
  after=$(fs_bytes)
  num "$after" "the size of /data"
  [ "$after" -gt "$FS_BEFORE" ] || { show; fail "/data did not grow ($FS_BEFORE -> $after bytes)"; }
  [ $((after * 100)) -ge $((target * 85)) ] ||
    { show; fail "/data is $after bytes on a $target-byte device"; }
  expect_no_log "/data did not grow"
  expect_marker
}

# pv_fills <pv>: the physical volume fills its device (less its metadata and extent rounding).
pv_fills() {
  local dev psz
  dev=$(size "$1")
  psz=$(pv_bytes "$1")
  num "$psz" "the size of PV $1"
  [ $((dev - psz)) -lt $((8 * MiB)) ] || { show; fail "PV $1 is $psz bytes on a $dev-byte device"; }
}

# check_lvm <vg> <pv>...: every PV fills its device, no extent is free, /data fills the LV.
check_lvm() {
  local vg="$1" pv free
  shift
  free=$(vg_free "$vg")
  num "$free" "the free extents of $vg"
  [ "$free" = 0 ] || { show; fail "$free extents are still free in $vg"; }
  for pv in "$@"; do
    pv_fills "$pv"
  done
  check_filled "$(lv_bytes "$vg")"
}

# check_partition <disk> <partition>: the partition reaches the end of the disk.
check_partition() {
  local d p
  d=$(size "$1")
  p=$(size "$2")
  [ $((d - p)) -lt $((3 * MiB)) ] || { show; fail "$2 is $p bytes on a $d-byte disk"; }
}

# run_again [vg] [why]: the case's layout has nothing more to grow into. The script must change
# nothing, exit 0 and say so, with the given reason (by default, no space on its disks).
run_again() {
  local vg="${1:-}" why="${2:-No unallocated space was found on its disks (}" fs lv=""
  start "$CASE, run again"
  fs=$(fs_bytes)
  num "$fs" "the size of /data"
  if [ -n "$vg" ]; then
    lv=$(lv_bytes "$vg")
    num "$lv" "the size of the logical volume"
  fi
  expand
  expect_rc 0
  [ "$(fs_bytes)" = "$fs" ] || { show; fail "/data changed on a second run"; }
  [ -z "$vg" ] || [ "$(lv_bytes "$vg")" = "$lv" ] || fail "the logical volume changed"
  expect_log "/data did not grow."
  expect_log "$why"
  expect_marker
  finish
}

# loop_released <file>: no loop device uses the file. losetup -d on a busy device only marks it
# to be released when it is closed, so this is checked before the file is deleted.
loop_released() {
  local out
  out=$(losetup -j "$1" 2>&1) || return 1
  [ -z "$out" ]
}

end_case() {
  local f
  remove_all || fail "could not remove this case's devices"
  for f in "${FILES[@]}"; do
    retry loop_released "$f" || fail "a loop device still uses $f"
    rm -f "$f"
  done
  VGS=()
  DMS=()
  LOOPS=()
  FILES=()
  update_filter
  # RHEL's LVM keeps a devices file; entries for this case's devices would otherwise collide
  # with the next case's loop devices, which reuse the same names.
  rm -f /etc/lvm/devices/system.devices
  finish
}

# hide_growpart / show_growpart: take growpart away for a case, and put it back.
hide_growpart() {
  GROWPART_PATH=$(command -v growpart) || fail "growpart is not installed"
  mv "$GROWPART_PATH" "$GROWPART_PATH.rig-hidden" || fail "could not hide growpart"
}
show_growpart() {
  mv "$GROWPART_PATH.rig-hidden" "$GROWPART_PATH" || fail "could not restore growpart"
}

# ---- Cases: LVM -------------------------------------------------------------

lvm_on_partition() {
  local fs="$1" vg="vg_${TAG}_a"
  start "LVM on a partition, $fs"
  new_disk "$SMALL" boot
  make_vg "$vg" "$PART"
  make_lv "$vg"
  mkfs_mount "$fs" "/dev/$vg/lv_data"
  before_growth
  grow_disk "$DISK" "$DISK_FILE" "$LARGE"
  expand
  expect_rc 0
  expect_log "Partition successfully grown"
  expect_log " Expansion Complete"
  check_partition "$DISK" "$PART"
  check_lvm "$vg" "$PART"
  finish
  run_again "$vg"
  end_case
}

lvm_whole_disk() {
  local vg="vg_${TAG}_b"
  start "LVM on a whole disk, xfs"
  new_disk "$SMALL"
  make_vg "$vg" "$DISK"
  make_lv "$vg"
  mkfs_mount xfs "/dev/$vg/lv_data"
  before_growth
  grow_disk "$DISK" "$DISK_FILE" "$LARGE"
  expand
  expect_rc 0
  expect_log "It is a whole disk"
  check_lvm "$vg" "$DISK"
  finish
  run_again "$vg"
  end_case
}

# two_pvs <fs> [failing-growpart]: a partition PV and a whole-disk PV, both grown, with a second
# logical volume that must keep its size.
two_pvs() {
  local fs="$1" vg="vg_${TAG}_c" d1 f1 p1 d2 f2 p1_before path="$PATH"
  start "LVM over a partition and a whole disk, $fs${2:+, growpart fails}"
  new_disk "$SMALL" boot
  d1="$DISK" f1="$DISK_FILE" p1="$PART"
  new_disk "$SMALL"
  d2="$DISK" f2="$DISK_FILE"
  make_vg "$vg" "$p1" "$d2"
  lvcreate -q -y -n lv_other -L 64M "$vg" >/dev/null || fail "lvcreate lv_other"
  make_lv "$vg"
  mkfs_mount "$fs" "/dev/$vg/lv_data"
  before_growth
  grow_disk "$d1" "$f1" "$LARGE"
  grow_disk "$d2" "$f2" "$LARGE"
  p1_before=$(size "$p1")
  num "$p1_before" "the size of $p1"
  if [ -n "${2:-}" ]; then
    printf '#!/bin/sh\necho "FAILED: growpart stub for the rig" >&2\nexit 2\n' > /rigbin/growpart
    chmod +x /rigbin/growpart
    path="/rigbin:$PATH"
  fi
  PATH="$path" expand
  if [ -n "${2:-}" ]; then
    rm -f /rigbin/growpart
    expect_rc 1
    expect_log " Expansion Incomplete"
    expect_log "these partitions were not grown: $d1 partition 2 (growpart exit code 2)"
    # The partition is unchanged; the whole disk was still added to /data.
    [ "$(size "$p1")" = "$p1_before" ] || fail "$p1 changed size"
    [ "$(vg_free "$vg")" = 0 ] || { show; fail "free extents left in $vg"; }
    pv_fills "$d2"
    check_filled "$(lv_bytes "$vg")"
  else
    expect_rc 0
    check_partition "$d1" "$p1"
    check_lvm "$vg" "$p1" "$d2"
  fi
  [ "$(lvs --noheadings --units m --nosuffix -o lv_size "$vg/lv_other" | tr -d ' ')" = "64.00" ] ||
    fail "lv_other changed size"
  finish
  [ -n "${2:-}" ] || run_again "$vg"
  end_case
}

# A whole-disk volume needs no growpart: the script must not ask for it.
no_growpart_whole_disk() {
  local vg="vg_${TAG}_b"
  start "LVM on a whole disk without growpart, offline"
  new_disk "$SMALL"
  make_vg "$vg" "$DISK"
  make_lv "$vg"
  mkfs_mount ext4 "/dev/$vg/lv_data"
  before_growth
  grow_disk "$DISK" "$DISK_FILE" "$LARGE"
  hide_growpart
  PATH="/rigbin-offline:$PATH" expand
  show_growpart
  expect_rc 0
  expect_no_log "Installing growpart"
  check_lvm "$vg" "$DISK"
  end_case
}

# no_growpart_partition <grow|keep>: a partition PV and a whole-disk PV, offline, without
# growpart. When the partition's disk grew, the partition cannot be grown: the whole disk is still
# used and the script exits 1. When it did not grow, nothing needs growpart: exit 0.
no_growpart_partition() {
  local vg="vg_${TAG}_c" d1 f1 p1 d2 f2 p1_before what=grown
  [ "$1" = grow ] || what="not grown"
  start "LVM over a partition (its disk $what) and a whole disk, without growpart, offline"
  new_disk "$SMALL" boot
  d1="$DISK" f1="$DISK_FILE" p1="$PART"
  new_disk "$SMALL"
  d2="$DISK" f2="$DISK_FILE"
  make_vg "$vg" "$p1" "$d2"
  make_lv "$vg"
  mkfs_mount xfs "/dev/$vg/lv_data"
  before_growth
  [ "$1" = grow ] && grow_disk "$d1" "$f1" "$LARGE"
  grow_disk "$d2" "$f2" "$LARGE"
  p1_before=$(size "$p1")
  num "$p1_before" "the size of $p1"
  hide_growpart
  PATH="/rigbin-offline:$PATH" expand
  show_growpart
  if [ "$1" = grow ]; then
    expect_rc 1
    expect_log "growpart is not installed and"
    expect_log "these partitions were not grown: $d1 partition 2 (growpart is not installed)"
  else
    expect_rc 0
    expect_log "Partition 2 on $d1 has no space after it to grow into."
    expect_no_log "/data did not grow"
    expect_no_log "growpart is not installed"
  fi
  [ "$(size "$p1")" = "$p1_before" ] || fail "$p1 changed size"
  [ "$(vg_free "$vg")" = 0 ] || { show; fail "free extents left in $vg"; }
  pv_fills "$d2"
  check_filled "$(lv_bytes "$vg")"
  end_case
}

# The script installs growpart when it is missing and a partition must grow. On almalinux:10
# this is the install that failed while it also asked for gdisk.
growpart_installed() {
  local vg="vg_${TAG}_a"
  start "LVM on a partition, growpart installed by the script"
  new_disk "$SMALL" boot
  make_vg "$vg" "$PART"
  make_lv "$vg"
  mkfs_mount xfs "/dev/$vg/lv_data"
  before_growth
  grow_disk "$DISK" "$DISK_FILE" "$LARGE"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get remove -y -qq "$GROWPART_PACKAGE" >/dev/null 2>&1 || fail "could not remove growpart"
  else
    dnf -y -q remove "$GROWPART_PACKAGE" >/dev/null 2>&1 || fail "could not remove growpart"
  fi
  ! command -v growpart >/dev/null 2>&1 || fail "growpart is still installed"
  expand
  expect_rc 0
  expect_log "Installing growpart utility"
  expect_log "Partition successfully grown"
  command -v growpart >/dev/null 2>&1 || fail "growpart was not installed"
  check_partition "$DISK" "$PART"
  check_lvm "$vg" "$PART"
  end_case
}

# The device-mapper device maps the loop device from 1 MiB on, so the PV label it carries is not
# also at the start of the loop device: LVM reads labels only there, and would otherwise see the
# same PV twice.
dm_pv() {
  local vg="vg_${TAG}_h" dm="${TAG}-dmpv" d f sectors skip=2048
  start "LVM on a device-mapper device, ext4"
  new_disk "$SMALL"
  d="$DISK" f="$DISK_FILE"
  owned "$d"
  sectors=$(blockdev --getsz "$d")
  num "$sectors" "the sectors of $d"
  dmsetup create "$dm" --table "0 $((sectors - skip)) linear $d $skip" || fail "dmsetup create $dm"
  DMS+=("$dm")
  update_filter
  wait_node "/dev/mapper/$dm"
  make_vg "$vg" "/dev/mapper/$dm"
  make_lv "$vg"
  mkfs_mount ext4 "/dev/$vg/lv_data"
  before_growth
  grow_disk "$d" "$f" "$LARGE"
  # The device-mapper device is grown by hand, as the script tells the operator to: reload loads
  # the new table without suspending the device, and resume swaps it in. (Suspending first would
  # leave I/O to /data blocked if the reload failed.)
  sectors=$(blockdev --getsz "$d")
  num "$sectors" "the sectors of $d"
  owned "/dev/mapper/$dm"
  dmsetup reload "$dm" --table "0 $((sectors - skip)) linear $d $skip" || fail "could not reload $dm"
  dmsetup resume "$dm" || fail "could not resume $dm"
  expand
  expect_rc 0
  expect_log "It is a device-mapper or RAID device."
  check_lvm "$vg" "/dev/mapper/$dm"
  finish
  run_again "$vg" "Its device-mapper or RAID devices (/dev/mapper/$dm) have not grown"
  expect_no_log "No unallocated space was found on its disks"
  end_case
}

# /data on a device-mapper device that is not LVM (an encrypted volume, for example): the script
# cannot grow it and must say so before changing anything.
dm_plain() {
  local dm="${TAG}-dmfs" d sectors
  start "filesystem on a device-mapper device that is not LVM"
  new_disk "$SMALL"
  d="$DISK"
  owned "$d"
  sectors=$(blockdev --getsz "$d")
  num "$sectors" "the sectors of $d"
  dmsetup create "$dm" --table "0 $sectors linear $d 0" || fail "dmsetup create $dm"
  DMS+=("$dm")
  update_filter
  wait_node "/dev/mapper/$dm"
  mkfs_mount ext4 "/dev/mapper/$dm"
  before_growth
  expand
  expect_rc 1
  expect_log "which is neither a partition, a whole"
  [ "$(fs_bytes)" = "$FS_BEFORE" ] || fail "/data changed"
  end_case
}

# The script's LVM commands name /data's volume group, so a second volume group of that name (a
# disk attached from another appliance) must stop it before it changes anything.
duplicate_vg_name() {
  local vg="vg_${TAG}_f" da fa db fb pva pvb count
  start "two volume groups named like /data's"
  new_disk "$SMALL"
  db="$DISK" fb="$DISK_FILE"
  make_vg "$vg" "$db"
  detach "$db"
  new_disk "$SMALL"
  da="$DISK" fa="$DISK_FILE"
  make_vg "$vg" "$da"
  make_lv "$vg"
  mkfs_mount xfs "/dev/$vg/lv_data"
  before_growth
  grow_disk "$da" "$fa" "$LARGE"
  attach "$fb"
  db="$DISK"
  rm -f /etc/lvm/devices/system.devices
  count=$(vgs --noheadings -o vg_uuid -S "vg_name=$vg" 2>/dev/null | wc -l)
  [ "$count" = 2 ] || fail "the rig made $count volume groups named $vg, not 2"
  pva=$(pv_bytes "$da")
  num "$pva" "the size of PV $da"
  pvb=$(pv_bytes "$db")
  num "$pvb" "the size of PV $db"
  expand
  expect_rc 1
  expect_log "2 volume groups are named $vg (expected 1)"
  [ "$(pv_bytes "$da")" = "$pva" ] || fail "PV $da was resized"
  [ "$(pv_bytes "$db")" = "$pvb" ] || fail "PV $db was resized"
  [ "$(fs_bytes)" = "$FS_BEFORE" ] || fail "/data changed"
  end_case
}

missing_pv() {
  local vg="vg_${TAG}_g" da db lv
  start "a volume group with a missing physical volume"
  new_disk "$SMALL"
  da="$DISK"
  new_disk "$SMALL"
  db="$DISK"
  make_vg "$vg" "$da" "$db"
  # The logical volume lies on the first disk only, so the second can be detached.
  lvcreate -q -y -n lv_data -l 100%PVS "$vg" "$da" >/dev/null || fail "lvcreate in $vg"
  mkfs_mount ext4 "/dev/$vg/lv_data"
  detach "$db"
  before_growth
  lv=$(lv_bytes "$vg")
  num "$lv" "the size of the logical volume"
  expand
  expect_rc 1
  expect_log "has a missing physical volume"
  [ "$(lv_bytes "$vg")" = "$lv" ] || fail "the logical volume changed"
  [ "$(fs_bytes)" = "$FS_BEFORE" ] || fail "/data changed"
  expect_marker
  end_case
}

# ---- Cases: no LVM ----------------------------------------------------------

# plain_partition <fs> [mbr]
plain_partition() {
  local fs="$1" layout="${2:-one}"
  start "plain partition${2:+ on an MBR disk}, $fs"
  new_disk "$SMALL" "$layout"
  mkfs_mount "$fs" "$PART"
  before_growth
  grow_disk "$DISK" "$DISK_FILE" "$LARGE"
  expand
  expect_rc 0
  expect_log "Layout: plain partition (no LVM)"
  check_partition "$DISK" "$PART"
  check_filled "$(size "$PART")"
  finish
  run_again
  end_case
}

# /data on a plain partition, beside another volume group with an LV named exactly "data": the
# old script took any LV named "data" for /data's. The script must leave that volume group alone.
plain_beside_data() {
  local vg="vg_${TAG}_i" od of lvb pvb
  start "plain partition beside another volume group's LV named data, xfs"
  new_disk "$SMALL"
  od="$DISK" of="$DISK_FILE"
  make_vg "$vg" "$od"
  lvcreate -q -y -n data -l 100%FREE "$vg" >/dev/null || fail "lvcreate data"
  # Its disk has grown too, so taking that volume group for /data's would change it.
  grow_disk "$od" "$of" "$LARGE"
  lvb=$(lvs --noheadings --units b --nosuffix -o lv_size "$vg/data" 2>/dev/null | tr -d ' ')
  num "$lvb" "the size of $vg/data"
  pvb=$(pv_bytes "$od")
  num "$pvb" "the size of PV $od"
  new_disk "$SMALL" one
  mkfs_mount xfs "$PART"
  before_growth
  grow_disk "$DISK" "$DISK_FILE" "$LARGE"
  expand
  expect_rc 0
  expect_log "Layout: plain partition (no LVM)"
  check_partition "$DISK" "$PART"
  check_filled "$(size "$PART")"
  [ "$(lvs --noheadings --units b --nosuffix -o lv_size "$vg/data" | tr -d ' ')" = "$lvb" ] ||
    fail "$vg/data changed size"
  [ "$(pv_bytes "$od")" = "$pvb" ] || fail "PV $od was resized"
  end_case
}

plain_whole_disk() {
  start "filesystem on a whole disk, ext4"
  new_disk "$SMALL"
  mkfs_mount ext4 "$DISK"
  before_growth
  grow_disk "$DISK" "$DISK_FILE" "$LARGE"
  expand
  expect_rc 0
  expect_log "Layout: filesystem on a whole disk (no LVM)"
  check_filled "$(size "$DISK")"
  finish
  run_again
  end_case
}

# ---- Cases: --add-disk ------------------------------------------------------

add_disk() {
  local vg="vg_${TAG}_d" d1 d2
  start "--add-disk, xfs"
  new_disk "$SMALL"
  d1="$DISK"
  make_vg "$vg" "$d1"
  make_lv "$vg"
  mkfs_mount xfs "/dev/$vg/lv_data"
  before_growth
  new_disk "$SMALL"
  d2="$DISK"
  expand --add-disk "$d2"
  expect_rc 0
  expect_log "Disk added"
  [ "$(vg_pvs "$vg")" = "$(printf '%s\n' "$d1" "$d2" | sort | tr '\n' ' ')" ] ||
    { show; fail "$vg has PVs $(vg_pvs "$vg"), expected $d1 and $d2"; }
  check_lvm "$vg" "$d1" "$d2"
  end_case
}

# signatures <device>: what wipefs finds, or "absent" for a device that does not exist.
signatures() {
  if [ -e "$1" ]; then
    wipefs --no-act --noheadings "$1" 2>&1 || fail "wipefs $1"
  else
    echo absent
  fi
}

# refuse <candidate> <message>: the script exits 1, says why, and neither /data's volume group,
# its logical volume, nor the candidate changed. Uses REF_VG, REF_LV and REF_PVS. The message is
# the refusal's ERROR line, device included, so a different refusal sharing a few words (such as
# "could not check whether '<dev>' is mounted.") cannot satisfy it.
refuse() {
  local dev="$1" before after
  before=$(signatures "$dev")
  expand --add-disk "$dev"
  expect_rc 1
  expect_log "$2"
  [ "$(vg_pvs "$REF_VG")" = "$REF_PVS" ] || { show; fail "$REF_VG changed: $(vg_pvs "$REF_VG")"; }
  [ "$(lv_bytes "$REF_VG")" = "$REF_LV" ] || { show; fail "the logical volume changed size"; }
  after=$(signatures "$dev")
  [ "$before" = "$after" ] || fail "$dev changed: [$before] -> [$after]"
}

add_disk_refusals() {
  local d1
  REF_VG="vg_${TAG}_e"
  start "--add-disk refusals"
  new_disk "$SMALL"
  d1="$DISK"
  make_vg "$REF_VG" "$d1"
  make_lv "$REF_VG"
  mkfs_mount ext4 "/dev/$REF_VG/lv_data"
  REF_LV=$(lv_bytes "$REF_VG")
  num "$REF_LV" "the size of the logical volume"
  REF_PVS=$(vg_pvs "$REF_VG")
  [ -n "$REF_PVS" ] || fail "could not list the PVs of $REF_VG"

  new_disk "$SMALL"
  owned "$DISK"
  mkfs.ext4 -q -F "$DISK" >/dev/null || fail "mkfs.ext4 $DISK"
  refuse "$DISK" "ERROR: '$DISK' is not blank."
  expect_log "ext4"

  new_disk "$SMALL"
  owned "$DISK"
  mkswap "$DISK" >/dev/null || fail "mkswap $DISK"
  refuse "$DISK" "ERROR: '$DISK' is not blank."
  expect_log "swap"

  new_disk "$SMALL" empty
  refuse "$DISK" "ERROR: '$DISK' is not blank."
  expect_log "gpt"

  new_disk "$SMALL" one
  refuse "$DISK" "ERROR: '$DISK' has partitions or volumes on it:"

  new_disk "$SMALL"
  owned "$DISK"
  mkfs.xfs -q -f "$DISK" >/dev/null || fail "mkfs.xfs $DISK"
  mount "$DISK" /mnt/other || fail "mount $DISK"
  refuse "$DISK" "ERROR: '$DISK' is mounted."
  umount /mnt/other || fail "umount /mnt/other"

  refuse "$d1" "ERROR: '$d1' is already an LVM physical volume:"
  refuse "/dev/$REF_VG/lv_data" "ERROR: '/dev/$REF_VG/lv_data' is a device-mapper or RAID device"
  refuse /dev/no-such-disk "ERROR: '/dev/no-such-disk' is not a block device."
  end_case

  # vgextend fails after pvcreate: the label pvcreate wrote is removed again.
  start "--add-disk, vgextend fails"
  new_disk "$SMALL"
  d1="$DISK"
  make_vg "$REF_VG" "$d1"
  make_lv "$REF_VG"
  mkfs_mount ext4 "/dev/$REF_VG/lv_data"
  REF_LV=$(lv_bytes "$REF_VG")
  num "$REF_LV" "the size of the logical volume"
  REF_PVS=$(vg_pvs "$REF_VG")
  [ -n "$REF_PVS" ] || fail "could not list the PVs of $REF_VG"
  new_disk "$SMALL"
  printf '#!/bin/sh\necho "vgextend stub for the rig" >&2\nexit 5\n' > /rigbin/vgextend
  chmod +x /rigbin/vgextend
  PATH="/rigbin:$PATH" refuse "$DISK" "ERROR: vgextend failed: $DISK was not added to $REF_VG."
  rm -f /rigbin/vgextend
  expect_log "The LVM label written to $DISK was removed again."
  end_case

  start "--add-disk on a plain partition"
  new_disk "$SMALL" one
  mkfs_mount ext4 "$PART"
  new_disk "$SMALL"
  expand --add-disk "$DISK"
  expect_rc 1
  expect_log "--add-disk needs /data on LVM"
  [ -z "$(signatures "$DISK")" ] || fail "$DISK was written to"
  end_case
}

# ---- Cases: preflight -------------------------------------------------------

preflight() {
  start "/data not mounted"
  expand
  expect_rc 1
  expect_log "/data is not a mounted filesystem"
  finish

  start "usage"
  expand --help
  expect_rc 0
  expect_log "add-disk"
  expand --bogus
  expect_rc 2
  expect_log "unknown argument"
  expand --add-disk
  expect_rc 2
  expect_log "needs a device"
  expand --add-disk=
  expect_rc 2
  expect_log "needs a device"
  expand --add-disk /dev/a --add-disk /dev/b
  expect_rc 2
  expect_log "give --add-disk once"
  finish

  start "not root"
  id tester >/dev/null 2>&1 || useradd -m tester || fail "useradd"
  su tester -s /bin/bash -c "bash /src/expand-disk.sh" > "$LOG" 2>&1
  RC=$?
  expect_rc 1
  expect_log "must be run as root"
  su tester -s /bin/bash -c "bash /src/expand-disk.sh --help" > "$LOG" 2>&1
  RC=$?
  expect_rc 0
  finish
}

lvm_on_partition xfs
lvm_on_partition ext4
lvm_whole_disk
two_pvs ext4
two_pvs xfs failing-growpart
no_growpart_whole_disk
no_growpart_partition grow
no_growpart_partition keep
growpart_installed
dm_pv
dm_plain
duplicate_vg_name
missing_pv
plain_partition xfs
plain_partition ext4
plain_partition ext4 mbr
plain_beside_data
plain_whole_disk
add_disk
add_disk_refusals
preflight

[ ! -s "$FAILED_FILE" ] || fail "a check failed: $(head -n 1 "$FAILED_FILE")"
[ "$DONE" = "$CASES" ] || fail "$CASES cases started, $DONE finished"
[ "$CASES" = "$EXPECTED_CASES" ] || fail "$CASES cases ran, $EXPECTED_CASES expected"
left=$(leftovers)
[ -z "$left" ] || fail "devices left on the host: $left"
echo "PASS: expand-disk on $(. /etc/os-release; echo "$PRETTY_NAME"): $CASES cases"
