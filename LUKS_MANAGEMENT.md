# LUKS Encryption Management

This guide covers managing LUKS encryption on Aegix Linux systems.

## Changing Your LUKS Passphrase

LUKS (Linux Unified Key Setup) supports multiple key slots, allowing you to add new passphrases before removing old ones. This ensures you never lock yourself out during the passphrase change process.

### Method 1: Add New, Remove Old (Safest)

This two-step process is the safest approach:

#### Step 1: Identify your encrypted partition

```bash
# List all block devices
lsblk

# Find your LUKS partition (usually /dev/nvme0n1p2 or /dev/sda2)
# Look for the partition that shows "crypt" in the TYPE column
sudo cryptsetup luksDump /dev/nvme0n1p2  # Replace with your partition
```

#### Step 2: Check current key slots

```bash
sudo cryptsetup luksDump /dev/nvme0n1p2 | grep "Key Slot"
```

You'll see something like:
```
Key Slot 0: ENABLED
Key Slot 1: DISABLED
Key Slot 2: DISABLED
...
```

#### Step 3: Add new passphrase to an empty slot

```bash
sudo cryptsetup luksAddKey /dev/nvme0n1p2
```

You'll be prompted:
1. Enter **existing** passphrase (to authenticate)
2. Enter **new** passphrase
3. Verify **new** passphrase

#### Step 4: Verify the new key works

**IMPORTANT: Test before removing the old key!**

```bash
# Try unlocking with the new passphrase
sudo cryptsetup open --test-passphrase /dev/nvme0n1p2
```

Enter your new passphrase. If it succeeds silently, the new key works!

#### Step 5: Remove the old passphrase

Only after confirming the new key works:

```bash
sudo cryptsetup luksRemoveKey /dev/nvme0n1p2
```

Enter your **old** passphrase when prompted. This removes it from the key slot.

#### Step 6: Verify only new key remains

```bash
sudo cryptsetup luksDump /dev/nvme0n1p2 | grep "Key Slot"
```

You should see one ENABLED slot (your new passphrase) and the rest DISABLED.

---

### Method 2: Change Key Directly (One Command)

For advanced users who want to change a passphrase in one step:

```bash
sudo cryptsetup luksChangeKey /dev/nvme0n1p2
```

You'll be prompted:
1. Enter **existing** passphrase
2. Enter **new** passphrase
3. Verify **new** passphrase

**WARNING:** This replaces the key in the same slot. If something goes wrong mid-process, you could be locked out. Method 1 is safer.

---

## Finding Your LUKS Partition

On Aegix systems installed with encryption:

### BIOS Systems (install.sh)
- Root partition is typically `/dev/sda2` or `/dev/vda2`
- Check with: `lsblk -f`

### UEFI Systems (uefi_install.sh)
- ESP (boot) partition is `/dev/nvme0n1p1` (or `/dev/sda1`)
- Root partition is `/dev/nvme0n1p2` (or `/dev/sda2`) - **this is the LUKS partition**

### Confirm your LUKS partition

```bash
# List all LUKS devices
sudo blkid | grep crypto_LUKS

# Example output:
# /dev/nvme0n1p2: UUID="abc123..." TYPE="crypto_LUKS"
```

---

## Managing Multiple Keys (Advanced)

LUKS supports up to 8 key slots (0-7), allowing multiple passphrases:

### Use case: Emergency backup passphrase

Add a strong backup passphrase and store it securely:

```bash
# Add backup passphrase to slot 1
sudo cryptsetup luksAddKey /dev/nvme0n1p2

# View which slots are in use
sudo cryptsetup luksDump /dev/nvme0n1p2 | grep "Key Slot"
```

### Remove a specific key slot

If you know which slot to remove:

```bash
sudo cryptsetup luksKillSlot /dev/nvme0n1p2 0  # Removes key in slot 0
```

**WARNING:** `luksKillSlot` removes the slot by number without asking for the passphrase. Make sure you have another working key slot before using this!

---

## Emergency Recovery

### What if I forget my passphrase?

**There is NO recovery if you lose all LUKS passphrases.** The encryption is designed to be unbreakable without the key. This is why:

1. **Test new passphrases before removing old ones**
2. **Keep a backup passphrase in a safe place** (password manager, safe, etc.)
3. **Never remove your last working key**

### What if something goes wrong during key change?

If you followed Method 1 (add new, then remove old), you should have both keys working until you explicitly remove the old one. Simply:

1. Reboot
2. Try both passphrases at the LUKS unlock prompt
3. Once booted, check key slots with `cryptsetup luksDump`

---

## Best Practices

1. **Always test new keys** with `cryptsetup open --test-passphrase` before removing old ones
2. **Keep a backup key** in a secure location (password manager, encrypted USB, etc.)
3. **Use strong passphrases**: 20+ characters with mixed case, numbers, symbols
4. **Document which partition is encrypted**: Note it down during installation
5. **Practice recovery** on a test VM or spare drive before doing it on your main system

---

## Common Errors

### "No key available with this passphrase"
- You entered the wrong passphrase
- The key slot is already removed
- Try other passphrases if you have multiple slots

### "Device /dev/sdX is not a valid LUKS device"
- You're targeting the wrong partition
- Use `lsblk -f` or `blkid` to find the correct LUKS partition

### "Cannot add key slot, all slots full"
- All 8 key slots are in use
- Remove an old key first with `luksRemoveKey` or `luksKillSlot`

---

## References

- [cryptsetup man page](https://man.archlinux.org/man/cryptsetup.8)
- [LUKS on ArchWiki](https://wiki.archlinux.org/title/Dm-crypt/Device_encryption#Encryption_options_for_LUKS_mode)
- Aegix installation scripts: `install.sh` (BIOS), `uefi_install.sh` (UEFI)

---

**Last updated**: 2025-10-06
