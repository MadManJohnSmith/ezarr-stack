#!/bin/bash
# lib/stack.sh — Registro de servicios y pasos de instalacion por componente.
#
# El chroot del telefono NO tiene systemd. Todo se gobierna con arr-stack +
# cron: un `case` por servicio que lanza el proceso, y un `pgrep` que decide si
# esta vivo. Este modulo es el unico sitio donde se sabe como arranca y como se
# comprueba cada cosa, para que ezarr.sh y ezarrctl no se dupliquen.
#
# Formato del registro:  id|componente|puerto|patron_pgrep|descripcion
# El patron se usa con `pgrep -f`, que es lo que de verdad distingue a los
# binarios: `sonarr` como nombre de proceso tambien lo lleva un `grep` nuestro.

EZARR_SERVICES=(
  "cron|core|-|cron|servicio de programacion (tareas de mantenimiento)"
  "redis|core|-|redis-server|cache para Homarr y los *arr"
  "avahi|core|-|avahi-daemon|resolucion mDNS: http://ezarr.local"
  "jellyfin|media|8096|/usr/bin/jellyfin|reproductor de peliculas, series y musica"
  "qbittorrent|downloads|8081|qbittorrent-nox|descargas BitTorrent (interfaz web)"
  "prowlarr|downloads|9696|/opt/Prowlarr/Prowlarr|proxy de indexadores"
  "jackett|downloads|9117|jackett|indexadores directos (alternativa a Prowlarr)"
  "sonarr|arr|8989|/opt/Sonarr/Sonarr|descarga y organiza series"
  "radarr|arr|7878|/opt/Radarr/Radarr|descarga y organiza peliculas"
  "bazarr|subs|6767|bazarr|subtitulos para la media"
  "homarr|dashboard|7575|next-server|panel web de acceso a los servicios"
  "motion|camera|8554|motion -c|deteccion de movimiento y grabacion (camara IP)"
  "cloudflared|remote|7844|cloudflared tunnel|tunel HTTPS de salida (sin abrir puertos)"
  "tailscale|remote|41641|tailscaled|acceso remoto por VPN mesh"
  "nginx|reverse|80,443|nginx: master|proxy inverso y terminacion TLS"
  "flaresolverr|search|8191|flaresolverr|puente para indexadores con anti-bot"
  "rclone|storage|-|rclone --config|sincronizacion con Google Drive"
  "mergerfs|storage|-|mergerfs.fuse|union de biblioteca local y Drive"
)

# ezarr_service_field <id> <2..5>
# Siempre devuelve 0 (vacio si no existe el servicio). Mismo motivo que
# ezarr_disk_free_mb: con `set -e`, devolver 1 aqui mata el script entero en
# vez de dejar que quien llama decida que hacer con un dato ausente.
ezarr_service_field() {
    local id="$1" n="$2" row
    for row in "${EZARR_SERVICES[@]}"; do
        if [ "${row%%|*}" = "$id" ]; then
            printf '%s' "$row" | cut -d'|' -f"$n" || true
            return 0
        fi
    done
    return 0
}

ezarr_service_ids() { local r; for r in "${EZARR_SERVICES[@]}"; do printf '%s\n' "${r%%|*}"; done; }

ezarr_services_for_component() {
    local c="$1" row
    for row in "${EZARR_SERVICES[@]}"; do
        [ "$(printf '%s' "$row" | cut -d'|' -f2)" = "$c" ] && printf '%s\n' "${row%%|*}"
    done
}

ezarr_service_installed() {
    local svc="$1" pat; pat="$(ezarr_service_field "$svc" 4)"
    [ -n "$pat" ] || return 1
    pgrep -f "$pat" >/dev/null 2>&1
}

# ------------------------------------------------- salud de un servicio -----
# Debe funcionar cuando la instalacion esta ROTA: por eso no consulta systemd
# (que en el chroot no existe) sino el proceso real y el puerto real.
# Imprime:  ok | dead | port-closed | unknown
ezarr_service_state() {
    local svc="$1" pat port
    pat="$(ezarr_service_field "$svc" 4)"
    [ -n "$pat" ] || { echo unknown; return 1; }
    if ! pgrep -f "$pat" >/dev/null 2>&1; then echo dead; return 1; fi
    port="$(ezarr_service_field "$svc" 3)"
    case "$port" in -|''|'80,443'|'41641'|'7844') echo ok; return 0 ;; esac
    if ezarr_port_open 127.0.0.1 "$port"; then echo ok; return 0; fi
    echo port-closed; return 1
}

# Puerto TCP abierto en localhost. /dev/tcp es de bash y no necesita netcat,
# que en un chroot minimo no suele estar.
ezarr_port_open() {
    local host="$1" port="$2"
    timeout "${EZARR_PORT_TIMEOUT:-2}" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null
}

ezarr_service_pid() {
    local svc="$1" pat; pat="$(ezarr_service_field "$svc" 4)"
    [ -n "$pat" ] || return 1
    pgrep -f "$pat" 2>/dev/null | head -n1
}

# ------------------------------------------------- arranque / parada --------
# Delegado en arr-stack: una sola implementacion de "como se levanta esto".
# Si arr-stack no esta instalado (instalacion parcial), se dice en vez de
# fingir que se hizo algo.
ezarr_service_action() {  # <start|stop|restart> <svc>
    local action="$1" svc="$2"
    local stack="${EZARR_STACK_BIN:-/usr/local/bin/arr-stack}"
    if [ ! -x "$stack" ]; then
        log_error "arr-stack no esta instalado: no se puede $action '$svc'"
        log_error_hint "instala el componente 'core' o ejecuta: ezarr.sh --only core"
        return "${EZARR_EX_NOTINST:-3}"
    fi
    "$stack" "$action" "$svc"
}

# ================================================== PASOS DE INSTALACION =====
# Cada par plan_/apply_ es puro/mutable respectivamente. Ver lib/plan.sh.

# --- 1. requisitos -------------------------------------------------------
plan_requisitos() {
    local problems=0

    if ! ezarr_is_root && [ "$EZARR_DRY_RUN" != "1" ]; then
        log_warn "no eres root: habra que usar sudo para escribir en ${EZARR_DATA_ROOT}"
        if ! have sudo; then
            log_error "hace falta root y no hay sudo disponible"
            log_error_hint "ejecuta: sudo ./ezarr.sh $*"
            problems=$((problems + 1))
        fi
    fi

    # RAM. En un telefono de 7 GB con el stack completo esto no es decorativo.
    if ezarr_ram_is_tight; then
        if [ -n "${EZARR_SET[media]:-}" ] && [ -n "${EZARR_SET[arr]:-}" ]; then
            log_warn "RAM ${EZARR_ENV_RAM_MB} MB por debajo del recomendado (${EZARR_MIN_RAM_MB} MB)"
            log_warn "el stack completo incluira 'watchdogs' para que la memoria no se agote sola"
        else
            log_info "RAM ${EZARR_ENV_RAM_MB} MB: suficiente para los componentes elegidos"
        fi
    fi
    if ezarr_disk_is_tight; then
        log_warn "quedan ${EZARR_ENV_DISK_FREE_MB} MB en ${EZARR_ENV_DATA_ROOT}, se recomiendan ${EZARR_MIN_DISK_MB} MB"
        log_warn "la base de datos de Jellyfin y las descargas se quedarian sin sitio"
    fi

    if [ "${EZARR_OFFLINE:-0}" != "1" ] && ! ezarr_network_ok; then
        log_error "no hay salida a internet"
        log_error_hint "conecta el telefono a la red, o usa --offline con la cache ya descargada"
        ezarr_plan_problem "sin red no se pueden descargar los binarios" "${EZARR_EX_NETWORK:-5}"
        problems=$((problems + 1))
    fi

    [ "$problems" -eq 0 ]
}

apply_requisitos() { EZARR_STEP_DETAIL_LAST="sin escrituras (comprobacion pura)"; return 0; }

# --- 2. estructura de directorios ---------------------------------------
ezarr_dirs_list() {
    cat <<EOF
${EZARR_STATE_DIR}
${EZARR_LOG_DIR}
${EZARR_BACKUP_DIR}
${EZARR_DATA_ROOT}/ezarr
${EZARR_DATA_ROOT}/ezarr/config
${EZARR_DATA_ROOT}/ezarr/media
${EZARR_DATA_ROOT}/ezarr/downloads
EOF
    [ -n "${EZARR_SET[storage]:-}" ] && printf '%s\n' "${EZARR_DATA_ROOT}/ezarr/remote"
    [ -n "${EZARR_SET[camera]:-}" ] && printf '%s\n' "${EZARR_DATA_ROOT}/ezarr/camera"
    return 0
}

plan_directorios() {
    local d missing=0
    while IFS= read -r d; do
        [ -d "$d" ] || missing=$((missing + 1))
    done < <(ezarr_dirs_list)
    fs_plan "+ $(ezarr_dirs_list | wc -l) directorios en ${EZARR_DATA_ROOT}/ezarr"
    log_info "creando estructura de datos bajo ${EZARR_DATA_ROOT}/ezarr"
    return 0
}

apply_directorios() {
    local d
    while IFS= read -r d; do
        fs_mkdir "$d"
    done < <(ezarr_dirs_list)
    return 0
}

# --- 3. configuracion ----------------------------------------------------
# Plantillas con placeholders. Ningun secreto real en el repo publico.
ezarr_conf_files_list() {
    printf '%s\n' "${EZARR_CONF_DIR}"/ezarr.conf "${EZARR_CONF_DIR}"/apps.conf "${EZARR_CONF_DIR}"/healthchecks.conf
    [ -n "${EZARR_SET[camera]:-}" ] && printf '%s\n' "${EZARR_CONF_DIR}"/camera.conf
    return 0
}

plan_configuracion() {
    local f missing=""
    while IFS= read -r f; do
        [ -f "$f" ] || missing="$missing $(basename "$f")"
    done < <(ezarr_conf_files_list)
    if [ -n "$missing" ]; then
        log_info "a crear:$missing"
        fs_plan "~ "${EZARR_CONF_DIR}"/  ($(printf '%s' "$missing" | wc -w) ficheros nuevos)"
    else
        log_info "la configuracion ya existe: se conserva"
        fs_plan "~ "${EZARR_CONF_DIR}"/  (sin cambios)"
    fi
    return 0
}

apply_configuracion() {
    fs_mkdir "${EZARR_CONF_DIR}"
    fs_chmod 0755 "${EZARR_CONF_DIR}"

    # ezarr.conf: lo que se puede generar sin secretos.
    if [ ! -f "${EZARR_CONF_DIR}"/ezarr.conf ]; then
        fs_write "${EZARR_CONF_DIR}"/ezarr.conf "$(ezarr_render_conf)" 0644
    else
        log_v "se conserva "${EZARR_CONF_DIR}"/ezarr.conf existente"
    fi

    # apps.conf: SIN claves reales. El usuario las pega (o las pone por entorno).
    if [ ! -f "${EZARR_CONF_DIR}"/apps.conf ]; then
        fs_write "${EZARR_CONF_DIR}"/apps.conf "$(ezarr_render_apps_conf)" 0600
        log_warn ""${EZARR_CONF_DIR}"/apps.conf creado sin claves: rellenalo para que funcionen los scripts que consultan las APIs"
    else
        log_v "se conserva "${EZARR_CONF_DIR}"/apps.conf existente"
    fi

    if [ ! -f "${EZARR_CONF_DIR}"/healthchecks.conf ]; then
        fs_write "${EZARR_CONF_DIR}"/healthchecks.conf "# URL de ping de Healthchecks.io, sin /fail. Vacio = dead-man switch desactivado.
# HC_PING_URL=" 0644
    fi

    if [ -n "${EZARR_SET[camera]:-}" ] && [ ! -f "${EZARR_CONF_DIR}"/camera.conf ]; then
        local cam_body
        cam_body="$(ezarr_render_camera_conf)"
        fs_write "${EZARR_CONF_DIR}"/camera.conf "$cam_body" 0600
        log_warn "camara por defecto 192.168.1.10 (placeholder): ajustala en "${EZARR_CONF_DIR}"/camera.conf"
    fi

    local selected
    selected="$(printf '%s\n' "${!EZARR_SET[@]}" | sort)"
    fs_write "${EZARR_CONF_DIR}"/components.list "$selected" 0644
    return 0
}

# Plantilla de camara. La IP por defecto es un PLACEHOLDER (192.168.1.10), nunca
# la real de nadie: la publica quien la instala.
ezarr_render_camera_conf() {
    cat <<EOF
# /etc/ezarr/camera.conf — camara IP.
RTSP_URL="${EZARR_CAMERA_RTSP:-rtsp://192.168.1.10:8554}"
EZARR_CAMERA_IP="${EZARR_CAMERA_IP:-192.168.1.10}"
EOF
}

ezarr_render_conf() {
    cat <<EOF
# /etc/ezarr/ezarr.conf — configuracion del stack.
# Generado por ezarr.sh el $(date -u '+%Y-%m-%dT%H:%M:%SZ'). Editable a mano.
# Solo pares NOMBRE=valor. Las lineas que no tengan esa forma se ignoran.

EZARR_DATA_ROOT=${EZARR_DATA_ROOT}
EZARR_STATE_DIR=${EZARR_STATE_DIR}
EZARR_LOG_DIR=${EZARR_LOG_DIR}
EZARR_BACKUP_DIR=${EZARR_BACKUP_DIR}
EZARR_TIMEZONE=${EZARR_TIMEZONE}

# Avisos push. Topic generico de ejemplo: cambialo por el tuyo.
EZARR_NTFY_SERVER=${EZARR_NTFY_SERVER}
EZARR_NTFY_TOPIC=${EZARR_NTFY_TOPIC:-ezarr-ejemplo}

# Componentes que se anaden o quitan siempre, por encima del perfil.
EZARR_COMPONENTS_EXTRA=
EZARR_COMPONENTS_SKIP=
EOF
}

ezarr_render_apps_conf() {
    cat <<EOF
# /etc/ezarr/apps.conf — claves de las aplicaciones. chmod 600.
# NO se versionan en el repo publico: rellenalas aqui, o defines las variables
# EZARR_*_* en el entorno de los scripts que las necesitan.
#
# La plantilla del repo publico lleva esto Vacio a proposito: una clave escrita
# en un fichero que se copia a Internet deja de ser un secreto.

EZARR_SONARR_API_KEY=
EZARR_RADARR_API_KEY=
EZARR_PROWLARR_API_KEY=
EZARR_JELLYFIN_API_KEY=
EZARR_QBIT_USER=
EZARR_QBIT_PASS=
EOF
}

# --- 4. paquetes base ----------------------------------------------------
ezarr_packages_for_components() {
    local pkgs=""
    _ezarr_in_set core    && pkgs="$pkgs cron redis-server avahi-daemon"
    _ezarr_in_set media   && pkgs="$pkgs jellyfin"
    _ezarr_in_set downloads && pkgs="$pkgs qbittorrent-nox"
    _ezarr_in_set reverse && pkgs="$pkgs nginx"
    _ezarr_in_set remote  && pkgs="$pkgs tailscale"
    _ezarr_in_set storage && pkgs="$pkgs rclone mergerfs curl jq sqlite3"
    _ezarr_in_set watchdogs && pkgs="$pkgs cron curl sqlite3"
    # base comun: lo que usan TODOS los pasos de este instalador.
    pkgs="$pkgs ca-certificates curl openssl util-linux"
    printf '%s\n' "$pkgs" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

plan_paquetes() {
    local pkgs; pkgs="$(ezarr_packages_for_components)"
    local missing=""
    for p in $pkgs; do
        have dpkg-query || break
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing="$missing $p"
    done
    fs_plan "paquetes a instalar: $(printf '%s' "$missing" | wc -w) de $(printf '%s' "$pkgs" | wc -w)"
    [ -n "$missing" ] && log_info "faltan:$missing" || log_info "todos los paquetes ya estan"
    return 0
}

apply_paquetes() { fs_apt "$(ezarr_packages_for_components)"; }

# --- 5. scripts de operacion --------------------------------------------
# Los binarios de terceros (Sonarr, Radarr, Prowlarr, Bazarr, FlareSolverr) no se
# compilan aqui: se descargan de una release firmada y se verifican.
ezarr_release_url_for() {  # <componente>
    local base="${EZARR_RELEASE_BASE:-https://releases.stack.example.com}"
    printf '%s/%s-%s_%s.deb' "$base" "$1" "${EZARR_STACK_VERSION:-1.0.0}" "${EZARR_ENV_ARCH}"
}

plan_descargas() {
    local c url sin_suma=0
    for c in arr subs downloads search; do
        [ -n "${EZARR_SET[$c]:-}" ] || continue
        url="$(ezarr_release_url_for "$c")"
        if [ -z "$(ezarr_conf_get "EZARR_SHA256_${c}" "")" ]; then
            # Aviso temprano y claro: sin checksum conocido la instalacion se
            # rechaza con codigo 6. Es mejor enterarse en el plan que en el
            # paso 5 de 8.
            log_warn "sin checksum definido para '$c' (EZARR_SHA256_$c): la instalacion lo rechazara"
            sin_suma=$((sin_suma + 1))
        else
            log_v "GET $url  (sha256 definido)"
        fi
    done
    if [ "$sin_suma" -gt 0 ]; then
        fs_plan "descargar $sin_suma release(s) BLOQUEADAS: faltan los sha256 en /etc/ezarr/ezarr.conf"
    else
        fs_plan "descargar releases con verificacion sha256 previa"
    fi
    return 0
}

apply_descargas() {
    local c url dest
    for c in arr subs downloads search; do
        [ -n "${EZARR_SET[$c]:-}" ] || continue
        url="$(ezarr_release_url_for "$c")"
        dest="${EZARR_STATE_DIR}/packages/${c}.deb"
        fs_mkdir "${EZARR_STATE_DIR}/packages"
        # Se descarga a cache y se verifica antes de instalar: una release sin
        # checksum conocido NO se instala. Es exit code 6, no una excepcion.
        _ezarr_fetch_verify "$url" "$dest" "$c"
    done
}

# _ezarr_fetch_verify <url> <destino> <etiqueta>
# Offline: usa la cache. Sin checksum conocido: se niega a instalar.
_ezarr_fetch_verify() {
    local url="$1" dest="$2" tag="$3"
    local sum; sum="$(ezarr_conf_get "EZARR_SHA256_${tag}" "")"
    if [ "$EZARR_DRY_RUN" = "1" ]; then
        log_v "dry-run: GET $(printf '%q' "$url")"
        log_v "dry-run: verify sha256 ${sum:-<sin checksum definido: instalacion rechazada>}"
        log_v "dry-run: install $dest"
        return 0
    fi
    if [ -f "$dest" ] && [ -n "$sum" ] && echo "$sum  $dest" | sha256sum -c - >/dev/null 2>&1; then
        log_info "cache valido: $tag"
    elif [ "${EZARR_OFFLINE:-0}" = "1" ] || [ ! -f "$dest" ]; then
        have curl || { log_error "falta curl para descargar"; return "${EZARR_EX_NETWORK:-5}"; }
        curl -fsSL --retry 3 --retry-delay 2 -o "$dest.part" "$url" || {
            log_error "fallo la descarga de $tag"
            log_error_hint "comprueba la red o usa --offline con la cache ya descargada"
            return "${EZARR_EX_NETWORK:-5}"
        }
        mv -f "$dest.part" "$dest"
    fi
    if [ -z "$sum" ]; then
        log_error "no hay checksum definido para $tag (EZARR_SHA256_$tag)"
        log_error_hint "define EZARR_SHA256_$tag en /etc/ezarr/ezarr.conf antes de instalar"
        return "${EZARR_EX_VERIFY:-6}"
    fi
    echo "$sum  $dest" | sha256sum -c - >/dev/null 2>&1 || {
        log_error "checksum incorrecto para $tag"
        log_error_hint "el paquete esta corrupto o la release cambio; no se instala"
        return "${EZARR_EX_VERIFY:-6}"
    }
    log_ok "$tag verificado (sha256)"
    dpkg -i "$dest" >/dev/null 2>&1 || log_warn "dpkg -i $tag devolvio error; revisa: dpkg -i $dest"
}

# --- 6. servicios (activacion) ------------------------------------------
plan_activar() {
    local svc
    fs_plan "arr-stack start: $(ezarr_selected_services | tr '\n' ' ')"
    for svc in $(ezarr_selected_services); do
        log_info "arranque: $svc"
    done
    return 0
}

apply_activar() {
    local stack="${EZARR_STACK_BIN:-/usr/local/bin/arr-stack}"
    if [ ! -x "$stack" ]; then
        log_error "arr-stack no esta instalado; no se pueden activar servicios"
        log_error_hint "reinstala con: ezarr.sh --only core"
        return "${EZARR_EX_NOTINST:-3}"
    fi
    fs_run "$stack" start
}

ezarr_selected_services() {
    local s comp
    for s in $(ezarr_service_ids); do
        comp="$(ezarr_service_field "$s" 2)"
        [ -n "${EZARR_SET[$comp]:-}" ] && printf '%s\n' "$s"
    done
}

# Carga el conjunto de componentes que el instalador dejo registrado.
# ezarrctl NO tiene flags de seleccion: no decide que esta instalado, lo lee.
# Sin este fichero no hay instalacion, y hay que decirlo con codigo 3 en vez de
# informar de "0 servicios ok" (que es verdad y no ayuda a nadie).
ezarr_components_load_installed() {
    local f="${EZARR_STATE_DIR}/components.list"
    EZARR_SET=(); EZARR_SET_WHY=(); EZARR_SELECTED_COUNT=0
    [ -r "$f" ] || return 1
    local id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        case "$id" in '#'*) continue ;; esac
        ezarr_component_exists "$id" || continue
        EZARR_SET[$id]=1
        EZARR_SET_WHY[$id]="instalado"
        EZARR_SELECTED_COUNT=$((EZARR_SELECTED_COUNT + 1))
    done < "$f"
    [ "$EZARR_SELECTED_COUNT" -gt 0 ]
}

ezarr_install_state() {
    # 0 = instalado · 1 = no instalado · 2 = instalado pero sin arr-stack
    ezarr_components_load_installed || return 1
    [ -x "${EZARR_STACK_BIN:-/usr/local/bin/arr-stack}" ] || return 2
    return 0
}

# Diagnostico unico y accionable cuando no hay instalacion. Lo usan status,
# start, stop, restart y logs: el mismo error cinco veces, dicho igual.
ezarr_require_installed() {
    local what="${1:-esta operacion}"
    ezarr_components_load_installed && return 0
    log_error "$what: el stack no esta instalado"
    log_error_hint "no existe ${EZARR_STATE_DIR}/components.list"
    log_error_hint "mira el plan antes de instalar: sudo ./ezarr.sh --dry-run"
    log_error_hint "y luego: sudo ./ezarr.sh"
    return "${EZARR_EX_NOTINST:-3}"
}

# --- 7. mas_scripts ------------------------------------------------------
plan_scripts() {
    fs_plan "+ ${EZARR_BIN_DIR}/ (arr-stack, ezarrctl y vigilantes)"
    return 0
}

apply_scripts() {
    local here; here="$(ezarr_repo_root)"
    fs_mkdir "$EZARR_BIN_DIR"
    [ -f "$here/ezarrctl" ] && fs_install -m 0755 "$here/ezarrctl" "$EZARR_BIN_DIR/ezarrctl"
    [ -f "$here/ezarr.sh" ]  && fs_install -m 0755 "$here/ezarr.sh"  "$EZARR_BIN_DIR/ezarr-stack-install"
    return 0
}

# --- 8. backups / estado -------------------------------------------------
plan_estado() {
    fs_plan "+ ${EZARR_STATE_DIR}/installed.json (componentes y version)"
    return 0
}

apply_estado() {
    fs_mkdir "$EZARR_STATE_DIR"
    fs_write "${EZARR_STATE_DIR}/installed.json" "{
  \"stack\": \"ezarr\",
  \"version\": \"${EZARR_STACK_VERSION:-1.0.0}\",
  \"installed\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",
  \"env\": \"${EZARR_ENV_KIND}\",
  \"arch\": \"${EZARR_ENV_ARCH}\",
  \"profile\": \"${EZARR_PROFILE}\",
  \"components\": \"$(printf '%s\\n' "${!EZARR_SET[@]}" | sort | tr '\\n' ' ')\"
}" 0644
    return 0
}