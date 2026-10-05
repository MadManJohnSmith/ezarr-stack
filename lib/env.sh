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

    local pid1; pid1="$(ezarr_pid1_comm)"

    # --- Android como host ---------------------------------------------------
    # TWRP deja /tmp/TWRP y escribe su version en /tmp/recovery/version.
    if [ -d /tmp/TWRP ] || [ -f /tmp/recovery/version ] || [ -f /tmp/twrp ]; then
        EZARR_ENV_TWRP=1
        EZARR_ENV_ANDROID=1
    fi
    # Un Android vivo con ADB tambien se reconoce por /system/build.prop.
    if [ -f /system/build.prop ] && [ -d /data/local/tmp ]; then
        EZARR_ENV_ANDROID=1
    fi
    # Host Android sin TWRP: puede quedar rastro en /proc/version o en /metadata.
    if [ -d /metadata ] || [ -f /proc/config.gz.ghost ]; then
        EZARR_ENV_ANDROID=1
    fi

    # --- chroot --------------------------------------------------------------
    # Tres senales independientes, porque ninguna sola es concluyente:
    #   1. marcador explicito que escribe el propio instalador
    #   2. PID 1 no es systemd/init del host -> namespace de otro initfs
    #   3. la raiz "/" y la raiz de PID 1 son el mismo inodo (chroot, no container)
    local chroot=0
    if [ -f /etc/ezarr/chroot.marker ]; then
        chroot=1
        EZARR_ENV_ROOTFS_MNT="$(sed -n 's/^MOUNTPOINT=//p' /etc/ezarr/chroot.marker 2>/dev/null | head -n1)"
    fi
    if [ "$chroot" -eq 0 ] && [ "$pid1" != "systemd" ] && [ "$pid1" != "init" ]; then
        # busybox-init (TWRP) o el propio init del chroot arrancado con chroot+unshare.
        case "$pid1" in
            busybox|sh|*android*|*survival*|*init*|/sbin/init) chroot=1 ;;
            *) : ;;
        esac
    fi
    if [ "$chroot" -eq 1 ]; then EZARR_ENV_KIND="chroot"; else EZARR_ENV_KIND="machine"; fi

    # --- init / gestor de servicios -----------------------------------------
    # El stack no usa systemd en el chroot: se gobierna con arr-stack + cron.
    if [ -d /run/systemd/system ] && [ "$pid1" = "systemd" ]; then
        EZARR_ENV_INIT="systemd"
    elif [ -x /usr/sbin/service ] && [ -d /etc/init.d ]; then
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
# El chroot arranca a veces sin resolv.conf valido (arr-stack lo parchea con
# 1.1.1.1). Detectar eso ANTES de descargar nada evita un fallo confuso.
ezarr_network_ok() {
    [ "${EZARR_OFFLINE:-0}" = "1" ] && return 0
    if have curl; then
        curl -fsS -m "${EZARR_NET_TIMEOUT:-8}" -o /dev/null "https://stack.example.com/" 2>/dev/null && return 0
    elif have wget; then
        wget -q -T "${EZARR_NET_TIMEOUT:-8}" -O /dev/null "https://stack.example.com/" 2>/dev/null && return 0
    fi
    return 1
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
# El instalador escribe /etc/ezarr/chroot.marker para que la deteccion no dependa
# de heuristicas en la siguiente ejecucion (y para saber donde vive el rootfs).
ezarr_write_env_marker() {
    local marker="/etc/ezarr/chroot.marker"
    ezarr_fs_write "$marker" "MOUNTPOINT=${EZARR_ENV_ROOTFS_MNT:-}
KIND=${EZARR_ENV_KIND}
ARCH=${EZARR_ENV_ARCH}
WRITTEN=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
" 0644
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