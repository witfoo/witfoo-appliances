#!/bin/bash
# WitFoo Appliance First-Run Setup
# Detects OS and uses appropriate package manager
set -euo pipefail

echo "==> WitFoo Appliance Setup"

# Detect OS and update/upgrade
if command -v apt &>/dev/null; then
    echo "==> Detected Ubuntu/Debian"
    sudo apt update
    sudo apt upgrade -y
elif command -v dnf &>/dev/null; then
    echo "==> Detected RHEL/Fedora"
    sudo dnf upgrade -y
else
    echo "ERROR: Unsupported OS - neither apt nor dnf found"
    exit 1
fi

# Configure WitFoo
echo "==> Running WitFoo configuration"
sudo wfa configure

echo "==> Setup complete"
