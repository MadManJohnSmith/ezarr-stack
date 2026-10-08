# shellcheck shell=bash
# lib/secrets.sh — los secretos del stack, en un solo sitio y sin que nadie
# tenga que abrir un editor con chmod 600 delante.
#
# Que hay aqui y por que existe:
#
#   * Un unico fichero (secrets.conf) para TODO lo que es credencial. Antes de
#     esto la contraseña de la camara vivia dentro de la URL del RTSP y el
#     token de Healthchecks en otro fichero, de modo que "configurar el stack"
#     era buscar el fichero cierto. Un sitio, una tabla, un comando.
#   * `ezarrctl secrets set` pregunta sin eco y escribe con modo 600. Nadie
#     tiene que recordar el chmod ni acordarse de dejar las comillas.
#   * `ezarrctl secrets doctor` dice que falta y que hacer, sin imprimir jamas
#     un valor. El fallo tipico al que apuntan estos comandos es "no me llega
#     el aviso", y la causa casi siempre es un secreto sin poner o con el valor
#     de ejemplo sin cambiar.
#
# Los valores NUNCA se imprimen: ni en list, ni en doctor, ni en un error. Solo
# el nombre de la clave y si esta puesta o no.

# ---------------------------------------------------------- el catalogo ----
# Formato: CLAVE|obligatorio|para que sirve. Es la unica lista de verdad: la
# usan init (que plantilla escribe), list (que muestra) y doctor (que exige).
# Anadir un secreto aqui es todo lo que hay que hacer para que los tres lo
# conozcan: plantilla, tabla y aviso de "falta" salen de esta misma lista.
ezarr_secrets_catalogue() {
    cat <<'CAT'
EZARR_CAMERA_RTSP_PASS|si|password del RTSP de la camara (usuario y contrasena del aparato)
EZARR_NTFY_TOPIC|si|topic de ntfy donde llegan los avisos del telefono
EZARR_HC_PING_URL|no|URL de Healthchecks.io: avisa si el watchdog deja de dar pings
RCLONE_REMOTE|no|nombre del remoto de rclone con tu Drive (se crea con `rclone config`)
EZARR_CF_TUNNEL_TOKEN|no|token del tunel de Cloudflare, si no usas un tunel con nombre
EZARR_SUBS_API_KEY|no|clave de OpenSubtitles o SubDL para los subtitulos de Bazarr
EZARR_TAILSCALE_AUTHKEY|no|auth key de Tailscale para unirse al tailnet sin tocar el teclado
CAT
}

# Valores de ejemplo que se cuelan al copiar la plantilla. Un secreto puesto en
# "su valor de ejemplo" esta tan sin configurar como ausente, pero es mucho mas
# dificil de ver, asi que doctor lo trata como falta.
#
# Se comparan por patron y no por igualdad exacta porque el caso tipico es
# "topic-de-prueba-123": alguien prueba, se le olvida cambiarlo y el push le
# llega a un topic que no es el suyo. Con igualdad exacta eso pasaba como
# configurado.
ezarr_secrets_placeholder() {
    case "$1" in
        ''|192.168.1.10|127.0.0.1|localhost) return 0 ;;
        *CAMBIAME*|*TU-*|*topic-de-prueba*|*pong-aqui*|*changeme*|*placeholder*) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------- rutas -------
ezarr_secrets_file() { printf '%s/secrets.conf' "${EZARR_CONF_DIR:-/etc/ezarr}"; }
ezarr_secrets_sample() { printf '%s/etc/ezarr/secrets.conf.sample' "${EZARR_ROOT:-.}"; }

# _secrets_field <fichero> <CLAVE>
# Devuelve el valor crudo de una clave del fichero de secretos. Parser propio y
# minimo a proposito: el de lib/config.sh es para leer y este para escribir, y
# aqui importa mas no execear nada de lo que hay en el fichero.
_secrets_field() {
    local file="$1" key="$2" line
    [ -r "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$key="*) printf '%s' "${line#*=}"; return 0 ;;
        esac
    done < "$file"
    return 1
}

_secrets_key_exists() {
    local key="$1" k
    while IFS='|' read -r k _ _; do
        [ "$k" = "$key" ] && return 0
    done <<< "$(ezarr_secrets_catalogue)"
    return 1
}

# ------------------------------------------------------- init --------------
# Escribe secrets.conf desde la plantilla, conservando los valores que ya
# estaban puestos. Refusar a sobrescribir sin --force es lo que evita que un
# `secrets init` sin querer borre la configuracion de credenciales de alguien.
ezarr_secrets_init() {
    local force=0 f sample tmp
    [ "${1:-}" = "--force" ] && force=1
    f=$(ezarr_secrets_file)
    sample=$(ezarr_secrets_sample)
    if [ -e "$f" ] && [ "$force" -ne 1 ]; then
        log_error "$f ya existe"
        log_error_hint "usa 'ezarrctl secrets init --force' si de verdad quieres regenerarlo (conserva los valores puestos)"
        return 1
    fi
    [ -r "$sample" ] || { log_error "no encuentro la plantilla $sample"; return 1; }
    tmp="${f}.new.$$"
    cp "$sample" "$tmp" || return 1
    chmod 600 "$tmp" || return 1
    # Conserva lo que ya estaba: si el fichero viejo tenia un valor puesto y la
    # plantilla tiene el valor de ejemplo, gana el viejo.
    if [ -r "$f" ]; then
        local key value
        while IFS='|' read -r key _ _; do
            [ -n "$key" ] || continue
            value=$(_secrets_field "$f" "$key" 2>/dev/null || true)
            [ -n "$value" ] || continue
            ezarr_secrets_placeholder "$value" && continue
            _secrets_write_line "$tmp" "$key" "$value" || return 1
        done <<< "$(ezarr_secrets_catalogue)"
    fi
    mv "$tmp" "$f" || return 1
    chmod 600 "$f"
    log_ok "escrito $f (modo 600)"
    return 0
}

# _secrets_write_line <fichero> <CLAVE> <valor>
# Escribe in situ: quita la linea si existe y pone la nueva al final, que es lo
# unico que hace falta para un fichero KEY=valor sin logica dentro.
_secrets_write_line() {
    local file="$1" key="$2" value="$3" tmp
    tmp="${file}.tmp.$$"
    grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    cat "$tmp" > "$file"     # mismo inode: quien lo tenga abierto sigue escribiendo aqui
    rm -f "$tmp"
    chmod 600 "$file"
}

# --------------------------------------------------------- set / unset -----
# El valor se pide con `read -s` (sin eco) y se acepta como argumento solo para
# scripting; el propio mensaje avisa de que un argumento queda en el historial
# del shell, que es el motivo de que la forma normal sea la del prompt.
ezarr_secrets_set() {
    local key="${1:-}" value="${2:-}" f
    if [ -z "$key" ]; then
        log_error "que clave? mira 'ezarrctl secrets list'"
        return 2
    fi
    _secrets_key_exists "$key" || { log_error "clave desconocida: $key"; log_error_hint "las de verdad estan en 'ezarrctl secrets list'"; return 2; }
    f=$(ezarr_secrets_file)
    [ -e "$f" ] || ezarr_secrets_init >/dev/null 2>&1
    if [ -z "$value" ]; then
        printf '  %s (sin eco): ' "$key" >&2
        read -rs value </dev/tty 2>/dev/null || read -rs value
        printf '\n' >&2
        if [ -z "$value" ]; then
            log_error "vacio: no se cambia nada"
            return 1
        fi
    else
        log_warn "el valor que pasas como argumento queda en el historial del shell"
    fi
    _secrets_write_line "$f" "$key" "$value" || { log_error "no pude escribir $f"; return 1; }
    log_ok "$key puesta en $f"
}

ezarr_secrets_unset() {
    local key="${1:-}" f
    _secrets_key_exists "$key" || { log_error "clave desconocida: $key"; return 2; }
    f=$(ezarr_secrets_file)
    [ -r "$f" ] || { log_error "$f no existe"; return 1; }
    _secrets_write_line "$f" "$key" ""
    log_ok "$key quitada (vacia)"
}

# ------------------------------------------------------------- list ---------
# Solo nombres y estado. El valor no sale de aqui ni con -v.
ezarr_secrets_list() {
    local f key req desc value state
    f=$(ezarr_secrets_file)
    printf '  %-26s %-9s %s\n' "CLAVE" "ESTADO" "PARA QUE SIRVE"
    while IFS='|' read -r key req desc; do
        [ -n "$key" ] || continue
        value=$(_secrets_field "$f" "$key" 2>/dev/null || true)
        if [ -z "$value" ]; then
            state=$([ "$req" = si ] && echo "falta*" || echo "falta")
        elif ezarr_secrets_placeholder "$value"; then
            state="ejemplo*"
        else
            state="puesta"
        fi
        printf '  %-26s %-9s %s\n' "$key" "$state" "$desc"
    done <<< "$(ezarr_secrets_catalogue)"
    printf '\n  * es obligatoria: sin ella el stack funciona a medias y no te avisa de nada\n'
}

# ----------------------------------------------------------- doctor ---------
# Cuenta los problemas en EZARR_CRED_PROBLEMS y devuelve 1 si hay alguno.
# Devolver el numero por stdout no vale: este comando escribe sus avisos por ahi
# y un numero suelto al final de la salida no lo distingue nadie de un mensaje.
# Lo usan 'secrets doctor' y el 'doctor' del stack entero, que es donde de
# verdad duele: por un secreto sin poner no llega ni el aviso ni la copia a Drive.
ezarr_secrets_doctor() {
    local f key req desc value mode="" perms
    EZARR_CRED_PROBLEMS=0
    [ "${1:-}" = "--fix" ] && mode=fix
    f=$(ezarr_secrets_file)
    if [ ! -e "$f" ]; then
        log_error "no existe $f: los secretos no estan configurados"
        log_error_hint "ezarrctl secrets init"
        EZARR_CRED_PROBLEMS=1
        return 1
    fi
    perms=$(stat -c '%a' "$f" 2>/dev/null || echo '?')
    case "$perms" in
        600) log_info "secrets.conf en 600" ;;
        *)
            log_warn "secrets.conf en $perms: cualquier cuenta del sistema puede leerlo"
            log_warn_hint "chmod 600 $f"
            if [ "$mode" = fix ]; then
                chmod 600 "$f" 2>/dev/null && log_ok "arreglado: 600"
            else
                EZARR_CRED_PROBLEMS=$((EZARR_CRED_PROBLEMS + 1))
            fi
            ;;
    esac
    while IFS='|' read -r key req desc; do
        [ -n "$key" ] || continue
        value=$(_secrets_field "$f" "$key" 2>/dev/null || true)
        if [ -z "$value" ]; then
            [ "$req" = si ] || { log_info "$key sin poner (opcional)"; continue; }
            log_warn "$key falta y es obligatoria: $desc"
            log_warn_hint "ezarrctl secrets set $key"
            EZARR_CRED_PROBLEMS=$((EZARR_CRED_PROBLEMS + 1))
            continue
        fi
        if ezarr_secrets_placeholder "$value"; then
            log_warn "$key tiene el valor de ejemplo, no el tuyo: $desc"
            log_warn_hint "ezarrctl secrets set $key"
            EZARR_CRED_PROBLEMS=$((EZARR_CRED_PROBLEMS + 1))
        fi
    done <<< "$(ezarr_secrets_catalogue)"
    [ "$EZARR_CRED_PROBLEMS" -eq 0 ]
}
