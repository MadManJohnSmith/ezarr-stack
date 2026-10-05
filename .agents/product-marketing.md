# Product Marketing Context

**Document version:** v1
**Last updated:** 2026-10-05

> Contexto de marketing de producto para `ezarr-stack-build`. Es un proyecto
> **personal y experimental**: no hay empresa, ni clientes, ni ingresos. El
> activo no es parecer grande, es **ser creíble**. Cualquier línea de este
> documento que no se pueda sostener con el código o con una comprobación
> ejecutada, no entra.

## Product Overview

**One-liner:** Instalador y plano de control para un stack *arr* pensado para un
chroot Ubuntu sobre un teléfono Android que ya no usas como teléfono (TWRP), sin
Docker y sin systemd.

**Estado real de la instalación (2026-10-05, medido, no estimado):** el perfil por
defecto (`standard`) **se rechaza con exit 6**; `minimal` sale con exit 0 e
instala `core` + `media`. De los 18 servicios catalogados, **9 tienen hoy el
binario instalado**, 6 dependen de un host de releases que no resuelve y 3
(`motion`, `homarr`, `cloudflared`) **no los instala ningún paso del instalador**.
Traducción para el mensaje: **hoy esto es un servidor multimedia con Jellyfin, no
un stack *arr*.** No se vende como otra cosa.

**What it does:** `ezarr.sh` instala (detecta si corre en un chroot o en una
máquina normal, resuelve qué componentes se instalan, **muestra el plan antes de
tocar nada** y pide confirmación). `ezarrctl` opera el stack ya instalado
(`status start stop restart logs backup update doctor`). `arr-stack` es el gestor
de servicios, porque el chroot no tiene init: es el fichero que sabe cómo se
levanta cada cosa. El instalador **no arranca nada** al terminar; instalar y
arrancar son dos decisiones distintas.

**Product category:** homelab / self-hosted media server / self-hosting sobre
hardware poco obvio. La repisa de "lo monto yo en casa", no la de "equipo de
infraestructura".

**Product type:** CLI de código abierto (Bash), proyecto personal. Sin servicio,
sin SaaS, sin cuenta.

**Business model:** ninguno. Coste marginal **cero en dinero**: el hardware ya
está pagado y en un cajón. El proyecto no cobra, no pide cuentas y no manda
telemetría.

**Lo que ese "cero" no cubre** (decirlo de antemano, no descubrirlo en la venta):
el dinero es cero, pero **el coste en personas no lo es**. Desbloquear el
bootloader **formatea `/data`**, así que el teléfono *como teléfono* queda
destruido: el hardware se reaprovecha, el aparato como tal no vuelve. Y no hay
autostart: **encender el stack es una persona, cada vez, y cada arranque pasa por
TWRP a mano.** Un corte de luz es una visita. Nada de esto se maquilla de "coste
cero": es coste cero *en euros*, con un precio en rato y en un aparato que deja
de ser teléfono.

## Target Audience

**Target companies:** ninguna. Es B2C técnico: una persona, su red y sus datos.

**Decision-makers:** la persona que lo instala. No hay comité, no hay proveedor,
no hay compra que aprobar.

**Target person:** alguien que ya self-hostea o quiere empezar, que tiene un
Android viejo sin uso (o un Xiaomi con TWRP en mente), y que sabe lo que es un
chroot aunque sea de oídas. Perfil típico: linuxero de homelab, 30-45 años,
con un NAS o un mini-PC que ya le sobró, y con la sospecha de que paga demasiado
por un servidor que solo transcodifica.

**Primary use case:** tener biblioteca multimedia (Jellyfin + *arr + subtitles)
siempre disponible, sin comprar hardware, sin abrir puertos en el router y sin
que el sistema operativo del móvil te robe la atención.

**Jobs to be done:**
- "Que mi servidor de multimedia no se caiga y no me cueste un euro al mes."
- "Que el móvil que tengo en un cajón vuelva a servir para algo sin vaciar el
  cajón de paso."
- "Que instalar esto sea reversible y legible, no un `curl | bash` que me deja
  un sistema que no entiendo."

**Use cases:**
- Biblioteca personal con Jellyfin + Sonarr/Radarr + Bazarr, acceso remoto por
  Tailscale o Cloudflare Tunnel sin abrir puertos.
  ⚠️ **Hoy solo la primera mitad es real:** Jellyfin se instala y arranca;
  Sonarr/Radarr/Bazarr no, porque su `.deb` viene de un host que no resuelve.
- Cámara IP de vigilancia con detección de movimiento, alimentada por el mismo
  cacharro que sirve la biblioteca.
  ⚠️ **`motion` no lo instala ningún paso de este instalador.** Es un hueco
  reservado, no una funcionalidad.
- Homelab de dificultad media-alta: el objetivo es el Triumph!, no la facilidad.

*Los tres casos de arriba son el destino del proyecto, no su estado. La regla de
este documento sigue siendo la del principio: si no se puede sostener con el
código o con una comprobación ejecutada, no entra. Estos tres solo se pueden
sostener como `roadmap`; como *producto* hoy, el único caso de uso real es
"tengo un móvil y quiero Jellyfin y el plano de control alrededor".*

## Personas

No aplica: no hay varios decisores en juego. Hay **una persona**, y su enemigo no
es un competidor, es la Laziness (no tocar nada) y la CTO virtual (¿y si rompo el
móvil?). Los roles se reparten dentro de la misma cabeza:

| Rol interno | Le preocupa | Su miedo | Lo que le prometemos |
|-------------|-------------|----------|----------------------|
| El que instala | Que el plan sea revisable antes de tocar el sistema | Instalar a ciegas y no saber qué cambió | `--dry-run` que imprime el plan entero y no escribe nada |
| El que opera | Saber qué está vivo y por qué | Un servicio caído que nadie mira | `ezarrctl status` y `doctor`, con checks nombrados e independientes |
| El que conserva | Que un update fallido no deje el stack a medias | Perder la biblioteca | `backup` con manifiesto sha256 y `--verify`, y `update` que hace copia antes y `doctor` después |
| El dueño del móvil | No perder sus fotos y sus contactos | Formatear `/data` por un servidor multimedia | Decirlo antes, muy claro, y dar la guía de copia |

## Problems & Pain Points

**Core problem:** servir multimedia 24/7 cuesta dinero o atención. Un mini-PC son
150-300 €, un hosting son 5-20 €/mes al forever, y un NAS propio es un mueble más.
La alternativa gratuita —reciclar un móvil— viene con una factura escondida: hay
que desbloquear el bootloader, y **desbloquear un Xiaomi formatea `/data`**
(`docs/recovery.md`, aviso literal: "esto borra el teléfono").

**Why alternatives fall short:**
- **`docker compose` en un NAS o mini-PC.** Funciona y es la respuesta correcta
  para el 90% de la gente. Cae por precio, por ruido (un mueble, un LED) y porque
  en Android directamente no hay daemon de Docker sin kernel parcheado.
- **Chroot en Android ya montados en GitHub.** Los que existen tienen 0-6
  estrellas, un commit cada uno, sin mantenedor. El patrón dominante es
  `[Y/n]` en TWRP, rootfs en un directorio, y arrancar a mano después de cada
  reinicio. Sin backup verificado, sin guía de "si no arranca", y con el riesgo
  real de que una OTA borre el kernel parcheado.
- **Alojarlo en cloud.** Coste recurrente, y pierdes el control de tus datos.
- **No hacer nada.** Alternativa real, y a veces la correcta.

**What it costs them:** el artículo que ya no usas, o el MinIPc, o el hosting, o
las horas de pelearte con un init que no existe. La opción de este proyecto es la
de coste marginal cero.

**Emotional tension:** "el móvil está en un cajón desde hace dos años"; "la última
actualización me borró las fotos y no me lo-creas"; "ya no me fío de tocar un
teléfono que uso". Y la reversed: "quiero que el servidor esté, pero no quiero
darle más trabajo al mío".

## Competitive Landscape

**Direct:** `docker compose` en un mini-PC o un NAS (Synology/QNAP/Portainer) —
funciona muy bien, pero cuesta hardware y no cabe en un cajón.

**Secondary:** los proyectos Android-chroot existentes (`Egebrktn/android-home-server`,
`xxx02/android-home-server`, `Emerichek/android-chroot-server`) — el mismo
hardware, cero proyecto. Caen por: sin guía de recuperación ("unbrick"), sin
backup automatizado y verificado, arranque manual o único, y rootfs en directorios
que heredan los `nosuid` de Android.

**Indirect:** los Servarr en un VPS; o no self-hostear.

**Inspiración, no competencia:** [`Luctia/ezarr`](https://github.com/Luctia/ezarr) —
MIT, ~1.079 estrellas. "EZ to deploy a Servarr mediacenter on an Ubuntu server",
con una CLI en Python que hace un cuestionario en cascada (pregunta Bazarr solo si
hay Sonarr o Radarr) y un `docker-compose.yml` generado. Toma de él: el
cuestionario en vez de un YAML a mano, el `[Y/n]` por defecto, `restart:
unless-stopped` como contrato de arranque, y el detalle de decir la verdad sobre
lo que el badge prueba. **No toma:** necesita Docker, necesita un Ubuntu server
(no un chroot de TWRP), y su badge prueba el camino manual, no el que su README
recomienda.

## Differentiation

**Key differentiators:**
- **1. Corre donde el resto no puede.** Chroot Ubuntu sobre TWRP, sin systemd, sin
  Docker, sin kernel parcheado. `arr-stack` hace de init, y `ezarr_detect_env`
  (`lib/env.sh:28`) sabe si está dentro del chroot o en una máquina normal.
- **2. El instalador no arranca nada.** Plan, `--dry-run` real, confirmación
  `[s/N/q]`, y el arranque se decide después con `ezarrctl start`. El artefacto es
  revisable antes de existir.
- **3. El móvil arranca en TWRP, no en Android.** Android no llega a ejecutarse:
  sin notificaciones, sin sincronización, sin Google. Ese es el "silencio" — es
  un hecho operativo, no una metáfora.
- **4. Honestidad como contrato, no como nota al pie.** Los docs declaran lo que
  el catálogo promete y el código no entrega.
- **5. El backup es verificable.** Manifiesto sha256, `backup --verify`, y
  `update` con copia previa y `doctor` posterior.
- **6. Componentes abiertos con opt-out por lista**, no una familia de flags
  `--no-X` que no escala a un componente que nadie había previsto.

**How we do it differently:** el hardware no es un servidor con el móvil como
caso raro; el servidor ES un móvil apagado que nunca entra en Android. El
coste de la máquina es cero porque la máquina ya existe.

**Why that's better:** porque el objetivo no es potencia, es **coste marginal,
silencio y no tirar hardware**. No es más rápido que Docker y no pretende serlo:
no hay TypeScript, ni SQLite transaccional, ni cgroups. Es más barato y más
callado.

**Why customers choose us:** por honestidad y por no exigir hardware nuevo. Si ya
tienes un NAS, este proyecto es peor para ti y el propio README lo dice.

## Objections & Anti-Persona

| Objection | Response |
|-----------|----------|
| "¿Esto me brick-ea el móvil?" | Desbloquear el bootloader de un Xiaomi formatea `/data`. Sin vuelta atrás. Se dice **antes**, en la primera línea de `docs/recovery.md`, con la cita de TeamWin. La mitigación es copia + TWRP permanente, no una promesa. |
| "Si pierdo el móvil, pierdo el stack." | Sí, y además una OTA puede borrar el kernel parcheado. Lo que este proyecto ofrece: `backup` copia el `rootfs.img` con manifiesto sha256 y `--verify` lo comprueba. Lo que **no** ofrece: ni un "si no arranca" de una línea, ni **ningún watchdog** — el componente `watchdogs` arranca cero servicios y no hay un solo script de vigilancia en el árbol. **Corrección 2026-10-05:** este documento decía antes que el proyecto ofrecía "watchdog con marca de parada". Eso era falso y contradecía la tabla de abajo; está borrado. |
| "¿Cómo vuelve a arrancar solo tras un corte de luz?" | **No lo hace, y hay que decirlo antes que nada.** No hay `init.d`, `rc.local`, `@reboot` ni enganche de TWRP en el árbol; `ezarr.sh` dice literalmente que instalar y arrancar son decisiones distintas. Encenderlo es una persona: TWRP a mano → montar `/data` → chroot → `ezarrctl start`. **Nadie relanza esto solo.** Es la objeción que más se salta el marketing y la que más caro sale: por eso tiene su propia sección en el README y no se esconde en una nota al pie. |
| "No me fío de un instalador que no ha corrido en un móvil." | Correcto, y por eso `ezarr.sh` no arranca nada y `--dry-run` no escribe. Hecho a fecha de hoy: 73 comprobaciones en la suite, **71 correctas y 2 con fallos (exit 1)**, 0 ejecuciones contra un teléfono físico, y **0 de los 6 *arr* instalables** porque el host de releases no resuelve. No se promete hardware. |
| "Cámara y servidor a la vez, en un móvil con la pantalla a los lados." | El catastro lo es (batería hinchada por carga 24/7, throttling térmico). El propio repo avisa y la respuesta es «carga controlada, sin funda, tareaset». Es un riesgo asumido, no una característica. |
| "¿Respaldos cifrados?" | **Los respaldos llevan manifiesto sha256 y `--verify`. El cifrado no lo pone este repositorio.** No hay gpg ni age en el código. Ponerlo es tuyo, y es un pendiente declarado. |

**Anti-persona:**
- Quien tenga fotos o contactos sin respaldar. No entres.
- Quiera un SLA o un soporte. Nadie responde a un ticket.
- Ya tenga un NAS o un mini-PC funcionando. Este proyecto es peor para ti.
- No acepte formatear `/data`, o no pueda hacerlo sin perder lo que le importa.
- Quiera algo que funcione sin tocarlo nunca. Nadie ha ejecutado este instalador
  contra un teléfono físico, y no hay forma honesta de prometer lo contrario.

## Switching Dynamics

**Push:** el artículo, el hosting, el ruido del salón, y un "ya lo miré
mañana". El hartazgo de pagar por algo que se usa por la noche.

**Pull:** coste cero, silencio, la sensación de cerrar un círculo (el cajón deja
de estar lleno de cosas que tiraste), y un servidor que hace algo útil de verdad.

**Habit:** el `docker compose` ya funcionando en el NAS; el Móvil en el cajón; y
la inertia técnica de no tocar un dispositivo que funciona.

**Anxiety:** romper el móvil, perder fotos, y que la ayuda no exista. Las tres son
reales y ninguna se resuelve con marketing: se resuelven con la copia, con
`doctor`, y con decir la verdad en la portada.

## Customer Language

**How they describe the problem:**
- "El móvil está en un cajón y me da pena tirarlo, pero tampoco lo uso."
- "Un servidor para ver series, ¿cuánto me va a costar? ¿Y el consumo?"
- "La última vez que actualicé se me borró todo y no había hecho copia."
- "Quiero algo que no haga ruido y que no me quite más trabajo del que ya tengo."

**How they describe us:**
- "Es un chroot de Ubuntu en el móvil, con TWRP, sin Docker."
- "El instalador te enseña el plan antes de tocar nada."
- "El catálogo promete más de lo que el código entrega — y está escrito en el
  repo." *(frase del propio repo, `docs/operacion.md`, que es exactamente el
  tono que queremos)*
- "No es más rápido que Docker. Es más barato y es más callado."

**Words to use:** cajón · coste cero · silencio · el plan antes de tocar nada ·
chroot · TWRP · respaldo con manifiesto · lo que sí hace / lo que no hace ·
disponibilidad · Experimental · personal.

**Words to avoid:** *fácil de instalar* (no lo es: formatea `/data`) · *gratis*
(cuesta un formateo) · *más rápido que Docker* · *nivel 1 / SLA* · *cifrado por
defecto* · *funciona en tu móvil* (no se ha probado en hardware) · *listo para
producción* · *militar-grade* · **«coste cero» sin matizar** (es cero en dinero;
el coste en tiempo de una persona que enciende el servidor cada vez es real) ·
**«servidor» sin calificar** (hoy es *una instalación que alguien enciende*: sin
autostart, un corte de luz es una visita; si se dice "servidor", va con la
limitación al lado) · **«se relanza solo» / «sobrevive a un corte de luz»** ·
**«stack *arr*» sin decir que hoy solo arranca Jellyfin**.

**Words to use:** *lo que sí hace / lo que no hace* · *probado con este comando* ·
*salida real* · *ninguno lo relanza: hay que encenderlo* · *exit 6, te enseño el
código* · *hoy esto es un servidor multimedia, no un stack \*arr\**.

**Glossary:**
| Term | Meaning |
|------|---------|
| chroot | Sistema de ficheros raíz alterno montado dentro de otro, sin máquina virtual ni kernel propio |
| TWRP | Recovery de Android basado en Linux; aquí se arranca el teléfono, y el chroot vive en `/data` |
| arr-stack | El gestor de servicios del stack. Sustituye al init que el chroot no tiene |
| componente | Bloque instalable del stack (`core`, `media`, `downloads`, `arr`, `subs`, `dashboard`, `camera`, `remote`, `storage`, `watchdogs`, `reverse`, `search`) |
| perfil | Preset de componentes: `minimal` (2), `standard` (7), `full` (12) |
| plan | La lista de operaciones que el instalador va a hacer. Con `--dry-run` se imprime y no se ejecuta |
| doctor | Diagnóstico con checks nombrados e independientes, cada uno ok/warn/fail/skip |
| vigilantes | Scripts que relanzan lo que se cae. El hueco está reservado (`cron` + Healthchecks.io) pero **no vienen escritos** |

## Brand Voice

**Tone:** español de España, seco y técnico. Sin superlativos, sin
"revolucionario", sin "potente". Cuando algo no funciona, se dice que no
funciona y en qué línea de código se comprueba.

**Style:** segunda persona, frases cortas, tablas antes que párrafos, límites
declarados cerca de la promesa. El eslogan no es una frase: es una lista de lo que
el código no hace.

**Personality:** honesto · técnico · cauto · sin lacas · alguien que prefiere que
te lleves una sorpresa buena antes que una promesa grande.

## Proof Points

**Metrics (verificadas el 2026-10-05 en esta máquina, no antes):**
- `bash tests/smoke.sh` → **71 correctas, 2 con fallos, exit 1**. Fallos: un
  SHA de commit y dos sumas de fuente embebidas en los HTML de los diagramas, y
  tres IPs de red local en `docs/diagrams/stack-architecture.json`.
- `bash -n` sobre los 10 ficheros de script → OK en los 10.
- `./ezarr.sh --dry-run --profile minimal` → **exit 0**, "plan correcto: 9 pasos,
  9 operaciones previstas".
- `./ezarr.sh --dry-run --profile standard` → **exit 6**: faltan los sha256 de **3**
  releases (`arr`, `subs`, `downloads`).
- `./ezarr.sh --dry-run --profile full` → **exit 6**: faltan los sha256 de **4**
  (los anteriores más `search`). *Corrección 2026-10-05: este documento decía que
  los dos perfiles fallaban por los mismos 3; es falso.*
- `curl -sS -o /dev/null https://packages.example.com/` → **NXDOMAIN**. Los cuatro
  componentes ⛔ no son un bug de configuración: el host no existe, así que poner
  los sha256 solo mueve el fallo de sitio.
- `./ezarr.sh --dry-run --only <c>` para los 12 componentes → **4 salen con exit 6**
  (`downloads`, `arr`, `subs`, `search`) y 8 salen con exit 0. De esos 8, tres
  (`dashboard`, `camera`, `watchdogs`) **no instalan el binario que dicen**: el
  perfil pasa y el plan no lo hace.
- `grep -rniE "autostart|rc\.local|@reboot" --include='*.sh' --include='ezarrctl'
  --include='arr-stack' --include='*.conf' --include='*.sample' .` → **cero
  resultados** (exit 1). No hay arranque automático. Es la prueba de que
  "servidor" aquí significa "instalación que alguien enciende". *Ojo: el grep hay
  que acotarlo a código y config. Un `grep` sobre todo el árbol da positivo por
  este mismo documento y por el README, que hablan del tema; y el único
  `init.d` real (`lib/env.sh:99-102`) es una rama de detección que no arranca
  nada.*
- 12 componentes, 3 perfiles, 18 servicios catalogados (`lib/stack.sh:13-31`), de
  los que **9 tienen hoy el binario instalado**.
- Umbral declarado por el instalador: **5120 MB de RAM y 8192 MB libres**
  (`lib/config.sh:178-179`, comprobado en `lib/env.sh:306-311`). Ojo: es un
  **umbral que el código exige**, no una medición de lo que el stack consume. No
  hay benchmark, ni cifras de transcodificación, ni dato sobre si FlareSolverr
  (Chrome headless) cabe en un Snapdragon 860. **Ese hueco no se rellena con
  estimaciones.**
- 2 commits en el repo. Sin remoto, sin estrellas, sin forks, sin issues.

**Customers:** ninguno. No hay usuarios fuera de quien lo escribió.

**Testimonials:** ninguno, y no se va a inventar ninguno. La única voz disponible
es la del propio repo: "Un error sin siguiente paso es un bug de la herramienta"
(`docs/operacion.md`).

**Value themes:**
| Theme | Proof |
|-------|-------|
| "El plan antes de tocar nada" | `--dry-run` existe y es de verdad: exit 0, 0 escrituras, salida JSON estable para CI |
| "Sabes qué está vivo y por qué" | `ezarrctl status`/`doctor`, 8 comandos, salida `--json` con esquema estable |
| "Un update no te deja a medias" | `update` = backup → update → doctor (`ezarrctl:552`) |
| "No te pide hardware nuevo" | El chroot lo monta el usuario; el repo no ejecuta `debootstrap` ni lo promete |
| "El backup se puede verificar" | Manifiesto sha256 + `backup --verify` (sin cifrado: no está en el código) |

## Goals

**Business goal:** que alguien con un móvil en un cajón entienda en 10 segundos
que esto existe, y entienda **también en 10 segundos** que tiene un coste real
(un formateo) y una madurez real (probado en sintaxis, no en hardware). La
métrica de éxito no es la conversión: es no ser desenmascarado por el primer
comentario.

**Conversion action:** copiar el comando de un paso y ejecutar `--dry-run`
primero. El segundo paso, y el que de verdad importa, es leer el plan.

**Current metrics:** sin remoto y sin hosting de métricas. 2 commits. Sin
estrellas, forks ni issues observados.

## Changelog
*Newest first. One line per revision: what changed and why.*
- v1 (2026-10-05) — Contexto inicial. Anclado en el estado real del repo del
  2026-10-05: smoke 71/2, `minimal` instala y `standard` falla por sha256, sin
  licence, sin CI, sin ejecución en hardware. Deliberadamente sin cifras de
  consumo eléctrico: no hay medición en el repo.
