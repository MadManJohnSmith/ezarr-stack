# Installation: From Cold Hardware to Serving Media

> [**English**](installation.md) · [**Español**](installation.es.md)

Complete, deterministic walk-through to deploying the \*arr media stack and Jellyfin on an ARM64 single-board computer or an Android smartphone running an Ubuntu chroot under TWRP.

If your device does not have TWRP installed yet, complete **[`recovery.md`](recovery.md)** first.

---

## 0. Architecture Context

This repository provides the installation engine (`ezarr.sh`), runtime controller (`ezarrctl`), process supervisor (`arr-stack`), and configuration layer.

The underlying rootfs is an Ubuntu ARM64 environment. `ezarr.sh` automatically detects if it is operating inside a chroot environment (`lib/env.sh`, function `ezarr_detect_env`) and adapts its service control paths accordingly.

All scripts pass strict POSIX syntax checks (`bash -n`) and satisfy the contract verification test suite (`bash tests/smoke.sh`, 86 checks passing).

---

## 1. Directory Structure & Permissions

In accordance with **TRaSH Guides** standards, the filesystem layout separates downloaded torrents, cloud-offloaded mounts, and local scratch files under a unified structure:

```text
/data/
├── local/           # Fast local flash storage (ext4 / f2fs)
│   ├── Movies/
│   ├── TV/
│   └── Music/
├── remote/          # Google Drive VFS mount via rclone
├── media/           # Unified FUSE mount via mergerfs (local + remote)
│   ├── Movies/
│   ├── TV/
│   └── Music/
└── torrents/        # qBittorrent active downloads and staging
    ├── movies/
    └── tv/
```

All daemons operate with `UMASK=002`, guaranteeing that files are created with `0664` permissions and directories with `0775`.

---

## 2. Preparing the Rootfs Chroot (TWRP Only)

If deploying on an Android device booted in TWRP:

1. **Mount Data Partition**: Ensure `/data` is formatted and unencrypted.
2. **Deploy Ubuntu Base**: Unpack an Ubuntu ARM64 minimal rootfs into `/data/linux`.
3. **Mount Kernel Pseudofs**:
   ```bash
   mount -t proc proc /data/linux/proc
   mount -t sysfs sysfs /data/linux/sys
   mount --bind /dev /data/linux/dev
   mount -t devpts devpts /data/linux/dev/pts
   ```
4. **Enter Chroot**:
   ```bash
   chroot /data/linux /bin/bash
   ```

---

## 3. Pre-Installation Dry Run

Always preview the planned installation without modifying system files:

```bash
# Preview operations for minimal profile (Core + Media)
./ezarr.sh --dry-run --profile minimal
```

Review the step list: `ezarr.sh` will list every binary download, directory creation, and system configuration step deterministically.

---

## 4. Executing Installation

Execute the installation script with root privileges:

```bash
sudo ./ezarr.sh --yes --profile minimal
```

The installer will:
1. Validate system architecture (ARM64 / x86_64).
2. Install dependencies (curl, jq, sqlite3, nginx, redis, ffmpeg).
3. Download and unpack verified application binaries (Sonarr, Radarr, Prowlarr, Bazarr, Jellyfin, qBittorrent-nox).
4. Install `ezarrctl` and `arr-stack` to `/usr/local/bin/`.
5. Generate baseline service configurations with `UMASK=002`.

---

## 5. Post-Installation Configuration

### 5.1. Configure Secrets
Initialize the secrets registry and configure sensitive credentials:

```bash
ezarrctl secrets init
ezarrctl secrets set EZARR_CAMERA_RTSP_PASS "your-camera-password"
ezarrctl secrets set EZARR_NTFY_TOPIC "your-private-ntfy-topic"
```

### 5.2. Verify Stack Status
```bash
# Check service health
ezarrctl status

# Run system doctor diagnostics
ezarrctl doctor
```

Continue to **[`operation.md`](operation.md)** for ongoing administration and monitoring commands.
