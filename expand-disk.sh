#!/bin/bash
# =============================================================================
# expand-disk.sh — Expand /data partition to use all available disk space
# =============================================================================
# Compatible with: Ubuntu 24, RHEL 10
# Hypervisors:     VMware, Hyper-V, QEMU/KVM
# Cloud:           AWS, Azure, Google Cloud
#
# Usage:
#   sudo ./expand-disk.sh                       grow /data into space added to its disks
#   sudo ./expand-disk.sh --add-disk /dev/sdc   add a new, blank disk to /data's volume group,
#                                               then grow /data
#
# Prerequisites:
#   1. Allocate additional disk space at the hypervisor or cloud layer, by growing a disk or by
#      attaching a new one
#   2. SSH into the appliance and run this script with sudo
#
# This script will:
#   - Find the device mounted at /data: an LVM logical volume, a partition, or a whole disk
#   - For LVM: grow every physical volume (PV) in /data's volume group. A PV on a partition has
#     its partition grown first; a PV that is a whole disk is resized directly. Then extend the
#     logical volume and resize the filesystem
#   - For a partition: grow it and resize the filesystem; for a whole disk: resize the filesystem
#   - With --add-disk: refuse a device that is not a blank disk or partition (see check_blank_disk
#     below), then add it to the volume group before growing /data
#
# Exit status: 0 when /data was grown or had nothing to grow into; 1 on an error, or when a
# partition that has space after it could not be grown; 2 on a usage error.
#
# See EXPAND_DISK.md for platform-specific instructions on expanding the
# underlying disk before running this script.
# =============================================================================

set -uo pipefail

usage() {
    cat <<'EOF'
Usage:
  expand-disk.sh                       grow /data into space added to its disks
  expand-disk.sh --add-disk <device>   add a new, blank disk to /data's volume group, then grow
                                       /data (LVM only)
  expand-disk.sh --help                show this help

Run as root. See EXPAND_DISK.md.
EOF
}

# ---- Arguments ---------------------------------------------------------------

ADD_DISK=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --add-disk|--add-disk=*)
            if [[ "$1" == --add-disk=* ]]; then
                value="${1#--add-disk=}"
                shift
            elif [[ $# -ge 2 ]]; then
                value="$2"
                shift 2
            else
                value=""
                shift
            fi
            if [[ -z "$value" ]]; then
                echo "ERROR: --add-disk needs a device, for example --add-disk /dev/sdc." >&2
                exit 2
            fi
            if [[ -n "$ADD_DISK" ]]; then
                echo "ERROR: give --add-disk once. Add one disk per run." >&2
                exit 2
            fi
            ADD_DISK="$value"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument '$1'." >&2
            usage >&2
            exit 2
            ;;
    esac
done

# ---- Preflight checks -------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: This script must be run as root or with sudo."
    exit 1
fi

echo "=========================================="
echo " WitFoo Appliance — Expand /data Partition"
echo "=========================================="
echo ""

# Verify /data is mounted
if ! mountpoint -q /data; then
    echo "ERROR: /data is not a mounted filesystem."
    echo "       Ensure the appliance was deployed from an official WitFoo image."
    exit 1
fi

# Verify core tools are available
for cmd in lsblk findmnt stat; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Required command '$cmd' not found."
        exit 1
    fi
done

# ---- Detect OS --------------------------------------------------------------

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
else
    OS_ID="unknown"
fi

echo "Detected OS: ${PRETTY_NAME:-$OS_ID}"

# ---- Partition growth tool (needed only when a partition must be grown) ------

# growpart edits GPT and MBR tables with sfdisk (util-linux), so gdisk is not installed. AlmaLinux 10,
# which stands in for RHEL 10 in CI, has no gdisk package, and asking for it failed the whole dnf
# install, so growpart was not installed either.
install_growpart() {
    echo "Installing growpart utility..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq && apt-get install -y -qq cloud-guest-utils > /dev/null 2>&1
            ;;
        rhel|centos|rocky|alma|almalinux|fedora)
            dnf install -y -q cloud-utils-growpart > /dev/null 2>&1 || \
            yum install -y -q cloud-utils-growpart > /dev/null 2>&1
            ;;
        *)
            echo "WARNING: Unknown OS '$OS_ID'. Attempting dnf, then apt..."
            # Grouped: as `dnf || apt-get update && apt-get install || true`, the apt-get install
            # also ran after a successful dnf (&& and || have equal precedence, left to right).
            dnf install -y -q cloud-utils-growpart > /dev/null 2>&1 || \
            { apt-get update -qq && apt-get install -y -qq cloud-guest-utils; } > /dev/null 2>&1 || \
            true
            ;;
    esac
}

# have_growpart: true when growpart is installed, installing it on first use if it is missing.
# It is asked for only when a partition has space after it, so an appliance without network
# access can still grow a volume that needs no partition grown.
GROWPART_READY=""
have_growpart() {
    if [[ -z "$GROWPART_READY" ]]; then
        command -v growpart &>/dev/null || install_growpart
        if command -v growpart &>/dev/null; then
            GROWPART_READY=yes
        else
            GROWPART_READY=no
        fi
    fi
    [[ "$GROWPART_READY" == yes ]]
}

# ---- Device helpers ----------------------------------------------------------

# classify_device <device> sets:
#   DEV_PATH     the device, with symlinks resolved
#   DEV_NAME     the kernel's name for it (sda3, nvme1n1, dm-0)
#   DEV_MAJMIN   its major:minor numbers
#   DEV_KIND     partition | disk | virtual (device-mapper or md RAID) | unknown
#   DEV_DISK     the whole disk holding it (partition, disk); empty otherwise
#   DEV_PARTNUM  the partition number (partition only)
# It finds the device in sysfs by its major:minor numbers, so it parses no device names: every
# naming scheme (sda3, nvme0n1p3, xvda3, mmcblk0p3) and every whole disk (sdb, nvme1n1) is
# handled the same way, under any name or symlink.
classify_device() {
    local hex sys
    DEV_PATH=$(readlink -f "$1")
    DEV_NAME=""
    DEV_MAJMIN=""
    DEV_KIND=unknown
    DEV_DISK=""
    DEV_PARTNUM=""
    [[ -b "$DEV_PATH" ]] || return 0
    hex=$(stat -L -c '%t %T' "$DEV_PATH" 2>/dev/null) || return 0
    DEV_MAJMIN=$(printf '%d:%d' "0x${hex% *}" "0x${hex#* }")
    sys=$(readlink -f "/sys/dev/block/$DEV_MAJMIN" 2>/dev/null) || return 0
    [[ -d "$sys" ]] || return 0
    DEV_NAME=$(basename "$sys")
    if [[ -r "$sys/partition" ]]; then
        DEV_KIND=partition
        DEV_PARTNUM=$(<"$sys/partition")
        DEV_DISK="/dev/$(basename "$(dirname "$sys")")"
    elif [[ -d "$sys/dm" || -d "$sys/md" ]]; then
        DEV_KIND=virtual
    else
        DEV_KIND=disk
        DEV_DISK="/dev/$DEV_NAME"
    fi
}

# Ask the kernel to re-read a disk's size: the SCSI device rescan for VMware, Hyper-V and most
# clouds, and the NVMe controller rescan (a namespace's device is its controller, or its
# subsystem when NVMe multipath is on). virtio and Xen disks report a new size themselves.
rescan_disk() {
    local dev f
    dev="/sys/block/$(basename "$1")/device"
    for f in "$dev/rescan" "$dev/rescan_controller" "$dev"/nvme*/rescan_controller; do
        if [[ -e "$f" ]]; then
            { echo 1 > "$f"; } 2>/dev/null
        fi
    done
}

# partition_room <disk> <partition name>: the bytes growpart could add to the partition, by its
# own rule (growpart 0.33): up to the next partition, or at the end of the disk up to the last 33
# sectors, which it keeps for a GPT backup header whatever the table type. sysfs counts in
# 512-byte sectors.
partition_room() {
    local disk part start size end limit keep=33 p s
    disk=$(basename "$1")
    part="$2"
    start=$(<"/sys/class/block/$part/start") || return 1
    size=$(<"/sys/class/block/$part/size") || return 1
    limit=$(<"/sys/class/block/$disk/size") || return 1
    end=$((start + size))
    for p in "/sys/class/block/$disk/$disk"*; do
        [[ -r "$p/start" ]] || continue
        s=$(<"$p/start")
        if (( s >= end && s < limit )); then
            limit=$s
            keep=0
        fi
    done
    echo $(((limit - keep - end) * 512))
}

# growpart does not grow a partition by less than 1 MiB.
GROW_MIN_BYTES=$((2048 * 512))
GROW_FAILED=()

# grow_partition <disk> <number> <partition name>: grows the partition into the space after it.
# A partition that could not be grown is added to GROW_FAILED; the caller carries on.
grow_partition() {
    local disk="$1" num="$2" name="$3" room status=0
    room=$(partition_room "$disk" "$name") || room=""
    if [[ "$room" =~ ^-?[0-9]+$ ]] && (( room < GROW_MIN_BYTES )); then
        echo "Partition $num on $disk has no space after it to grow into."
        return 0
    fi
    if ! have_growpart; then
        echo "ERROR: partition $num on $disk has space after it, but growpart is not installed and"
        echo "       could not be installed. Install it, then run this script again:"
        echo "         Ubuntu: apt install cloud-guest-utils"
        echo "         RHEL:   dnf install cloud-utils-growpart"
        GROW_FAILED+=("$disk partition $num (growpart is not installed)")
        return 0
    fi
    echo "Growing partition $num on $disk to fill available disk space..."
    echo "Running: growpart $disk $num"
    growpart "$disk" "$num" 2>&1 || status=$?
    if [[ $status -eq 0 ]]; then
        echo "Partition successfully grown."
    elif [[ $status -eq 1 ]]; then
        echo "Partition is already at maximum size (no unallocated space found after it)."
    else
        echo "WARNING: growpart returned exit code $status for partition $num on $disk."
        echo "         Continuing with the rest; the script will exit 1 at the end."
        GROW_FAILED+=("$disk partition $num (growpart exit code $status)")
    fi
    if command -v partprobe &>/dev/null; then
        partprobe "$disk" 2>/dev/null || true
    fi
    sleep 1
}

# ephemeral_reason <disk>: prints why the disk is local storage that is erased when the VM or
# instance stops, or nothing. Only identifiers the vendors document are used:
#   AWS:    an instance store volume's model is "Amazon EC2 NVMe Instance Storage"
#           (repost.aws/knowledge-center/ec2-linux-instance-store-volumes)
#   Azure:  the temp NVMe disk's model is "Microsoft NVMe Direct Disk"
#           (learn.microsoft.com/azure/virtual-machines/enable-nvme-temp-faqs)
#   Google: Local SSDs appear as /dev/disk/by-id/google-local-ssd-N or google-local-nvme-ssd-N,
#           names the Google guest environment creates
#           (cloud.google.com/compute/docs/disks/add-local-ssd)
#   Linux:  RAM disks (ram*, zram*)
# This check passes a disk it cannot identify; EXPAND_DISK.md warns about local storage.
ephemeral_reason() {
    local name model link
    name=$(basename "$1")
    case "$name" in
        ram[0-9]*|zram[0-9]*)
            echo "it is a RAM disk"
            return 0
            ;;
    esac
    model=$(cat "/sys/block/$name/device/model" 2>/dev/null || true)
    model="${model%"${model##*[![:space:]]}"}"
    if [[ "$model" == *"NVMe Instance Storage"* ]]; then
        echo "its model is '$model', an AWS instance store volume"
        return 0
    fi
    if [[ "$model" == *"NVMe Direct Disk"* ]]; then
        echo "its model is '$model', Azure's temporary NVMe disk"
        return 0
    fi
    for link in /dev/disk/by-id/google-local-ssd-* /dev/disk/by-id/google-local-nvme-ssd-*; do
        if [[ -e "$link" && "$(readlink -f "$link")" == "/dev/$name" ]]; then
            echo "it is a Google Cloud Local SSD ($link)"
            return 0
        fi
    done
}

# check_blank_disk <device>: refuses (exit 1) anything that is not a blank disk or partition on
# durable storage: a device-mapper or RAID device, local storage that is erased when the VM stops
# (see ephemeral_reason), an LVM physical volume, a device with partitions or volumes built on it,
# a mounted device, or one with any signature wipefs finds (a partition table, a filesystem, swap,
# a RAID or LVM label). The partitions, mount and signature checks fail closed: if one cannot run,
# the device is refused. The PV check passes a device pvs cannot report on, which leaves its LVM
# label to the signature check. A program using the raw device without writing a signature is not
# detected.
check_blank_disk() {
    local dev="$1" reason children signatures line rc
    if [[ ! -b "$dev" ]]; then
        echo "ERROR: '$dev' is not a block device."
        echo "       List the disks with: lsblk"
        exit 1
    fi
    classify_device "$dev"
    case "$DEV_KIND" in
        disk|partition)
            ;;
        virtual)
            echo "ERROR: '$dev' is a device-mapper or RAID device ($DEV_NAME), not a disk or a"
            echo "       partition. Only a new disk can be added."
            exit 1
            ;;
        *)
            echo "ERROR: '$dev' is not a disk or a partition this script recognises."
            exit 1
            ;;
    esac
    reason=$(ephemeral_reason "$DEV_DISK")
    if [[ -n "$reason" ]]; then
        echo "ERROR: '$dev' is local storage that is erased when the VM or instance stops: $reason."
        echo "       /data would then lose part of its volume group. Attach a durable disk instead."
        exit 1
    fi
    if pvs "$DEV_PATH" &>/dev/null; then
        echo "ERROR: '$dev' is already an LVM physical volume:"
        pvs -o pv_name,vg_name,pv_size "$DEV_PATH" 2>/dev/null || true
        exit 1
    fi
    # lsblk lists the device, then its partitions and anything built on it (device-mapper, RAID).
    if ! children=$(lsblk -nro NAME "$DEV_PATH" 2>&1); then
        echo "ERROR: could not list what is on '$dev': $children"
        exit 1
    fi
    children=$(tail -n +2 <<< "$children" | tr '\n' ' ')
    if [[ -n "${children// /}" ]]; then
        echo "ERROR: '$dev' has partitions or volumes on it: $children"
        echo "       Only a new, blank disk can be added."
        exit 1
    fi
    # A mount of the device, by its numbers, under any name.
    awk -v mm="$DEV_MAJMIN" '$3 == mm { found = 1 } END { exit found ? 0 : 1 }' /proc/self/mountinfo
    rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "ERROR: '$dev' is mounted."
        exit 1
    elif [[ $rc -ne 1 ]]; then
        echo "ERROR: could not check whether '$dev' is mounted."
        exit 1
    fi
    if ! command -v wipefs &>/dev/null; then
        echo "ERROR: wipefs (util-linux) is needed to check that '$dev' is blank."
        exit 1
    fi
    if ! signatures=$(wipefs --no-act --noheadings "$DEV_PATH" 2>&1); then
        echo "ERROR: could not read '$dev' to check that it is blank: $signatures"
        exit 1
    fi
    if [[ -n "$signatures" ]]; then
        echo "ERROR: '$dev' is not blank. It has these signatures (partition table, filesystem,"
        echo "       swap, RAID or LVM label):"
        while IFS= read -r line; do
            echo "         $line"
        done <<< "$signatures"
        echo "       This script adds only a blank disk, so that it never destroys data. If you are"
        echo "       certain nothing on it is needed, erase it yourself and run this again."
        exit 1
    fi
}

# ---- Identify the /data device and determine its layout ----------------------

DATA_SOURCE=$(findmnt -n -o SOURCE /data 2>/dev/null || true)
DATA_MAJMIN=$(findmnt -n -o MAJ:MIN /data 2>/dev/null | tr -d ' ' || true)
if [[ -z "$DATA_SOURCE" || -z "$DATA_MAJMIN" ]]; then
    echo "ERROR: Could not determine the source device for /data."
    exit 1
fi
echo "Source device for /data: $DATA_SOURCE ($DATA_MAJMIN)"

USE_LVM=false
DATA_LV=""
DATA_VG=""
DATA_VG_UUID=""
DATA_LV_NAME=""
DATA_PVS=()
DATA_DISKS=()
VIRTUAL_PVS=()

# Every physical volume of /data's volume group, chosen by the group's UUID: a volume group of
# the same name on another disk (one attached from another appliance) is never touched.
list_pvs() {
    DATA_PVS=()
    local pv
    while IFS= read -r pv; do
        pv="${pv//[[:space:]]/}"
        [[ -n "$pv" ]] && DATA_PVS+=("$pv")
    done < <(pvs --noheadings -o pv_name -S "vg_uuid=$DATA_VG_UUID" 2>/dev/null)
}

# /data is on LVM when a logical volume has the major:minor numbers of the device mounted there.
if command -v lvs &>/dev/null; then
    while read -r vg lv uuid major minor; do
        if [[ "$major:$minor" == "$DATA_MAJMIN" ]]; then
            DATA_VG="$vg"
            DATA_LV_NAME="$lv"
            DATA_VG_UUID="$uuid"
        fi
    done < <(lvs --noheadings -o vg_name,lv_name,vg_uuid,lv_kernel_major,lv_kernel_minor 2>/dev/null)
fi

if [[ -n "$DATA_VG" ]]; then
    USE_LVM=true

    # The LVM commands below name the volume group, so its name must be unique.
    if ! VG_UUIDS=$(vgs --noheadings -o vg_uuid -S "vg_name=$DATA_VG" 2>/dev/null); then
        echo "ERROR: Could not list the volume groups named $DATA_VG."
        exit 1
    fi
    VG_COUNT=$(grep -c . <<< "$VG_UUIDS")
    if [[ "$VG_COUNT" -ne 1 ]]; then
        echo "ERROR: $VG_COUNT volume groups are named $DATA_VG (expected 1). Rename the one that"
        echo "       does not hold /data before running this script: vgrename <its UUID> <new name>."
        vgs -o vg_name,vg_uuid,pv_count 2>/dev/null || true
        exit 1
    fi

    DATA_LV="/dev/${DATA_VG}/${DATA_LV_NAME}"
    if ! lvs "$DATA_LV" &>/dev/null; then
        DATA_LV="/dev/mapper/${DATA_VG//-/--}-${DATA_LV_NAME//-/--}"
    fi

    list_pvs
    if [[ ${#DATA_PVS[@]} -eq 0 ]]; then
        echo "ERROR: Could not list the physical volumes of volume group $DATA_VG."
        exit 1
    fi
    for pv in "${DATA_PVS[@]}"; do
        if [[ "$pv" != /dev/* ]]; then
            echo "ERROR: Volume group $DATA_VG has a missing physical volume ($pv)."
            echo "       Repair the volume group before expanding it (see: vgs, pvs)."
            exit 1
        fi
    done

    echo "Layout: LVM"
    echo "Logical volume: $DATA_LV (VG: $DATA_VG, LV: $DATA_LV_NAME)"
    echo "Physical volumes: ${DATA_PVS[*]}"
else
    classify_device "$DATA_SOURCE"
    case "$DEV_KIND" in
        partition)
            echo "Layout: plain partition (no LVM)"
            ;;
        disk)
            echo "Layout: filesystem on a whole disk (no LVM)"
            ;;
        *)
            echo "ERROR: /data is on $DATA_SOURCE ($DEV_NAME), which is neither a partition, a whole"
            echo "       disk nor an LVM logical volume this script can find (for example, an"
            echo "       encrypted volume). This script cannot grow it; grow it by hand."
            if ! command -v lvs &>/dev/null; then
                echo "       If it is an LVM logical volume, install lvm2 and run this script again."
            fi
            exit 1
            ;;
    esac
    if [[ -n "$ADD_DISK" ]]; then
        echo "ERROR: --add-disk needs /data on LVM, as on the official images."
        echo "       Grow the existing disk instead, then run this script without --add-disk."
        exit 1
    fi
fi
echo ""

# ---- Capture current state ---------------------------------------------------

BEFORE_FS_SIZE=$(df -BG /data | tail -1 | awk '{print $2}')
BEFORE_FS_BYTES=$(df -B1 --output=size /data | tail -1 | tr -d ' ')
echo "Current /data filesystem size: ${BEFORE_FS_SIZE}"

declare -A BEFORE_PV_SIZE=()
if [[ "$USE_LVM" == true ]]; then
    for pv in "${DATA_PVS[@]}"; do
        BEFORE_PV_SIZE["$pv"]=$(pvs --noheadings --nosuffix --units g -o pv_size "$pv" 2>/dev/null | tr -d ' ')
        echo "Physical volume $pv: ${BEFORE_PV_SIZE[$pv]}G"
    done
    BEFORE_LV_SIZE=$(lvs --noheadings --nosuffix --units g -o lv_size "$DATA_LV" 2>/dev/null | tr -d ' ')
    echo "Logical volume:   ${BEFORE_LV_SIZE}G"
fi
echo ""

# ---- Rescan disks (for hypervisors/cloud that need it) -----------------------

echo "Rescanning disk devices..."

# Rescan SCSI bus (VMware, Hyper-V, some cloud): finds newly attached disks
if ls /sys/class/scsi_host/host*/scan &>/dev/null; then
    for host in /sys/class/scsi_host/host*/scan; do
        echo "- - -" > "$host" 2>/dev/null || true
    done
fi

# The disks holding /data, for the rescan and for the closing summary
add_data_disk() {
    local d
    [[ -n "$1" ]] || return 0
    for d in "${DATA_DISKS[@]}"; do
        [[ "$d" == "$1" ]] && return 0
    done
    DATA_DISKS+=("$1")
}
if [[ "$USE_LVM" == true ]]; then
    for pv in "${DATA_PVS[@]}"; do
        classify_device "$pv"
        add_data_disk "$DEV_DISK"
        [[ "$DEV_KIND" == virtual ]] && VIRTUAL_PVS+=("$pv")
    done
else
    classify_device "$DATA_SOURCE"
    add_data_disk "$DEV_DISK"
fi
for disk in "${DATA_DISKS[@]}"; do
    rescan_disk "$disk"
done

# Brief pause to let the kernel settle
sleep 2

echo "Rescan complete."
echo ""

# ---- Add a new disk (--add-disk) ---------------------------------------------

if [[ -n "$ADD_DISK" ]]; then
    check_blank_disk "$ADD_DISK"
    NEW_PV="$DEV_PATH"
    echo "Adding $ADD_DISK ($NEW_PV) to volume group $DATA_VG:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL "$NEW_PV" 2>/dev/null || true
    if ! pvcreate "$NEW_PV"; then
        echo "ERROR: pvcreate failed on $NEW_PV."
        exit 1
    fi
    if ! vgextend "$DATA_VG" "$NEW_PV"; then
        echo "ERROR: vgextend failed: $NEW_PV was not added to $DATA_VG."
        if pvremove "$NEW_PV" &>/dev/null; then
            echo "       The LVM label written to $NEW_PV was removed again."
        else
            echo "       $NEW_PV now has an unused LVM label; remove it with: pvremove $NEW_PV"
        fi
        exit 1
    fi
    echo "Disk added."
    echo ""
    BEFORE_PV_SIZE["$NEW_PV"]="0"
    list_pvs
fi

# ---- Grow the partitions and physical volumes --------------------------------

# Detect filesystem type (used for both LVM and plain partition paths)
FS_TYPE=$(findmnt -n -o FSTYPE /data 2>/dev/null || true)

# Function to resize the filesystem
resize_filesystem() {
    local device="$1"
    echo ""
    echo "Resizing filesystem on /data..."
    case "$FS_TYPE" in
        ext4|ext3|ext2)
            if ! resize2fs "$device"; then
                echo "ERROR: resize2fs failed on $device."
                exit 1
            fi
            ;;
        xfs)
            if ! xfs_growfs /data; then
                echo "ERROR: xfs_growfs failed on /data."
                exit 1
            fi
            ;;
        "")
            echo "WARNING: Could not detect filesystem type. Trying both resize methods..."
            resize2fs "$device" 2>/dev/null || xfs_growfs /data 2>/dev/null || {
                echo "ERROR: Failed to resize filesystem."
                exit 1
            }
            ;;
        *)
            echo "ERROR: Unsupported filesystem type '$FS_TYPE'."
            echo "       Only ext4 and xfs are supported."
            exit 1
            ;;
    esac
    echo "Filesystem resized."
}

if [[ "$USE_LVM" == true ]]; then
    # ---- LVM path: (growpart →) pvresize for each PV → lvextend → resize fs --

    for pv in "${DATA_PVS[@]}"; do
        classify_device "$pv"
        echo "Physical volume $pv ($DEV_NAME):"
        case "$DEV_KIND" in
            partition)
                lsblk "$DEV_DISK" -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null || true
                grow_partition "$DEV_DISK" "$DEV_PARTNUM" "$DEV_NAME"
                ;;
            disk)
                echo "It is a whole disk, so there is no partition to grow."
                lsblk -d "$DEV_DISK" -o NAME,SIZE,TYPE 2>/dev/null || true
                ;;
            virtual)
                echo "It is a device-mapper or RAID device. Grow that device first if it has not"
                echo "grown; this script resizes the physical volume to whatever size it has."
                ;;
            *)
                echo "WARNING: $DEV_PATH is not a block device this script recognises; resizing the"
                echo "         physical volume to its current size."
                ;;
        esac

        echo "Resizing physical volume $pv..."
        if ! pvresize "$pv"; then
            echo "ERROR: pvresize failed on $pv."
            exit 1
        fi
        echo ""
    done

    echo "Extending logical volume $DATA_LV to use all free space..."
    FREE_EXTENTS=$(vgs --noheadings --nosuffix -o vg_free_count -S "vg_uuid=$DATA_VG_UUID" 2>/dev/null | tr -d ' ')
    echo "Free extents in VG $DATA_VG: ${FREE_EXTENTS:-unknown}"

    if [[ ! "$FREE_EXTENTS" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Could not read the free space of volume group $DATA_VG."
        exit 1
    elif [[ "$FREE_EXTENTS" -gt 0 ]]; then
        if ! lvextend -l +100%FREE "$DATA_LV"; then
            echo "ERROR: lvextend failed on $DATA_LV."
            exit 1
        fi
        echo "Logical volume extended."
    else
        echo "No free extents available in volume group $DATA_VG."
        echo "The logical volume is already using all available space."
    fi

    echo ""
    echo "Filesystem type: ${FS_TYPE:-unknown}"
    resize_filesystem "$DATA_LV"

else
    # ---- No LVM: grow the partition, if any → resize fs -----------------------

    classify_device "$DATA_SOURCE"
    echo "Device: $DEV_PATH ($DEV_NAME)"
    if [[ "$DEV_KIND" == partition ]]; then
        lsblk "$DEV_DISK" -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null || true
        grow_partition "$DEV_DISK" "$DEV_PARTNUM" "$DEV_NAME"
    else
        echo "/data is a filesystem on the whole disk, so there is no partition to grow."
    fi

    echo ""
    echo "Filesystem type: ${FS_TYPE:-unknown}"
    resize_filesystem "$DEV_PATH"
fi

# ---- Report results ----------------------------------------------------------

echo ""
echo "=========================================="
if [[ ${#GROW_FAILED[@]} -gt 0 ]]; then
    echo " Expansion Incomplete"
else
    echo " Expansion Complete"
fi
echo "=========================================="
echo ""

if [[ "$USE_LVM" == true ]]; then
    for pv in "${DATA_PVS[@]}"; do
        after=$(pvs --noheadings --nosuffix --units g -o pv_size "$pv" 2>/dev/null | tr -d ' ')
        echo "Physical volume $pv: ${BEFORE_PV_SIZE[$pv]:-?}G → ${after}G"
    done
    AFTER_LV_SIZE=$(lvs --noheadings --nosuffix --units g -o lv_size "$DATA_LV" 2>/dev/null | tr -d ' ')
    echo "Logical volume:   ${BEFORE_LV_SIZE}G → ${AFTER_LV_SIZE}G"
    echo ""
fi

df -h /data
echo ""

AFTER_FS_BYTES=$(df -B1 --output=size /data | tail -1 | tr -d ' ')
if [[ ${#GROW_FAILED[@]} -eq 0 && "$AFTER_FS_BYTES" -le "$BEFORE_FS_BYTES" ]]; then
    echo "/data did not grow."
    if [[ ${#DATA_DISKS[@]} -gt 0 ]]; then
        echo "No unallocated space was found on its disks (${DATA_DISKS[*]})."
    fi
    if [[ ${#VIRTUAL_PVS[@]} -gt 0 ]]; then
        echo "Its device-mapper or RAID devices (${VIRTUAL_PVS[*]}) have not grown: grow them first."
    fi
    echo "If you expected more space, verify that:"
    echo "  1. The disk was expanded at the hypervisor/cloud layer"
    echo "  2. The VM was rebooted (if required by your platform)"
    echo "  3. lsblk shows the new size for the disk"
    echo ""
fi

# Warn if /data is over 50% full
USAGE_PCT=$(df /data --output=pcent | tail -1 | tr -d ' %')
if [[ "$USAGE_PCT" -ge 50 ]]; then
    echo "WARNING: /data is ${USAGE_PCT}% full."
    echo "         The /data partition should remain at least 50% free"
    echo "         for healthy database compaction and cleanup."
    echo "         Consider adding more disk or Data Nodes to the cluster."
fi

if [[ ${#GROW_FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "ERROR: these partitions were not grown: ${GROW_FAILED[*]}"
    echo "       /data does not include the space after them. Fix the cause shown above and run"
    echo "       this script again."
    exit 1
fi

echo ""
echo "Done."
