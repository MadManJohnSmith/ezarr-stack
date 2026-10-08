# ezarr-stack

**Un instalador y un plano de control para un stack *arr* en un teléfono Android
que ya no usas como teléfono.** Chroot Ubuntu sobre TWRP, sin Docker y sin
systemd. 12 componentes catalogados, 3 perfiles, 18 servicios en el catálogo —
de los cuales hoy el camino documentado deja el binario instalado en **9**.

![licencia](https://img.shields.io/badge/licencia-sin%20declarar-lightgrey)
![suite](https://img.shields.io/badge/suite-71%20ok%20%2F%2073-red)

> **Proyecto personal y experimental.** Sin empresa, sin soporte, sin promesas de
> nada. No hay licencia declarada, así que por defecto es copyright tuyo: no lo
> uses como dependencia.

### Estado real, sin adornos

No hay insignia que diga "instalador de un comando" porque no lo hay, ni insignia
de CI en gris porque este repositorio no tiene remoto donde corra nada. Los
cuatro datos que de verdad tienen que saber antes de seguir:

| Comprobación | Comando | Resultado ahora |
|---|---|---|
| Suite de contrato | `bash tests/smoke.sh` | **71 correctas, 2 con fallos**, sale con **1** |
| Perfil por defecto | `./ezarr.sh --dry-run` | **código 6**: faltan los sha256 de 3 releases |
| Perfil mínimo | `./ezarr.sh --dry-run --profile minimal` | **código 0**: instala core + media |
| Servidor de releases | `curl -sS -o /dev/null https://packages.example.com/` | **NXDOMAIN**: el dominio no existe |

Y el que más se salta todo el mundo, porque es el que convierte "servidor" en
"esto":

> **No hay autostart, y no es un olvido.** Tras un corte de luz el teléfono está
> apagado y **nadie lo relanza**. No hay `init.d`, ni `rc.local`, ni `@reboot`, ni
> enganche de TWRP en este árbol. Encender el servidor es una persona pulsando
> botones. Está en [quién arranca esto](#quién-arranca-esto-y-por-qué-es-la-cuarta-pregunta).

La insignia de arriba es estática como todas las de shields.io: **si la suite
estuviera en verde, seguiría poniendo rojo**. Léela como el estado en el momento
del último commit, no como una fuente de verdad.

---

## Lo primero: qué es y qué no es

**Es** un instalador (`ezarr.sh`), un plano de control (`ezarrctl`) y un gestor
de servicios (`arr-stack`) para montar un stack *arr* sobre un chroot Ubuntu que
vive en la partición `/data` de un Android con TWRP. El teléfono arranca en TWRP,
**Android no llega a ejecutarse**: sin notificaciones, sin sincronización, sin
Google. Ese es el silencio del que se habla aquí, y es un hecho operativo, no una
metáfora.

**No es** más rápido que Docker. No pretende serlo. No hay TypeScript, ni SQLite
transaccional, ni cgroups. Lo que compra es coste marginal **cero en dinero** —el
hardware ya estaba pagado y en un cajón— y silencio.

Y lo que cuesta, con nombre, porque un cajón no es gratis:

- **El teléfono como teléfono desaparece.** Desbloquear el bootloader formatea
  `/data`. El aparato sobrevive como hardware; como teléfono deja de existir.
- **Cada arranque cuesta una persona.** No hay autostart
  ([abajo](#quién-arranca-esto-y-por-qué-es-la-cuarta-pregunta)). Un servidor al
  que hay que ir a encender no es un servidor que esté ahí.
- **Cada arranque pasa por TWRP.** Eso es más lento, más frágil y más manual
  que encender un portátil y abrir una terminal.

**No** lo ha ejecutado nadie contra un teléfono físico. Lo que sí está probado es
la sintaxis, los contratos, los códigos de salida y la idempotencia
(`tests/smoke.sh`), y **la suite está en rojo: 2 de 73**.

Antes este README mencionaba que "el stack que hay detrás lleva meses
funcionando en un Poco X3 Pro". Lo he quitado: este repositorio no contiene ese
código, no lo puede comprobar nadie aquí y no sostiene ninguna de las frases de
arriba. Si algún día alguien monta esto en un teléfono, que lo escriba con su
fecha y su máquina.

**Y antes de nada, porque es lo primero que pasa:** desbloquear el bootloader de
un Xiaomi **formatea `/data`**. Se van fotos, contactos, WhatsApp, claves. No hay
vuelta atrás. Si no has hecho copia, cierra esta página. Está en
[`docs/recovery.md`](docs/recovery.md) con la cita literal de TeamWin, y también
en la primera línea de esta portada porque es la primera cosa que pasa.

---

## Instalación

El instalador **no arranca nada** al terminar. Instalar y arrancar son dos
decisiones distintas: el plan te lo enseña entero, tú lo confirmas, y luego decides.

```bash
# 1. SIEMPRE primero. Imprime el plan completo y no escribe nada.
./ezarr.sh --dry-run --profile minimal

# 2. Si el plan te cuadra, instalar.
sudo ./ezarr.sh --yes --profile minimal
```

**Por qué `--profile minimal` y no el perfil por defecto.** A fecha de hoy
(`2026-10-05`) el perfil por defecto es `standard`, y `standard` **falla**:

```
$ ./ezarr.sh --dry-run --profile standard
error: faltan los sha256 de 3 release(s): define EZARR_SHA256_<arr|subs|downloads|search> en /etc/ezarr/ezarr.conf
error: --dry-run: el plan NO es valido (codigo 6). No se ha tocado nada.
$ echo $?
6
```

No es un problema de permisos ni de red: el instalador se niega a descargar
`arr`, `subs` y `downloads` sin checksum, y hace bien. `minimal` (2 componentes:
`core` + `media`) pasa el plan con exit 0. `full` da el mismo exit 6 pero
pidiendo **4** sha256, porque además busca `search`.

> ⚠️ **No te engañes con esto: poner los sha256 no desbloquea nada.** El
> instalador está esperando una suma que necesita, pero los `.deb` se bajarían de
> `https://packages.example.com`, **un dominio que no existe**. La tabla de
> [qué se instala hoy](#qué-incluye-y-qué-se-instala-hoy) tiene el detalle.
> `--profile minimal` no es un rodeo temporal "hasta que te dé la gana": es, a
> día de hoy, **la única forma de instalar algo**.

**Y antes de que ejecutes el paso 2, un aviso que el repo no resuelve:** los
`.deb` de Jellyfin y compañía traen scripts `postinst` que llaman a `systemctl`,
que no existe dentro del chroot. `fs_apt()` (`lib/plan.sh:349-363`) lanza
`apt-get install -y` y no gestiona ese caso. Va detallado en
[los huecos que la suite no cubre](#los-2-fallos-son-míos-y-no-están-arreglados).

**No hay instalador remoto.** No hay `curl | bash`, ni release, ni contenedor: este
repositorio todavía no tiene remoto Git, así que la instalación es clonar y ejecutar.
Un instalador de un comando que se descarga de un sitio que todavía no existe
sería fiction — y por eso la insignia que lo prometía está quitada de arriba.

<details>
<summary>Y el chroot, que este repo <strong>no</strong> crea</summary>

`ezarr.sh` **detecta** si está dentro de un chroot (`lib/env.sh:28`,
`ezarr_detect_env`) y a partir de ahí trabaja, pero el chroot lo montas tú a mano
en el paso 1 de [`docs/instalacion.md`](docs/instalacion.md). No hay ningún
`debootstrap` en el repo ni ningún enlace al respecto, y no se va a añadir. Al
igual que la imagen del TWRP: la descargas tú y la montas.

</details>

---

## Qué incluye, y qué se instala hoy

12 componentes, agrupados por perfil. Los identificadores son en inglés
(`core`, `media`, `downloads`…); lo que ves en el resumen del instalador es la
etiqueta en español.

La columna **Estado hoy** está medida, no estimada: sale de ejecutar
`./ezarr.sh --dry-run --only <componente>` para cada uno de los doce y mirar lo
que hace. Es la diferencia entre lo que el catálogo *describe* y lo que el
instalador *hace*.

| Componente | Etiqueta | Perfil mínimo | Estado hoy | Qué instala de verdad |
|---|---|---|---|---|
| `core` | base | `minimal` | ✅ sale 0 | `apt`: cron, redis-server, avahi-daemon. Estructura de datos, `http://ezarr.local` |
| `media` | media | `minimal` | ✅ sale 0 | `apt`: jellyfin. **El único *arr* que arranca hoy por el camino documentado** |
| `downloads` | descargas | `standard` | ⛔ sale **6** | qBittorrent sí está en la lista `apt`, pero el componente entero se bloquea esperando el sha256 de la release |
| `arr` | servarr | `standard` | ⛔ sale **6** | Sonarr y Radarr solo existen como `.deb` en `packages.example.com`, que no resuelve |
| `subs` | subtítulos | `standard` | ⛔ sale **6** | Bazarr, mismo caso |
| `dashboard` | dashboard | `standard` | ⚠️ sale 0, **no instala nada** | El perfil pasa el plan, pero `homarr` no está en ninguna lista de paquetes ni de descargas |
| `watchdogs` | vigilantes | `standard` | ⚠️ sale 0, **arranca 0 servicios** | `cron`, `curl`, `sqlite3` y ya. **No hay ningún script de vigilancia en el árbol** |
| `camera` | cámara | `full` | ⚠️ sale 0, **no instala nada** | Igual que `dashboard`: `motion` no lo instala ningún paso de este instalador. Solo queda el `camera.conf` de ejemplo |
| `remote` | remoto | `full` | ✅ a medias | `apt`: tailscale. **`cloudflared` no lo instala nadie** |
| `storage` | almacenamiento | `full` | ✅ sale 0 | `apt`: rclone + mergerfs, contra Google Drive |
| `reverse` | proxy | `full` | ✅ sale 0 | `apt`: nginx como proxy inverso y terminación TLS |
| `search` | búsqueda | `full` | ⛔ sale **6** | FlareSolverr, mismo caso que `arr` y `subs` |

✅ se instala hoy · ⛔ el perfil se rechaza con código 6 · ⚠️ el perfil pasa el
`--dry-run` pero el binario no lo instala nada de este repo.

**Los cuatro ⛔ no son un bug esperando un parche.** Los cuatro necesitan bajar
`.deb` de `https://packages.example.com`, un dominio que hoy no resuelve:

```
$ getent hosts packages.example.com
$ curl -sS -o /dev/null https://packages.example.com/
curl: (6) Could not resolve host: packages.example.com
```

Mientras ese host no exista, **Sonarr, Radarr, Bazarr, Prowlarr, Jackett y
FlareSolverr no son instalables por el camino documentado.** Poner sus sha256 en
la configuración no lo arregla: solo movería el fallo del paso 6 a una descarga
que no va a llegar. Se arregla levantando ese servidor, y ese trabajo no está en
este repositorio.

**De los 18 servicios catalogados, 9 tienen hoy el binario instalado**
(cron, redis, avahi, jellyfin, qbittorrent, tailscale, nginx, rclone, mergerfs),
6 dependen del host inexistente y 3 —`homarr`, `motion`, `cloudflared`— no los
instala ningún paso de este instalador. La "18 servicios" que ponía el README
antes era el tamaño del catálogo, no servicios en marcha.

Los montajes FUSE (rclone, mergerfs) además **no son procesos**: `arr-stack` los
lista aparte y dice en voz alta que no los gestiona, en vez de fingir que
arrancaron.

### Tus credenciales, en un comando

Los secretos (topic de ntfy, contraseña de la cámara, URL de Healthchecks, remoto
de Drive, token del túnel, clave de subtítulos) van todos en
`/etc/ezarr/secrets.conf`, en 600 y fuera de git. No hace falta que edites nada
a mano:

```bash
ezarrctl secrets init      # crea el fichero desde la plantilla
ezarrctl secrets set EZARR_NTFY_TOPIC   # te lo pide sin que se vea
ezarrctl secrets list      # qué falta, sin mostrar ningún valor
ezarrctl secrets doctor    # permisos, obligatorias y valores de ejemplo
```

El comando nunca imprime un valor, ni cuando algo falla. Detalle completo en
[docs/instalacion.md §7.1](docs/instalacion.md).

### `ezarrctl`: el día después

```
status              qué está vivo, qué está parado y por qué   (solo lectura)
start [servicio...] arrancar uno, varios o todo
stop  [servicio...] parar uno o varios
restart             stop + start, en orden de dependencias, nunca en paralelo
logs                registros del stack, con prefijo por línea
backup              copia de config, datos y BD, con manifiesto sha256
update              actualizar (con backup antes, y doctor al final)
doctor              diagnóstico: comprobaciones nombradas e independientes
```

Todos aceptan `--json` con esquema estable, `--timeout` y `--component`.

### Seis cosas que este repo no promete

Las seis están comprobadas con un comando, no son promesas de roadmap.

1. **Vigilantes que no vienen escritos.** El componente `watchdogs` instala tres
   paquetes (`cron`, `curl`, `sqlite3`) y arranca **cero servicios**: `./ezarr.sh
   --dry-run --only watchdogs` imprime `arr-stack start:` vacío. No hay ningún
   script de watchdog en el árbol, ni `.sh`, ni crontab. El hueco está reservado
   y cableado a Healthchecks.io, pero el vigilante lo escribes tú.
   [`docs/operacion.md`](docs/operacion.md) lo dice con estas palabras.
2. **Respaldos sin cifrar.** `backup` genera copia + manifiesto sha256 y
   `--verify` lo comprueba. El cifrado no está en el código: ponlo tú (rclone
   crypt, gpg, lo que uses).
3. **Tres binarios que nadie instala: `motion`, `homarr` y `cloudflared`.** El
   catálogo los declara como servicios (`arr-stack:63-65`) y el perfil pasa el
   `--dry-run` con exit 0, pero **no están en `ezarr_packages_for_components()`
   ni en la lista de descargas** (`lib/stack.sh:416-428`, `lib/stack.sh:452`).
   El perfil dice que sí y el plan no lo hace: es peor que un error, porque
   `arr-stack start: motion` se imprime igual. `camera` además genera un
   `camera.conf` con una IP de ejemplo (`192.168.1.10`) para un binario que no
   va a existir.
4. **Los seis *arr* de verdad no se instalan.** Sonarr, Radarr, Bazarr, Prowlarr,
   Jackett y FlareSolverr salen de un `.deb` en un dominio que no resuelve. Sus
   servicios están en el catálogo, sus puertos están publicados y sus `.deb` no.
   `minimal` levanta Jellyfin y poco más: **esto hoy es un servidor multimedia,
   no un stack *arr*.**
5. **No hay autostart.** Detallado en
   [la sección siguiente](#quién-arranca-esto-y-por-qué-es-la-cuarta-pregunta),
   porque es lo más caro de toda esta lista.
6. **Ni una sola cifra de recursos.** No hay RAM, ni disco, ni prueba de
   transcodificación, ni benchmark, para ningún teléfono. Concretamente **no hay
   dato de si FlareSolverr cabe**: arrastra un Chrome headless, y en un Snapdragon
   860 con 4-6 GB es la primera pregunta, no la última. No lo voy a estimar, porque
   una cifra inventada aquí valdría exactamente lo que vale el badge que acabo de
   quitar. Si alguien lo monta y lo mide, que escriba el número y el modelo.

---

## Quién arranca esto, y por qué es la cuarta pregunta

> «¿Cómo vuelve a arrancar solo después de un corte de luz, y quién se encarga?»

**La respuesta corta: no lo hace. Se encarga una persona, cada vez.**

Esto no es un descuido pendiente, es una decisión que ya está escrita en el
código, y conviene citarla en vez de taparla:

- `ezarr.sh:13-14` — *"No arranca nada al terminar: la instalacion no es el
  arranque. Tras instalar, el arranque lo decides tu con `ezarrctl start`"*.
- `ezarr.sh:312` — al acabar, imprime *"NO se ha arrancado nada. El arranque lo
  decides tu"*.
- `docs/instalacion.md:61` — *"### 1.1. Encender en TWRP, siempre"*. El procedimiento es
  **Power + Vol↓ a mano**, y hay que montar `/data` otra vez.

Y lo que **no** existe en el árbol, comprobado sobre el código y las
configuraciones (no sobre los `.md`, que aquí solo hablan del tema):

```
$ grep -rniE "autostart|rc\.local|@reboot" \
      --include='*.sh' --include='ezarrctl' --include='arr-stack' \
      --include='*.conf' --include='*.sample' . | grep -v '\.bak-'
$ echo $?
1                    # sin coincidencias

$ grep -rn "init\.d" --include='*.sh' --include='ezarrctl' --include='arr-stack' . \
    | grep -v '\.bak-' | grep -v 'lib/env.sh'
$ echo $?
1                    # sin coincidencias
```

Único `init.d` que aparece en el repo es `lib/env.sh:99-102`, y **no arranca
nada**: es una rama de *detección* que clasifica el init del host como `sysv`
cuando `/etc/init.d` existe, precisamente para decidir que en el chroot **no**
serve. Es leer, no instalar.

No hay script de init, no hay unidad de systemd, no hay entrada de rc.local, no hay
crontab de arranque, y **no hay ningún enganche de TWRP** que entre solo en el
chroot. Sumado a que el arranque pasa por TWRP y no por Android, la secuencia
real tras un corte de luz es:

> alguien coge el teléfono → lo enciende en TWRP → monta `/data` → entra en el
> chroot → `ezarrctl start`

Consecuencias que asumo en voz alta, porque cambian lo que esto es:

- **No es un servidor.** Es una instalación que alguien enciende. La diferencia
  entre un servidor y esto es exactamente si hace falta que estés delante.
- **Un corte de luz de 30 segundos es una visita.** Un corte de noche, un
  apagón de la compañía o una batería agotada significan el stack parado hasta
  que vuelvas a él. Si necesitas Jellyfin a las 23:00, esto no lo da.
- **"Coste marginal cero" no incluye esta hora.** El dinero es cero; el rato es
  tuyo.

Lo que haría falta para cerrarlo —y que **no** implementa este repo— es una de
estas dos, y ambas son trabajo de rooting que va más allá de un instalador bash:
un arranque automático de TWRP por hardware (botón de volumen al encender, o
`fastboot` con `boot_once`), o dejar de depender de TWRP. Ninguna de las dos está
escrita aquí, así que **no la voy a prometer en este README**. Lo que sí hago es
dejar de fingir que el arranque es un problema resuelto.

---

## Diagramas

Tres diagramas, **no todos del mismo tipo**. La distinción importa: uno describe
lo que hay, dos describen lo que *debería* haber.

| | |
|---|---|
| [**Arquitectura del stack**](docs/diagrams/stack-architecture.html) | **Describe lo que hay.** Chroot, `/data`, servicios, puertos y accesos remotos. |
| [**Ciclo de vigilancia y respaldo**](docs/diagrams/ciclo-vigilancia-respaldo.html) | ⚠️ **Diseño, no implementado.** Dibuja el ciclo de un fallo: qué se comprueba, qué se relanza y cuándo entra el rescate. **Ese vigilante no existe en este árbol** (`watchdogs` arranca 0 servicios; no hay ningún script de watchdog). Léelo como la especificación de lo que habría que escribir. |
| [**Flujo de la cámara**](docs/diagrams/flujo-camara.html) | ⚠️ **Diseño, no implementado.** Del movimiento en el pasillo al clip y su subida. **El binario `motion` no lo instala ningún paso de este instalador**, así que hoy el flujo no arranca. |

HTML autónomo, con tema claro/oscuro y animación opcional. Se abren desde el
navegador, sin nada que instalar.

Puse las dos marcas ⚠️ porque el problema de un diagrama bonito de algo que no
existe es peor que no tener diagrama: hace que el hueco parezca relleno.

---

## Estado verificado

Todo lo de esta tabla se ejecutó en esta máquina el **2026-10-05**. No es una
wishlist, es la salida real.

| Comprobación | Comando | Resultado |
|---|---|---|
| Suite de contrato | `bash tests/smoke.sh` | **71 correctas, 2 con fallos, exit 1** |
| Sintaxis | `bash -n` en los 10 scripts | OK en los 10 |
| Plan `minimal` | `./ezarr.sh --dry-run --profile minimal` | exit 0, 9 pasos, 9 operaciones previstas |
| Plan `standard` | `./ezarr.sh --dry-run --profile standard` | **exit 6**: faltan 3 sha256 |
| Plan `full` | `./ezarr.sh --dry-run --profile full` | **exit 6**: faltan 4 sha256 |
| Plan en JSON | `./ezarr.sh --dry-run --only core --json` | esquema estable, pensado para CI |
| Host de releases | `curl -sS -o /dev/null https://packages.example.com/` | **NXDOMAIN**, no existe |
| Los 12 componentes | `./ezarr.sh --dry-run --only <c>` | **4 salen 6**, 8 salen 0 (ver la tabla de arriba) |
| En hardware | — | **no ejecutado**. Nunca contra un teléfono físico |

#### Los 2 fallos: son míos, y no están arreglados

Antes este README decía que los 2 fallos «no vienen de este código» y que «la
suite está haciendo su trabajo». Eso era racionalizar un rojo. Lo que dicen es
más simple:

| Test | Qué encuentra | Dónde |
|---|---|---|
| `hash/clave con forma de credencial` | Un SHA de 40 hex y dos sumas de fuente de 64 hex | `docs/diagrams/stack-architecture.json:16`, `docs/diagrams/ciclo-vigilancia-respaldo.html:43-44` |
| `IPs que no son placeholder` | Tres direcciones de LAN de ejemplo (las que salen de la salida del propio test) | `docs/diagrams/**` |

*(No repito aquí las tres IP literales a propósito: el escáner también recorre
este README, `tests/smoke.sh:69`, y si las escribiera aquí seguirían marcando
fallo después de arreglar los diagramas. Copia las que te dé el propio test.)*

Es verdad que son *metadatos de diagramas generados* y no secretos. Pero son
**ficheros que este repositorio entrega**, y mi propio escáner los marca. Un rojo
que se explica pero no se arregla es un rojo que sigue rojo. Dos salidas, y las
dos son legítimas:

1. Arreglar los ficheros —cambiar las IPs por rangos de documentación
   (`203.0.113.x`) y quitar los hex de los diagramas— y la suite sale a 73/73.
2. O reconocer que el escáner es demasiado ancho para artefactos generados y
   **añadir una exclusión explícita y justificada** al test.

Lo que **no** es una salida es relajar la comprobación a escondidas para que la
insignia salga verde. Hasta que una de las dos pase, este README dice **rojo**, y
el workflow de CI (`.github/workflows/ci.yml`, que no se ejecuta porque este repo
no tiene remoto) sigue en rojo a propósito.

#### Huecos que la suite no cubre

La suite es verde en muchas cosas y aun así esto no funciona. Lo que sigue **no
lo comprueba ningún test**, y por eso no está en la tabla de arriba:

- **Chroot sin systemd.** Los `.deb` de Sonarr, Radarr y Jellyfin traen
  scripts `postinst` que llaman a `systemctl`, que **no existe** en el chroot. El
  instalador no lo contempla: `fs_apt()` (`lib/plan.sh:349-363`) lanza
  `apt-get install -y -qq` con `DEBIAN_FRONTEND=noninteractive` y nada más. No
  crea `policy-rc.d` ni maneja ese fallo. Es el fallo clásico de este terreno y
  **no está resuelto aquí**; que nadie lo descubra en su propio teléfono.
- **Recursos.** Ninguna cifra de RAM, disco ni transcodificación. Sin benchmark.
- **Autostart.** Ningún test puede dártelo: no existe. Ver
  [la sección dedicada](#quién-arranca-esto-y-por-qué-es-la-cuarta-pregunta).

---

## Créditos

Este proyecto **no habría existido** sin
**[Luctia/ezarr](https://github.com/Luctia/ezarr)** (MIT). La idea de fondo —que
montar un mediacenter Servarr sea *fácil*— es suya, y también algunas decisiones
que este repo copia a propósito:

- **Un cuestionario, no un YAML a mano.** Su CLI pregunta en cascada y respeta
  las dependencias reales del dominio: Bazarr solo se pregunta si hay Sonarr o
  Radarr. Aquí se traduce a `--with` / `--without` / `--only` sobre un catálogo
  abierto, porque aquí los servicios son paquetes de un chroot y no contenedores.
- **Generar y arrancar son cosas separadas.** Su instalador escribe el fichero y
  te delega el `docker compose up -d`. Aquí igual: `ezarr.sh` deja el stack
  instalado y el arranque lo decides con `ezarrctl start`.
- **`[Y/n]` por defecto** y **avisar sin bloquear**: una categoría vacía avisa, no
  impide instalar.
- **El badge honesto.** El suyo prueba que el script no se rompe, y lo dice. El
  de este repo **está en rojo y lo dice**: `71 ok / 73` en la insignia, y la tabla
  de [estado verificado](#estado-verificado) enseña los dos fallos con su
  fichero y su línea en vez de esconderlos. Por eso quité la insignia verde de
  «instalador de 1 comando»: este repo no tiene instalador remoto, y una insignia
  que promete lo que no existe rompe la única regla que tenía.

La diferencia: *ezarr* despliega sobre un **servidor Ubuntu** con Docker. Esto
despliega sobre un **Android con TWRP**, sin Docker, sin systemd y sin kernel
parcheado, y todo lo que hay en el catálogo son servicios que el chroot puede
mantener con `cron` y `arr-stack`.

También: [TeamWin/TWRP](https://twrp.me/xiaomi/xiaomipocox3pro.html) por el
recovery, y los proyectos que se leyeron para no repetir sus errores —
`Egebrktn/android-home-server`, `xxx02/android-home-server` y
`Emerichek/android-chroot-server`, ninguno con más de 6 estrellas. La lista
completa, con lo tomado y lo descartado de cada uno, está en
[`docs/creditos.md`](docs/creditos.md).

---

## Documentación

| Documento | Para qué |
|---|---|
| [`docs/instalacion.md`](docs/instalacion.md) | Del teléfono apagado a Jellyfin respondiendo. 9 pasos, ordenados. |
| [`docs/operacion.md`](docs/operacion.md) | `ezarrctl`, `doctor`, logs, respaldos y las trampas de TWRP. |
| [`docs/recovery.md`](docs/recovery.md) | TWRP permanente, y **qué se pierde** antes de empezar. |
| [`docs/creditos.md`](docs/creditos.md) | De dónde sale cada idea, con enlace a la fuente. |
| [`CHANGELOG.md`](CHANGELOG.md) | Qué cambió y por qué. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Cómo colaborar, y qué se acepta. |

---

## Licencia

**Este repositorio no trae fichero `LICENSE`.** No se ha elegido licencia, y
mientras no haya una, aplica el copyright por defecto: nadie tiene permiso para
copiarlo, modificarlo ni redistribuirlo.

No es un descuido de forma. Elegir licencia es una decisión del dueño, no del
generador de estas líneas. Cuando se elija, se añade el fichero y este párrafo se
sustituye por el texto de la licencia.

Lo que sí tiene licencia, y hay que respetarla igual, es el trabajo ajeno que
inspira este repo: *ezarr* es MIT, y los proyectos listados arriba tienen las
suyas.

---

## English

**A *arr* server on the phone you no longer use as a phone.** An Ubuntu chroot on
TWRP, 12 installable components, no Docker and no systemd.

> **Personal, experimental project.** No company, no support, no promises. There
> is no declared licence, so by default all rights reserved. Unlocking a Xiaomi
> bootloader **wipes `/data`** — photos, contacts, keys, no way back. Back up
> first, then read [`docs/recovery.md`](docs/recovery.md).

### Install

```bash
./ezarr.sh --dry-run --profile minimal   # print the plan, write nothing
sudo ./ezarr.sh --yes --profile minimal # install it
```

Your credentials go in one file (`/etc/ezarr/secrets.conf`, mode 600, never
committed) and there is a command for them: `ezarrctl secrets init` to create it
from the template, `secrets set KEY` to be asked for a value without it appearing
on screen, `secrets list` to see what is missing, and `secrets doctor` to check
permissions and placeholder values. No subcommand ever prints a value back.

The installer **starts nothing** when it finishes. As of 2026-10-05 the default
`standard` profile **fails with exit 6** — `arr`, `subs` and `downloads` ship
without sha256 checksums and the installer refuses to download unverified
releases. `minimal` (`core` + `media`) plans cleanly with exit 0. This repo has no
Git remote yet, so there is no `curl | bash`: clone it and run it.

### What is honest about it

- **Not faster than Docker**, and it does not pretend to be. What it buys is zero
  marginal cost, silence, and not binning a phone.
- **Never run against real hardware.** Tested: syntax, contracts, exit codes,
  idempotency. `bash tests/smoke.sh` → **71 pass, 2 fail, exit 1** (both failures
  are hex-looking strings and LAN IPs inside the generated diagrams, not code).
- **This repo does not create the chroot.** You mount it; there is no
  `debootstrap` anywhere in the tree.
- **The watchdogs are not written.** The `watchdogs` component installs `cron`,
  `curl` and `sqlite3`. The Healthchecks.io seam is there; the watchdog is yours.
- **Backups are not encrypted.** Copy plus sha256 manifest plus `--verify`. No
  encryption code in the tree.

### Diagrams

[Stack architecture](docs/diagrams/stack-architecture.html) ·
[Watchdog and backup cycle](docs/diagrams/ciclo-vigilancia-respaldo.html) ·
[Camera flow](docs/diagrams/flujo-camara.html) — standalone HTML, light/dark.

### Credits

Inspired by **[Luctia/ezarr](https://github.com/Luctia/ezarr)** (MIT): the
cascading questionnaire, separating "generate" from "start", `[Y/n]` defaults,
warning without blocking, and the honest badge. Details in
[`docs/creditos.md`](docs/creditos.md).

### Licence

**No `LICENSE` file.** No licence has been chosen; default copyright applies. Do
not depend on this.
