# Install WitFoo Software

WitFoo software is deployed to a **WitFoo Appliance**. Follow these three steps to get up and running:

1. **Deploy the Appliance** — Select a deployment target below (hypervisor, cloud marketplace, or bare metal) and launch the instance.
2. **Expand Disk as Needed** — If your workload requires additional storage, [expand the disk](EXPAND_DISK.md) before or after setup. This is critical for AIO and Data Node roles — the `/data` partition must stay at least 50% free for database health.
3. **SSH in and run setup** — Connect to the appliance via SSH and run `sudo ./setup.sh` to configure the appliance role. For details on the configuration wizard, see [WFA Configure Documentation](https://docs.witfoo.com/getting-started/wfa-configure/). If setup.sh is not present, run the appropriate commands for your OS:
   - **Ubuntu**: `sudo apt update && sudo apt upgrade -y && sudo wfa configure`
   - **RHEL**: `sudo dnf update -y && sudo wfa configure`
4. **Connect to the Interface** — Open a browser, navigate to the appliance IP, and complete the setup wizard. See [First Login Documentation](https://docs.witfoo.com/getting-started/first-login/).

For full documentation on configuration and use, visit [docs.witfoo.com](https://docs.witfoo.com/).

> **Note:** If you do not have a license key, a 15-day trial license can be automatically generated during setup.

Have questions? [Submit a Ticket](https://witfoo.zendesk.com/hc/en-us/requests/new). Free self-paced training and certification is available at [witfoo.myabsorb.com](https://witfoo.myabsorb.com/).

---

## On-Prem Hypervisor Install Files

| Platform | Ubuntu24 | RHEL10 |
| --- | --- | --- |
| <img src="logos/vmware.png" alt="VMware" width="200"> | [<img src="logos/us.svg" alt="US" width="30"> ⬇️](https://objectstorage.us-chicago-1.oraclecloud.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-ubuntu24.zip) [<img src="logos/au.svg" alt="AU" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-ubuntu24.zip) | [<img src="logos/us.svg" alt="US" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-rhel10.zip) [<img src="logos/au.svg" alt="AU" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-rhel10.zip) |
| <img src="logos/hyper-v.png" alt="Hyper-V" width="200"> | [<img src="logos/us.svg" alt="US" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-ubuntu24.zip) [<img src="logos/au.svg" alt="AU" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-ubuntu24.zip) | [<img src="logos/us.svg" alt="US" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-rhel10.zip) [<img src="logos/au.svg" alt="AU" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-rhel10.zip) |
| <img src="logos/qemu.png" alt="QEMU" width="200"> | [<img src="logos/us.svg" alt="US" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-qemu-ubuntu24.zip) [<img src="logos/au.svg" alt="AU" width="30"> ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-qemu-ubuntu24.zip) | --- |

> The <img src="logos/us.svg" alt="US" width="20"> US and <img src="logos/au.svg" alt="AU" width="20"> Australia download links are identical images hosted on separate mirrors. Choose the region closest to you for the fastest download.

## Hypervisor Instructions

### VMware (OVA)

The VMware download is a full OVA export compatible with **ESXi 6.5 and above** (virtual hardware version 13+).

1. Download the `.zip` file for your region and extract the `.ova` file
2. In vSphere Client, select **File → Deploy OVF Template**
3. Browse to the extracted `.ova` file and follow the wizard
4. Assign a network, datastore, and resource pool as needed
5. Power on the VM and proceed to [Configuration](#configuration)

For more information, see [Deploying OVF/OVA Templates](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/vsphere-virtual-machine-administration-guide-8-0.html)

### Hyper-V (Gen 2)

The Hyper-V download is a full **Version 10 Generation 2** virtual machine export.

1. Download the `.zip` file for your region and extract to a local folder
2. Open **Hyper-V Manager** and select **Import Virtual Machine**
3. Browse to the extracted folder containing the VM files
4. Select **Copy the virtual machine** (creates a new unique ID)
5. Assign a virtual switch for networking
6. Power on the VM and proceed to [Configuration](#configuration)

Generation 2 VMs use UEFI firmware and support Secure Boot. For more information, see [Export and Import Virtual Machines](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/deploy/export-and-import-virtual-machines) and [Generation 2 VMs](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/plan/should-i-create-a-generation-1-or-2-virtual-machine-in-hyper-v)

### QEMU/KVM

1. Download the `.zip` file for your region and extract the disk image
2. Import the image using `virt-manager` or `virsh`
3. Power on the VM and proceed to [Configuration](#configuration)

## Cloud Marketplace Installs

| Platform | Marketplace |
| --- | --- |
| <a href="https://aws.amazon.com/marketplace/search/results?searchTerms=witfoo"><img src="logos/aws.png" alt="AWS" width="200"></a> | [WitFoo Appliance Ubuntu 24 for AWS](https://aws.amazon.com/marketplace/search/results?searchTerms=witfoo) |
| <a href="https://azuremarketplace.microsoft.com/en-us/marketplace/apps?search=witfoo&page=1"><img src="logos/azure.png" alt="Azure" width="200"></a> | [WitFoo Appliance Ubuntu 24 for Azure Cloud](https://azuremarketplace.microsoft.com/en-us/marketplace/apps?search=witfoo&page=1) |
| <a href="https://console.cloud.google.com/marketplace/browse?q=witfoo"><img src="logos/google.png" alt="Google Cloud" width="200"></a> | [WitFoo Appliance Ubuntu 24 for Google Cloud](https://console.cloud.google.com/marketplace/browse?q=witfoo) |

## Bare Metal Install Files

| Platform | Script |
| --- | --- |
| Ubuntu 24 | [ubuntu-install.sh](ubuntu-install.sh) |
| RHEL 10 | [rhel-install.sh](rhel-install.sh) |

## Appliance Scripts

| Script | Description |
| --- | --- |
| [setup.sh](setup.sh) | Initial appliance configuration wizard — assigns the appliance role |
| [expand-disk.sh](expand-disk.sh) | Expands the `/data` LVM partition after adding disk at the hypervisor/cloud layer |

> **Important:** When installing on bare metal, ensure the [Disk Partition Layout](#disk-partition-layout) is followed before running the install script. The isolated partitions are critical for stable performance and preventing resource contention between services.

---

## WitFoo Appliance Roles

| WitFoo Role | CPU Cores (minimum) | CPU Cores (recommended) | RAM (minimum) | RAM (recommended) |
| --- | --- | --- | --- | --- |
| Conductor | 4 CPU | 6 CPU | 8GB | 12GB |
| Console | 4 CPU | 6 CPU | 8GB | 12GB |
| Analytics AIO with Conductor | 12 CPU | 18 CPU | 16GB | 24GB |
| Analytics AIO no Conductor | 8 CPU | 12 CPU | 12GB | 18GB |
| Analytics Node | 6 CPU | 9 CPU | 8GB | 12GB |
| Data Node | 4 CPU | 6 CPU | 8GB | 12GB |

> **Note:** CPU performance varies significantly across processor architectures. Not all cores are equal — newer processors can handle higher throughput with fewer cores. See [Benchmarks](BENCHMARKS.md) for tested configurations and throughput ratings.

---

## Default Credentials

### On-Prem / Hypervisor

- **Username**: `witfooadmin`
- **Password**: `F00theN0ise!`

Change these immediately after first login.

### Cloud Marketplace

- **Username**: `ubuntu`
- **Authentication**: SSH key (required at launch)

Cloud marketplace appliances do not use a default password. You must provide an SSH key when launching the instance.

## Expanding Disk

As data is ingested and retained, disk usage will grow — particularly on **Analytics AIO** and **Data Node** roles. Plan for **1TB to 8TB of total disk space per Data Node or AIO node** depending on ingestion volume and retention requirements. It is critical to scale data clusters vertically (expanding disk on existing nodes) or horizontally (adding more Data Nodes). The `/data` partition must remain at least **50% free** to allow database compaction and cleanup to run properly.

See [EXPAND_DISK.md](EXPAND_DISK.md) for step-by-step instructions on expanding disk across all supported hypervisors and cloud platforms.

## Scaling the Data Cluster

For production deployments, horizontal scaling by adding Data Nodes to the cluster is strongly recommended. Multiple nodes provide fault tolerance, distribute read/write load, and increase total retention capacity. With a replication factor of 3, the cluster can tolerate node failures without data loss or downtime. The default single-node configuration is suitable for evaluation, non-critical, or smaller workloads.

See [DATA_CLUSTER.md](DATA_CLUSTER.md) for replication strategy commands, recommended cluster sizes, and step-by-step instructions for adding nodes.

## Disk Partition Layout

All appliance images use LVM with the following partition layout. These partitions are critical for stable performance — isolating Docker storage, logs, audit trails, and application data prevents any single volume from starving the others. If building on bare metal, do not skip meeting these minimums.

| Mount Point | Size | Purpose |
| --- | --- | --- |
| /boot | 1GB | Boot partition |
| / | 30GB | Root filesystem |
| /docker | 30GB | Docker data-root |
| /var/log | 5GB | System logs |
| /var/log/audit | 5GB | Audit logs |
| /cassandra_commit | 10GB | Cassandra commit log |
| /data | ~190GB | Application data |

**Total disk size**: ~280GB

## Benchmarks

Different CPU architectures and core counts enable different workloads. Selecting the right processor family and vCPU allocation directly impacts the message throughput a WitFoo appliance can sustain. Newer architectures such as AMD EPYC 9R45 and Intel Xeon Granite Rapids deliver significantly higher per-core performance, allowing smaller instances to handle heavier ingestion rates.

See [BENCHMARKS.md](BENCHMARKS.md) for detailed hardware requirements and tested processor configurations at various throughput levels.

## Resources

| Resource | Access | Notes |
| --- | --- | --- |
| [Documentation](https://docs.witfoo.com/) | Open | All WitFoo Product, API, MCP, and User Documentation |
| [Discussions](https://github.com/witfoo/witfoo-appliances/discussions) | GitHub Account | Public conversations on WitFoo Products |
| [Downloads](https://github.com/witfoo/witfoo-appliances) | Open | Download or Launch WitFoo Appliances |
| [Release Notes](https://github.com/witfoo/release-notes) | Open | WitFoo product release notes and changelogs |
| [Demo](https://demo.witfoo.com) | Open | Live demo of WitFoo Analytics Platform |
| [Open Ticket](https://witfoo.zendesk.com/hc/en-us/requests/new) | Open | Open a (private) ticket with the WitFoo team. Can be product or business related. |
| [Training](https://witfoo.myabsorb.com/) | Free Registration (click Sign Up) | Official WitFoo training courses for users, engineers, and partners. Include WitFoo Certifications (upon passing exams.) |
| [LinkedIn](https://www.linkedin.com/company/witfoo) | Open | Public Updates and Social Engagement |
| [Videos](https://vimeo.com/witfoo) | Open | WitFoo Public videos (training and marketing) |
| [WWW](https://www.witfoo.com) | Open | WitFoo official website |
