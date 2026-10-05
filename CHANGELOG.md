# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto sigue [SemVer](https://semver.org/lang/es/).

## [1.0.0] — 2026-10-05

Primera versión del instalador y del control central. Todo lo que hay aquí es
nuevo; no hay migración porque antes no había nada.

### Añadido — `ezarr.sh`, instalador de un solo comando

- **Detección de entorno.** Distingue chroot de teléfono de máquina normal con
  tres señales independientes (marcador explícito, PID 1, y que `/` y la raíz de
  PID 1 sean el mismo inodo). De ahí depende el gestor de servicios, el método
  de arranque y el lugar de los datos. No es un adorno: es lo que decide si
  funciona en un Poco X3 Pro o en un servidor.
- **`--dry-run` que se puede creer.** Cada paso tiene dos funciones: `plan_X()`
  pura y `apply_X()` que muta. El dry-run ejecuta `plan_X()` y **no alcanza**
  `apply_X()`. No es una reimplementación parecida al instalador: es el mismo
  código con la mitad de las llamadas eliminadas.
- **Auditoría de escrituras.** Toda mutación pasa por un envoltorio `fs_*` que
  en dry-run registra la operación y devuelve sin hacer nada.
  `tests/smoke.sh` verifica el contrato tomando el hash del árbol antes y
  después, y además comprueba que `ezarr.sh` no escribe fuera de un envoltorio.
- **Selección de componentes con `--with` / `--without` / `--only` /
  `--profile`.** El opt-out es una lista, no una familia de `--no-X`: el
  conjunto de componentes es abierto y `--no-web --no-metrics --no-agent` te
  obliga a conocer el catálogo entero para desactivarlo todo. `--only` no es un
  azúcar de `--with`: pone a cero el conjunto y hace inertes perfil y config.
- **El instalador no arranca nada.** Terminar la instalación y arrancar el stack
  son dos decisiones distintas. Entradar en esto no genera un sistema medio
  arrancado a mitad.
- **`--yes` sin forma corta, a propósito.** En `pacman` la `-y` es "refrescar",
  en `apt` es "sí". Quien ya conoce `-y` de otro gestor tiene que mirar `--help`
  en vez de asumir. Igual con `--version` sin forma corta: `-v` es `--verbose` en
  todas partes, que es lo que la gente teclea por reflejo.
- **`--json`** con progreso por stderr, para que sea usable en un pipe.
- **Resumen siempre antes de tocar nada**, generado *desde el plan*, no con un
  segundo renderizado que divergiría del primero.
- **Confirmación por `/dev/tty`**, nunca por stdin: así `ezarr.sh | tee log`
  funciona. Sin terminal y sin `--yes`, falla en vez de colgarse esperando.

### Añadido — `ezarrctl`, control central

- Ocho subcomandos: `status`, `start`, `stop`, `restart`, `logs`, `backup`,
  `update`, `doctor`. Planos, no anidados: los ocho apuntan al mismo objeto (la
  instalación), así que anidarlos costaría pulsaciones en lo que más se teclea.
- **`doctor`** con comprobaciones nombradas e independientes. No se aborta en la
  primera: un fallo solo escondiendo los demás no sirve de nada. Salidas 0
  limpio, 1 problemas, 2 solo avisos, para servir de puerta en CI.
- **`doctor --fix`** solo aplica correcciones seguras y reversibles, y las
  anuncia antes. **Se niega a matar el proceso que ocupa un puerto**: puede ser
  otro servicio tuyo, y esa decisión es del usuario.
- **`status` funciona cuando la instalación está rota**, que es justo cuando
  hace falta. No consulta systemd: mira el proceso real y el puerto real.
- **Al expirar un `--timeout`, se imprimen las últimas 20 líneas de log en
  línea.** Es lo más útil que puede hacer una herramienta cuando un servicio no
  arranca.
- **`backup` con manifiesto sha256** para que un `restore` pueda verificar.
  `--keep N` **enumera lo que va a borrar antes de borrar** y nunca se lleva el
  último respaldo bueno. Es el único sitio donde un default destructivo sería
  imperdonable.
- **`update --check` no escribe nada.** El update real hace copia antes, actualiza
  en orden de dependencias y lanza `doctor` al final. Si el doctor falla, lo dice
  fuerte — pero **no hace rollback automático**: un rollback ciego puede pisar
  datos creados después de la copia.
- **Gestor de servicios Abstracto.** D-Bus si hay systemd, PID-file y supervisor
  si no. `ezarrctl` nunca hace `systemctl` a ciegas.
- **`logs` multiplexado** con prefijo por línea (`api | …`) cuando hay más de un
  fichero. Sin prefijo no se sabe de quién es la línea con seis servicios
  escribiendo.

### Añadido — `lib/`, módulos compartidos

- `log.sh` — niveles de verbosidad, color condicional, códigos de salida estables
  y **normalización de `--opcion=valor`**.
- `env.sh` — detección de entorno, recursos, red y privilegios.
- `config.sh` — configuración desde fichero, con precedencia explícita
  (defecto < fichero del sistema < fichero del usuario < entorno < flags).
- `plan.sh` — el motor plan/apply y los envoltorios de escritura.
- `components.sh` — catálogo y resolución opt-in/opt-out.
- `stack.sh` — registro de servicios (qué es cada uno, en qué puerto y cómo se
  comprueba) y los pasos de instalación.

### Añadido — configuración, plantillas y pruebas

- `etc/ezarr/*.sample` — cuatro plantillas **con placeholders**: la IP de ejemplo
  es `192.168.1.10` y ninguna credencial real está en el repositorio.
  `tests/smoke.sh` lo comprueba y falla si aparece una.
- `tests/smoke.sh` — 65 comprobaciones, sin dependencias. Incluye la del
  dry-run (hash del árbol antes/después) y la de idempotencia (instalar dos
  veces y comparar).

### Corregido — credenciales reales que estaban en el historial

La primera versión del test de secretos buscaba con una lista de valores
prohibidos escrita dentro del propio test. Una lista así tiene que escribir
esos valores en el fichero para poder buscarlos, de modo que **el guardián
era la fuga**: el topic real de ntfy, la contraseña real de qBittorrent, tres
claves de API reales de Sonarr/Radarr/Bazarr y el nombre real del autor
estaban en `tests/smoke.sh`, y por tanto en el commit, y por tanto en el
historial.

Qué se hizo, en este orden:

- El test ya no nombra ningún valor. Comprueba la **forma** de una credencial
  (un hash de 32/40/64 hex, una asignación con valor, una URL con `user:pass@`)
  en lugar de una lista de cadenas prohibidas. Es más estricto —no depende de
  acordarse de qué escribir— y no se puede colar nada por escribirlo.
- El historial se reescribió (`commit --amend` + `reflog expire` + `gc
  --prune=now`) y se verificó objeto a objeto: cero coincidencias de las seis
  cadenas en todo el almacén de objetos.
- La identidad de git del repositorio es `ezarr-stack-build
  <noreply@example.com>`, no la global de la máquina, que es el nombre y el
  correo reales de quien lo mantiene.

Si alguien clonó este repositorio antes de esta corrección, las credenciales
de arriba deben considerarse comprometidas y rotadas: el topic de ntfy, la
contraseña de qBittorrent y las tres claves de API.

### Corregido — el instalador instalaba antes de preguntar

Este era el fallo serio, y era invisible en el entorno de pruebas.

`ezarr_plan_run` se ejecuta **dos veces**: la primera dibuja el resumen y la
segunda aplica. La primera también llamaba a `apply()`, y como la segunda solo
se lanza después de `ezarr_confirm`, **el stack se instalaba entero antes de
que se pidiera confirmación**. El prompt decoraba una instalación ya hecha.

En una cuenta sin permisos para `/data` el efecto no se veía —el `mkdir` de
la estructura de directorios fallaba, el paso se marcaba como problema y la
ejecución moría ahí por casualidad. Como root, que es como se instala en el
teléfono, se instalaba.

La puerta es ahora `EZARR_APPLY_ARMED`, que `ezarr.sh` arma después de la
confirmación. Hay dos pruebas nuevas que lo comprueban, y se comprobaron
contra el código anterior para verificar que fallan: la estática (la bandera
se arma en una línea posterior a `ezarr_confirm`) y la dinámica (una
ejecución real sin `--yes` no produce ni un `no se pudo:`, que era la firma
del `apply()` ejecutado).

### Corregido — otros

- **`/dev/tty` existente pero no abrible.** La comprobación era `[ -e /dev/tty ]`.
  En un contenedor el fichero existe y abrirlo falla con *No such device or
  address*, así que el error de bash crudo se imprimía en mitad del resumen.
  Ahora se comprueba que se pueda **abrir**, que es la pregunta que importa.
- **El contador de escrituras contaba intentos.** `_fsim` suma antes de
  escribir, así que un `mkdir` que acaba en *Permission denied* salía en el
  resumen como una escritura hecha. `_fs_fail` descuenta, y el resumen
  distingue "nada se ha modificado" de "N pasos aplicados, M escrituras
  hechas" — que es la pregunta que un instalador tiene que responder cuando
  se para a mitad.
- **La configuración se leía de una ruta fija mientras se escribía en otra.**
  `EZARR_CONF_FILES` tenía `/etc/ezarr` escrito dentro, pero el instalador
  escribe en `$EZARR_CONF_DIR`. Con el directorio cambiado, el instalador
  escribía una configuración que el runtime no leía nunca. La lista sale ahora
  de la variable, y se reconstruye en cada `ezarr_config_load` para que un
  `--set EZARR_CONF_DIR=…` posterior al `source` también cuente.
- **`.gitignore` nuevo.** Los `*.bak-YYYYMMDD` del trabajo en curso se crean
  antes de sobrescribir, pero no se suben.

### Decisiones documentadas

- **El instalador deja de arrancar servicios al terminar.** Separar "generar
  configuración" de "hacer cambios en el sistema" es lo que hace el instalador
  re-ejecutable sin sorpresas. Para arrancar está `ezarrctl start`.
- **Automatizar el cableado entre servicios crearía credenciales compartidas.**
  Por eso las claves de las apps **se piden**, nunca se inventan: `/etc/ezarr/apps.conf`
  se genera vacío y se avisa. Un secreto emitido por un instalador es un secreto
  que conoce todo el que lo ha instalado.
- **Una release sin checksum conocido no se instala.** Sale con código 6 y dice
  qué variable falta. Es preferible a instalar algo que no se puede verificar.
- **El parser de configuración no hace `source`.** Solo acepta pares
  `NOMBRE=valor`. El código real del stack sí hace `source`; aquí no, porque un
  fichero de configuración que cualquiera con root puede escribir es ejecución
  de código arbitrario.