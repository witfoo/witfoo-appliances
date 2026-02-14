# WitFoo VM Appliance Images

Pre-built VM images for WitFoo Analytics platform deployment.

## Available Formats

| Format | Platform | File Extension |
|--------|----------|---------------|
| QCOW2 | KVM/QEMU/OpenStack | `.qcow2.zip` |
| VMDK | VMware ESXi/vSphere | `.vmdk.zip` |
| VHDX | Microsoft Hyper-V | `.vhdx.zip` |

## Download

Download images from [Releases](https://github.com/witfoo/witfoo-appliances/releases).

## Default Credentials

- **Username**: `witfooadmin`
- **Password**: `F00theN0ise!`
- **Sudo**: NOPASSWD access

Change these immediately after first login.

## Partition Layout

| Mount Point | Size | Purpose |
|-------------|------|---------|
| /boot | 1 GB | Boot partition |
| / | 30 GB | Root filesystem |
| /docker | 30 GB | Docker data-root |
| /var/log | 5 GB | System logs |
| /var/log/audit | 5 GB | Audit logs |
| /data | 200 GB | Application data |

## First-Time Setup

After deploying the VM:

```bash
# Login as witfooadmin
# Run the setup wizard
sudo wfa configure
```

## Image Verification

Each release includes `SHA256SUMS` for integrity verification:

```bash
sha256sum -c SHA256SUMS
```
