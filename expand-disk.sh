#!/bin/bash
# =============================================================================
# expand-disk.sh — Expand /data partition to use all available disk space
# =============================================================================
# Compatible with: Ubuntu 24, RHEL 10
# Hypervisors:     VMware, Hyper-V, QEMU/KVM
# Cloud:           AWS, Azure, Google Cloud
#
# Prerequisites:
#   1. Allocate additional disk space at the hypervisor or cloud layer
#   2. SSH into the appliance and run: sudo ./expand-disk.sh
#
# This script will:
#   - Detect the physical volume (PV) used by the /data logical volume
#   - Grow the partition to fill the expanded disk
#   - Resize the physical volume to use the new space
#   - Extend the /data logical volume to use all free extents
#   - Resize the filesystem online
#
# See EXPAND_DISK.md for platform-specific instructions on expanding the
# underlying disk before running this script.
# =============================================================================

set -uo pipefail

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

# Verify LVM tools are available
for cmd in pvs vgs lvs pvresize lvextend lsblk; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Required command '$cmd' not found."
        echo "       Install LVM tools: apt install lvm2 (Ubuntu) or dnf install lvm2 (RHEL)"
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

# ---- Install partition growth tools if missing -------------------------------

install_growpart() {
    echo "Installing growpart utility..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq && apt-get install -y -qq cloud-guest-utils gdisk > /dev/null 2>&1
            ;;
        rhel|centos|rocky|alma|fedora)
            dnf install -y -q cloud-utils-growpart gdisk > /dev/null 2>&1 || \
            yum install -y -q cloud-utils-growpart gdisk > /dev/null 2>&1
            ;;
        *)
            echo "WARNING: Unknown OS '$OS_ID'. Attempting dnf, then apt..."
            dnf install -y -q cloud-utils-growpart gdisk > /dev/null 2>&1 || \
            apt-get update -qq && apt-get install -y -qq cloud-guest-utils gdisk > /dev/null 2>&1 || \
            true
            ;;
    esac
}

if ! command -v growpart &>/dev/null; then
    install_growpart
fi

if ! command -v growpart &>/dev/null; then
    echo "ERROR: growpart is required but could not be installed."
    echo "       Ubuntu: apt install cloud-guest-utils"
    echo "       RHEL:   dnf install cloud-utils-growpart"
    exit 1
fi

# ---- Identify the /data logical volume and its physical volume ---------------

# Get LV path for /data (e.g., /dev/mapper/rhel_witfoo--appliance-data)
DATA_SOURCE=$(findmnt -n -o SOURCE /data 2>/dev/null || true)
if [[ -z "$DATA_SOURCE" ]]; then
    echo "ERROR: Could not determine the source device for /data."
    exit 1
fi
echo "Source device for /data: $DATA_SOURCE"

# Use lvs to find the LV and VG by scanning all LVs and matching the dm path
# findmnt may return /dev/mapper/... or /dev/dm-N — both need special handling
DATA_LV=""
DATA_VG=""

# First try: use lvs directly with the mapper path
DATA_VG=$(lvs --noheadings -o vg_name "$DATA_SOURCE" 2>/dev/null | tr -d ' ' || true)
DATA_LV_NAME=$(lvs --noheadings -o lv_name "$DATA_SOURCE" 2>/dev/null | tr -d ' ' || true)

# Second try: resolve to dm path and match against lvs output
if [[ -z "$DATA_VG" ]]; then
    DM_PATH=$(readlink -f "$DATA_SOURCE")
    echo "Resolved dm path: $DM_PATH"
    # Get all LVs and find the one matching our dm path
    while IFS= read -r line; do
        lv_vg=$(echo "$line" | awk '{print $1}')
        lv_name=$(echo "$line" | awk '{print $2}')
        lv_dm=$(echo "$line" | awk '{print $3}')
        lv_dm_resolved=$(readlink -f "$lv_dm" 2>/dev/null || echo "$lv_dm")
        if [[ "$lv_dm_resolved" == "$DM_PATH" ]] || [[ "$lv_dm" == "$DATA_SOURCE" ]]; then
            DATA_VG="$lv_vg"
            DATA_LV_NAME="$lv_name"
            break
        fi
    done < <(lvs --noheadings -o vg_name,lv_name,lv_dm_path 2>/dev/null)
fi

# Third try: look for an LV named "data" in any VG
if [[ -z "$DATA_VG" ]]; then
    echo "Scanning for LV named 'data'..."
    DATA_VG=$(lvs --noheadings -o vg_name -S "lv_name=data" 2>/dev/null | tr -d ' ' | head -1 || true)
    DATA_LV_NAME="data"
fi

if [[ -z "$DATA_VG" || -z "$DATA_LV_NAME" ]]; then
    echo "ERROR: Could not determine the volume group for /data."
    echo "       Source device: $DATA_SOURCE"
    echo ""
    echo "LVM status:"
    lvs 2>/dev/null || true
    exit 1
fi

# Build the full LV path
DATA_LV="/dev/${DATA_VG}/${DATA_LV_NAME}"
echo "Logical volume: $DATA_LV (VG: $DATA_VG, LV: $DATA_LV_NAME)"

# Verify the LV exists
if ! lvs "$DATA_LV" &>/dev/null; then
    # Try the mapper path format: /dev/mapper/VG-LV (with dashes doubled in VG name)
    MAPPER_VG=$(echo "$DATA_VG" | sed 's/-/--/g')
    DATA_LV="/dev/mapper/${MAPPER_VG}-${DATA_LV_NAME}"
    echo "Using mapper path: $DATA_LV"
    if ! lvs "$DATA_LV" &>/dev/null; then
        echo "ERROR: Logical volume $DATA_LV does not exist."
        exit 1
    fi
fi

echo "Volume group: $DATA_VG"

# Get the physical volume(s) in this VG
DATA_PV=$(pvs --noheadings -o pv_name -S "vg_name=$DATA_VG" 2>/dev/null | tr -d ' ' | head -1)
if [[ -z "$DATA_PV" ]]; then
    echo "ERROR: Could not determine the physical volume for VG $DATA_VG."
    exit 1
fi
echo "Physical volume: $DATA_PV"

# ---- Identify the disk and partition number ----------------------------------

# Resolve symlinks (e.g., /dev/mapper/... → /dev/sdaX)
PV_RESOLVED=$(readlink -f "$DATA_PV")

# Extract the base disk and partition number
# Handles: /dev/sda3, /dev/nvme0n1p3, /dev/vda3, /dev/xvda3
if [[ "$PV_RESOLVED" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
    DISK="${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[2]}"
elif [[ "$PV_RESOLVED" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
    DISK="${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[2]}"
elif [[ "$PV_RESOLVED" =~ ^(/dev/xvd[a-z]+)([0-9]+)$ ]]; then
    DISK="${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[2]}"
elif [[ "$PV_RESOLVED" =~ ^(/dev/[a-z]+[0-9]+)p([0-9]+)$ ]]; then
    # Fallback for other partitioned devices like /dev/mmcblk0p3
    DISK="${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[2]}"
else
    echo "ERROR: Could not parse disk and partition from '$PV_RESOLVED'."
    echo "       Expected format like /dev/sda3, /dev/nvme0n1p3, or /dev/vda3."
    exit 1
fi

echo "Disk: $DISK"
echo "Partition number: $PART_NUM"
echo ""

# Show current disk layout
echo "Current disk layout:"
lsblk "$DISK" -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null || lsblk "$DISK" -o NAME,SIZE,TYPE 2>/dev/null || true
echo ""

# ---- Capture current state ---------------------------------------------------

BEFORE_PV_SIZE=$(pvs --noheadings --nosuffix --units g -o pv_size "$DATA_PV" 2>/dev/null | tr -d ' ')
BEFORE_LV_SIZE=$(lvs --noheadings --nosuffix --units g -o lv_size "$DATA_LV" 2>/dev/null | tr -d ' ')
BEFORE_FS_SIZE=$(df -BG /data | tail -1 | awk '{print $2}')

echo "Current sizes:"
echo "  Physical volume:  ${BEFORE_PV_SIZE}G"
echo "  Logical volume:   ${BEFORE_LV_SIZE}G"
echo "  Filesystem:       ${BEFORE_FS_SIZE}"
echo ""

# ---- Rescan disks (for hypervisors/cloud that need it) -----------------------

echo "Rescanning disk devices..."

# Rescan SCSI bus (VMware, Hyper-V, some cloud)
if ls /sys/class/scsi_host/host*/scan &>/dev/null; then
    for host in /sys/class/scsi_host/host*/scan; do
        echo "- - -" > "$host" 2>/dev/null || true
    done
fi

# Rescan individual SCSI devices
if ls /sys/class/scsi_device/*/device/rescan &>/dev/null; then
    for dev in /sys/class/scsi_device/*/device/rescan; do
        echo 1 > "$dev" 2>/dev/null || true
    done
fi

# Rescan block devices (NVMe, virtio)
if [[ -e "/sys/block/$(basename "$DISK")/device/rescan" ]]; then
    echo 1 > "/sys/block/$(basename "$DISK")/device/rescan" 2>/dev/null || true
fi

# Notify kernel of disk size changes
if command -v partprobe &>/dev/null; then
    partprobe "$DISK" 2>/dev/null || true
fi

# Brief pause to let the kernel settle
sleep 2

echo "Rescan complete."
echo ""

# ---- Grow the partition ------------------------------------------------------

echo "Growing partition $PART_NUM on ${DISK} to fill available disk space..."
echo "Running: growpart $DISK $PART_NUM"

# growpart exits 0 on success, 1 on "no change needed" (NOCHANGE)
GROW_EXIT=0
growpart "$DISK" "$PART_NUM" 2>&1 || GROW_EXIT=$?

if [[ $GROW_EXIT -eq 0 ]]; then
    echo "Partition successfully grown."
elif [[ $GROW_EXIT -eq 1 ]]; then
    echo "Partition is already at maximum size (no unallocated space found)."
    echo ""
    echo "If you expected more space, verify that:"
    echo "  1. The disk was expanded at the hypervisor/cloud layer"
    echo "  2. The VM was rebooted (if required by your platform)"
    echo "  3. The disk rescan above detected the new size"
    echo ""
    echo "Current disk size:"
    lsblk "$DISK" -o NAME,SIZE,TYPE 2>/dev/null || true
    # Continue anyway — PV/LV might still have room to expand
else
    echo "WARNING: growpart returned exit code $GROW_EXIT."
    echo "         Attempting to continue..."
fi

# Notify kernel of partition table change
if command -v partprobe &>/dev/null; then
    partprobe "$DISK" 2>/dev/null || true
fi
sleep 1

# ---- Resize the physical volume ---------------------------------------------

echo ""
echo "Resizing physical volume $DATA_PV..."
if ! pvresize "$DATA_PV"; then
    echo "ERROR: pvresize failed on $DATA_PV."
    exit 1
fi

# ---- Extend the logical volume -----------------------------------------------

echo ""
echo "Extending logical volume $DATA_LV to use all free space..."

FREE_EXTENTS=$(vgs --noheadings --nosuffix -o vg_free_count "$DATA_VG" 2>/dev/null | tr -d ' ')
echo "Free extents in VG $DATA_VG: $FREE_EXTENTS"

if [[ "$FREE_EXTENTS" -gt 0 ]]; then
    if ! lvextend -l +100%FREE "$DATA_LV"; then
        echo "ERROR: lvextend failed on $DATA_LV."
        exit 1
    fi
    echo "Logical volume extended."
else
    echo "No free extents available in volume group $DATA_VG."
    echo "The logical volume is already using all available space."
fi

# ---- Resize the filesystem ---------------------------------------------------

echo ""
echo "Resizing filesystem on /data..."

# Detect filesystem type
FS_TYPE=$(findmnt -n -o FSTYPE /data 2>/dev/null || true)
echo "Filesystem type: ${FS_TYPE:-unknown}"

case "$FS_TYPE" in
    ext4|ext3|ext2)
        resize2fs "$DATA_LV"
        ;;
    xfs)
        xfs_growfs /data
        ;;
    "")
        echo "WARNING: Could not detect filesystem type. Trying both resize methods..."
        resize2fs "$DATA_LV" 2>/dev/null || xfs_growfs /data 2>/dev/null || {
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

# ---- Report results ----------------------------------------------------------

echo ""
echo "=========================================="
echo " Expansion Complete"
echo "=========================================="

AFTER_PV_SIZE=$(pvs --noheadings --nosuffix --units g -o pv_size "$DATA_PV" 2>/dev/null | tr -d ' ')
AFTER_LV_SIZE=$(lvs --noheadings --nosuffix --units g -o lv_size "$DATA_LV" 2>/dev/null | tr -d ' ')

echo ""
echo "Physical volume:  ${BEFORE_PV_SIZE}G → ${AFTER_PV_SIZE}G"
echo "Logical volume:   ${BEFORE_LV_SIZE}G → ${AFTER_LV_SIZE}G"
echo ""
df -h /data
echo ""

# Warn if /data is over 50% full
USAGE_PCT=$(df /data --output=pcent | tail -1 | tr -d ' %')
if [[ "$USAGE_PCT" -ge 50 ]]; then
    echo "WARNING: /data is ${USAGE_PCT}% full."
    echo "         The /data partition should remain at least 50% free"
    echo "         for healthy database compaction and cleanup."
    echo "         Consider adding more disk or Data Nodes to the cluster."
fi

echo ""
echo "Done."
