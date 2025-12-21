#!/bin/bash
echo "NixOS Secure Boot Pre-Installation Check"
echo "========================================="

# Check if running Ubuntu
if [[ -f /etc/os-release ]] && grep -q "Ubuntu" /etc/os-release; then
    echo "✓ Running Ubuntu"
else
    echo "✗ Not running Ubuntu"
    exit 1
fi

# Check Secure Boot
if command -v mokutil &> /dev/null; then
    if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
        echo "✓ Secure Boot enabled"
    else
        echo "⚠ Secure Boot not enabled"
    fi
else
    echo "⚠ mokutil not installed"
fi

# Check Nix
if command -v nix-env &> /dev/null; then
    echo "✓ Nix installed"
else
    echo "✗ Nix not installed"
    echo "  Install with: curl -L https://nixos.org/nix/install | sh"
fi

# Check disk layout
echo ""
echo "Disk layout:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL

# Check EFI
if [[ -d /sys/firmware/efi ]]; then
    echo "✓ UEFI boot"
else
    echo "✗ Legacy BIOS boot (not supported)"
fi
