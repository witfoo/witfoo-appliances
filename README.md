# Install WitFoo Software

WitFoo software is available for trial in multiple configurations. WitFoo software is always deployed to a **WitFoo Appliance**. Running `sudo wfa configure` will select the function the specific appliance will execute.

Self-paced, no-cost training and certification is available here: [https://witfoo.myabsorb.com/](https://witfoo.myabsorb.com/)

Support is available at [Submit a request](https://witfoo.zendesk.com/hc/en-us/requests/new)

---

## On-Prem Hypervisor Install Files

| Platform | Ubuntu24 |  RHEL10  |
|----------|----------|----------|
| <img src="logos/vmware.png" alt="VMware" width="200"> | COMING | COMING |
| <img src="logos/hyper-v.png" alt="Hyper-V" width="200"> | [🇺🇸 ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-ubuntu24.zip) [🇦🇺 ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-hyperv-ubuntu24.zip) | COMING |
| <img src="logos/qemu.png" alt="QEMU" width="200"> | [🇺🇸 ⬇️](https://ax4xtzq35yny.objectstorage.us-chicago-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-qemu-ubuntu24.zip) [🇦🇺 ⬇️](https://ax4xtzq35yny.objectstorage.ap-melbourne-1.oci.customer-oci.com/n/ax4xtzq35yny/b/VM-Images/o/witfoo-appliance-qemu-ubuntu24.zip) | COMING |

## Cloud Marketplace Installs

| Platform | Marketplace |
|----------|-------------|
| <a href="https://aws.amazon.com/marketplace/search/results?searchTerms=witfoo"><img src="logos/aws.png" alt="AWS" width="200"></a> | [WitFoo Appliance Ubuntu 24 for AWS](https://aws.amazon.com/marketplace/search/results?searchTerms=witfoo) |
| <a href="https://azuremarketplace.microsoft.com/en-us/marketplace/apps?search=witfoo&page=1"><img src="logos/azure.png" alt="Azure" width="200"></a> | [WitFoo Appliance Ubuntu 24 for Azure Cloud](https://azuremarketplace.microsoft.com/en-us/marketplace/apps?search=witfoo&page=1) |
| <a href="https://console.cloud.google.com/marketplace/browse?q=witfoo"><img src="logos/google.png" alt="Google Cloud" width="200"></a> | [WitFoo Appliance Ubuntu 24 for Google Cloud](https://console.cloud.google.com/marketplace/browse?q=witfoo) |

## Bare Metal Install Files

| Platform | Script |
|----------|--------|
| Ubuntu 24 | [ubuntu-install.sh](ubuntu-install.sh) |
| RHEL 10 | [rhel-install.sh](rhel-install.sh) |

---

## WitFoo Appliance Roles

| WitFoo Role | CPU Cores (minimum) | RAM (minimum) | Installation Guides |
|-------------|---------------------|---------------|---------------------|
| Conductor | 4 CPU | 8GB | [with license](https://witfoo.zendesk.com/hc/en-us/articles/45699743001235-Configuring-Conductor-with-license) / [without license](https://witfoo.zendesk.com/hc/en-us/articles/45191358366611-Configuring-Conductor-without-license) |
| Reporter | 8 CPU | 32GB | [with license](https://witfoo.zendesk.com/hc/en-us/articles/46410473880467-Configuring-Reporter-with-license) / [without license](https://witfoo.zendesk.com/hc/en-us/articles/46410307000339-Configuring-Reporter-without-license) |
| Console | 4 CPU | 8GB | [with license](https://witfoo.zendesk.com/hc/en-us/articles/46412264771219-Configure-Console-with-license) / [without license](https://witfoo.zendesk.com/hc/en-us/articles/46412421655571-Configure-Console-without-license) |
| Precinct All-In-One | 8 CPU | 32GB | [with license](https://witfoo.zendesk.com/hc/en-us/articles/46337323517075-Precinct-AIO-Configuration-with-license) |
| Precinct Data Node | 4 CPU | 12GB | [with license](https://witfoo.zendesk.com/hc/en-us/articles/46411002510483-Configure-WitFoo-Analytics-Data-Node-with-license) |
| Precinct Streamer Node | 4 CPU | 12GB | [with license](https://witfoo.zendesk.com/hc/en-us/articles/46192215765267-Configure-WitFoo-Analytics-Streamer-Node-with-license) |
| Precinct Mgmt Node | 4 CPU | 8GB | [with license](https://witfoo.zendesk.com/hc/en-us/articles/46411467686419-Configure-WitFoo-Analytics-Mgmt-Node-with-license) |

---

## Default Credentials

- **Username**: `witfooadmin`
- **Password**: `F00theN0ise!`

Change these immediately after first login.

## Disk Partition Layout

All appliance images use LVM with the following partition layout:

| Partition | Mount Point | Size | Purpose |
|-----------|-------------|------|---------|
| /boot | /boot | 1GB | Boot partition |
| lv_root | / | 30GB | Root filesystem |
| lv_docker | /docker | 30GB | Docker data-root |
| lv_var_log | /var/log | 5GB | System logs |
| lv_var_log_audit | /var/log/audit | 5GB | Audit logs |
| lv_cassandra_commit | /cassandra_commit | 10GB | Cassandra commit log |
| lv_data | /data | ~190GB | Application data |

**Total disk size**: ~280GB

## Configuration

After deploying the appliance, run:

```bash
sudo wfa configure
```

This will guide you through selecting the role for this appliance.

## Resources

| Resource | Access | Notes |
|----------|--------|-------|
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
