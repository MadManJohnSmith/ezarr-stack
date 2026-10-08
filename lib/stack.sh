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
    # Solo se saltan los puertos sin numero real (cron, redis, avahi) y nginx,
    # que responde en 80/443 y se comprueba por su cuenta. tailscale (41641) y
    # cloudflared (7844) tambien se comprueban: decir "ok" solo porque el proceso
    # existe hacia que un tunel caido pasa por sano.
    case "$port" in -|''|'80,443') echo ok; return 0 ;; esac
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

# --- 0. DNS --------------------------------------------------------------
# En el chroot /etc/resolv.conf es casi siempre un symlink a un fichero que vive
# bajo /run. Ese /run es el del host en el momento del arranque: en cuanto el
# host reinicia, el destino desaparece y queda un symlink colgante. Sin
# resolucion de nombres no hay descargas ni proxy inverso, y el fallo sale un
# paso mas tarde con un mensaje que no lo dice.
ezarr_resolv_link() {
    # Lo que hay que tener EN PIE, no lo que hay que escribir.
    local rc="${1:-/etc/resolv.conf}" tgt
    if [ -L "$rc" ]; then tgt="$(readlink -f -- "$rc" 2>/dev/null || echo "$rc")"; else tgt="$rc"; fi
    printf '%s\n' "$tgt"
}

plan_resolv() {
    local rc="${EZARR_RESOLV_CONF:-/etc/resolv.conf}" tgt
    tgt="$(ezarr_resolv_link "$rc")"
    if [ -s "$rc" ] && [ -r "$rc" ]; then
        log_info "resolucion de nombres: $rc -> $tgt"
        return 0
    fi
    fs_plan "asegurar $rc (apunta a $tgt y ahi no hay nada)"
    log_warn "$rc no resuelve: apunta a $tgt y ahi no hay nada"
    log_warn "sin DNS no hay descargas, ni actualizacion de certificados, ni proxy inverso"
    return 0
}

apply_resolv() {
    local rc="${EZARR_RESOLV_CONF:-/etc/resolv.conf}" ns body n
    if [ -s "$rc" ] && [ -r "$rc" ]; then
        EZARR_STEP_DETAIL_LAST="resolucion de nombres ya utilizable"
        return 0
    fi
    ns="${EZARR_RESOLV_NAMESERVER:-1.1.1.1 9.9.9.9}"
    body="# Generado por ezarr.sh: el resolv.conf original no era utilizable.
# Nameserver publicos; cambialos con EZARR_RESOLV_NAMESERVER si tu red lo pide."
    for n in $ns; do body="$body
nameserver $n"; done
    body="$body
options timeout:2 attempts:2"
    # Se escribe sobre $rc y no sobre el destino: si es un symlink a
    # /run/systemd/resolve/stub-resolv.conf, esto regenera ese fichero y deja el
    # symlink como estaba, que es lo que el resto del sistema espera.
    fs_write "$rc" "$body" 0644
    if [ -s "$rc" ]; then
        log_ok "resolucion de nombres escrita en $rc"
        EZARR_STEP_DETAIL_LAST="escrito $rc ($(printf '%s' "$ns" | wc -w) nameserver(s))"
    else
        log_warn "no se pudo escribir $rc: sin root no hay way"
        EZARR_STEP_DETAIL_LAST="$rc sin cambios"
    fi
    return 0
}

# --- 1. requisitos -------------------------------------------------------
# _ezarr_require_tool <herramienta>
# El instalador llama a estas herramientas sin guarda propia, asi que si faltan
# el fallo sale con codigo 4 (requisito no satisfecha) y no mas tarde como un
# error de descarga o de verificacion que no dice lo que pasa.
_ezarr_require_tool() {
    have "$1" && return 0
    ezarr_plan_problem "falta '$1', que el instalador necesita" "${EZARR_EX_CONFLICT:-4}"
    return 1
}

# /dev/net/tun. tailscaled solo levanta la VPN en modo tun si el nodo existe, y
# en el chroot de TWRP /dev es un tmpfs propio que no lo trae. No es un fallo
# de instalacion (tailscale tambien funciona con --tun=userspace-networking), asi
# que aqui se avisa y en apply_requisitos se intenta crear.
_ezarr_tun_preflight() {
    _ezarr_in_set remote || return 0
    if [ -c /dev/net/tun ]; then
        log_info "/dev/net/tun presente"
        return 0
    fi
    fs_plan "crear /dev/net/tun (lo necesita tailscale en modo tun)"
    log_warn "'remote' esta seleccionado pero no existe /dev/net/tun"
    log_warn "se creara en este paso; si no es posible, arranca tailscale con --tun=userspace-networking"
    return 0
}

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

    # Dependencias externas. Se usan sin guarda en varios sitios (pgrep para
    # comprobar que un servicio vive, sha256sum para verificar una release,
    # curl/wget para bajarla), asi que su ausencia tiene que salir aqui y no
    # como un fallo raro en el paso 5 con el mensaje equivocado.
    _ezarr_require_tool pgrep || problems=$((problems + 1))
    _ezarr_require_tool sha256sum || problems=$((problems + 1))
    if [ "${EZARR_OFFLINE:-0}" != "1" ] && ! have curl && ! have wget; then
        ezarr_plan_problem "falta curl o wget, y sin --offline hace falta uno de los dos" "${EZARR_EX_CONFLICT:-4}"
        problems=$((problems + 1))
    fi

    _ezarr_tun_preflight

    if [ "${EZARR_OFFLINE:-0}" != "1" ] && ! ezarr_network_ok; then
        log_error "no hay salida a internet"
        # env.sh deja el motivo concreto (DNS, TCP o HTTP). "No hay red" a secas
        # obliga a ir a buscarlo a mano cuando el paso 0 ya lo resolvio.
        [ -n "${EZARR_NET_WHY:-}" ] && log_error_hint "motivo: ${EZARR_NET_WHY}"
        log_error_hint "conecta el telefono a la red, o usa --offline con la cache ya descargada"
        ezarr_plan_problem "sin red no se pueden descargar los binarios" "${EZARR_EX_NETWORK:-5}"
        problems=$((problems + 1))
    fi

    [ "$problems" -eq 0 ]
}

apply_requisitos() {
    # /dev/net/tun solo si 'remote' esta elegido y no existe ya. Si mknod falla
    # (sin root, sin CAP_MKNOD, tmpfs de solo lectura) NO es motivo para parar la
    # instalacion: tailscale tiene modo userspace. Se dice y se sigue.
    if _ezarr_in_set remote && [ ! -c /dev/net/tun ]; then
        fs_mkdir /dev/net
        if fs_run mknod c 10 200 /dev/net/tun; then
            log_ok "creado /dev/net/tun"
            EZARR_STEP_DETAIL_LAST="creado /dev/net/tun"
        else
            log_warn "no se pudo crear /dev/net/tun: hace falta root y CAP_MKNOD"
            log_warn "arranca tailscale con --tun=userspace-networking o el VPN no levantara"
            EZARR_STEP_DETAIL_LAST="/dev/net/tun no creado (usar --tun=userspace-networking)"
        fi
        return 0
    fi
    EZARR_STEP_DETAIL_LAST="sin escrituras (comprobacion pura)"
    return 0
}

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
    # El registro de lo instalado es ESTADO, no configuracion: va a
    # $EZARR_STATE_DIR porque es de donde lo leen ezarr_components_load_installed
    # (abajo) y ezarrctl (ezarrctl, cmd_status). Por defecto /var/lib/ezarr y
    # /etc/ezarr son directorios distintos, asi que escribirlo en
    # $EZARR_CONF_DIR lo dejaba invisible para todo el que lo busca.
    fs_write "${EZARR_STATE_DIR}"/components.list "$selected" 0644
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
    local base="${EZARR_RELEASE_BASE:-https://packages.example.com}"
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
        # Un aviso no es un fallo: si aqui solo se avisa y se devuelve 0,
        # --dry-run declara valido un plan que el instalador real va a rechazar
        # con codigo 6 en el paso 5. Un dry-run que miente no vale como puerta.
        fs_plan "descargar $sin_suma release(s) BLOQUEADAS: faltan los sha256 en ${EZARR_CONF_DIR}/ezarr.conf"
        ezarr_plan_problem "faltan los sha256 de $sin_suma release(s): define EZARR_SHA256_<arr|subs|downloads|search> en ${EZARR_CONF_DIR}/ezarr.conf" "${EZARR_EX_VERIFY:-6}"
        return "${EZARR_EX_VERIFY:-6}"
    fi
    fs_plan "descargar releases con verificacion sha256 previa"
    return 0
}

apply_descargas() {
    local c url dest rc=0 r
    for c in arr subs downloads search; do
        [ -n "${EZARR_SET[$c]:-}" ] || continue
        url="$(ezarr_release_url_for "$c")"
        dest="${EZARR_STATE_DIR}/packages/${c}.deb"
        fs_mkdir "${EZARR_STATE_DIR}/packages"
        # Se descarga a cache y se verifica antes de instalar: una release sin
        # checksum conocido NO se instala. Es exit code 6, no una excepcion.
        #
        # El rc se acumula en una variable y NO se confia en el estado del bucle:
        # el `for` devuelve el del ULTIMO comando ejecutado, y como las
        # iteraciones que no aplican terminan en `continue` (que vale 0), un
        # fallo de descarga se comia solo y apply_descargas acababa en 0.
        _ezarr_fetch_verify "$url" "$dest" "$c" || { r=$?; [ "$rc" -eq 0 ] && rc="$r"; }
    done
    return "$rc"
}

# _ezarr_fetch_fail <operacion>
# Marca el fallo para la SEGUNDA red de seguridad del plan (EZARR_FS_FAILED, que
# plan.sh revisa despues del apply) sin inventarse un codigo: el codigo real lo
# pone quien llama. _fs_fail descuenta la escritura pendiente, asi que se cierra
# antes: aqui no se ha tocado nada y lo que se escribio antes sigue en pie.
_ezarr_fetch_fail() {
    EZARR_FS_PENDING=0
    _fs_fail "$1"
    return 0
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
    elif [ ! -f "$dest" ] && [ "${EZARR_OFFLINE:-0}" != "1" ]; then
        # Descargar solo si NO hay cache Y no se pidio offline. Con la condicion
        # al reves (`offline || sin cache`) el caso offline caia aqui: --offline
        # era justo lo que disparaba la descarga que dice evitar.
        have curl || { log_error "falta curl para descargar"; _ezarr_fetch_fail "curl ausente para $tag"; return "${EZARR_EX_NETWORK:-5}"; }
        curl -fsSL --retry 3 --retry-delay 2 -o "$dest.part" "$url" || {
            log_error "fallo la descarga de $tag"
            log_error_hint "comprueba la red y reintenta; --offline solo sirve con la cache ya descargada en $dest"
            _ezarr_fetch_fail "descarga de $tag"; return "${EZARR_EX_NETWORK:-5}"
        }
        mv -f "$dest.part" "$dest"
    fi
    if [ ! -f "$dest" ]; then
        # Offline y sin cache: no hay de donde sacar el paquete. Cae en el
        # codigo de verificacion (6), que es el que el plan ya anuncia.
        log_error "sin cache para $tag y --offline impide descargarlo"
        log_error_hint "descarga $url a mano y dejalo en $dest, o quita --offline"
        _ezarr_fetch_fail "cache ausente para $tag"; return "${EZARR_EX_VERIFY:-6}"
    fi
    if [ -z "$sum" ]; then
        log_error "no hay checksum definido para $tag (EZARR_SHA256_$tag)"
        log_error_hint "define EZARR_SHA256_$tag en ${EZARR_CONF_DIR}/ezarr.conf antes de instalar"
        _ezarr_fetch_fail "sin checksum para $tag"; return "${EZARR_EX_VERIFY:-6}"
    fi
    echo "$sum  $dest" | sha256sum -c - >/dev/null 2>&1 || {
        log_error "checksum incorrecto para $tag"
        log_error_hint "el paquete esta corrupto o la release cambio; no se instala"
        _ezarr_fetch_fail "checksum de $tag"; return "${EZARR_EX_VERIFY:-6}"
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
        # No vale decir "vuelve a instalar": este paso viene DESPUES de
        # scripts de operacion, que lo copia. Si aqui no esta, el problema es el
        # repo o el destino, y eso se mira antes de repetir el comando entero.
        log_error_hint "el paso 'scripts de operacion' lo deja en ${stack}"
        log_error_hint "comprueba el origen con: git ls-files arr-stack  y que ${EZARR_BIN_DIR} sea escribible"
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
    # Se anuncia exactamente lo que hay en el repo y lo que se copia abajo. Un
    # plan que promete algo que apply no instala es la forma mas rapida de que
    # el paso 7 falle ("arr-stack no esta instalado") siendo el plan valido.
    local here f
    here="$(ezarr_repo_root)"
    for f in arr-stack ezarrctl ezarr.sh; do
        [ -f "$here/$f" ] || { log_warn "el repo no trae $f: no se podra instalar"; continue; }
        fs_plan "+ ${EZARR_BIN_DIR}/$f"
    done
    # lib/ viaja con ellos, no por capricho: ezarrctl y ezarr.sh resuelven
    # EZARR_ROOT como el directorio del propio script, asi que una vez copiados a
    # $EZARR_BIN_DIR buscan $EZARR_BIN_DIR/lib/. Sin esto el ezarrctl instalado
    # muere en el primer source con "lib/log.sh: No such file or directory".
    if [ -d "$here/lib" ]; then
        fs_plan "+ ${EZARR_BIN_DIR}/lib/ ($(ls -1 "$here"/lib/*.sh 2>/dev/null | wc -l) ficheros .sh)"
    fi
    # arr-stack sin el cual nada arranca: si falta del checkout, se dice AHORA y
    # con codigo, no en el paso 7 cuando apply_activar ya no puede hacer nada.
    if [ ! -f "$here/arr-stack" ]; then
        ezarr_plan_problem "el repo no trae arr-stack: sin el no hay gestor de servicios" "${EZARR_EX_NOTINST:-3}"
        return "${EZARR_EX_NOTINST:-3}"
    fi
    return 0
}

apply_scripts() {
    local here; here="$(ezarr_repo_root)"
    fs_mkdir "$EZARR_BIN_DIR"
    # arr-stack es el gestor de servicios y va PRIMERO: es lo que hace que los
    # demas (ezarrctl, el paso 7) tengan algo que ejecutar. Sin el, una
    # instalacion se queda sin forma de arrancar o parar nada.
    [ -f "$here/arr-stack" ] && fs_install -m 0755 "$here/arr-stack" "$EZARR_BIN_DIR/arr-stack"
    [ -f "$here/ezarrctl" ] && fs_install -m 0755 "$here/ezarrctl" "$EZARR_BIN_DIR/ezarrctl"
    [ -f "$here/ezarr.sh" ]  && fs_install -m 0755 "$here/ezarr.sh"  "$EZARR_BIN_DIR/ezarr-stack-install"
    # Los .sh de lib/ se sourcean, no se ejecutan: 0644 es lo correcto y deja
    # claro que no son nada ejecutable por si misma.
    if [ -d "$here/lib" ]; then
        fs_mkdir "$EZARR_BIN_DIR/lib"
        local f
        for f in "$here"/lib/*.sh; do
            [ -f "$f" ] || continue
            fs_install -m 0644 "$f" "$EZARR_BIN_DIR/lib/$(basename "$f")"
        done
    fi

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
    # El marcador de entorno se escribe aqui y no antes: es lo que permite que
    # la siguiente ejecucion sepa si esta en un chroot sin adivinar por PID 1.
    # Sin el, la deteccion se apoya en una senal que en Android es ambigua.
    ezarr_write_env_marker \
        || log_warn "no se pudo escribir ${EZARR_CONF_DIR:-/etc/ezarr}/chroot.marker (hace falta root)"
    return 0
}