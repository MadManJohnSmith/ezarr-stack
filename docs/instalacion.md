# Instalación: del teléfono apagado al stack sirviendo

Camino completo, en orden, desde el Poco X3 Pro apagado hasta que Jellyfin
responde en el navegador.

Esta página cubre **desde TWRP ya instalado**. Si el teléfono todavía no lo
tiene, empieza por **[`recovery.md`](recovery.md)** y vuelve aquí.

---

## Aviso de honestidad, antes de nada

**Este repositorio no crea el chroot Ubuntu.** `ezarr.sh` y `ezarrctl` **detectan**
si están dentro de un chroot (`lib/env.sh:28`, función `ezarr_detect_env`) y a
partir de ahí trabajan, pero el chroot lo montas tú en el paso 1. No hay ningún
script en el repo que haga `debootstrap`, ni ningún enlace al respecto en el
código. Lo digo aquí para que nadie busque un comando que no existe.

**Y lo que sí está probado:** `bash -n` pasa en los 10 ficheros de scripts, y
`bash tests/smoke.sh` da **73 comprobaciones, todas correctas** (exit 0). Eso
comprueba sintaxis, contratos, códigos de salida e idempotencia. **No prueba
que el stack funcione en un teléfono real**: nadie ha ejecutado este instalador
contra un `vayu` físico. Lo que lleva meses funcionando en un Poco X3 Pro es
**otro** stack, no este código. Si algo falla, empieza por `ezarrctl doctor`.

---

## Estado verificado de este repositorio

Comprobado el **2026-10-05** en esta máquina:

```bash
$ cd ezarr-stack      # tras `git clone`
$ for f in ezarr.sh ezarrctl arr-stack lib/*.sh tests/smoke.sh; do
      printf '%-22s ' "$f"; bash -n "$f" && echo "OK (bash -n)"; done
ezarr.sh               OK (bash -n)
ezarrctl               OK (bash -n)
arr-stack              OK (bash -n)
lib/components.sh      OK (bash -n)
lib/config.sh          OK (bash -n)
lib/env.sh             OK (bash -n)
lib/log.sh             OK (bash -n)
lib/plan.sh            OK (bash -n)
lib/stack.sh           OK (bash -n)
tests/smoke.sh         OK (bash -n)

$ bash tests/smoke.sh
...
73 comprobaciones, todas correctas
EXIT=0
```

> **Pequeña incoherencia del repo:** `README.md:8`, `README.md:21` y
> `CHANGELOG.md:91` dicen "65 comprobaciones". El test imprime **73**. Las
> cifras pequeñas del README están desfasadas; el número real es 73.

---

## 1. Teléfono apagado → TWRP → chroot

### 1.1. Encender en TWRP, siempre

Con el teléfono apagado: **Power + Vol down**, suelta Power, suelta Vol down.
Espera a la pantalla de TeamWin.

Android no sirve aquí: su gestión de memoria mata lo que no esté en pantalla, y
además no hay sitio donde meter un rootfs completo. **TWRP no es el paso previo
al stack, es el sistema con el que va a vivir el servidor.**

### 1.2. Montar /data

TWRP → *Mount*. Marca:

- ☑ `data` — **obligatorio**, aquí va todo
- ☑ `system` — solo para poder leer el `/system/build.prop` si hace falta

Comprueba que la barra de arriba pone **"Mounted"**. Si no monta `data`, vuelve
a Wipe → Format Data (`recovery.md`, paso 4.3).

### 1.3. Crear el chroot Ubuntu

**Esto lo escribes tú; el repo no lo hace.** Lo mínimo que necesita el stack
para funcionar:

| Requisito | Por qué |
|---|---|
| `bin` y `lib` de **arm64** | El Poco X3 Pro es arm64; el chroot no puede ser amd64 |
| `/etc/resolv.conf` con nombres | **Todos** los pasos de red lo necesitan. `lib/stack.sh:115` dice que en el chroot de TWRP suele ser un symlink roto |
| `/proc`, `/dev`, `/sys` montados | Sin `/proc` no ve `pgrep`, y `arr-stack` decide si algo está vivo con `pgrep` |
| `ca-certificates` | Sin ellos no hay HTTPS: ni descargas, ni firmas |
| `pgrep`, `sha256sum`, `curl` o `wget` | `lib/stack.sh:224-227` los exige en el paso 2 y falla si faltan |

Un `debootstrap` a mano con `arm64` sobre busybox de TWRP es lo habitual. Si tu
distribución de busybox no trae `debootstrap`, haz el bootstrap en un PC arm64
(o en un contenedor `arm64`) y **copia el árbol al teléfono** por USB o por red;
esa es la parte que ningún script de este repo te ahorra.

**Apunta dónde lo montaste.** Lo vas a necesitar para el marcador.

### 1.4. Comprobar que el instalador detecta el chroot

Entra en el chroot:

```bash
chroot /data/ezarr-rootfs /bin/bash
```

Y entonces:

```bash
./ezarr.sh --dry-run -v
```

La primera línea del log en `-v` dice el entorno detectado
(`ezarr.sh:215`):

```
entorno detectado: chroot (init=none, android=1)
```

Y el resumen del entorno (`lib/env.sh:254`, `ezarr_env_summary`) tiene que
decir:

```
entorno     chroot de telefono (TWRP)
servicios   sin init (cron + arr-stack)
```

> **Si dice `maquina normal`, para.** El instalador no va a hacer nada útil
> hasta que lo detects bien. Las tres señales que usa están en `lib/env.sh:38-88`:
> marcador `chroot.marker`, PID 1 que no sea `systemd`, y PID 1 bajo `/system`.
> Comprueba las tres antes de seguir.

---

## 2. Preparar el repositorio

Dentro del chroot:

```bash
apt-get update && apt-get install -y git
cd /ruta/al/repo
```

O, si copiaste el repo desde el PC por USB, simplemente `cd` hasta él. **No hace
falta root para leer.**

---

## 3. Elegir qué componentes

Hay **12** componentes (`lib/components.sh:19-32`). Tres perfiles, definidos en
`lib/components.sh:34-36`:

| Perfil | Componentes |
|---|---|
| `minimal` | `core media` |
| `standard` (por defecto) | `core media downloads arr subs dashboard watchdogs` |
| `full` (`--all`) | todo |

| Id | Qué instala |
|---|---|
| `core` | estructura de datos, cron, redis, avahi, scripts de operación |
| `media` | Jellyfin y sus bibliotecas |
| `downloads` | qBittorrent, Prowlarr, Jackett |
| `arr` | Sonarr y Radarr |
| `subs` | Bazarr |
| `dashboard` | Homarr |
| `watchdogs` | vigilantes de pila y de resiliencia |
| `camera` | Motion + scripts de captura y subida |
| `remote` | Cloudflare Tunnel y Tailscale |
| `storage` | rclone a Google Drive y unión mergerfs |
| `reverse` | nginx como proxy inverso y TLS |
| `search` | FlareSolverr |

Para un Poco X3 Pro, **`standard` es el punto de partida sensato**. `--all`
 mete cámara, proxy, búsqueda y almacenamiento; no añado potencia al servidor,
 suma consumo de RAM y te deja con un stack que no has probado.

---

## 4. SIEMPRE primero: el plan

> **Esta guía no se salta este paso.** Si te lo saltas, estás instalando a
> ciegas.

```bash
./ezarr.sh --dry-run
```

`--dry-run` ejecuta **exactamente el mismo `plan()`** que la instalación real y
salta los `apply()` (`lib/plan.sh:10-13`). No es una simulación parecida: es el
mismo código con la mitad de las llamadas eliminadas. Además, toda escritura
pasa por un envoltorio `fs_*` que registra la operación y devuelve sin tocar
nada (`lib/plan.sh:264-292`).

**Lo que verás** (ejecutado aquí el 2026-10-05, en una máquina sin instalar):

```
-> entorno
entorno     maquina normal
arquitectura x86_64 (12 nucleos)
memoria     23932 MB
datos       / (91705 MB libres)
servicios   systemd
-> [1/9] resolucion de nombres
-> [2/9] verificar requisitos
-> [3/9] estructura de directorios
   dry-run: + 7 directorios en /data/ezarr
-> [4/9] escribir configuracion
   a crear: ezarr.conf apps.conf healthchecks.conf
-> [5/9] paquetes base
   dry-run: paquetes a instalar: 0 de 10
-> [6/9] descargas verificadas
error: faltan los sha256 de 3 release(s): define EZARR_SHA256_<arr|subs|downloads|search> ...
```

### 4.1. El muro de los sha256

El `--dry-run` **falla con código 6** si faltan los checksums, y está bien que
faille (`lib/stack.sh:452-477`): una release sin checksum conocido **no se
instala**. Un `--dry-run` que saliese 0 aquí estaría mintiendo y no valdría como
puerta.

Esto es lo que pasó en la ejecución real de arriba: exit **6**, sin tocar nada.

Los sha256 van en `/etc/ezarr/ezarr.conf`. Todavía no existe, porque la
instalación es lo que lo crea. Dos formas de salir del paso:

**Opción A — escribir el fichero primero.**

```bash
mkdir -p /etc/ezarr
cp etc/ezarr/ezarr.conf.sample /etc/ezarr/ezarr.conf
chmod 600 /etc/ezarr/ezarr.conf
nano /etc/ezarr/ezarr.conf      # rellena EZARR_SHA256_arr, _subs, _downloads
```

**Opción B — variables de entorno para esta pasada.**

```bash
EZARR_SHA256_arr=<64-hex> \
EZARR_SHA256_subs=<64-hex> \
EZARR_SHA256_downloads=<64-hex> \
  ./ezarr.sh --dry-run
```

Verificado: con los tres definidos por entorno, el plan es válido y sale **0**:

```
OK plan correcto: 9 pasos, 9 operaciones previstas
EXIT=0
```

> **Aviso real, encontrado hoy: `-c` / `--config` no funciona.**
> `ezarr.sh:219-220` añade los ficheros extra a `EZARR_CONF_FILES`, pero
> `ezarr_config_load()` **reconstruye ese array desde cero** en
> `lib/config.sh:87-92` y se loses de vista. Comprobado: `./ezarr.sh --dry-run
> -c /tmp/t.conf` seguía fallando con exit 6 porque el fichero `-c` nunca se
> leyó. **Usa la opción A o la B**, no `-c`.

### 4.2. Los 9 pasos

Definidos en `ezarr.sh:248-256`. En orden:

| # | Paso | Qué hace |
|---|---|---|
| 1 | `resolucion de nombres` | Arregla `/etc/resolv.conf`. Va primero porque lo usan todos los demás |
| 2 | `verificar requisitos` | root, RAM, disco libre, `pgrep`/`sha256sum`/`curl`, salida a internet |
| 3 | `estructura de directorios` | Los 7 directorios bajo `$EZARR_DATA_ROOT/ezarr` |
| 4 | `escribir configuracion` | `ezarr.conf`, `apps.conf`, `healthchecks.conf` desde las plantillas |
| 5 | `paquetes base` | `cron redis-server avahi-daemon` y compañía, según componentes |
| 6 | `descargas verificadas` | Descarga releases, **verificando sha256 antes de instalar** |
| 7 | `scripts de operacion` | Copia `ezarrctl` y `arr-stack` a `$EZARR_BIN_DIR` |
| 8 | `activar servicios` | `arr-stack start` de lo que corresponda |
| 9 | `registrar estado` | Escribe `components.list` e `installed.json` |

Requisitos mínimos (`lib/config.sh:178-179`): **5120 MB** de RAM y **8192 MB**
libres en la raíz de datos. Con 6 GB de RAM el stack completo va justo; el
instalador avisa y recomienda el componente `watchdogs` (`lib/stack.sh:207-212`).

---

## 5. Instalar

```bash
sudo ./ezarr.sh
```

Sin flags de componentes, usa el perfil `standard`. Sin `--yes`, **pregunta**
antes de escribir nada. La pregunta se lee de `/dev/tty`, no de `stdin`
(`lib/log.sh:204`), así que `sudo ./ezarr.sh | tee log` sigue funcionando.

Respuestas válidas: `s`/`y`/`si`/`yes` = sí · `n`/`no` = no · `q` = abortar ·
intro = no · **cualquier otra cosa = aborta**, y Ctrl-C sale con **130**.

Para instalar sin preguntar (instaladores automáticos, containers):

```bash
sudo ./ezarr.sh --yes
```

### 5.1. El instalador NO arranca nada

Dice exactamente esto al terminar:

```
OK instalacion terminada en 0.8s
   NO se ha arrancado nada. El arranque lo decides tu:
     ezarrctl status   y luego   ezarrctl start
```

Es deliberado (`ezarr.sh:12-15`): instalar y arrancar son dos decisiones
distintas, y un instalador que te levanta 17 servicios a la vez te hides los
problemas.

### 5.2. Verificación real de una instalación

Ejecutado aquí, con las rutas del stack en `/tmp` para no tocar el sistema:

```bash
$ ./ezarr.sh --only core --yes
-> [7/9] scripts de operacion
OK scripts de operacion (0.8s -> 0.8s)
-> [8/9] activar servicios
aviso    cron no arranca: el binario no esta instalado (no es un fallo de arr-stack)
aviso    redis no arranca: el binario no esta instalado (no es un fallo de arr-stack)
  avahi ya estaba arriba
OK activar servicios (0.6s -> 0.8s)
-> [9/9] registrar estado
OK registrar estado (0.8s -> 0.8s)
OK instalacion terminada en 0.8s
   NO se ha arrancado nada. El arranque lo decides tu:
     ezarrctl status   y luego   ezarrctl start
OK completado: 9/9 pasos
EXIT=0
```

Y los ficheros que deja:

```
/tmp/ezinst/bin/arr-stack   ezarrctl   ezarr-stack-install
/tmp/ezinst/state/components.list   installed.json

$ cat /tmp/ezinst/state/components.list
core
```

`components.list` es el contrato con `arr-stack`: sin ese fichero, `arr-stack`
avisa y **no arranca nada** (`arr-stack:19-22`). Es lo que hace que arrancar
servicios que nadie instaló sea imposible por diseño.

### 5.3. Fallo real que puedes encontrar: `arr-stack no esta instalado`

```
error: arr-stack no esta instalado; no se pueden activar servicios
  -> el paso 'scripts de operacion' lo deja en /usr/local/bin/arr-stack
```

Ocurre cuando cambias `EZARR_BIN_DIR`. El paso 7 instala en `$EZARR_BIN_DIR`,
pero el paso 8 busca en `$EZARR_STACK_BIN` (`lib/stack.sh:566`), que **tiene su
propio valor por defecto** (`/usr/local/bin/arr-stack`) y no sigue a
`EZARR_BIN_DIR`. Los dos tienen que ir juntos:

```bash
export EZARR_BIN_DIR=/data/ezarr/bin
export EZARR_STACK_BIN=$EZARR_BIN_DIR/arr-stack
sudo ./ezarr.sh --only core --yes
```

Es **el** defecto del instalador que encontré ejecutándolo, no una mala
configuración tuya. Si lo saltas sin `--yes`, el instalador **no deshace** lo ya
hecho y te lo dice:

```
warning: interrumpido en el paso 8/9: 7 pasos aplicados, 17 escrituras hechas
  -> lo aplicado hasta ahi se queda; no se ha deshecho nada
  -> para reintentar sin romper lo hecho: vuelve a ejecutar el instalador
```

Volver a ejecutar es seguro: el test de idempotencia del smoke test instala dos
veces y compara que la segunda no cambia nada.

---

## 6. Arrancar

```bash
ezarrctl status     # qué está vivo
ezarrctl start      # ahora sí
```

`ezarrctl` decide el gestor de servicios él solo (`ezarrctl:162`): en un chroot
usa `arr-stack`, en una máquina con systemd usa `systemctl`. Nunca hace
`systemctl` a ciegas.

Real, contra la instalación del apartado 5.2:

```bash
$ ezarrctl status
-> estado del stack ezarr 1.0.0
entorno     maquina normal
arquitectura x86_64 (12 nucleos)
memoria     23932 MB
datos       /tmp/ezinst/data (11927 MB libres)
servicios   systemd

   instalado: 2026-10-05T11:29:54Z · 1 componente(s)
  SERVICIO       ESTADO   PID     QUE ES
  -------------- -------- ------- ---------------------------------
  cron           ?        -       servicio de programacion (tareas de mantenimiento)
  redis          ?        -       cache para Homarr y los *arr
  avahi          ok       659     resolucion mDNS: http://ezarr.local

OK 1 servicios ok
EXIT=0
```

Los `?` son servicios sin puerto que comprobar: `cron` y `redis` están bien,
simplemente no hay nada que mirar (`lib/stack.sh:74-79`).

`start` **espera de verdad** a que el proceso levante y el puerto responda, y
vence por defecto a los 60 s (`ezarrctl:305-307`). Si no levanta, no te dice
"fallo" a secas: te **vuelca las últimas 20 líneas del log** y te dice el
comando exacto para mirar más (`ezarrctl:372-386`).

---

## 7. Rellenar la configuración

El instalador deja **plantillas con placeholders**, nunca tus valores
(`etc/ezarr/*.conf.sample`). Las IPs de ejemplo son `192.168.1.10` **a
propósito**.

```bash
$EDITOR /etc/ezarr/ezarr.conf
```

| Qué | Dónde |
|---|---|
| Topic de ntfy (avisos push) | `EZARR_NTFY_TOPIC` — **usa uno largo y aleatorio**: quien lo adivine puede publicar en él |
| IP de la cámara | `EZARR_CAMERA_IP`, `EZARR_CAMERA_RTSP` |
| Dead-man switch | `EZARR_HC_PING_URL` (URL de Healthchecks **sin** la parte `/fail`). Vacío = apagado |
| Checksums de releases | `EZARR_SHA256_arr`, `_subs`, `_downloads`, `_search` |
| Claves de las apps | `/etc/ezarr/apps.conf` |
| Zona horaria | `EZARR_TIMEZONE` |

El parser de configuración **no ejecuta** el fichero: lee línea a línea y solo
acepta `NOMBRE=valor` con nombre en `[A-Z0-9_]`; cualquier otra cosa se ignora,
y los valores con `$(...)` o backticks se rechazan (`lib/config.sh:44-75`). Es
la diferencia entre configurar y abrir una puerta.

Precedencia, de menor a mayor (`lib/config.sh:16-20`):

```
valor por defecto  <  /etc/ezarr/ezarr.conf  <  ~/.config/ezarr/ezarr.conf
                   <  entorno EZARR_*  <  flags
```

---

### 7.1. Los secretos, sin abrir un editor

Todo lo que es credencial vive en **un solo fichero**, `/etc/ezarr/secrets.conf`,
en modo 600 y nunca versionado. Y hay un comando para ponerlo:

```bash
ezarrctl secrets init        # crea el fichero desde la plantilla
ezarrctl secrets list        # qué falta y qué está puesto (nunca el valor)
ezarrctl secrets set CLAVE   # te lo pide sin eco y lo escribe en 600
ezarrctl secrets doctor      # permisos, obligatorias y valores de ejemplo sin cambiar
```

| Clave | ¿Obligatoria? | De dónde sale | Qué pasa si no la pones |
|---|---|---|---|
| `EZARR_CAMERA_RTSP_PASS` | sí | La del aparato, en la pegatina o en su app | La cámara no responde y no hay aviso de por qué |
| `EZARR_NTFY_TOPIC` | sí | El que crees en ntfy.sh: largo y aleatorio | **No te llega nada.** El watchdog cura bien y no te cuenta nada: es el fallo que más cuesta diagnosticar |
| `EZARR_HC_PING_URL` | no | Healthchecks.io → New Check → ping, sin `/fail` | Si el watchdog se muere, nadie se entera |
| `RCLONE_REMOTE` | no | El nombre del remoto que creaste con `rclone config` | No hay copia a Drive ni offload |
| `EZARR_CF_TUNNEL_TOKEN` | no | Cloudflare Zero Trust → Tunnels → token | Sin túnel; el acceso es solo por Tailscale o LAN |
| `EZARR_SUBS_API_KEY` | no | OpenSubtitles.com o SubDL | Bazarr va al límite gratis del proveedor (unas 20 al día) |
| `EZARR_TAILSCALE_AUTHKEY` | no | Tailscale → Settings → Keys | El teléfono se une al tailnet escribiendo la URL de login |

Dos detalles que hacen que esto sea seguro por construcción, y no por costumbre:

- **Ningún comando imprime un valor.** Ni `list`, ni `doctor`, ni un error. Solo
  el nombre de la clave y si está puesta. Hay un test que lo comprueba.
- **`doctor` distingue "puesta" de "puesta de verdad".** Si copias la plantilla
  y dejas `topic-de-prueba-123`, eso es un valor de ejemplo y el doctor lo trata
  como si faltara: es el error que más se cuela y el que menos se ve.

`doctor` del stack entero incluye esta comprobación al final, precisamente por
eso: todo lo demás puede estar en verde y aun así no llegarte ni un aviso.

---


## 8. Comprobar

```bash
ezarrctl doctor
```

Ocho comprobaciones, **independientes**: nunca se para en la primera, porque un
fallo escondiendo los demás no sirve de nada (`ezarrctl:608-620`).

Salida real de una máquina sin instalar:

```
-> doctor ezarr 1.0.0
  problema  descubrimiento no encuentro arr-stack en /usr/local/bin/arr-stack
  aviso     privilegios    sin root: algunas comprobaciones son parciales
  ok        espacio        91719 MB libres en /data
  problema  configuracion  faltan: /etc/ezarr/ezarr.conf /etc/ezarr/apps.conf
  problema  servicios      no hay componentes instalados: falta /var/lib/ezarr/components.list
  ok        puertos        sin conflictos en los puertos del stack
  aviso     healthchecks   sin URL: el dead-man switch esta apagado
  problema  logs           /var/log/arr no existe: los servicios no podran escribir

error: 4 problema(s), 2 aviso(s)
   siguiente: ezarrctl doctor --fix   (solo correcciones seguras y reversibles)
```

`doctor --fix` solo hace correcciones **seguras, reversibles y las anuncia
antes**: crea el directorio de logs, corrige permisos, crea la configuración que
falte desde las plantillas. Hay una cosa que **deliberadamente no hace**: matar
el proceso que ocupa un puerto. Puede ser tuyo y esa decisión es tuya
(`ezarrctl:644-648`).

---

## 9. Comprobar desde el navegador

Con `avahi` vivo, el panel se llama `http://ezarr.local` (verificado en la
tabla de servicios de `lib/stack.sh:16`).

| Servicio | Puerto | Interfaz |
|---|---|---|
| Jellyfin | 8096 | <http://IP:8096> |
| qBittorrent | 8081 | <http://IP:8081> |
| Sonarr | 8989 | <http://IP:8989> |
| Radarr | 7878 | <http://IP:7878> |
| Prowlarr | 9696 | <http://IP:9696> |
| Jackett | 9117 | <http://IP:9117> |
| Bazarr | 6767 | <http://IP:6767> |
| Homarr | 7575 | <http://IP:7575> |
| Motion (cámara) | 8554 | <http://IP:8554> |
| FlareSolverr | 8191 | <http://IP:8191> |
| nginx | 80, 443 | `http://ezarr.local` |

**Y ya está sirviendo.** A partir de aquí el manejo diario está en
**[`operacion.md`](operacion.md)**.

---

## Índice de todos los comandos de instalación

```bash
# --- en TWRP, en el shell del teléfono ---------------------------------------
                                   # Wipe → Format Data, desde la interfaz

# --- dentro del chroot -------------------------------------------------------
cd /ruta/al/repo

./ezarr.sh --dry-run                # SIEMPRE primero. Exit 6 si faltan sha256
./ezarr.sh --dry-run -v             # añade la línea de entorno detectado

sudo mkdir -p /etc/ezarr             # si vas por la opción A de los sha256
sudo cp etc/ezarr/ezarr.conf.sample /etc/ezarr/ezarr.conf
sudo chmod 600 /etc/ezarr/ezarr.conf
sudo nano /etc/ezarr/ezarr.conf     # EZARR_SHA256_arr / _subs / _downloads

sudo ./ezarr.sh                      # instala, preguntando
sudo ./ezarr.sh --yes                # instala sin preguntar
sudo ./ezarr.sh --only core --yes    # solo el núcleo
sudo ./ezarr.sh --all --yes          # perfil full
sudo ./ezarr.sh --with camera --yes  # añade uno al perfil
sudo ./ezarr.sh --without camera --yes  # quita uno del perfil

ezarrctl status                      # qué está vivo (solo lectura)
ezarrctl start                       # arrancar
ezarrctl doctor                      # diagnosticar
ezarrctl doctor --fix                # correcciones seguras

# --- flags de ezarr.sh, tal cual los acepta el parseador (ezarr.sh:160-200) --
#   --with <id,...>        opt-in
#   --without <id,...>     opt-out
#   --only <id,...>        parte de cero
#   --profile minimal|standard|full        (por defecto standard)
#   --all                                  atajo de --profile=full
#   --yes / --dry-run / --offline / --no-progress
#   -c, --config <ruta>                    ⚠ NO FUNCIONA, ver 4.1
#   --data-root <ruta>                     (por defecto /data)
#   --release-base <url>
#   --set NOMBRE=VALOR                     repetible
#   -q -v -vv -D   --color auto|always|never   --json   -h   --version
```

---

Continúa con **[`operacion.md`](operacion.md)** — el día a día: subcomandos,
vigilantes, logs, respaldos y qué hacer cuando algo falla.
