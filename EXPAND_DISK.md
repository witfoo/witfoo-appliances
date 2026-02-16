# Expanding Disk on a WitFoo Appliance

Disk expansion is a critical operational task for WitFoo appliances, especially for **Analytics AIO** and **Data Node** roles. As log data is ingested and retained, the `/data` partition will grow. If it fills beyond capacity, database compaction and cleanup processes cannot run, leading to degraded performance, failed writes, and potential data loss.

> **The `/data` partition should always remain at least 50% free** to allow the database to perform cleanup, compaction, and repair operations. Monitor disk usage proactively and expand before reaching this threshold.

## Why Disk Expansion Matters

- **Data Retention** — AIO and Data Node appliances store ingested log data on the `/data` partition. The volume of retained data is directly tied to your retention policy and ingestion rate. Higher retention periods or throughput require more disk. Plan for **1TB to 8TB of total disk space per Data Node or AIO node** depending on ingestion volume and retention requirements.
- **Database Health** — Cassandra requires free disk space to perform compaction (merging and cleaning up SSTables). Without adequate headroom, compaction stalls and the database becomes unresponsive.
- **Vertical vs. Horizontal Scaling** — It is critical to scale data clusters either vertically (expanding disk on existing nodes) or horizontally (adding more Data Nodes to the cluster). Failure to scale in either direction will result in storage exhaustion and service interruption. Plan capacity proactively — do not wait for alerts.

## Step 1: Allocate Additional Disk in Your Platform

Before running the expansion script, you must first increase the virtual disk or volume size at the hypervisor or cloud layer.

### VMware (ESXi / vSphere)

1. Power off the VM (or expand online if supported by your ESXi version)
2. In vSphere Client, right-click the VM → **Edit Settings**
3. Under **Hard Disk**, increase the disk size
4. Click **OK** and power the VM back on

See: [VMware — Increase the Size of a Virtual Disk](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-virtual-machine-administration-guide-8-0.html)

### Hyper-V

1. Shut down the VM
2. In **Hyper-V Manager**, right-click the VM → **Settings**
3. Select the virtual hard disk under **SCSI Controller**
4. Click **Edit** → **Expand** and set the new size
5. Start the VM

See: [Microsoft — Expand a Virtual Hard Disk](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/manage/manage-hyper-v-virtual-hard-disk)

### QEMU/KVM

1. Shut down the VM
2. Expand the disk image:
   ```bash
   qemu-img resize /path/to/disk.qcow2 +100G
   ```
3. Start the VM

See: [QEMU Documentation — Disk Images](https://www.qemu.org/docs/master/system/images.html)

### AWS (EBS)

1. In the **EC2 Console**, select the instance
2. Go to **Storage** → click the volume ID
3. Select **Actions** → **Modify Volume** and increase the size
4. Wait for the volume state to show **optimizing** or **completed**

See: [AWS — Modify an EBS Volume](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-modify-volume.html)

### Azure (Managed Disk)

1. Stop (deallocate) the VM
2. In the **Azure Portal**, navigate to the VM → **Disks**
3. Select the data disk → **Size + performance** → increase the size
4. Start the VM

See: [Azure — Expand a Managed Disk](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/expand-disks)

### Google Cloud (Persistent Disk)

1. In the **Google Cloud Console**, go to **Compute Engine** → **Disks**
2. Select the disk → **Edit** → increase the size
3. No VM restart is required for size increases

See: [Google Cloud — Resize a Persistent Disk](https://cloud.google.com/compute/docs/disks/resize-persistent-disk)

## Step 2: Run the Expansion Script

Once the underlying disk has been expanded at the platform level, SSH into the appliance and run:

```bash
sudo ./expand-disk.sh
```

This script detects the new disk capacity and extends the LVM logical volume and filesystem for the `/data` partition automatically.

## Monitoring Disk Usage

Check current disk usage at any time:

```bash
df -h /data
```

Set up alerts or monitoring to trigger when `/data` usage exceeds **50%**. This gives you time to plan and execute an expansion before performance is impacted.
