# ezarr-stack

[![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-Diagramas%20Interactivos-2ea44f?style=flat&logo=github)](https://madmanjohnsmith.github.io/ezarr-stack/)
[![Tests](https://img.shields.io/badge/Tests-86%2F86%20Correctas-3fb950?style=flat)](tests/smoke.sh)
[![Licencia: MIT](https://img.shields.io/badge/Licencia-MIT-blue?style=flat)](LICENSE)
[![TRaSH Guides](https://img.shields.io/badge/TRaSH%20Guides-UMASK=002-orange?style=flat)](https://trash-guides.info/)
[![Plataforma](https://img.shields.io/badge/Plataforma-ARM64%20%7C%20x86__64-lightgrey?style=flat)](#requisitos-previos)

**Documentación:** [English](README.md) · [Español](README.es.md) · [Explorador Interactivo de Arquitectura](https://madmanjohnsmith.github.io/ezarr-stack/)

Servidor multimedia con stack Servarr y Jellyfin blindado para producción, optimizado para hardware ARM64 de bajo consumo y teléfonos Android reciclados mediante un chroot Ubuntu bajo TWRP. Incluye supervisión nativa de procesos sin Docker ni systemd, almacenamiento híbrido por niveles (mergerfs + rclone Google Drive VFS), acceso perimetral seguro sin puertos abiertos mediante Cloudflare Zero Trust y Tailscale, y vigilantes continuos de auto-curación.

---

> [!TIP]
> **Explora la Arquitectura en Línea**
>
> Puedes navegar la topología completa del sistema, las capas de red y el modelo de almacenamiento híbrido directamente en el navegador mediante el **[Explorador Interactivo de Arquitectura](https://madmanjohnsmith.github.io/ezarr-stack/)**, desplegado continuamente en GitHub Pages.

---

## Diagramas de Arquitectura

<p align="center">
  <a href="https://madmanjohnsmith.github.io/ezarr-stack/stack-architecture.html">
    <img src="docs/diagrams/stack-architecture.png" alt="Diagrama de Arquitectura del Stack" width="90%">
  </a>
</p>

<details>
<summary><strong>Ver Diagramas de Resiliencia y Flujo de Cámara</strong></summary>

### 1. Ciclo de Resiliencia, Vigilantes y Recuperación Automática
Bucle continuo de auto-curación cada 5 segundos (`resilience-watchdog`), comprobaciones de salud del stack vía Healthchecks.io, control térmico, purga proactiva de releases con malware y copias cifradas semanales:

<p align="center">
  <a href="https://madmanjohnsmith.github.io/ezarr-stack/ciclo-vigilancia-respaldo.html">
    <img src="docs/diagrams/ciclo-vigilancia-respaldo.png" alt="Ciclo de Resiliencia y Respaldo" width="85%">
  </a>
</p>

### 2. Cámara IP y Detección de Movimiento
Captura directa RTSP, motor de detección de movimiento con `motion`, búfer local, subida automática a Google Drive y alertas push instantáneas mediante `ntfy`:

<p align="center">
  <a href="https://madmanjohnsmith.github.io/ezarr-stack/flujo-camara.html">
    <img src="docs/diagrams/flujo-camara.png" alt="Canal de la Cámara y Movimiento" width="85%">
  </a>
</p>

</details>

---

## Comparativa Arquitectónica

La mayoría de tutoriales asumen hardware x86 con Docker, matrices de discos mecánicos y elevado consumo de energía. **ezarr-stack** está diseñado para un entorno operativo diferente:

| Dimensión | Homelab x86 Tradicional con Docker | ezarr-stack en ARM64 / Chroot de Teléfono |
|---|---|---|
| **Consumo Eléctrico** | 35W – 120W (consumo continuo de pared) | **< 5W** (reposo ~2W, respaldado por batería) |
| **Disipación y Ruido** | Ventiladores activos de chasis y CPU | **100% silencioso**, disipación pasiva |
| **Sobrecarga de Init** | Daemon de Docker, containerd, overlay2 | **Binarios nativos**, supervisor `arr-stack`, ajuste selectivo de `oom_score_adj` |
| **Almacenamiento** | Múltiples discos físicos en RAID | **Almacenamiento Híbrido por Niveles**: flash local rápida + Google Drive VFS crypt vía mergerfs |
| **Modelo de Permisos** | Conflictos recurrentes y bucles `chmod -R 777` | **Estándar TRaSH Guides**: `UMASK=002` unificado (ficheros `0664`, carpetas `0775`) |
| **Exposición WAN** | Apertura de puertos en router, DDNS dinámico | **Cero puertos abiertos**: túnel Cloudflare redundante + malla WireGuard Tailscale |
| **Transporte BitTorrent** | Anuncios solo por TCP por defecto | **Dual TCP + uTP (puerto 6881)** para enjambre DHT y trackers UDP |
| **Recuperación tras Apagón**| Encendido manual o Wake-on-LAN | **Autostart desatendido en TWRP Stage 2** vía `/init.recovery.qcom.rc` (~15s) |
| **Defensa contra Malware** | Revisión manual de descargas | **Autodefensa heurística en watchdog**: detecta y purga torrents falsos con `.exe` |

---

## Catálogo de Servicios

| Servicio | Puerto / Protocolo | Función | Gestor de Procesos |
|---|---|---|---|
| **Jellyfin** | `8096` / HTTP | Servidor de streaming multimedia (prioridad DirectPlay) | `arr-stack` |
| **Sonarr** | `8989` / HTTP | Gestión y seguimiento de series de TV | `arr-stack` |
| **Radarr** | `7878` / HTTP | Gestión y metadatos de colecciones de películas | `arr-stack` |
| **Prowlarr** | `9696` / HTTP | Administración de indexadores y sincronización proxy | `arr-stack` |
| **Bazarr** | `6767` / HTTP | Descargador automatizado de subtítulos (OpenSubtitles, SubDL) | `arr-stack` |
| **qBittorrent-nox** | `8080` (Web) / `6881` (TCP/UDP) | Cliente BitTorrent con DHT, uTP y enlace exclusivo a eth0 | `arr-stack` |
| **Homarr** | `7575` / HTTP | Panel de control ligero | `arr-stack` |
| **Nginx** | `80` / `8000` / `443` | Proxy inverso y pasarela de control LAN | `arr-stack` |
| **FlareSolverr** | `8191` / HTTP | Resolución de retos Cloudflare Turnstile | `arr-stack` |
| **Motion** | `8082` / RTSP | Motor de detección de movimiento de videovigilancia | `arr-stack` |
| **Cloudflared** | Túnel (QUIC) | Acceso exterior Zero Trust con réplica doble | `arr-stack` |
| **Tailscale** | Tailnet (WireGuard) | Malla de administración cifrada punto a punto | `arr-stack` |
| **Redis** | `6379` / En Memoria | Caché de alta velocidad para aplicaciones | `arr-stack` |

---

## Inicio Rápido

### 1. Requisitos Previos
- Un dispositivo ARM64 (ej. Poco X3 Pro, Raspberry Pi 4/5, placa SBC) o un host x86_64 con Ubuntu/Debian.
- Si utilizas un smartphone Android: consulta la **[Guía de Recuperación TWRP](docs/recovery.md)**.

### 2. Verificación Previa (Dry-Run)
Inspecciona las descargas de binarios, creación de directorios y rutas antes de modificar el sistema:

```bash
# Previsualizar operaciones para el perfil mínimo (Core + Media)
./ezarr.sh --dry-run --profile minimal
```

### 3. Ejecución
```bash
# Ejecutar instalación no interactiva
sudo ./ezarr.sh --yes --profile minimal
```

---

## Gestión de Secretos (`ezarrctl secrets`)

> [!IMPORTANT]
> Nunca subas credenciales en texto claro ni claves API a repositorios git. `ezarrctl secrets` proporciona una interfaz por consola que aísla los secretos en `/etc/ezarr/secrets.conf` con permisos estrictos `0600`.

```bash
# Inicializar archivo de configuración de secretos
ezarrctl secrets init

# Asignar credenciales requeridas
ezarrctl secrets set EZARR_CAMERA_RTSP_PASS "tu-password-de-camara"
ezarrctl secrets set EZARR_NTFY_TOPIC "tu-topic-privado-ntfy"
ezarrctl secrets set EZARR_SUBS_API_KEY "tu-api-key-opensubtitles"

# Auditar permisos y verificar ausencia de valores por defecto
ezarrctl secrets list
ezarrctl secrets doctor
```

---

## Operación y Comandos (`ezarrctl`)

El stack se supervisa a través de la herramienta `ezarrctl`:

```bash
ezarrctl status           # Muestra el estado activo/detenido de los servicios
ezarrctl start [servicio] # Arranca uno, varios o todos los servicios
ezarrctl stop [servicio]  # Detiene los servicios de forma limpia
ezarrctl restart          # Reinicia secuencialmente respetando dependencias
ezarrctl logs -f [servicio]# Visualiza registros con prefijos y marcas temporales
ezarrctl backup           # Genera un respaldo comprimido y firmado con SHA-256
ezarrctl doctor           # Ejecuta comprobaciones independientes de puertos y montajes
```

<details>
<summary><strong>Ver Tabla de Códigos de Salida</strong></summary>

```bash
ezarrctl exit-codes
```

| Código de Salida | Significado |
|---|---|
| `0` | Operación exitosa / Todas las comprobaciones pasadas |
| `1` | Error general de ejecución |
| `2` | Argumentos o sintaxis de comando no válidos |
| `3` | Falta configuración o credenciales |
| `4` | Permiso denegado (requiere privilegios root) |
| `5` | Red no disponible |
| `6` | Error de verificación de dependencias o sumas de control |

</details>

---

## Documentación

- **[Guía de Hardware y Recuperación](docs/recovery.md)** ([Español](docs/recovery.es.md)) — Flasheo de TWRP, descifrado FBE y autostart en frío.
- **[Guía de Instalación](docs/installation.md)** ([Español](docs/installation.es.md)) — Despliegue del rootfs y puesta en marcha del stack.
- **[Guía de Operación](docs/operation.md)** ([Español](docs/operation.es.md)) — Mantenimiento diario, gestión de procesos y respaldos.
- **[Créditos y Reconocimientos](docs/credits.md)** ([Español](docs/credits.es.md)) — Origen del proyecto, Luctia/ezarr y guías TRaSH.

---

## Reconocimientos y Licencia

`ezarr-stack` fue inspirado por y desarrollado con agradecimiento a [Luctia/ezarr](https://github.com/Luctia/ezarr) (Licencia MIT) y los estándares de [TRaSH Guides](https://trash-guides.info/).

Distribuido bajo la [Licencia MIT](LICENSE).
