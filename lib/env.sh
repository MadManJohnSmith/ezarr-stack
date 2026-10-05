#!/bin/bash
# lib/env.sh — Deteccion de entorno.
#
# El mismo instalador tiene que correr en dos sitios muy distintos:
#   * dentro del chroot Ubuntu del telefono (TWRP + chroot, sin systemd);
#   * en una maquina normal (desktop, servidor, CI) para preparar imagenes.
# Detectar cual es NO es un adorno: decide el gestor de servicios, el metodo de
# arranque y el lugar donde viven los datos.
#
# Todas las funciones son puras: escriben en EZARR_ENV_* y no tocan el sistema.

# --------------------------------------------------------------- proceso 1 --
# El mejor senal de "estoy en un chroot" es que PID 1 no es el init esperado.
ezarr_pid1_comm() { cat /proc/1/comm 2>/dev/null || echo "?"; }
# El binario al que apunta PID 1. Es la unica senal de "que initfs corre" que
# no depende de rutas del host: /proc/1/exe se ve igual desde el chroot que desde
# fuera, mientras que /system, /tmp/TWRP o /metadata no existen dentro.
ezarr_pid1_exe() { readlink /proc/1/exe 2>/dev/null || echo ""; }

# --------------------------------------------------- deteccion del entorno --
# Rellena:
#   EZARR_ENV_KIND      chroot | machine | unknown
#   EZARR_ENV_ANDROID   1 si el host es Android (TWRP o sistema vivo)
#   EZARR_ENV_TWRP      1 si el host es TWRP
#   EZARR_ENV_INIT      systemd | sysv | none
#   EZARR_ENV_ARCH      arm64 | amd64 | ...
#   EZARR_ENV_ROOTFS_MNT punto donde vive el chroot en el host, si se conoce
ezarr_detect_env() {
    EZARR_ENV_KIND="unknown"
    EZARR_ENV_ANDROID=0
    EZARR_ENV_TWRP=0
    EZARR_ENV_INIT="none"

    local pid1 pid1_exe
    pid1="$(ezarr_pid1_comm)"
    pid1_exe="$(ezarr_pid1_exe)"

    # --- Android como host ---------------------------------------------------
    # Estas cuatro senales son del HOST y solo se ven si el instalador corre
    # directamente sobre el (recovery de TWRP, Android vivo con adb). Dentro del
    # chroot no existen: ahi / es el / del chroot, no el / de Android, asi que
    # comprobarlas no da la respuesta y da sensacion de haber comprobado algo.
    if [ -d /tmp/TWRP ] || [ -f /tmp/recovery/version ] || [ -f /tmp/twrp ]; then
        EZARR_ENV_TWRP=1
        EZARR_ENV_ANDROID=1
    fi
    if [ -f /system/build.prop ] && [ -d /data/local/tmp ]; then
        EZARR_ENV_ANDROID=1
    fi
    if [ -d /metadata ] || [ -f /proc/config.gz.ghost ]; then
        EZARR_ENV_ANDROID=1
    fi
    # La senal que SI sobrevive al chroot: el init de Android se llama
    # literalmente "init" (env.sh:14), asi que el nombre no lo distingue de un
    # init normal, pero el binario al que apunta es /system/bin/init.
    case "$pid1_exe" in
        /system/bin/init|/system/xbin/init|/system/*) EZARR_ENV_ANDROID=1 ;;
    esac

    # --- chroot --------------------------------------------------------------
    # Tres senales independientes, porque ninguna sola es concluyente:
    #   1. marcador explicito que escribe el propio instalador
    #   2. PID 1 no es systemd -> namespace/initfs de otro
    #   3. que PID 1 viva bajo /system -> el host es Android, no este chroot
    # La ruta del marcador sale de $EZARR_CONF_DIR: el que escribe
    # ezarr_write_env_marker pone ahi, no en /etc/ezarr fijo.
    local chroot=0 marker="${EZARR_CONF_DIR:-/etc/ezarr}/chroot.marker" mkind
    if [ -f "$marker" ]; then
        EZARR_ENV_ROOTFS_MNT="$(sed -n 's/^MOUNTPOINT=//p' "$marker" 2>/dev/null | head -n1)"
        # KIND= lo escribio el instalador en su momento, cuando aun no habia nada
        # que decidir. Es mas fiable que volver a adivinarlo ahora.
        mkind="$(sed -n 's/^KIND=//p' "$marker" 2>/dev/null | head -n1)"
        case "$mkind" in
            chroot|machine|unknown) EZARR_ENV_KIND="$mkind" ;;
        esac
        [ "$mkind" = "chroot" ] && chroot=1
    fi
    if [ "$chroot" -eq 0 ] && [ "$pid1" != "systemd" ]; then
        # Android (init de /system) o un initfs de recovery (busybox). Antes se
        # exigia pid1 != "init" para entrar aqui, y eso descartaba justo el caso
        # de Android, que es donde vive el chroot de TWRP.
        case "$pid1_exe" in
            /system/*) chroot=1; EZARR_ENV_ANDROID=1 ;;
        esac
        case "$pid1" in
            busybox|sh|*android*|*survival*) chroot=1 ;;
        esac
    fi
    if [ "$chroot" -eq 1 ]; then
        EZARR_ENV_KIND="chroot"
    elif [ "$EZARR_ENV_KIND" != "chroot" ]; then
        EZARR_ENV_KIND="machine"
    fi

    # --- init / gestor de servicios -----------------------------------------
    # El stack no usa systemd en el chroot: se gobierna con arr-stack + cron.
    if [ -d /run/systemd/system ] && [ "$pid1" = "systemd" ]; then
        EZARR_ENV_INIT="systemd"
    # En un chroot, /etc/init.d y /usr/sbin/service pueden estar ahi pero
    # pertenece al host: no son el gestor de estos servicios. Sin systemd se
    # queda en "none", que es lo que refleja de verdad.
    elif [ "$EZARR_ENV_KIND" = "machine" ] && [ -x /usr/sbin/service ] && [ -d /etc/init.d ]; then
        EZARR_ENV_INIT="sysv"
    else
        EZARR_ENV_INIT="none"
    fi

    # --- arquitectura y recursos --------------------------------------------
    EZARR_ENV_ARCH="$(uname -m 2>/dev/null || echo unknown)"
    ezarr_detect_resources
    return 0
}

# RAM, CPU y disco. En un telefono de 7 GB estos numeros deciden si el stack
# completo cabe; por eso el instalador los muestra antes de preguntar nada.
ezarr_detect_resources() {
    EZARR_ENV_RAM_MB=0
    if [ -r /proc/meminfo ]; then
        # MemTotal esta en kB. awk en vez de grep por locale.
        EZARR_ENV_RAM_MB="$(awk '/^MemTotal:/ {printf "%d", $2/1024; exit}' /proc/meminfo 2>/dev/null || echo 0)"
        [ -n "$EZARR_ENV_RAM_MB" ] || EZARR_ENV_RAM_MB=0
    fi
    EZARR_ENV_CPU_COUNT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)"
    [ -n "$EZARR_ENV_CPU_COUNT" ] || EZARR_ENV_CPU_COUNT=0

    # Espacio en el destino de datos (/data en Android, /var en maquina normal).
    local probe="${EZARR_DATA_ROOT:-/data}"
    if [ ! -d "$probe" ]; then probe="/"; fi
    EZARR_ENV_DATA_ROOT="$probe"
    EZARR_ENV_DISK_FREE_MB="$(ezarr_disk_free_mb "$probe")"
    return 0
}

# Espacio libre en MB del sistema de ficheros que contiene $1.
# Siempre devuelve 0: con `set -e`, una asignacion como `x="$(df ...)"` cuyo
# comando falla ABORTA el script entero. Un dato ausente debe ser un 0, no un
# final Fulminante en mitad de un diagnostico.
ezarr_disk_free_mb() {
    local dir="$1" out=""
    [ -d "$dir" ] || dir="/"
    out="$(df -Pm "$dir" 2>/dev/null | awk 'NR==2 {print $4; exit}')" || out=""
    case "$out" in ''|*[!0-9]*) out=0 ;; esac
    printf '%s' "$out"
    return 0
}

# ------------------------------------------------------ herramientas comunes --
# tool_path <nombre> [alternativas...] — imprime la ruta o nada.
# Se usa para TODO lo que el instalador necesita: si no esta, se dice que falta
# y se da el paquete, en vez de fallar 200 lineas mas abajo.
tool_path() {
    local t
    for t in "$@"; do
        if command -v "$t" >/dev/null 2>&1; then
            command -v "$t"
            return 0
        fi
        # En el chroot el PATH de Android puede no incluir /opt/... ni /usr/local/bin
        for d in /usr/local/bin /usr/bin /bin /usr/sbin /sbin /opt/bin; do
            if [ -x "$d/$t" ]; then printf '%s\n' "$d/$t"; return 0; fi
        done
    done
    return 1
}

have() { tool_path "$@" >/dev/null 2>&1; }

# --------------------------------------------------------------- red y DNS --
# El chroot arranca a veces sin resolv.conf valido, y detectarlo ANTES de
# descargar nada: si no, el fallo sale en el paso 5 como "no se pudo descargar",
# que no dice nada de la causa.
#
# Tres comprobaciones, y solo la ultima DECIDE:
#   1. DNS. Sin nombres no hay descarga aunque haya salida: pesa mas que el TCP.
#   2. Salida por IP. No decide, pero distingue "no hay red" de "no hay nombres".
#   3. Una peticion HTTP de verdad, por el proxy y el TLS que usara el paso 5.
# Y ninguna contra un dominio de este proyecto: la comprobacion tiene que
# seguir siendo valida cuando el dominio no existe todavia, que es el caso
# normal hasta que haya una release publicada.
ezarr_network_ok() {
    [ "${EZARR_OFFLINE:-0}" = "1" ] && return 0
    local t="${EZARR_NET_TIMEOUT:-8}" host
    EZARR_NET_WHY=""
    host="$(printf '%s' "${EZARR_RELEASE_BASE:-https://packages.example.com}" | sed -e 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||' -e 's|/.*$||')"

    # 1. DNS del host de descarga.
    if ! { have getent && getent hosts "$host" >/dev/null 2>&1; }; then
        EZARR_NET_WHY="$host no resuelve (revisa /etc/resolv.conf)"
    fi

    # 2. Salida a internet por IP, sin depender del DNS ni del proxy.
    if ! timeout "$t" bash -c "exec 3<>/dev/tcp/${EZARR_NET_PROBE_IP:-1.1.1.1}/443" 2>/dev/null; then
        EZARR_NET_WHY="${EZARR_NET_WHY:+$EZARR_NET_WHY; }sin salida TCP a ${EZARR_NET_PROBE_IP:-1.1.1.1}:443"
    fi

    # 3. La pregunta que importa: se puede bajar algo. Primero un endpoint neutro
    # de conectividad y, si tampoco responde, el host real de la descarga, que
    # es el ultimo recurso porque es el unico que prueba el camino completo.
    if ezarr_http_ok "${EZARR_NET_PROBE_URL:-https://connectivitycheck.gstatic.com/generate_204}" "$t" \
    || ezarr_http_ok "$host" "$t"; then
        return 0
    fi
    EZARR_NET_WHY="${EZARR_NET_WHY:+$EZARR_NET_WHY; }ninguna peticion HTTP responde"
    return 1
}

# Un GET a $1 con el timeout $2. 0 si hay respuesta HTTP de verdad (2xx/3xx).
ezarr_http_ok() {
    local url="$1" t="${2:-8}"
    if have curl; then
        curl -fsS -m "$t" -o /dev/null "$url" 2>/dev/null
    elif have wget; then
        wget -q -T "$t" -O /dev/null "$url" 2>/dev/null
    else
        return 1
    fi
}

# --------------------------------------------------------------- temporales --
# mktemp con capacidad de decision: en un telefono con poco sitio, fallar aqui
# con un mensaje claro es mejor que reventar a mitad de una descarga.
ezarr_mktemp() {
    local t
    t="$(mktemp "${TMPDIR:-/tmp}/ezarr.XXXXXXXX" 2>/dev/null)" || return 1
    printf '%s\n' "$t"
}

ezarr_cleanup_tmp() {
    local f
    for f in "${EZARR_TMPFILES[@]:-}"; do
        [ -n "$f" ] && rm -f "$f" 2>/dev/null || true
    done
    return 0
}

# --------------------------------------------------------------- privilegios --
ezarr_is_root() { [ "$(id -u 2>/dev/null || echo 1000)" = "0" ]; }

# Reintento con sudo. En el chroot casi siempre se es root ya; en un desktop no.
# Se comprueba primero: pedir sudo para algo que no lo necesita es ruido.
ezarr_need_root() {
    local what="${1:-esta operacion}"
    ezarr_is_root && return 0
    log_error "$what requiere privilegios de root"
    if have sudo; then
        log_error_hint "reintenta con sudo, o ejecuta el instalador como root"
    else
        log_error_hint "no hay sudo en este sistema: ejecuta como root"
    fi
    ezarr_exit "${EZARR_EX_PERM:-7}"
}

# --------------------------------------------------- resumen legible del env --
ezarr_env_summary() {
    local kind init_desc
    case "$EZARR_ENV_KIND" in
        chroot)   kind="chroot de telefono${EZARR_ENV_TWRP:+ (TWRP)}" ;;
        machine)  kind="maquina normal" ;;
        *)        kind="desconocido" ;;
    esac
    case "$EZARR_ENV_INIT" in
        systemd) init_desc="systemd" ;;
        sysv)    init_desc="sysvinit" ;;
        *)       init_desc="sin init (cron + arr-stack)" ;;
    esac

    printf 'entorno     %s\n'      "$kind"   >&2
    printf 'arquitectura %s (%s)\n' "${EZARR_ENV_ARCH:-?}" "${EZARR_ENV_CPU_COUNT:-?} nucleos" >&2
    printf 'memoria     %s MB\n'   "${EZARR_ENV_RAM_MB:-?}" >&2
    printf 'datos       %s (%s MB libres)\n' "${EZARR_ENV_DATA_ROOT:-?}" "${EZARR_ENV_DISK_FREE_MB:-?}" >&2
    printf 'servicios   %s\n'      "$init_desc" >&2
    return 0
}

# -------------------------------------------------- marcadores del entorno ----
# El instalador escribe $EZARR_CONF_DIR/chroot.marker para que la deteccion no
# dependa de heuristicas en la siguiente ejecucion (y para saber donde vive el
# rootfs). La ruta sale de $EZARR_CONF_DIR y no de /etc/ezarr escrito a fuego:
# con el directorio cambiado, un marcador en la ruta por defecto lo escribiria
# donde el resto de la configuracion no esta y nadie lo leeria.
ezarr_write_env_marker() {
    local marker="${EZARR_CONF_DIR:-/etc/ezarr}/chroot.marker"
    # Por el envoltorio fs_*, y no por ezarr_fs_write: ese nombre no existe en
    # ningun sitio (los envoltorios son fs_write/fs_mkdir/... en lib/plan.sh) y,
    # sobre todo, solo fs_* pasa la auditoria de dry-run, que comprueba que EZARR_
    # FS_PERFORMED se queda en 0 cuando EZARR_DRY_RUN=1.
    if command -v fs_write >/dev/null 2>&1; then
        fs_write "$marker" "MOUNTPOINT=${EZARR_ENV_ROOTFS_MNT:-}
KIND=${EZARR_ENV_KIND}
ARCH=${EZARR_ENV_ARCH}
WRITTEN=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
" 0644
        return $?
    fi
    # ezarrctl no carga lib/plan.sh: ahi no hay envoltorios y no se esta
    # instalando nada, asi que no hay mutacion que auditar.
    mkdir -p -- "$(dirname -- "$marker")" 2>/dev/null || return 1
    printf 'MOUNTPOINT=%s\nKIND=%s\nARCH=%s\nWRITTEN=%s\n' \
        "${EZARR_ENV_ROOTFS_MNT:-}" "${EZARR_ENV_KIND:-}" "${EZARR_ENV_ARCH:-}" \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$marker"
}

# Chroot con celdas de 7 GB: el umbral no es arbitrario, es donde Jellyfin + el
# stack *arr + qBittorrent empiezan a pelearse por la memoria.
ezarr_ram_is_tight() {
    local need="${EZARR_MIN_RAM_MB:-5120}"
    [ "${EZARR_ENV_RAM_MB:-0}" -lt "$need" ]
}

ezarr_disk_is_tight() {
    local need="${EZARR_MIN_DISK_MB:-8192}"
    [ "${EZARR_ENV_DISK_FREE_MB:-0}" -lt "$need" ]
}