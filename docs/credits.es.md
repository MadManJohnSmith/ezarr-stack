# Créditos y atribuciones

De dónde viene todo lo que hay en este repositorio y en estas guías.

---

## 1. ezarr — de Luctia

**Proyecto:** <https://github.com/Luctia/ezarr>
**Licencia:** MIT — <https://github.com/Luctia/ezarr/blob/main/LICENSE.md>
**Autoría:** Luctia · creado el 2022-06-26 · 1079 estrellas en el momento de
comprobarlo

> Verificado el 2026-10-05 con la API de GitHub: `"spdx_id": "MIT"` y
> `https://github.com/Luctia/ezarr/blob/main/LICENSE.md` → **200**.

**Ezarr es la inspiración directa de este repositorio**, y conviene decir
exactamente en qué sentido y en cuál no.

### Lo que le tomamos

**El conjunto de componentes.** Ezarr se define a sí mismo como
*"a project built to make it EZ to deploy a Servarr mediacenter on an Ubuntu
server"* y su README enumera Sonarr, Radarr, Prowlarr, Jackett, qBittorrent,
Bazarr, FlareSolverr, Homarr y compañía. Ese es exactamente el conjunto de
componentes de `lib/components.sh:19-32`: `media`, `downloads`, `arr`, `subs`,
`dashboard`, `search`. La idea de que todo esto se organice en **unidades con
identidad propia** (`--with` / `--without` / `--only`) viene de ahí.

**La idea de que esto se pueda hacer de un comando.** Un `./ezarr.sh --yes` que
deja el stack entero montado es la razón de ser de este proyecto también.

### Lo que **no** le tomamos

Nada de código. Ezarr es un script de shell + un `docker-compose` para Ubuntu.
Este repositorio **no usa Docker** y **no usa el código de ezarr**: `ezarr.sh`,
`ezarrctl` y `arr-stack` están escritos desde cero para funcionar sin systemd
dentro de un chroot de Android, que es un problema que Ezarr no tiene.

La licencia MIT cubre la reutilización del código si algum día quisiera
reutilizarlo; hoy, lo reutilizado es **la idea**, no el código.

---

## 2. Las guías TRaSH

<https://trash-guides.info/>

Las guías de TRaSH son la referencia community de facto sobre cómo montar un
stack *arr* sin que se rompa todo a la primera semana. De ahí vienen criterios
concretos:

| De dónde | Qué |
|---|---|
| <https://trash-guides.info/Getting-Started/> | Por qué la estructura de carpetas importa antes que los ajustes |
| <https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/> | Los hardlinks en el mismo filesystem, y por qué importan |
| <https://trash-guides.info/File-and-Folder-Structure/Check-if-hardlinks-are-working/> | Cómo **comprobar** que los hardlinks funcionan, en vez de suponerlo |
| <https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/> | Montar la estructura de biblioteca |
| <https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/> | qBittorrent bien puesto, sin romper los *arr* |
| <https://trash-guides.info/Guide-Sync/sonarr-cf-groups/> | Grupos de calidad de Sonarr |
| <https://trash-guides.info/Guide-Sync/radarr-cf-groups/> | Grupos de calidad de Radarr |
| <https://trash-guides.info/Glossary/> | El glosario, para no reexplicar qué es un indexador |
| <https://trash-guides.info/Hardlinks/How-to-setup-for/Docker/> | La variante para Docker (es la que sigue el README de Ezarr) |

Los 9 enlaces comprobados el 2026-10-05 devuelven **200**.

> **Nota honesta.** La página de hardlinks para Docker
> (`Hardlinks/How-to-setup-for/Docker/`) es una ruta antigua y **también
> funciona**, pero las guías se han reorganizado. Si una de las rutas de arriba
> te da 404 dentro de un tiempo, entra por <https://trash-guides.info/> y busca
> desde el índice.

---

## 3. Un teléfono sin sistema operativo puede ser un servidor

Esta es la idea que sostiene el proyecto entero, y no sale de ningún sitio de
referencia: sale de una pregunta práctica.

Un Poco X3 Pro es hardware de sobra para servir Jellyfin, Sonarr, Radarr y
qBittorrent a una casa. Su problema no son las especificaciones: es que está
diseñado para ser **consumido**, no para estar encendido, y su sistema
operativo lo trata así.

La respuesta es cambiarle el sistema por uno que **no espere** a nadie:

- **TWRP en lugar de Android.** Android mata lo que no está en pantalla, no te
  deja montar a voluntad y no tiene sitio para un rootfs. TWRP es un shell de
  recuperación que espera exactamente lo que tú le digas.
- **Un chroot Ubuntu en lugar de "aplicaciones Android".** Entras por SSH y
  trabajas como en cualquier servidor.
- **Cuidado con lo que Android te destrozaría en silencio.** De ahí toda la
  insistencia en `EZARR_DATA_ROOT`, en el backup previo, en los checksums
  obligatorios y en no confiar nunca solo en "el proceso existe".

El teléfono **ya no es un teléfono**. Eso no es un defecto: es lo que lo hace
servidor. Lo que se pierde (una cámara decente, las notificaciones de verdad, la
batería como sistema de energía) es justo lo que un servidor no necesita.

**Y el aviso honesto del `README.md:7-12` de este repositorio, que hacemos
nuestro:** el stack real que lleva meses funcionando en un Poco X3 Pro **no es
este código**. Este `ezarr.sh` no se ha ejecutado contra un teléfono físico.
Lo que está probado son 73 comprobaciones de sintaxis, contrato, códigos de
salida e idempotencia. Confundir las dos cosas es un error, y por eso está
dicho aquí con todas las letras.

---

## 4. Créditos de terceros usados en estas guías

### Texto citado literalmente

**TeamWin / TWRP** — <https://twrp.me/xiaomi/xiaomipocox3pro.html>

Copyright de TeamWin LLC. Material citado en `recovery.md`:

- Los tres comandos de flasheo (`adb reboot bootloader`,
  `fastboot flash recovery twrp.img`, `fastboot reboot`), reproducidos de la
  sección *"Fastboot Install Method (No Root Required)"* de esa página.
- La advertencia de desbloqueo: *"Understand that unlocking your device will
  wipe all of your personal data, settings, and apps from its memory."*
- La advertencia de que muchos dispositivos sobrescriben la recovery
  customization: *"many devices will replace your custom recovery automatically
  during first boot... you will have to repeat the install."*
- La advertencia sobre imágenes por dispositivo: *"TWRP images are specific to
  each device"*.
- El aviso de particiones dinámicas: *"This device uses Dynamic Partitions."*
- Estado de soporte (*Current*) y mantenedor (*Nebrassy*).

**Xiaomi** — <https://en.miui.com/unlock/>

Copyright de Xiaomi. `recovery.md` describe el procedimiento oficial de
desbloqueo (petición de solicitud → espera de aprobación → Mi Unlock Tool).
Se cita como **procedimiento publicado por el fabricante**, no como obra
literaria.

### Datos técnicos que vienen del proyecto original

| Dato | De dónde |
|---|---|
| Hash sha256 de `twrp-3.7.1_12-0-vayu.img` | `https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img.sha256` |
| Versiones de TWRP disponibles para `vayu` | Listado de `https://dl.twrp.me/vayu/` |

### Software y proyectos referenciados (nombres y enlaces)

Sólo como **referencia y enlaces**: no hay código de estos proyectos en el
repositorio, ni dentro de estos documentos.

- **Android Platform Tools** (Google) — <https://developer.android.com/tools/releases/platform-tools>
- **TWRP** (TeamWin) — <https://twrp.me/>
- **Magisk** (topjohnwu) — <https://github.com/topjohnwu/Magisk>
- **LineageOS** — <https://wiki.lineageos.org/devices/vayu/>
- **MIUI.eu** — <https://xiaomi.eu/>
- **Jellyfin** — <https://jellyfin.org/downloads/linux/>
- **Sonarr / Radarr / Prowlarr** — <https://sonarr.tv/> · <https://radarr.video/> · <https://prowlarr.com/>
- **Bazarr** — <https://bazarr.media/>
- **qBittorrent** — <https://www.qbittorrent.org/>
- **Jackett** — <https://github.com/Jackett/Jackett>
- **FlareSolverr** — <https://github.com/FlareSolverr/FlareSolverr>
- **Homarr** — <https://homarr.dev/>
- **Motion** — <https://motion-project.github.io/>
- **rclone** — <https://rclone.org/>
- **mergerfs** — <https://github.com/trapexit/mergerfs>
- **nginx** — <https://nginx.org/>
- **Tailscale** — <https://tailscale.com/kb/>
- **Cloudflare Tunnel** — <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/>
- **ntfy** — <https://ntfy.sh/> · <https://docs.ntfy.sh/>
- **Healthchecks.io** — <https://healthchecks.io/>

### Capturas y diagramas

> **En estos cuatro documentos no hay ni una captura de pantalla ni un diagrama
> de terceros.** Todo lo que hay son tablas y bloques de texto escritos aquí.

- `recovery.md`: la tabla de imágenes de TWRP reproduce **datos técnicos**
  (nombre, fecha, tamaño) del listado público de TeamWin, con el enlace al
  origen junto. No hay ninguna captura.
- `instalacion.md`: el resumen de 9 pasos y los bloques de salida de consola
  son de los propios scripts de este repositorio, ejecutados en esta máquina.
- `operacion.md`: la tabla de puertos sale de `lib/stack.sh:13-31` y las salidas
  de consola son ejecuciones reales. El diagrama del ciclo de `update` es una
  lista escrita aquí.

Si alguna vez se añade una imagen de terceros, hay que poner debajo el autor,
la licencia y el enlace de origen. Una imagen sin fuente es un plagio con
enlace, que es peor.

---

## 5. Licencia de estos documentos

Las guías de `docs/` son texto original de este repositorio. Se distribuyen
junto a él y bajo su misma licencia.
