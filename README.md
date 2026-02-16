# Install WitFoo Software

WitFoo software is available for trial in multiple configurations. WitFoo software is always deployed to a **WitFoo Appliance**. Running `sudo wfa configure` will select the function the specific appliance will execute.

Self-paced, no-cost training and certification is available here: [https://witfoo.myabsorb.com/](https://witfoo.myabsorb.com/)

Support is available at [Submit a request](https://witfoo.zendesk.com/hc/en-us/requests/new)

---

## On-Prem Hypervisor Install Files

| Platform | Ubuntu24 | RHEL10 |
| --- | --- | --- |
| <img src="logos/vmware.png" alt="VMware" width="200"> | [:us: ⬇️](https://objectstorage.us-chicago-1.oraclecloud.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-ubuntu24.zip) [:australia: ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-ubuntu24.zip) | [:us: ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-rhel10.zip) [:australia: ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-vmware-rhel10.zip) |
| <img src="logos/hyper-v.png" alt="Hyper-V" width="200"> | [:us: ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-ubuntu24.zip) [:australia: ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-ubuntu24.zip) | [:us: ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-rhel10.zip) [:australia: ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-rhel10.zip) |
| <img src="logos/qemu.png" alt="QEMU" width="200"> | [:us: ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-qemu-ubuntu24.zip) [:australia: ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-qemu-ubuntu24.zip) | --- |

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

---

## WitFoo Appliance Roles

| WitFoo Role | CPU Cores (minimum) | RAM (minimum) |
| --- | --- | --- |
| Conductor | 4 CPU | 8GB |
| Console | 4 CPU | 8GB |

---

## Default Credentials

- **Username**: `witfooadmin`
- **Password**: `F00theN0ise!`

Change these immediately after first login.

## Disk Partition Layout

All appliance images use LVM with the following partition layout:

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

## Configuration

After deploying the appliance, run:

```bash
sudo ./setup.sh
```

This will guide you through selecting the role for this appliance. (If setup.sh is not present, run `sudo apt update ; sudo apt upgrade -y ; sudo wfa configure`)

For detailed installation instructions, see [The WitFoo "Getting Started" Documentation](https://docs.witfoo.com/getting-started/)

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
