> [!NOTE]
>
> Issues and PRs are only accepted on the Codeberg [repo](https://codeberg.org/backtail/nixos-secure-boot-infection). Github is a mirror only.


# NixOS Secure Boot Infection

## Overview

This script enables the installation of NixOS on systems with **Secure Boot enabled** by leveraging Ubuntu's Microsoft-signed shim bootloader. Since NixOS doesn't officially support Secure Boot, this "switch-in-place" method first requires an Ubuntu install, then replaces it with NixOS while preserving Secure Boot functionality.

## Disclaimer

This method involves modifying Secure Boot validation. While tested and functional, it:
- Is not an officially supported NixOS installation method
- May not work on all hardware
- Could be affected by firmware updates
- Is not **secure** in the sense where the validation chain from the TPM/BIOS is broken (intentionally)

> [!CAUTION] 
>
> Before running this script, please setup a KVM and test it yourself, that's how I did it as well. I am providing no liability for damaged data and/or soft-locked devices.

Always have recovery media ready and backup important data before proceeding. If you feel like this method goes over your head, maybe don't try it, or at least very carfully.

## Resources

- [Original Method](https://github.com/yglcode/nixos_secureboot) (by [
Yigong Liu](https://github.com/yglcode))
- [My Blog Post](https://www.maxgenson.de/blog/nixos-is-also-a-parasite/) (goes into more detail on how this method works)


## Technical Flow

1. Ubuntu secure boot scheme

```
secure boot environment                                            
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│ ┌──────┐verify┌────────────┐verify┌────────────┐verify┌────────┐ │
│ │ UEFI ┼──────►  shim.efi  ┼──────►  grub.efi  ┼──────► UBUNTU │ │
│ └──────┘ only └────────────┘ MS & └────────────┘ MS & └────────┘ │
│          MS                  MOK                 MOK             │
│          keys                keys                keys            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

2. Disable MOK validation

```
secure boot environment          insecure boot environment          
┌─────────────────────┐ ┌──────────────────────────────────────────┐
│                     │ │                                          │
│ ┌──────┐verify┌─────┴─┴────┐ignore┌────────────┐ignore┌────────┐ │
│ │ UEFI ┼──────►  shim.efi  ┼──────►  grub.efi  ┼──────► UBUNTU │ │
│ └──────┘ only └─────┬─┬────┘ keys └────────────┘ keys └────────┘ │
│          MS         │ │                                          │
│          keys       │ │                                          │
│                     │ │                                          │
└─────────────────────┘ └──────────────────────────────────────────┘
```

3. Infect host (Ubuntu)

```
secure boot environment          insecure boot environment          
┌─────────────────────┐ ┌──────────────────────────────────────────┐
│                     │ │                                          │
│ ┌──────┐ENTRY0┌─────┴─┴────┐      ┌────────────┐      ┌────────┐ │
│ │ UEFI ┼──────►  shim.efi  ┼──────►  grub.efi  ┼──┬───►  GEN1  │ │
│ └────┬─┘      └─────┬─┬────┘      └────────────┘  │   └────────┘ │
│      │              │ │               NixOS       │   ┌────────┐ │
│      │              │ │                           ├───►  GEN2  │ │
│      │              │ │                           │   └────────┘ │
│      │              │ │                           │   ┌────────┐ │
│      │              │ │                           └───►  GEN3  │ │
│      │              │ │                               └────────┘ │
│      │  ENTRY1┌─────┴─┴────┐      ┌────────────┐      ┌────────┐ │
│      └────────►  shim.efi  ┼──────►  grub.efi  ┼──┬───► KERNEL │ │
│               └─────┬─┬────┘      └────────────┘  │   └────────┘ │
│                     │ │               Ubuntu      │   ┌────────┐ │
│                     │ │                           └───► KERNEL │ │
│                     │ │                               └────────┘ │
│                     │ │                                          │
└─────────────────────┘ └──────────────────────────────────────────┘
```

4. Remove host OS (Ubuntu) and EFI entry

```
secure boot environment          insecure boot environment          
┌─────────────────────┐ ┌──────────────────────────────────────────┐
│                     │ │                                          │
│ ┌──────┐verify┌─────┴─┴────┐ignore┌────────────┐ignore┌────────┐ │
│ │ UEFI ┼──────►  shim.efi  ┼──────►  grub.efi  ┼──────► NixOS  | │
│ └──────┘ only └─────┬─┬────┘ keys └────────────┘ keys └────────┘ │
│          MS         │ │                                          │
│          keys       │ │                                          │
│                     │ │                                          │
└─────────────────────┘ └──────────────────────────────────────────┘
```

## Installation Process

### Phase 0: Prerequisites
- A system with UEFI firmware and Secure Boot enabled
- Ubuntu installed (fresh install recommended)
- Nix package manager installed

### Phase 1: Disable Shim Validation
```bash
sudo mokutil --disable-validation
# Set password → Reboot → Confirm in MOK Manager → Reboot again
```

### Phase 2: Run Sanity Checker
```bash
chmod +x sanity-checker.sh
sudo ./sanity-checker.sh
```

### Phase 3: Run Installer
```bash
chmod +x install.sh
sudo ./install.sh
```

### Phase 4: Follow Interactive Prompts
The script will ask for:
- Disk and partition information
- Desired username and hostname
- NixOS version (default: 25.11)
- Configuration preference (default/custom/minimal)

## Post-Installation Checklist

### Immediate Actions (First Boot)
1. **Login**: Use your username with password `changeme`
2. **Change passwords**:
   ```bash
   passwd                    # Change user password
   sudo passwd root          # Change root password
   ```
3. **Verify installation**:
   ```bash
   nixos-version
   sudo mokutil --sb-state   # Should show "SecureBoot enabled"
   ```

### System Configuration
4. **Update system**:
   ```bash
   sudo nix-channel --update
   sudo nixos-rebuild switch --upgrade
   ```

## Troubleshooting

### Common Issues

#### Boot Problems
```bash
# Check EFI entries
sudo efibootmgr

# Boot from fallback
# Select "Ubuntu" in BIOS boot menu to fall back
```

#### Secure Boot
```bash
# Verify Secure Boot status
sudo mokutil --sb-state

# Re-enable validation if needed
sudo mokutil --enable-validation
```

### Recovery Scenarios

#### Can't Boot to NixOS
1. Use BIOS boot menu (F12/Esc) to select "Ubuntu" entry
2. Boot from NixOS Live USB
3. Chroot and repair:
   ```bash
   mount /dev/nvme0n1p2 /mnt
   mount /dev/nvme0n1p1 /mnt/boot
   nixos-enter
   ```
## Contributing

Found an issue or have improvements?
1. Check existing issues
2. Fork the repository
3. Create a feature branch
4. Submit a pull request
