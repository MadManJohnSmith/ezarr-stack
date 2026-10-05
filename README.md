# ezarr-stack-build

Instalador y control central para un stack de servidores multimedia en un
**chroot Ubuntu sobre un teléfono Android** (TWRP). La misma herramienta corre
en una máquina normal, para preparar imágenes.

> **Lo que esto no garantiza.** El `ezarr.sh` de este repositorio no se ha
> ejecutado contra un teléfono real. Lo que sí está probado son 57
> comprobaciones de contrato, sintaxis, códigos de salida e idempotencia
> (`bash tests/smoke.sh`). La configuración que hay detrás —el stack real— lleva
> meses funcionando en un Poco X3 Pro. La diferencia entre las dos cosas es
> real y conviene no mezclarla.

## Qué hay aquí

```
ezarr.sh            instalador de un solo comando, con --dry-run de verdad
ezarrctl            el control central: status start stop restart logs backup update doctor
lib/                log.sh  env.sh  config.sh  plan.sh  components.sh  stack.sh
etc/ezarr/          plantillas de configuración (con placeholders, sin secretos)
tests/smoke.sh      57 comprobaciones, sin dependencias externas
CHANGELOG.md        qué cambió y por qué
```

## Empezar

```bash
# 1. SIEMPRE primero: ver el plan sin tocar nada
./ezarr.sh --dry-run

# 2. Si el plan te cuadra, instalar
sudo ./ezarr.sh --yes
```

`ezarr.sh` **no arranca nada** al terminar. La instalación y el arranque son dos
decisiones distintas:

```bash
ezarrctl status     # qué está vivo
ezarrctl start      # ahora sí, arrancar
ezarrctl doctor     # si algo no va
```

## `ezarr.sh`

### Componentes

| id | Qué instala |
|---|---|
| `core` | estructura de datos, servicios básicos, scripts de operación |
| `media` | Jellyfin y sus bibliotecas |
| `downloads` | qBittorrent, Prowlarr, Jackett |
| `arr` | Sonarr y Radarr |
| `subs` | Bazarr |
| `dashboard` | Homarr |
| `camera` | Motion y los scripts de captura y subida |
| `remote` | Cloudflare Tunnel y Tailscale |
| `storage` | rclone a Google Drive y unión mergerfs |
| `watchdogs` | vigilantes de pila y de resiliencia, con cron y montajes |
| `reverse` | nginx como proxy inverso |
| `search` | FlareSolverr |

### Flags

```
SELECCIÓN
      --with <id,...>      opt-in:  añade componentes
      --without <id,...>   opt-out: quita componentes
      --only <id,...>      parte de cero: solo estos, ignorando perfil y config
      --profile <name>     minimal | standard | full   (por defecto: standard)
      --all                atajo de --profile=full

FLUJO
      --yes                no pedir confirmación (sin forma corta, a propósito)
  -n, --dry-run            imprimir el plan completo y no tocar nada
      --offline            resolver solo con caché
      --no-progress        sin contadores, conservando las líneas de paso

CONFIGURACIÓN
  -c, --config <ruta>      fichero de configuración adicional
      --data-root <ruta>   dónde viven los datos (por defecto: /data)
      --release-base <url> base de las releases descargadas
      --set <NOMBRE=VALOR> override de una variable, repetible

GLOBALES
  -q, --quiet / -v, --verbose / -D, --debug
      --color <when>       auto | always | never
      --json               salida en JSON por stdout
  -h, --help               ayuda
      --version            versión (sin forma corta: -v es --verbose)
```

### Cómo se resuelve el conjunto de componentes

Orden fijo, determinista y visible en el resumen:

```
1. base por defecto del perfil
2. /etc/ezarr/ezarr.conf  (COMPONENTS_EXTRA / COMPONENTS_SKIP)
3. ~/.config/ezarr/ezarr.conf
4. --with a,b          →  unión
5. --without x,y       →  resta
6. --only a,b          →  descarta 1-5 (sí se aplican versión y canal)
```

`--without` va **después** de `--with`, así que `--with web --without web` es
"off" y no hay caso especial. Una regla, un orden.

## `ezarrctl`

| Subcomando | Qué hace |
|---|---|
| `status` | qué está vivo y **por qué** no lo está. Salidas: 0 sano · 1 degradado · 3 no instalado |
| `start` / `stop` / `restart` | en orden de dependencias, nunca en paralelo |
| `logs` | `-f`, `--tail N`, `--since 1h`, `--component`. Multiplexa con prefijo por línea |
| `backup` | config + datos + volcado de BBDD + `manifest.json` sha256. `--keep N` enumera antes de borrar |
| `update` | `--check` no escribe nada. El update real copia antes y lanza `doctor` al final |
| `doctor` | comprobaciones nombradas e independientes. `--fix` solo corrige lo seguro |

### Códigos de salida

| | |
|---|---|
| `0` | correcto |
| `1` | error genérico, o `doctor` encontró problemas |
| `2` | uso incorrecto (flag o argumento inválido) |
| `3` | no instalado / estado incompatible |
| `4` | conflicto de componentes o requisito no satisfecha |
| `5` | fallo de red o descarga |
| `6` | verificación de integridad fallida (checksum o firma) |
| `7` | permisos insuficientes |
| `130` | interrumpido por el usuario |

`ezarrctl exit-codes` los imprime. Un error sin siguiente paso es un bug de la
herramienta: **todos los errores llevan remedio accionable**.

## Configuración

Nada de lo que depende de tu instalación está escrito en el código.

| Fichero | Qué |
|---|---|
| `/etc/ezarr/ezarr.conf` | rutas, IPs, ajustes no secretos |
| `/etc/ezarr/apps.conf` | claves de las apps — **se genera vacío y se pide** |
| `/etc/ezarr/healthchecks.conf` | token del dead-man switch |
| `/etc/ezarr/camera.conf` | URL RTSP de la cámara |

Precedencia: defecto < fichero del sistema < fichero del usuario < entorno
`EZARR_*` < flags.

Las plantillas están en `etc/ezarr/*.sample`. La IP de ejemplo es
`192.168.1.10`; **ninguna credencial real está en este repositorio**, y
`tests/smoke.sh` falla si aparece una.

### Por qué `apps.conf` se genera vacío

Automatizar el cableado entre servicios habría significado emitir credenciales
compartidas: todo el que instala el stack tendría las mismas. Es peor que
pedirle al usuario cinco claves. Por eso el instalador **pide** y **avisa**, en
vez de inventar un valor que luego nadie sabe rotar.

## El `--dry-run` en serio

No es una simulación parecida al instalador. Cada paso tiene dos funciones:

```
plan_<algo>()    puro: pregunta, mide, comprueba. No escribe nada.
apply_<algo>()   ejecuta. El único sitio donde se muta el sistema.
```

`--dry-run` ejecuta `plan_<algo>()` y **no alcanza** `apply_<algo>()`. Y como un
único punto de contacto puede fallar, hay una segunda capa: toda escritura pasa
por un envoltorio `fs_*` que en dry-run registra la operación y devuelve un
stub.

`tests/smoke.sh` verifica el contrato tomando el `sha256sum` recursivo del árbol
antes y después y exigiendo igualdad. Es el único test que verifica la promesa,
y es el que importa.

Además, **`--dry-run` sale con código distinto de 0 si el plan es inválido**, con
el mismo código que daría la instalación real. Por eso sirve como puerta en CI:

```bash
./ezarr.sh --dry-run || echo "el plan no es válido, ni siquiera en teoria"
```

## Pruebas

```bash
bash tests/smoke.sh
```

Sin red, sin dependencias. Comprueba sintaxis, permisos, ausencia de secretos,
códigos de salida, resolución de componentes, la promesa del dry-run, la
idempotencia del instalador y que la salida vaya por los canales correctos.

## Requisitos

- `bash` 4 o superior, `coreutils`, `curl`, `sed`, `awk`
- `apt-get` para los paquetes (opcional: el instalador funciona sin él y avisa)
- root, o `sudo`

## Licencia

Todavía no elegida. Este repositorio no trae `LICENSE`: la licencia es una
decisión del dueño del proyecto, no del instalador.