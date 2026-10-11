# Permanent TWRP Recovery & Hardware Setup

> [**English**](recovery.md) · [**Español**](recovery.es.md)

Comprehensive guide to permanently flashing TeamWin Recovery Project (TWRP) on a **Poco X3 Pro (codename `vayu`)**, unlocking storage access, and configuring unattended chroot autostart for the \*arr stack (see [`installation.md`](installation.md)).

All external links were verified with HTTP status code probes. Fastboot commands strictly follow TeamWin's official device specifications.

---

## 0. Prerequisites & Data Disclaimer

> [!WARNING]
> **Unlocking the bootloader completely wipes the device storage.**
>
> Unlocking a Xiaomi bootloader issues a hardware factory reset on `/data`: all photos, personal media, credentials, and internal files are permanently erased.
>
> Furthermore, TWRP requires **Format Data** on first boot to remove proprietary file-based encryption (FBE). Without this step, `/data` cannot be mounted, preventing the Linux chroot from deploying.

### Verification Matrix

| Check | How to Verify | Expected Value |
|---|---|---|
| Hardware Codename | Settings → About Phone → Device Name | Must be `vayu` |
| Official TWRP Status | <https://twrp.me/xiaomi/xiaomipocox3pro.html> | Status: **Current**, Maintainer: **Nebrassy** |
| Offsite Backups | Verify external backup of 2FA and keys | Completed before proceeding |
| Power Supply | Keep device connected to 5V/2A+ charger | 80%+ battery charge |

If your device is not a Poco X3 Pro (`vayu`), **do not proceed** with this recovery image.

---

## 1. Bootloader Unlock

1. Create a Xiaomi account and bind it under **Developer Options → Mi Unlock Status**.
2. Download official **Mi Unlock Tool** from <https://en.miui.com/unlock/>.
3. Boot phone to Fastboot mode: turn off device, then hold <kbd>Power</kbd> + <kbd>Volume Down</kbd>.
4. Connect via USB-C to PC, launch Mi Unlock Tool, and complete verification.

---

## 2. PC Platform-Tools Setup

Install official Android SDK platform-tools (`fastboot` and `adb`):

- Official Download: <https://developer.android.com/tools/releases/platform-tools>
- Fastboot Documentation: <https://developer.android.com/tools/fastboot>

Verify CLI accessibility before proceeding:

```bash
fastboot --version
```

---

## 3. Flashing TWRP Recovery

### 3.1. Image Download & Hash Verification
Download `twrp-3.7.1_12-0-vayu.img` from <https://dl.twrp.me/vayu/> using a standard web browser:

```bash
# Verify checksum
sha256sum -c twrp-3.7.1_12-0-vayu.img.sha256
```

### 3.2. Fastboot Deployment
```bash
# 1. Confirm fastboot device connectivity
fastboot devices

# 2. Flash recovery partition
fastboot flash recovery twrp-3.7.1_12-0-vayu.img

# 3. Reboot into recovery
fastboot reboot
```

Hold <kbd>Volume Up</kbd> immediately during reboot until the TWRP splash screen appears.

---

## 4. Making TWRP Permanent & Preparing Storage

### 4.1. Stock ROM Patching
When TWRP boots for the first time, accept the prompt to patch the stock ROM. This prevents the stock Android kernel from overwriting TWRP on subsequent boots.

### 4.2. Format Data (FBE Removal)
1. Select **Wipe** → **Format Data**.
2. Type `yes` to confirm.
3. Reboot recovery: **Reboot** → **Recovery**.

### 4.3. Unattended TWRP Autostart Architecture

On headless server hardware without a physical display, the server must automatically resume operation following a power outage. In our TWRP environment:

1. **Native Init Service**: `/init.recovery.qcom.rc` registers and launches `service overrideprops /system/bin/overrideprops.sh`.
2. **Detection & Decryption**: TWRP unlocks `/data` via `dm-default-key`, and the startup script polls until `/data/linux` is accessible.
3. **Kernel Pseudofs Binding**: Virtual kernel filesystems (`proc`, `sys`, `dev`, `dev/pts`, `dev/shm`) are mounted to `/data/linux`.
4. **Daemon Launch**: `sshd` starts on port 22, and `/usr/local/bin/resilience-watchdog.sh` initializes Ethernet/DHCP, mounts Google Drive via mergerfs, and brings up `arr-stack`.

The entire stack reaches operational state ~15 seconds after cold power connection without requiring manual touch interaction.

---

## 5. Next Steps

Proceed to **[`installation.md`](installation.md)** to deploy the Ubuntu rootfs and initialize the \*arr media stack.
