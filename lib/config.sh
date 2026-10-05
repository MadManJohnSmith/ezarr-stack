#!/bin/bash
# lib/config.sh — Configuracion leida de ARCHIVO, no fija en el codigo.
#
# Principio: un valor que depende de la instalacion (topic de ntfy, IP de la
# camara, claves de las apps, URL de Healthchecks) no se escribe en un script.
# Vive en /etc/ezarr/*.conf y se lee al arrancar.
#
# Decisiones que importan:
#
#   1. El fichero NO se hace `source`. El codigo real del stack lo hace
#      (`[ -f "$CONF" ] && . "$CONF"`), pero un `source` de un fichero que
#     anyone pueda escribir es ejecucion de codigo arbitrario. Aqui se parsea
#      linea a linea y SOLO se acepta `NOMBRE=valor`. Cualquier otra cosa se
#      ignora en silencio (con aviso en -v). Es la diferencia entre "configurar"
#      y "abrir una puerta".
#
#   2. Precedencia, de menor a mayor:
#        valor por defecto  <  /etc/ezarr/ezarr.conf
#        <  ~/.config/ezarr/ezarr.conf  <  entorno EZARR_*  <  flags
#      El usuario siempre puede ganar desde donde le sea comodo.
#
#   3. Sin credenciales reales en ningun fichero del repo publico: las
#      plantillas van en etc/ezarr/*.conf.sample con placeholders.

EZARR_CONF_DIR="${EZARR_CONF_DIR:-/etc/ezarr}"
EZARR_CONF_USER="${EZARR_CONF_USER:-${XDG_CONFIG_HOME:-$HOME/.config}/ezarr/ezarr.conf}"

# Ficheros que se cargan en este orden (todos opcionales).
#
# Se derivan de EZARR_CONF_DIR y no llevan /etc/ezarr escrito dentro a proposito:
# el instalador ESCRIBE en $EZARR_CONF_DIR (lib/stack.sh) y aqui se LEE. Si las
# dos rutas no salieran de la misma variable, una instalacion con el directorio
# cambiado escribiria una configuracion que nadie leeria nunca.
EZARR_CONF_FILES=(
    "${EZARR_CONF_DIR}/ezarr.conf"        # sistema: topics, IPs, red
    "${EZARR_CONF_DIR}/apps.conf"         # sistema: claves de las apps
    "${EZARR_CONF_DIR}/healthchecks.conf" # sistema: dead-man switch
    "${EZARR_CONF_USER}"                  # usuario: overrides locales
)

# ------------------------------------------------------- parser sin source --
# _conf_parse_file <ruta>
# Acepta unicamente lineas `NOMBRE=valor` con NOMBRE en [A-Z0-9_].
# Ignora comentarios, lineas en blanco y cualquier otra cosa.
_conf_parse_file() {
    local file="$1" line name value
    [ -r "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        # fuera comentarios y lineas en blanco
        case "$line" in ''|'#'*) continue ;; esac
        # solo `NOMBRE=valor`
        case "$line" in
            [A-Z0-9_]*=*) : ;;
            *) log_trace "config: linea ignorada (no es NOMBRE=valor) en $file: $line"; continue ;;
        esac
        name="${line%%=*}"
        # valida el nombre: solo A-Z 0-9 _
        if ! printf '%s' "$name" | grep -qE '^[A-Z0-9_]+$'; then
            log_trace "config: nombre invalido ignorado en $file: $name"
            continue
        fi
        value="${line#*=}"
        # quita comillas envolventes si las hay
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        # evita smuggling de comandos en el valor
        case "$value" in *'$('*|*'`'*) log_trace "config: valor con sustitucion rechazado en $file: $name"; continue ;; esac
        printf -v "$name" '%s' "$value"
        EZARR_CONF_LOADED+=("$name=$file")
    done < "$file"
    return 0
}

# ------------------------------------------------------------- carga y api --
# ezarr_config_load — lee todos los ficheros y aplica el entorno como override.
ezarr_config_load() {
    EZARR_CONF_LOADED=()
    declare -gA EZARR_ENV_OVERRIDE=()

    # La lista se RECONSTRUYE aqui, no se usa la que se construyo al cargar el
    # fichero. `--set EZARR_CONF_DIR=/opt/ezarr` se aplica despues de que este
    # fichero se sourceara; si la lista fuera la del principio, el instalador
    # escribiria en /opt/ezarr y leeria de /etc/ezarr, que es la mitad del
    # sistema creyendo que tiene configuracion y sin ella.
    EZARR_CONF_FILES=(
        "${EZARR_CONF_DIR}/ezarr.conf"
        "${EZARR_CONF_DIR}/apps.conf"
        "${EZARR_CONF_DIR}/healthchecks.conf"
        "${EZARR_CONF_USER}"
    )

    # 1) entorno: se captura ANTES de leer ficheros. Solo escalares: un array
    #    llamado EZARR_COMPONENTS NO es un override, y expandido dentro de un
    #    `eval` se ejecutaria como comando. Ese fallo seebugueo aqui.
    local n decl
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        case "$n" in EZARR_ENV_OVERRIDE) continue ;; esac
        decl="$(declare -p "$n" 2>/dev/null || true)"
        case "$decl" in
            'declare -a'*|'declare -A'*|'declare -[aA][aA]') continue ;;
        esac
        EZARR_ENV_OVERRIDE["${n#EZARR_}"]="${!n}"
    done < <(compgen -v 2>/dev/null | grep '^EZARR_' || true)

    # 2) ficheros, en orden
    local f
    for f in "${EZARR_CONF_FILES[@]}"; do
        [ -r "$f" ] || continue
        log_debug "config: leyendo $f"
        _conf_parse_file "$f"
    done

    # 3) el entorno gana: se re-aplica encima de lo leido
    local k
    for k in "${!EZARR_ENV_OVERRIDE[@]}"; do
        printf -v "EZARR_$k" '%s' "${EZARR_ENV_OVERRIDE[$k]}"
        log_trace "config: entorno gana para EZARR_$k"
    done

    EZARR_CONFIG_LOADED=1
    return 0
}

# ezarr_conf_get <NOMBRE> [defecto]
ezarr_conf_get() {
    local name="$1" default="${2:-}"
    local v="${!name:-}"
    if [ -z "$v" ]; then printf '%s' "$default"; return 0; fi
    printf '%s' "$v"
}

# ezarr_conf_require <NOMBRE> [remedio...]
# Si falta un valor obligatorio, error con remedio. Nunca un valor inventado.
ezarr_conf_require() {
    local name="$1"; shift
    local v="${!name:-}"
    if [ -n "$v" ]; then return 0; fi
    log_error "falta la variable de configuracion $name"
    log_error_hint "define $name en $EZARR_CONF_DIR/ezarr.conf (copia etc/ezarr/ezarr.conf.sample)"
    local hint
    for hint in "$@"; do log_error_hint "$hint"; done
    ezarr_exit "${EZARR_EX_CONFLICT:-4}"
}

# ezarr_conf_list — volca la configuracion efectiva. `doctor` lo usa.
ezarr_conf_list() {
    local n
    for n in EZARR_NTFY_TOPIC EZARR_NTFY_URL EZARR_CAMERA_RTSP EZARR_CAMERA_IP \
             EZARR_HEALTHCHECKS_URL EZARR_SONARR_API_KEY EZARR_RADARR_API_KEY \
             EZARR_PROWLARR_API_KEY EZARR_JELLYFIN_API_KEY EZARR_QBIT_USER \
             EZARR_QBIT_PASS EZARR_DATA_ROOT EZARR_TIMEZONE; do
        local v="${!n:-}"
        # Las claves NUNCA se imprimen en claro, ni en -vvv.
        case "$n" in
            *API_KEY|*PASS) if [ -n "$v" ]; then v="(definida, ${#v} chars)"; else v="(sin definir)"; fi ;;
            EZARR_QBIT_USER) if [ -n "$v" ]; then v="(definido)"; else v="(sin definir)"; fi ;;
        esac
        printf '%-26s %s\n' "$n" "${v:-<vacio>}"
    done
}

# ------------------------------------------------------------- perfiles ----
# Perfil = un punto de partida para el conjunto de componentes. El usuario puede
# siempre('--with' / '--without') partir de donde quiera.
ezarr_conf_defaults() {
    : "${EZARR_TIMEZONE:=$(ezarr_detect_timezone)}"
    : "${EZARR_DATA_ROOT:=/data}"
    : "${EZARR_STATE_DIR:=/var/lib/ezarr}"
    : "${EZARR_LOG_DIR:=/var/log/arr}"
    : "${EZARR_BACKUP_DIR:=/var/backups/ezarr}"
    : "${EZARR_BIN_DIR:=/usr/local/bin}"
    : "${EZARR_NTFY_SERVER:=https://ntfy.sh}"
    : "${EZARR_PROFILE:=standard}"
    : "${EZARR_CHANNEL:=stable}"
    : "${EZARR_MIN_RAM_MB:=5120}"
    : "${EZARR_MIN_DISK_MB:=8192}"
    return 0
}

ezarr_detect_timezone() {
    # /etc/localtime como symlink es el metodo fiable. Si no lo es, el offset
    # UTC del kernel es una aproximacion que al menos no revienta.
    if [ -L /etc/localtime ]; then
        readlink -f /etc/localtime 2>/dev/null | sed 's|^.*/zoneinfo/||'
        return 0
    fi
    if [ -r /etc/timezone ]; then head -n1 /etc/timezone; return 0; fi
    date +%Z
}