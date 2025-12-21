#!/usr/bin/env bash

# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <https://unlicense.org>

set -euo pipefail

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Print header
print_header() {
    clear
    echo "==============================================="
    echo "    NixOS Secure Boot Bait & Switch Installer"
    echo "==============================================="
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
    
    # Check if we're in Ubuntu
    if [[ ! -f /etc/os-release ]] || ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script must be run from Ubuntu"
        log_info "The bait-and-switch method requires Ubuntu to be installed first"
        exit 1
    fi
    
    # Check if Nix is installed
    if ! command -v nix-env &> /dev/null; then
        log_warn "Nix package manager is not installed"
        log_info "Please install Nix first with:"
        echo "    curl -L https://nixos.org/nix/install | sh"
        echo "    # Then restart your shell session"
        echo "    # Then run this script again with sudo"
        exit 1
    fi
    
    # Check if Secure Boot is enabled
    if ! command -v mokutil &> /dev/null; then
        apt-get install -y mokutil
    fi
    
    if ! mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
        log_warn "Secure Boot does not appear to be enabled"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Gather user input
gather_input() {
    print_header
    log_step "Gathering system information..."
    
    # Detect disks
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE,TRAN | grep -v "loop"
    echo ""
    
    # Ask for disk
    read -p "Enter the disk to use (e.g., nvme0n1, sda): " DISK
    if [[ ! -b "/dev/$DISK" ]]; then
        log_error "Disk /dev/$DISK not found"
        exit 1
    fi
    
    # Show partitions
    echo ""
    echo "Current partitions on /dev/$DISK:"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL "/dev/$DISK"
    echo ""
    
    # Ask for EFI partition
    read -p "Enter the EFI partition number (e.g., 1 for ${DISK}1, p1 for ${DISK}p1): " EFI_PART_NUM
    EFI_PART="/dev/${DISK}${EFI_PART_NUM}"
    if [[ ! -b "$EFI_PART" ]]; then
        log_error "Partition $EFI_PART not found"
        exit 1
    fi
    
    # Ask for root partition
    read -p "Enter the root partition number (e.g., 2 for ${DISK}2): " ROOT_PART_NUM
    ROOT_PART="/dev/${DISK}${ROOT_PART_NUM}"
    if [[ ! -b "$ROOT_PART" ]]; then
        log_error "Partition $ROOT_PART not found"
        exit 1
    fi
    
    # Get username
    read -p "Enter your desired username: " USERNAME
    if [[ -z "$USERNAME" ]]; then
        log_error "Username cannot be empty"
        exit 1
    fi
    
    # Get hostname
    read -p "Enter your desired hostname [nixos]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-nixos}
    
    # Ask for NixOS version
    read -p "Enter NixOS version [25.11]: " NIXOS_VERSION
    NIXOS_VERSION=${NIXOS_VERSION:-25.11}
    
    # Ask for configuration file
    echo ""
    log_info "Configuration options:"
    echo "1. Use default configuration (basic setup with NetworkManager)"
    echo "2. Use custom configuration file"
    echo "3. Generate minimal configuration only"
    read -p "Select option [1]: " CONFIG_OPTION
    CONFIG_OPTION=${CONFIG_OPTION:-1}
    
    if [[ "$CONFIG_OPTION" == "2" ]]; then
        read -p "Enter path to your configuration.nix: " CUSTOM_CONFIG
        if [[ ! -f "$CUSTOM_CONFIG" ]]; then
            log_error "Configuration file not found: $CUSTOM_CONFIG"
            exit 1
        fi
    fi
    
    # Confirm
    echo ""
    echo "==============================================="
    echo "Summary:"
    echo "  Disk: /dev/$DISK"
    echo "  EFI Partition: $EFI_PART"
    echo "  Root Partition: $ROOT_PART"
    echo "  Username: $USERNAME"
    echo "  Hostname: $HOSTNAME"
    echo "  NixOS Version: $NIXOS_VERSION"
    echo "==============================================="
    read -p "Proceed with installation? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0
    
    # Export variables for use in functions
    export DISK EFI_PART ROOT_PART USERNAME HOSTNAME NIXOS_VERSION CONFIG_OPTION CUSTOM_CONFIG 2>/dev/null
}

# Disable shim validation if needed
disable_shim_validation() {
    log_step "Checking Secure Boot validation..."
    
    if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
        log_info "Secure Boot is enabled"
        if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot validation is disabled in shim"; then
            log_info "Shim validation already disabled"
        else
            log_warn "Shim validation needs to be disabled"
            log_info "Run this command, then reboot and follow MOK prompts:"
            echo ""
            echo "    mokutil --disable-validation"
            echo ""
            echo "Set a simple password (you'll need it in MOK Manager)"
            echo "After reboot and MOK confirmation, run this script again."
            exit 0
        fi
    fi
}

# Setup Nix channels and tools
setup_nix() {
    log_step "Setting up Nix channels..."
    
    # Add channels
    nix-channel --add "https://channels.nixos.org/nixos-${NIXOS_VERSION}" nixos
    nix-channel --add "https://channels.nixos.org/nixos-${NIXOS_VERSION}" nixpkgs
    nix-channel --update
    
    # Install tools
    log_info "Installing NixOS tools..."
    nix-env -f '<nixpkgs>' -iA nixos-install-tools
}

# Generate and fix configuration
generate_config() {
    log_step "Generating NixOS configuration..."
    
    # Generate initial config
    export LANG=C.UTF-8
    nixos-generate-config
    
    # Fix hardware-configuration.nix
    log_info "Fixing hardware-configuration.nix..."
    
    # Remove snapd entries more reliably
    sed -i '/snap/,/^[[:space:]]*};/d' /etc/nixos/hardware-configuration.nix
    
    # Fix mount point from /boot/efi to /boot
    sed -i 's|/boot/efi|/boot|g' /etc/nixos/hardware-configuration.nix
    
    # Remove any duplicate fileSystems entries for /boot
    log_info "Cleaning up filesystems configuration..."
    
    # Create configuration.nix based on user choice
    case "$CONFIG_OPTION" in
        1)
            create_default_config
            ;;
        2)
            use_custom_config
            ;;
        3)
            create_minimal_config
            ;;
        *)
            create_default_config
            ;;
    esac
    
    log_info "Configuration files ready in /etc/nixos/"
}

create_default_config() {
    log_info "Creating default configuration..."
    
    cat > /etc/nixos/configuration.nix << EOF
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  
  boot.loader = {
    systemd-boot.enable = false;
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      useOSProber = true;
      efiInstallAsRemovable = false;
    };
  };
  
  networking.hostName = "${HOSTNAME}";
  networking.networkmanager.enable = true;
  
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };
  
  users.users.${USERNAME} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "storage" ];
    initialPassword = "changeme";
    shell = pkgs.bash;
  };
  
  security.sudo.wheelNeedsPassword = false;
  
  nixpkgs.config.allowUnfree = true;
  
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  
  services.openssh.enable = false;
  
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    htop
  ];
  
  system.stateVersion = "${NIXOS_VERSION}";
}
EOF
}

create_minimal_config() {
    log_info "Creating minimal configuration..."
    
    cat > /etc/nixos/configuration.nix << EOF
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  
  boot.loader = {
    systemd-boot.enable = false;
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
    };
  };
  
  networking.hostName = "${HOSTNAME}";
  
  users.users.${USERNAME} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
  };
  
  system.stateVersion = "${NIXOS_VERSION}";
}
EOF
}

use_custom_config() {
    log_info "Using custom configuration from $CUSTOM_CONFIG"
    cp "$CUSTOM_CONFIG" /etc/nixos/configuration.nix
    
    # Still need to ensure user exists
    if ! grep -q "users.users.${USERNAME}" /etc/nixos/configuration.nix; then
        log_warn "Custom config doesn't seem to define user ${USERNAME}"
        log_info "Adding user definition..."
        
        # Append user config if not present
        cat >> /etc/nixos/configuration.nix << EOF

# Added by NixOS installer
users.users.${USERNAME} = {
  isNormalUser = true;
  extraGroups = [ "wheel" ];
  initialPassword = "changeme";
};
EOF
    fi
}

# Build NixOS system
build_system() {
    log_step "Building NixOS system..."
    
    # Build the system
    nix-env -p /nix/var/nix/profiles/system \
            -f '<nixpkgs/nixos>' \
            -I nixos-config=/etc/nixos/configuration.nix \
            -iA system
    
    # Set NixOS markers
    touch /etc/NIXOS
    touch /etc/NIXOS_LUSTRATE
    echo "etc/nixos" >> /etc/NIXOS_LUSTRATE
    
    # Fix permissions
    chown -R 0:0 /nix
    
    log_info "System built successfully"
}

# Setup boot
setup_boot() {
    log_step "Setting up boot..."
    
    # Unmount and remount EFI partition at /boot
    log_info "Remounting EFI partition..."
    umount /boot/efi 2>/dev/null || true
    mv /boot /boot.bak 2>/dev/null || true
    mkdir -p /boot
    mount "$EFI_PART" /boot
    
    # Install bootloader
    log_info "Installing bootloader..."
    /nix/var/nix/profiles/system/bin/switch-to-configuration boot
    
    # Copy shim files from Ubuntu
    log_info "Copying Secure Boot shim files..."
    mkdir -p /boot/EFI/NixOS-boot
    cd /boot/EFI/ubuntu
    cp BOOTX64.CSV grub.cfg mmx64.efi shimx64.efi ../NixOS-boot/
    
    # Setup EFI boot entry with correct path format
    setup_efi_entry
    
    log_info "Boot setup complete"
}

setup_efi_entry() {
    log_step "Setting up EFI boot entry..."
    
    log_info "Creating EFI boot entry..."

    efibootmgr -c -L "NixOS" -d "$EFI_PART" -l "\\EFI\\NixOS-boot\\shimx64.efi" 2>/dev/null

    # Update boot order
    update_boot_order
}

update_boot_order() {
    # Get the new NixOS boot entry
    local nixos_entry
    nixos_entry=$(efibootmgr -v | grep -i "NixOS" | head -1 | grep -o 'Boot[0-9A-F]*')
    
    if [[ -n "$nixos_entry" ]]; then
        local boot_num="${nixos_entry#Boot}"
        log_info "Found NixOS boot entry: $nixos_entry"
        
        # Get current boot order
        local current_order
        current_order=$(efibootmgr | grep "BootOrder:" | cut -d: -f2 | tr -d ' ')
        
        if [[ -n "$current_order" ]]; then
            # Remove NixOS from current order if present
            local new_order="${boot_num}"
            for entry in $(echo "$current_order" | tr ',' ' '); do
                if [[ "$entry" != "$boot_num" ]]; then
                    new_order="${new_order},${entry}"
                fi
            done
            
            efibootmgr --bootorder "$new_order"
            log_info "Updated boot order: $new_order"
        fi
    else
        log_warn "Could not find NixOS boot entry to update boot order. Please try manualy."
    fi
    
    # Show final boot configuration
    echo ""
    log_info "Final boot configuration:"
    efibootmgr -v
}

# Final steps and instructions
finalize() {
    log_step "Installation complete!"
    
    echo ""
    echo "==============================================="
    echo "            INSTALLATION SUCCESSFUL"
    echo "==============================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. REBOOT the system:"
    echo "   sudo reboot"
    echo ""
    echo "2. Login with:"
    echo "   Username: ${USERNAME}"
    echo "   Password: changeme"
    echo ""
    echo "3. After login, immediately:"
    echo "   passwd                         # Change your password"
    echo "   sudo passwd root               # Change root password"
    echo ""
    echo "4. Optional cleanup:"
    echo "   sudo rm -rf /boot.bak          # Remove backup"
    echo "   sudo nix-collect-garbage -d    # Clean up old generations"
    echo ""
    echo "5. Update and customize:"
    echo "   sudo nix-channel --update"
    echo "   sudo nixos-rebuild switch"
    echo "   nano /etc/nixos/configuration.nix"
    echo ""
    echo "==============================================="
    echo ""
    
    # Create a cleanup script for later
    cat > /tmp/nixos-post-install.sh << EOF
#!/bin/bash
# Post-install cleanup script
echo "Cleaning up installation files..."
sudo rm -rf /boot.bak 2>/dev/null
sudo rm -rf /old-root 2>/dev/null
sudo nix-collect-garbage -d
echo "Cleanup complete!"
EOF
    
    chmod +x /tmp/nixos-post-install.sh
    log_info "Post-install cleanup script created: /tmp/nixos-post-install.sh"
}

# Main execution flow
main() {
    print_header
    check_prerequisites
    gather_input
    disable_shim_validation
    setup_nix
    generate_config
    build_system
    setup_boot
    finalize
}

# Handle interrupts
trap 'log_error "Installation interrupted"; exit 1' INT TERM

# Run main function
main "$@"
