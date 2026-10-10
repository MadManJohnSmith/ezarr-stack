# ezarr-stack ⚡

[![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-Interactive%20Diagrams-2ea44f?style=for-the-badge&logo=github)](https://madmanjohnsmith.github.io/ezarr-stack/)
[![Tests](https://img.shields.io/badge/Tests-86%2F86%20Passed-brightgreen?style=for-the-badge)](tests/smoke.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)
[![TRaSH Guides](https://img.shields.io/badge/TRaSH%20Guides-UMASK=002-orange?style=for-the-badge)](https://trash-guides.info/)

> **A production-hardened \*arr stack & Jellyfin media server designed for low-power ARM64 single-board computers and decommissioned Android devices running an Ubuntu chroot under TWRP.**
>
> 🌐 [**English**](README.md) | 🇪🇸 [**Español**](README.es.md) | 📊 [**Interactive Architecture Explorer**](https://madmanjohnsmith.github.io/ezarr-stack/)

---

## 🏛️ Interactive Architecture & Topology

Explore the interactive system diagram, service network layers, and hybrid storage topology directly in your browser:

👉 **[Launch Interactive Architecture Explorer](https://madmanjohnsmith.github.io/ezarr-stack/)** *(Hosted on GitHub Pages)*

### 1. Complete Stack Architecture
Ubuntu chroot running on TWRP (*vayu* / ARM64), hybrid tiered storage (local F2FS flash + Google Drive VFS via Mergerfs), Cloudflare Zero Trust tunnel, Tailscale VPN mesh, and native \*arr binaries:

[![Stack Architecture](docs/diagrams/stack-architecture.png)](https://madmanjohnsmith.github.io/ezarr-stack/stack-architecture.html)

### 2. Resilience, Watchdogs & Automated Recovery
5-second continuous self-healing loop (`resilience-watchdog`), periodic stack health probes via Healthchecks.io, thermal governor, automated malware detection, and encrypted offsite backups:

[![Resilience & Recovery Cycle](docs/diagrams/ciclo-vigilancia-respaldo.png)](https://madmanjohnsmith.github.io/ezarr-stack/ciclo-vigilancia-respaldo.html)

### 3. Hallway Camera & Motion Detection
RTSP IP camera capture stream, motion detection engine with `motion`, automatic cloud sync, and instant push alerts via `ntfy`:

[![Camera Pipeline](docs/diagrams/flujo-camara.png)](https://madmanjohnsmith.github.io/ezarr-stack/flujo-camara.html)

---

## 💡 What Makes ezarr-stack Different?

Most media server guides assume an x86 server running Docker with high electricity consumption and direct SATA drives. **ezarr-stack** solves a completely different engineering challenge: **repurposing silent, low-power ARM64 hardware (under 5W) into a zero-maintenance, enterprise-grade media hub.**

1. **Native Init & Service Control Without Systemd**:
   Android recovery/chroot kernels do not run systemd or Docker. `arr-stack` provides lightweight process supervision, deterministic stop/start ordering, and persistent `oom_score_adj` tuning (protecting Jellyfin while deprioritizing background crawlers).
2. **Tiered Hybrid Storage (Mergerfs + Rclone VFS Crypt)**:
   Overcomes small onboard flash storage by fusing fast local ext4/f2fs storage with Google Drive encrypted cloud storage into a unified `/data/media` mount with transparent auto-offloading.
3. **TRaSH Guides Standards & POSIX UMASK=002**:
   All services inherit `UMASK=002`, guaranteeing that downloaded media (`0664`) and directories (`0775`) are atomically accessible by Sonarr, Radarr, and Jellyfin without dangerous `chmod -R 777` loops.
4. **Dual TCP + UDP BitTorrent Optimization (Port 6881)**:
   qBittorrent is tuned for modern DHT trackers using hybrid TCP & uTP protocol bindings to eliminate queue stalls and maximize peer connectivity.
5. **Zero Open WAN Ports (Cloudflare Tunnel + Tailscale Mesh)**:
   External traffic is securely routed via encrypted Cloudflare Zero Trust tunnels and Tailscale WireGuard meshes. No router port forwarding required.
6. **Built-in Malicious Release & Executable Interception**:
   Automated watchdog heuristics immediately detect and purge fake torrent releases containing `.exe` or executable scripts before wasting bandwidth or storage.
7. **Hands-Off TWRP Autostart**:
   Full unattended boot from cold hardware shutoff: TWRP init stage 2 executes `overrideprops.sh`, detects `/data/linux`, binds virtual filesystems, and brings up the stack automatically in ~15 seconds.

---

## 📦 Service Catalog & Ports

| Service | Port | Description | Managed By |
|---|---|---|---|
| **Jellyfin** | `8096` | Hardware-optimized media streaming server | `arr-stack` |
| **Sonarr** | `8989` | TV show acquisition & episode tracker | `arr-stack` |
| **Radarr** | `7878` | Movie collection acquisition & metadata | `arr-stack` |
| **Prowlarr** | `9696` | Torrent indexer proxy & sync engine | `arr-stack` |
| **Bazarr** | `6767` | Automated subtitle downloader (OpenSubtitles/SubDL) | `arr-stack` |
| **qBittorrent-nox** | `8080` (Web) / `6881` (TCP/UDP) | BitTorrent client with DHT & uTP enabled | `arr-stack` |
| **Homarr** | `7575` | Lightweight status dashboard | `arr-stack` |
| **Nginx** | `80` / `8000` / `443` | Reverse proxy & local LAN gatekeeper | `arr-stack` |
| **FlareSolverr** | `8191` | Cloudflare challenge solver for indexers | `arr-stack` |
| **Motion** | `8082` / RTSP | Motion detection & video surveillance | `arr-stack` |
| **Cloudflared** | Tunnel | Dual-replica Zero Trust remote access | `arr-stack` |
| **Tailscale** | Tailnet | Secure WireGuard remote administration mesh | `arr-stack` |
| **Redis** | `6379` | In-memory key-value cache | `arr-stack` |

---

## 🚀 Quick Start

### 1. Prerequisites
- An ARM64 device (e.g. Poco X3 Pro, Raspberry Pi 4/5, or Linux SBC) with an Ubuntu/Debian chroot or base installation.
- If using an Android smartphone: follow the [TWRP Recovery Guide](docs/recovery.md).

### 2. Verify and Dry-Run
Always inspect the planned operations before modifying system state:

```bash
# Preview the installation plan without making changes
./ezarr.sh --dry-run --profile minimal
```

### 3. Installation
```bash
# Execute installation
sudo ./ezarr.sh --yes --profile minimal
```

---

## 🔒 Safe Secrets Management (`ezarrctl secrets`)

`ezarr-stack` includes a safe CLI interface for configuring sensitive keys without risk of committing them to git:

```bash
# Initialize secrets configuration
ezarrctl secrets init

# Set an API key or password
ezarrctl secrets set EZARR_CAMERA_RTSP_PASS "my-secure-password"
ezarrctl secrets set EZARR_NTFY_TOPIC "my-private-topic"
ezarrctl secrets set EZARR_SUBS_API_KEY "my-opensubtitles-key"

# Verify secrets permissions and presence
ezarrctl secrets list
ezarrctl secrets doctor
```

All credentials are encrypted or isolated with `0600` permissions in `/etc/ezarr/secrets.conf`.

---

## 🛠️ Daily Operations (`ezarrctl`)

The stack is governed by `ezarrctl`, providing a single unified entry point:

```bash
ezarrctl status           # Display running/stopped status of all services
ezarrctl start [service]  # Start one, multiple, or all services
ezarrctl stop [service]   # Gracefully terminate services
ezarrctl restart          # Restart services respecting dependency graph
ezarrctl logs -f [service]# Stream service logs in real time
ezarrctl backup           # Generate verified database & config backup
ezarrctl doctor           # Run comprehensive diagnostic checks
```

---

## 📖 Documentation

- [Hardware & TWRP Recovery Guide](docs/recovery.md)
- [Complete Installation Guide](docs/instalacion.md)
- [Daily Operations & Maintenance](docs/operacion.md)
- [Architecture & Storage Deep Dive](docs/diagrams/stack-architecture.html)
- [Credits & Attribution](docs/creditos.md)

---

## 🤝 Attribution & Credits

`ezarr-stack` was inspired by and built with gratitude to [Luctia/ezarr](https://github.com/Luctia/ezarr) (MIT License) and the community recommendations from [TRaSH Guides](https://trash-guides.info/).

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
