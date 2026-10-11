# ezarr-stack

[![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-Interactive%20Diagrams-2ea44f?style=flat&logo=github)](https://madmanjohnsmith.github.io/ezarr-stack/)
[![Tests](https://img.shields.io/badge/Tests-86%2F86%20Passed-3fb950?style=flat)](tests/smoke.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)](LICENSE)
[![TRaSH Guides](https://img.shields.io/badge/TRaSH%20Guides-UMASK=002-orange?style=flat)](https://trash-guides.info/)
[![Platform](https://img.shields.io/badge/Platform-ARM64%20%7C%20x86__64-lightgrey?style=flat)](#prerequisites)

**Documentation:** [English](README.md) · [Español](README.es.md) · [Interactive Architecture Explorer](https://madmanjohnsmith.github.io/ezarr-stack/)

A production-hardened Servarr stack and Jellyfin media server optimized for low-power ARM64 hardware and repurposed Android devices running an Ubuntu chroot under TWRP. Features native process orchestration without Docker or systemd, tiered hybrid storage (mergerfs + rclone Google Drive VFS), zero-open-port ingress via Cloudflare Zero Trust and Tailscale, and continuous self-healing watchdogs.

---

> [!TIP]
> **Explore the Architecture Online**
>
> You can navigate the complete system topology, service network layers, and tiered storage model in the browser via the **[Interactive Architecture Explorer](https://madmanjohnsmith.github.io/ezarr-stack/)**, deployed automatically on GitHub Pages.

---

## Architecture Diagrams

<p align="center">
  <a href="https://madmanjohnsmith.github.io/ezarr-stack/stack-architecture.html">
    <img src="docs/diagrams/stack-architecture.png" alt="Stack Architecture Diagram" width="90%">
  </a>
</p>

<details>
<summary><strong>View Additional System Diagrams (Resilience Cycle & Camera Pipeline)</strong></summary>

### 1. Resilience, Watchdogs & Automated Recovery Cycle
Continuous 5-second self-healing loop (`resilience-watchdog`), periodic health pings via Healthchecks.io, thermal regulation, automated malware release purging, and weekly offsite backups:

<p align="center">
  <a href="https://madmanjohnsmith.github.io/ezarr-stack/ciclo-vigilancia-respaldo.html">
    <img src="docs/diagrams/ciclo-vigilancia-respaldo.png" alt="Resilience and Recovery Cycle" width="85%">
  </a>
</p>

### 2. Hallway IP Camera & Motion Stream
Direct RTSP ingestion, motion detection daemon, local buffering, automatic Google Drive sync, and push notifications via `ntfy`:

<p align="center">
  <a href="https://madmanjohnsmith.github.io/ezarr-stack/flujo-camara.html">
    <img src="docs/diagrams/flujo-camara.png" alt="Camera Stream and Motion Pipeline" width="85%">
  </a>
</p>

</details>

---

## Architectural Comparison

Traditional media server guides assume dedicated x86 hardware running Docker, multi-drive SATA arrays, and high electricity consumption. **ezarr-stack** is engineered for an entirely different operational envelope:

| Dimension | Traditional x86 Docker Homelab | ezarr-stack on ARM64 / Phone Chroot |
|---|---|---|
| **Power Consumption** | 35W – 120W (continuous wall draw) | **< 5W** (idle ~2W, battery-buffered) |
| **Cooling & Acoustics** | Active chassis & CPU fans | **100% silent**, passive thermal management |
| **Supervision Overhead** | Docker daemon, containerd, overlay2 | **Direct binaries**, `arr-stack` supervisor, custom `oom_score_adj` |
| **Storage Architecture** | Multi-TB physical disks / RAID | **Tiered Hybrid Storage**: fast local flash + Google Drive VFS crypt via mergerfs |
| **Permissions Model** | Recurring `chmod -R 777` conflicts | **TRaSH Guides Standard**: unified `UMASK=002` (files `0664`, dirs `0775`) |
| **Network Exposure** | Router port forwards, dynamic DNS | **Zero exposed ports**: dual-replica Cloudflare Tunnel + Tailscale WireGuard |
| **BitTorrent Transport** | Default TCP-only announces | **Dual TCP + uTP (port 6881)** for resilient DHT bootstrap and tracker announces |
| **Cold Recovery** | Manual power button or Wake-on-LAN | **Automated TWRP Stage 2 init autostart** via `/init.recovery.qcom.rc` (~15s) |
| **Malware Defense** | Manual torrent inspection | **Automated heuristic defense**: detects and purges fake `.exe`/script torrents |

---

## Service Catalog

| Service | Port / Protocol | Function | Process Manager |
|---|---|---|---|
| **Jellyfin** | `8096` / HTTP | Media streaming server (DirectPlay prioritized) | `arr-stack` |
| **Sonarr** | `8989` / HTTP | TV series acquisition and organization | `arr-stack` |
| **Radarr** | `7878` / HTTP | Movie collection acquisition and metadata | `arr-stack` |
| **Prowlarr** | `9696` / HTTP | Indexer management and proxy sync | `arr-stack` |
| **Bazarr** | `6767` / HTTP | Subtitle downloader (OpenSubtitles, SubDL) | `arr-stack` |
| **qBittorrent-nox** | `8080` (Web) / `6881` (TCP/UDP) | BitTorrent client with DHT, uTP, and eth0 binding | `arr-stack` |
| **Homarr** | `7575` / HTTP | Lightweight resource dashboard | `arr-stack` |
| **Nginx** | `80` / `8000` / `443` | Reverse proxy and local LAN gatekeeper | `arr-stack` |
| **FlareSolverr** | `8191` / HTTP | Cloudflare Turnstile challenge solver | `arr-stack` |
| **Motion** | `8082` / RTSP | Video motion detection engine | `arr-stack` |
| **Cloudflared** | Tunnel (QUIC) | Dual-replica Zero Trust external ingress | `arr-stack` |
| **Tailscale** | Tailnet (WireGuard) | Encrypted administration mesh network | `arr-stack` |
| **Redis** | `6379` / In-Memory | High-speed cache for applications | `arr-stack` |

---

## Quick Start

### 1. Prerequisites
- An ARM64 device (e.g. Poco X3 Pro, Raspberry Pi 4/5, Rockchip SBC) or an x86_64 host with Ubuntu/Debian.
- For Android smartphone deployment: review the **[Hardware & TWRP Recovery Guide](docs/recovery.md)**.

### 2. Dry-Run Verification
Inspect all planned binary downloads, directory creations, and configuration writes before modifying system state:

```bash
# Preview operations for the minimal profile (Core + Media)
./ezarr.sh --dry-run --profile minimal
```

### 3. Execution
```bash
# Run non-interactive installation
sudo ./ezarr.sh --yes --profile minimal
```

---

## Secrets Administration (`ezarrctl secrets`)

> [!IMPORTANT]
> Never commit plain-text credentials or API keys to git. `ezarrctl secrets` provides a command-line interface that isolates credentials inside `/etc/ezarr/secrets.conf` with `0600` permissions.

```bash
# Initialize secrets configuration
ezarrctl secrets init

# Set required credentials
ezarrctl secrets set EZARR_CAMERA_RTSP_PASS "your-camera-password"
ezarrctl secrets set EZARR_NTFY_TOPIC "your-private-ntfy-topic"
ezarrctl secrets set EZARR_SUBS_API_KEY "your-opensubtitles-key"

# Verify permissions and absence of default placeholders
ezarrctl secrets list
ezarrctl secrets doctor
```

---

## Operations & CLI (`ezarrctl`)

The stack is governed through a single utility, `ezarrctl`:

```bash
ezarrctl status           # Display running/stopped status of all services
ezarrctl start [service]  # Start one, multiple, or all services
ezarrctl stop [service]   # Terminate services cleanly with forced fallback
ezarrctl restart          # Sequentially restart respecting dependencies
ezarrctl logs -f [service]# Stream timestamped logs in real time
ezarrctl backup           # Generate verified config and database tarball
ezarrctl doctor           # Run independent health probes on ports and mounts
```

<details>
<summary><strong>View Exit Codes and CLI Specification</strong></summary>

```bash
ezarrctl exit-codes
```

| Exit Code | Meaning |
|---|---|
| `0` | Success / All probes passed |
| `1` | General runtime error |
| `2` | Invalid arguments or command syntax |
| `3` | Missing configuration or credentials |
| `4` | Permission denied (root required) |
| `5` | Network unavailable |
| `6` | Missing checksum or dependency verification |

</details>

---

## Documentation

- **[Hardware & Recovery Guide](docs/recovery.md)** ([Español](docs/recovery.es.md)) — Flashing TWRP, removing FBE encryption, and cold-boot autostart.
- **[Installation Guide](docs/installation.md)** ([Español](docs/installation.es.md)) — Step-by-step rootfs provisioning and stack deployment.
- **[Operations Guide](docs/operation.md)** ([Español](docs/operation.es.md)) — Day-to-day maintenance, service control, and backups.
- **[Credits & Attribution](docs/credits.md)** ([Español](docs/credits.es.md)) — Project origin, Luctia/ezarr, and TRaSH Guides.

---

## Attribution & License

`ezarr-stack` was inspired by and built with gratitude to [Luctia/ezarr](https://github.com/Luctia/ezarr) (MIT License) and the community architectural standards from [TRaSH Guides](https://trash-guides.info/).

Distributed under the [MIT License](LICENSE).
