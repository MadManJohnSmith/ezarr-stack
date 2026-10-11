# Operación: el día a día

Todo lo que se teclea una vez instalado. La instalación está en
[`instalacion.md`](instalacion.md).

---

## El comando que se usa todos los días

```bash
ezarrctl
```

Y ya está. Ese es el diseño: **un solo comando, con subcomandos**, porque cada
utilidad nueva es un sitio más donde equivocarse.

Nueve cosas que hace, y una que **no** hace:

| Subcomando | Qué hace | ¿Muta el sistema? |
|---|---|---|
| `status` | Qué está vivo, qué está parado y por qué | **No**, solo lectura |
| `start [servicio...]` | Arrancar uno, varios o todo | Sí |
| `stop [servicio...]` | Parar uno, varios o todo | Sí |
| `restart [servicio...]` | `stop` + `start`, **en orden de dependencias y nunca en paralelo** | Sí |
| `logs` | Registros del stack, con prefijo por línea | No |
| `backup` | Copia de configuración, estado y BBDD, con manifiesto sha256 | Escribe (en el destino del backup) |
| `update` | **Backup antes → actualiza → `doctor` al final** | Sí |
| `doctor` | Diagnóstico: comprobaciones nombradas e independientes | No |
| `exit-codes` | Imprime la tabla de códigos de salida y sale con 0 | No |
| `version` | Versión, sistema y arquitectura | No |

### Y lo que `ezarrctl` no hace nunca

**Nunca hace `systemctl` a ciegas.** Detecta el entorno y decide
(`ezarrctl:162`, `svc_manager`):

- Chroot de teléfono → usa `arr-stack` (arranque directo + `pgrep`)
- Máquina con systemd → usa `systemctl`
- Lo dice antes de hacerlo

En el chroot de TWRP **no hay systemd**. Todo lo gobierna `arr-stack` + `cron`:
un `case` por servicio que lanza el proceso y un `pgrep` que decide si está
vivo (`lib/stack.sh:4-7`).

---

## Los 5 comandos del 90 %

```bash
ezarrctl status      # ¿qué está vivo?
ezarrctl start       # arrancar
ezarrctl logs -f     # mirar en vivo
ezarrctl backup      # respaldar
ezarrctl doctor      # ¿qué está roto?
```

---

## `status`

```bash
ezarrctl status
ezarrctl status --json          # JSON por stdout, para scripts
ezarrctl status --component arr # solo los del componente arr
```

Salida real, ejecutada el 2026-10-05:

```
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

Estados posibles (`lib/stack.sh:68-81`):

| Estado | Qué significa |
|---|---|
| `ok` | El proceso está vivo **y** su puerto responde |
| `dead` | No hay proceso |
| `port-closed` | El proceso corre pero el puerto no responde — **el caso peligroso** |
| `?` | Sin puerto real que comprobar (`cron`, `redis`, `avahi`) |

> `port-closed` es el estado que más engaña. Por eso `ezarrctl_service_state`
> **comprueba el puerto de verdad**, no solo que el proceso exista. Decir
> "sano" porque el proceso está ahí hace que un túnel caído pase por bueno.

`--json` va **después** del subcomando (`ezarrctl status --json`). Con el flag
delante (`ezarrctl --json status`) el parser se lo come como comando y sale
con **código 2**. Probado.

---

## `start`, `stop`, `restart`

```bash
ezarrctl start                      # todo
ezarrctl start sonarr radarr        # solo esos dos
ezarrctl stop                       # todo
ezarrctl restart jellyfin           # uno, en orden de dependencias
ezarrctl start --timeout 2m         # espera hasta 2 minutos
ezarrctl start --component media    # solo los del componente
```

| Subcomando | Espera por defecto |
|---|---|
| `start` | 60 s |
| `restart` | 60 s |
| `stop` | 30 s |

**`start` espera de verdad.** No devuelve en cuanto lanza el proceso: va
comprobando el estado cada 2 segundos hasta que la respuesta sea `ok`, y va
avisando cada 10 s (`ezarrctl:355-366`):

```
sonarr aun levantando... 30s/60s
```

Si no levanta dentro del plazo, **no dice "fallo" a secas**: vuelca las últimas
20 líneas del log en línea y te da el comando para mirar más
(`ezarrctl:372-386`):

```
error: sonarr no levanto en 60s
  --- ultimas 20 lineas ---
  (/var/log/arr/sonarr.log)
  | [Info] Application started
  | [Warn] Couldn't find folder: /data/media/tv
  | [Fatal] ...
  -> mira el log: ezarrctl logs --component sonarr
```

Busca el log en `$EZARR_LOG_DIR/<servicio>.log`, luego en `.log.1`, luego en
`/var/log/<servicio>/<servicio>.log`. Si no hay ninguno, te lo dice y te
recomienda `journalctl` por si hay systemd.

---

## `logs`

```bash
ezarrctl logs                    # últimos 100 de todo
ezarrctl logs --tail 500
ezarrctl logs --since 2h
ezarrctl logs --component arr    # solo Sonarr/Radarr
ezarrctl logs --level error
ezarrctl logs --follow           # Ctrl-C para salir
```

Con más de un fichero, cada línea va **prefijada con el servicio**:

```
sonarr | [Warn] Auto-update disabled
radarr | [Info] Application started
qbittorrent | [Error] Couldn't bind
```

Sin prefijo no hay forma de saber de quién es la línea cuando seis servicios
escriben a la vez (`ezarrctl:427-430`).

`-f` desactiva el color automáticamente: el color en un fichero que se mueve a
ojo molesta (`ezarrctl:391`).

Si no hay logs, no se calla:

```
error: no hay logs que mostrar
  -> directorio esperado: /var/log/arr/  (define EZARR_LOG_DIR en /etc/ezarr/ezarr.conf)
```

Exit **3**.

---

## `backup`

```bash
ezarrctl backup
ezarrctl backup --verify          # comprueba el manifiesto justo después
ezarrctl backup --keep 10         # conserva 10, por defecto 10
ezarrctl backup --include data    # mete también los medios
ezarrctl backup --output /sdcard/backup-copiado
```

**Qué copia** (`ezarrctl:444-475`):

| Ruta | Qué es |
|---|---|
| `/etc/ezarr/` | Configuración, apps y healthchecks |
| `/var/lib/ezarr/` | `components.list` e `installed.json` |
| `$EZARR_BIN_DIR/arr-stack` | El gestor de servicios |
| `$EZARR_DATA_ROOT/ezarr/config` | Configuración de las apps |
| `$EZARR_DATA_ROOT/ezarr/db/*.sqlite` | Bases de datos |
| `$EZARR_DATA_ROOT/ezarr/media` | **Solo** con `--include data` |

**Te lo dice antes de copiar**, con el número de rutas y de bases de datos, y
avisa explícitamente si los medios no entran:

```
incluye: 4 ruta(s), 3 base(s) de datos
los medios NO se incluyen (usa --include data; pueden ser cientos de GB)
```

**Los medios nunca entran por defecto.** Son cientos de GB y no caben en un
teléfono. Una copia que se lleva tu catálogo entero de vídeo sin preguntar es
justo el tipo de cosa que te llena el disco a las tres de la mañana.

Después genera un `manifest.json` con el sha256 de cada fichero. Sin eso, un
restore no puede saber si lo que hay dentro está corrupto:

```bash
cd $destino && sha256sum -c manifest.json
```

`--verify` lo hace por ti y falla con exit **1** si algo no cuadra.

### La poda nunca se lleva el último respaldo bueno

`--keep N` **enumera lo que va a borrar antes de borrar** y **siempre conserva
el más reciente**, incluso si `-keep` dice 0 (`ezarrctl:516-545`). Un prune que
se lleva el último bueno no es un prune: es una pérdida de datos con pasos de
cortesía.

---

## `update`

```bash
ezarrctl update --check        # solo comprobar, no escribir nada
ezarrctl update --channel stable
ezarrctl update --no-backup    # no recomendado
ezarrctl update --yes
```

El ciclo se cierra, y esto es lo que lo separa de un juguete
(`ezarrctl:554-599`):

1. **Comprueba** versiones (usa `/usr/local/bin/update-ezarr` si existe; si no,
   lo avisa y cae a `apt-get update && apt-get upgrade`).
2. **Backup previo.** Si el backup falla, **no actualiza a ciegas**:
   `el backup previo fallo: no se actualiza a ciegas`.
3. **Aplica** la actualización.
4. **`doctor` al final.** Si encuentra problemas, avisa MUY fuerte y te dice
   dónde está el respaldo para volver atrás.

El ciclo **no** se cierra con un "OK" de la actualización: se cierra con la
comprobación posterior. Si `doctor` falla, la actualización se considera fallida
aunque `apt` haya salido con 0.

---

## `doctor`

```bash
ezarrctl doctor
ezarrctl doctor --fix
```

Ocho comprobaciones, cada una **independiente**: nunca para en la primera, porque
un fallo escondiendo todos los demás no arregla nada.

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

| Comprobación | Qué mira | Exit |
|---|---|---|
| `descubrimiento` | Que exista `arr-stack` en `$EZARR_STACK_BIN` | 1 si falta |
| `privilegios` | Si es root (sin root, todo es parcial) | aviso |
| `espacio` | < 1024 MB libres en la raíz de datos | 1 si es crítico |
| `configuracion` | Que existan `ezarr.conf` y `apps.conf` | 1 si faltan |
| `servicios` | Que haya `components.list` y que los servicios estén vivos | 1 |
| `puertos` | Conflictos con lo que ya está escuchando | 1 |
| `healthchecks` | Si el dead-man switch tiene URL | aviso |
| `logs` | Que exista y sea escribible `$EZARR_LOG_DIR` | 1 |

Códigos de salida: **0** todo correcto · **1** hay problemas · **2** todo
correcto con avisos.

### `doctor --fix`

Solo hace correcciones **seguras, reversibles, y las anuncia antes**:

1. Crear `$EZARR_LOG_DIR` si falta; darle permisos 0755
2. Crear `/etc/ezarr/ezarr.conf` y `apps.conf` desde las plantillas, con modo
   **0600** (sin secretos: se rellenan después)
3. **NO** toca los procesos

> **Hay una cosa que `--fix` deliberadamente NO hace: matar el proceso que
> ocupa un puerto.** Puede ser otro servicio tuyo, y esa decisión es tuya
> (`ezarrctl:644-648`). En vez de ejecutarla, la dice:
>
> ```
> warning: jellyfin corre pero su puerto no responde: NO lo mato
>   -> puede ser otro proceso: ss -tlnp | grep 8096
> ```

---

## Los vigilantes (`watchdogs`)

### Lo que este repo hace hoy, exactamente

**Sea claro, porque el catálogo promete más de lo que el código entrega.**

El componente `watchdogs` está en el catálogo (`lib/components.sh:29`) y en los
perfiles `standard` y `full` (`lib/components.sh:36-37`). Su descripción es
*"Watchdogs de pila y de resiliencia, con cron y montajes"*.

Ejecuté una instalación real de `--only core` y repasé el código. Lo que el
componente **hace** es exactamente una cosa (`lib/stack.sh:424`):

```bash
_ezarr_in_set watchdogs && pkgs="$pkgs cron curl sqlite3"
```

**Instala tres paquetes.** Nada más.

**No hay ningún script de watchdog en el repositorio.** Lo comprobé buscando
en todo el árbol:

```bash
$ grep -rn "watchdog" --include="*.sh" --include="ezarr*" --include="arr-stack" . | grep -v bak
./lib/components.sh:29:  "watchdogs|vigilantes|standard|Watchdogs de pila..."
./lib/components.sh:36: EZARR_PROFILE_BASE_STANDARD="... watchdogs"
./lib/components.sh:37: EZARR_PROFILE_BASE_FULL="... watchdogs ..."
./lib/stack.sh:210:     log_warn "el stack completo incluira 'watchdogs' ..."
./lib/stack.sh:424:     _ezarr_in_set watchdogs && pkgs="$pkgs cron curl sqlite3"
./etc/ezarr/ezarr.conf.sample:34:# URL de ping de Healthchecks.io...
./ezarrctl:409:         [ "${#files[@]}" -eq 0 ] && files=("${EZARR_LOG_DIR}/watchdog.log" ...)
```

Los únicos sitios donde aparece `watchdog.log` son `ezarrctl:409`, que lo
**busca** como fichero de log, y el comentario de la plantilla de configuración.
Y `apply_scripts` (`lib/stack.sh:646-655`) solo instala tres binarios:

```bash
fs_install "$here/arr-stack" "$EZARR_BIN_DIR/arr-stack"
fs_install "$here/ezarrctl" "$EZARR_BIN_DIR/ezarrctl"
fs_install "$here/ezarr.sh"  "$EZARR_BIN_DIR/ezarr-stack-install"
```

**No escribe ni una entrada de cron.** `cron` está instalado porque lo usan los
*arr* y `core`, no porque haya un watchdog.

> **Consecuencia práctica.** Con el perfil `standard` tienes `cron` instalado
> pero **ningún vigilante corriendo**. Si el OOM killer se come Jellyfin a las
> tres de la mañana, nadie lo levanta. `lib/stack.sh:210` le promete al usuario
> que el componente `watchdogs` evitará eso, y hoy no lo evita. **Móntalo tú a
> mano** (sección siguiente), o acepta de entrada que todavía no lo hay.

### Montar el tuyo: dos piezas

**Pieza 1 — dead-man switch (aviso de que el vigilante murió).**
Un checker externo es el único que puede avisar de que tu watchdog dejó de dar
la señal. Configúralo en `healthchecks.io`:

- URL de ping, **sin** la parte `/fail`
- Margen de fallo: si el watchdog no da señal en X minutos, Healthchecks.io te
  avisa

```bash
nano /etc/ezarr/healthchecks.conf
# EZARR_HC_PING_URL=https://hc-ping.com/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Vacío = apagado. `doctor` avisa: `sin URL: el dead-man switch esta apagado`.

- <https://healthchecks.io/>
- <https://ntfy.sh/> y <https://docs.ntfy.sh/> — para los avisos push

```bash
curl -m 10 -fsS "$EZARR_HC_PING_URL" >/dev/null   # en la tarea de cron
```

**Pieza 2 — el vigilante de verdad.** Un script tuyo en `cron` que:

```bash
#!/bin/sh
# algo-que-tuede-caerse.sh — dead-man switch primero
curl -m 10 -fsS "$EZARR_HC_PING_URL" >/dev/null || exit 1
ezarrctl status --json > /tmp/st.json
# si algún servicio está dead: reiniciar y avisar
```

```cron
*/10 * * * * /usr/local/bin/vigilante-ezarr.sh >> /var/log/arr/vigilante.log 2>&1
```

Y ponle su log en `${EZARR_LOG_DIR}/vigilante.log` para que `ezarrctl logs` lo
vea.

**Avisos al móvil**: `EZARR_NTFY_SERVER` y `EZARR_NTFY_TOPIC` en
`/etc/ezarr/ezarr.conf`. El topic es **la parte secreta**: cualquiera que lo
adivine puede publicar en él (y suscribirse). Largo y aleatorio.

---

## Cuándo algo falla

### Antes de nada: mira los logs

```bash
ezarrctl logs --component arr --tail 200
ezarrctl logs --follow
```

### Guía de decisiones

| Síntoma | Qué hacer |
|---|---|
| Un servicio no levanta | `ezarrctl logs --component <id>` — `start` ya te habrá dado las últimas 20 líneas |
| `no instalado` (exit **3**) | Falta `/var/lib/ezarr/components.list`. Instala: `sudo ./ezarr.sh` |
| `arr-stack no esta instalado` | `EZARR_BIN_DIR` y `EZARR_STACK_BIN` tienen que apuntar al mismo sitio (ver `instalacion.md` 5.3) |
| `doctor` dice `configuracion` falta | `ezarrctl doctor --fix` |
| `doctor` dice `logs` no existe | `ezarrctl doctor --fix` |
| `port-closed` en `status` | El proceso corre pero no escucha. `ss -tlnp \| grep PUERTO` |
| Dos cosas en el mismo puerto | `ss -tlnp`. `--fix` **no** mata procesos: es decisión tuya |
| Faltan los sha256 (exit **6**) | `EZARR_SHA256_*` en `/etc/ezarr/ezarr.conf`. El `--dry-run` también falla así, a propósito |
| Sin red (exit **5**) | `lib/env.sh` guarda el motivo (DNS, TCP o HTTP). `cat /etc/resolv.conf` |
| Sin root (exit **7**) | `sudo` |
| Interrumpido, exit **130** | Ctrl-C |
| Apagado el teléfono entero sin avisar | Falta de RAM o sobrecalentamiento. Los *arr* + Jellyfin en 6 GB van al límite |

### Los códigos de salida

```
  0    correcto
  1    error generico, o `doctor` encontro problemas
  2    uso incorrecto (flag o argumento invalido)
  3    no instalado, o el estado es incompatible con la operacion
  4    conflicto de componentes o requisito no satisfecha
  5    fallo de red o descarga
  6    verificacion de integridad fallida (checksum o firma)
  7    permisos insuficientes (no root)
  130  interrumpido por el usuario (Ctrl-C)
```

Definidos en `lib/log.sh:244-252`. `ezarrctl exit-codes` los imprime.

> **Un error sin siguiente paso es un bug de la herramienta.** Si ves uno,
> mira si el mensaje te dice qué hacer. Si no, eso hay que arreglarlo.

---

## Notas de operación real

### Arrancar el teléfono en TWRP, no en Android

Android es un sistema operativo de consumo. Para este uso:

1. Con el teléfono apagado: **Power + Vol down**.
2. Una vez en TWRP, `ezarrctl status` y, si hace falta, `ezarrctl start`.

### Los montajes FUSE no los gestiona `arr-stack`

`rclone` (Drive) y `mergerfs` (unión de biblioteca local y Drive) son **montajes
FUSE, no procesos**. `arr-stack` los **reconoce y los dice en voz alta** en vez
de fingir que arrancaron (`arr-stack:73-77`, `arr-stack:201-215`):

```
$ arr-stack list
SERVICIO      COMPONENTE  ESTADO    GESTIONADO
cron          core        stopped   si
redis         core        stopped   si
avahi         core        running   si
...
rclone        storage     montaje   no (FUSE)
mergerfs      storage     montaje   no (FUSE)
  arr-stack 1.0.0
  los montajes FUSE no los gestiona este script: se montan a mano o con tu propio unit
```

Si usas el componente `storage`, esos dos los montas tú (o con una unidad
propia). `ezarrctl status` tampoco los da por buenos.

### Los servicios y sus puertos

De `lib/stack.sh:13-31`:

| Servicio | Componente | Puerto |
|---|---|---|
| `cron` | core | — |
| `redis` | core | — |
| `avahi` | core | — (mDNS: `http://ezarr.local`) |
| `jellyfin` | media | 8096 |
| `qbittorrent` | downloads | 8081 |
| `prowlarr` | downloads | 9696 |
| `jackett` | downloads | 9117 |
| `sonarr` | arr | 8989 |
| `radarr` | arr | 7878 |
| `bazarr` | subs | 6767 |
| `homarr` | dashboard | 7575 |
| `motion` | camera | 8554 |
| `cloudflared` | remote | 7844 |
| `tailscale` | remote | 41641 |
| `nginx` | reverse | 80, 443 |
| `flaresolverr` | search | 8191 |
| `rclone` | storage | — (FUSE) |
| `mergerfs` | storage | — (FUSE) |

**Patrón importante:** `pgrep -f` usa la ruta completa (`/opt/Sonarr/Sonarr`,
no `sonarr`), porque `sonarr` como nombre de proceso también lo lleva un `grep`
nuestro y el chequeo mentiría (`lib/stack.sh:9-11`).

### Acceso desde fuera

Sin abrir un solo puerto:

- **Cloudflare Tunnel** — `cloudflared tunnel`, HTTPS de salida (7844)
  — <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/>
- **Tailscale** — VPN mesh (41641) — <https://tailscale.com/kb/>

### Backups automáticos

`ezarrctl backup` es manual a propósito. Si quieres que sea diario:

```cron
30 4 * * * /usr/local/bin/ezarrctl backup --keep 7 --yes >> /var/log/arr/backup.log 2>&1
```

Y **verifica que el respaldo existe y no está vacío** alguna vez:

```bash
ls -la /var/backups/ezarr/
cd /var/backups/ezarr/<mas-reciente> && sha256sum -c manifest.json
```

Un backup que nunca has restaurado no es un backup.

---

## Enlaces de esta página

Verificados el **2026-10-05** con `curl -o /dev/null -w '%{http_code}'`:

| Enlace | Código |
|---|---|
| <https://healthchecks.io/> | 200 |
| <https://ntfy.sh/> | 200 |
| <https://docs.ntfy.sh/> | 200 |
| <https://tailscale.com/kb/> | 200 |
| <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/> | 200 |
| <https://jellyfin.org/downloads/linux/> | 200 |
| <https://www.qbittorrent.org/> | 200 |
| <https://prowlarr.com/> | 200 |
| <https://github.com/Jackett/Jackett> | 200 |
| <https://sonarr.tv/> | 200 |
| <https://radarr.video/> | 200 |
| <https://bazarr.media/> | 200 |
| <https://homarr.dev/> | 200 |
| <https://motion-project.github.io/> | 200 |
| <https://github.com/FlareSolverr/FlareSolverr> | 200 |
| <https://rclone.org/> | 200 |
| <https://github.com/trapexit/mergerfs> | 200 |
| <https://nginx.org/> | 200 |
| <https://trash-guides.info/> | 200 |
| <https://developer.android.com/tools/releases/platform-tools> | 200 |

Los créditos y la atribución están en **[`creditos.md`](creditos.md)**.
