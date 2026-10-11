# Credits & Attribution

> [**English**](credits.md) · [**Español**](credits.es.md)

Detailed attribution and origins of the tools, inspirations, and specifications behind `ezarr-stack`.

---

## 1. Luctia/ezarr

- **Repository**: <https://github.com/Luctia/ezarr>
- **License**: MIT License
- **Original Author**: Luctia

`ezarr-stack` was directly inspired by Luctia's original ezarr project. Luctia established the vision of a unified, single-command installer for deploying the Servarr media ecosystem on Ubuntu. While Luctia/ezarr is built around Docker Compose on x86 machines, `ezarr-stack` re-engineers this vision for native execution inside low-power ARM64 chroot environments without systemd or Docker overhead.

---

## 2. TRaSH Guides

- **Reference**: <https://trash-guides.info/>

TRaSH Guides represent the gold standard for community media automation architecture. `ezarr-stack` incorporates:
- **Consistent Filesystem Layout**: Proper separation of torrent staging and unified media libraries under `/data/`.
- **POSIX UMASK=002**: Ensuring that downloaded assets and folders maintain `0664`/`0775` permissions across services.

---

## 3. TeamWin Recovery Project (TWRP)

- **Reference**: <https://twrp.me/>
- **Poco X3 Pro Device Profile**: Maintainer **Nebrassy** (<https://twrp.me/xiaomi/xiaomipocox3pro.html>)

TWRP provides the permanent recovery environment, partition unlocking, and kernel boot layer enabling Ubuntu chroot execution on decommissioned smartphone hardware.

---

## 4. Diagramming & Visualization

- **Archify**: System diagrams and interactive explorer generated with Archify.

---

## 5. Upstream Open-Source Projects

We gratefully acknowledge the developers of the foundational software powering this stack:
- **Jellyfin**: <https://jellyfin.org/>
- **Sonarr**: <https://sonarr.tv/>
- **Radarr**: <https://radarr.video/>
- **Prowlarr**: <https://prowlarr.com/>
- **Bazarr**: <https://www.bazarr.media/>
- **qBittorrent**: <https://www.qbittorrent.org/>
- **Mergerfs**: <https://github.com/trapexit/mergerfs>
- **Rclone**: <https://rclone.org/>
- **Cloudflare Tunnel**: <https://github.com/cloudflare/cloudflared>
- **Tailscale**: <https://tailscale.com/>
- **Homarr**: <https://homarr.dev/>
- **Nginx**: <https://nginx.org/>
