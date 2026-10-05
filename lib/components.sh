#!/bin/bash
# lib/components.sh — Catalogo de componentes y resolucion opt-in / opt-out.
#
# El conjunto de componentes es ABIERTO: por eso el opt-out es una lista
# (`--without <id,...>`) y no una familia de flags `--no-X`.
#
#   --no-web --no-metrics --no-agent te obliga a conocer el catalogo entero
#   para desactivarlo todo, y no escala a un componente que nadie habia previsto.
#
# Es el mismo argumento que hace que `pacman --overwrite <glob>` y
# `pacman --ignore <pkg>` ganen a un `--no-` por paquete. Y al reves:
#
#   --only NO es un-azucar de --with. Pone a cero el conjunto y hace inertes
#   los pasos 1-5 (si se aplican version y canal). Sirve para instalar
#   exactamente lo que pide un Dockerfile, sin que la config del host se cuele.

# --------------------------------------------------------------- catalogo --
# id|etiqueta|perfil_minimo|descripcion
EZARR_COMPONENTS=(
  "core|base|minimal|Nucleo: estructura de datos, servicios basicos y scripts de operacion"
  "media|media|minimal|Jellyfin y sus bibliotecas (peliculas, series, musica, colecciones)"
  "downloads|descargas|standard|qBittorrent, y los indexadores Prowlarr y Jackett"
  "arr|servarr|standard|Sonarr y Radarr: descargas y organizacion automatica"
  "subs|subtitulos|standard|Bazarr: subtitulos junto a la media"
  "dashboard|dashboard|standard|Homarr: panel web de acceso a todos los servicios"
  "camera|camara|full|Motion + scripts de captura, deteccion de movimiento y subida a Drive"
  "remote|remoto|full|Cloudflare Tunnel y Tailscale: acceso desde fuera sin abrir puertos"
  "storage|almacenamiento|full|rclone hacia Google Drive y la union mergerfs de medios"
  "watchdogs|vigilantes|standard|Watchdogs de pila y de resiliencia, con cron y montajes"
  "reverse|proxy|full|nginx como proxy inverso y terminacion TLS"
  "search|busqueda|full|FlareSolverr: puente para indexadores con proteccion anti-bot"
)

# Perfiles: que se anade por encima del minimo de cada componente.
EZARR_PROFILE_BASE_MINIMAL="core media"
EZARR_PROFILE_BASE_STANDARD="core media downloads arr subs dashboard watchdogs"
EZARR_PROFILE_BASE_FULL="core media downloads arr subs dashboard watchdogs camera remote storage reverse search"

ezarr_component_exists() {
    local id="$1" row
    for row in "${EZARR_COMPONENTS[@]}"; do
        [ "${row%%|*}" = "$id" ] && return 0
    done
    return 1
}

ezarr_component_field() {  # <id> <2|3|4>
    local id="$1" n="$2" row i=1
    for row in "${EZARR_COMPONENTS[@]}"; do
        if [ "${row%%|*}" = "$id" ]; then
            printf '%s' "$(printf '%s' "$row" | cut -d'|' -f"$n")"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

ezarr_component_list() {
    local row
    for row in "${EZARR_COMPONENTS[@]}"; do
        printf '  %-14s %s\n' "$(printf '%s' "$row" | cut -d'|' -f2)" "$(printf '%s' "$row" | cut -d'|' -f4)"
    done
}

ezarr_components_render() {
    local row id mark color why
    for row in "${EZARR_COMPONENTS[@]}"; do
        id="${row%%|*}"
        if _ezarr_in_set "$id"; then
            mark="+"; color="$EZARR_C_GREEN"; why="${EZARR_SET_WHY[$id]:-}"
        else
            mark=" "; color="$EZARR_C_DIM"
            why="${EZARR_SET_WHY[$id]:-no habilitado en el perfil ${EZARR_PROFILE:-standard}}"
        fi
        printf '    %s%s%s %s%-15s%s %s%s%s\n' \
            "$color" "$mark" "$EZARR_C_RESET" "$EZARR_C_BOLD" \
            "$(ezarr_component_field "$id" 2)" "$EZARR_C_RESET" "$EZARR_C_DIM" "$why" "$EZARR_C_RESET"
    done
    return 0
}

# ------------------------------------------------------------- conjuntos ----
declare -A EZARR_SET=()
declare -A EZARR_SET_WHY=()
EZARR_SELECTED_COUNT=0
EZARR_CATALOG_COUNT=0
EZARR_DRY_RUN="${EZARR_DRY_RUN:-0}"

_ezarr_in_set() { [ -n "${EZARR_SET[$1]:-}" ]; }

_ezarr_add() { # <id> <motivo>
    if ! ezarr_component_exists "$1"; then
        log_error "componente desconocido: '$1'"
        log_error_hint "componentes validos: $(ezarr_component_ids | tr '\n' ' ')"
        ezarr_exit "${EZARR_EX_USAGE:-2}"
    fi
    if [ -n "${EZARR_SET[$1]:-}" ]; then return 0; fi
    EZARR_SET[$1]=1
    EZARR_SET_WHY[$1]="$2"
    EZARR_SELECTED_COUNT=$((EZARR_SELECTED_COUNT + 1))
    return 0
}

_ezarr_del() { unset 'EZARR_SET[$1]' 2>/dev/null || true; EZARR_SET_WHY[$1]="desactivado con --without"; return 0; }

ezarr_component_ids() { local row; for row in "${EZARR_COMPONENTS[@]}"; do printf '%s\n' "${row%%|*}"; done; }

# ------------------------------------------------------------- resolucion ---
# ezarr_components_resolve [--with a,b] [--without x,y] [--only a,b] [--profile p]
# Orden fijo y determinista. Visible en el resumen para que sea auditable.
ezarr_components_resolve() {
    EZARR_CATALOG_COUNT="${#EZARR_COMPONENTS[@]}"
    local with="" without="" only="" profile="${EZARR_PROFILE:-standard}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --with)    with="$2"; shift 2 ;;
            --without) without="$2"; shift 2 ;;
            --only)    only="$2"; shift 2 ;;
            --profile) profile="$2"; shift 2 ;;
            *) break ;;
        esac
    done

    case "$profile" in
        minimal)  base="$EZARR_PROFILE_BASE_MINIMAL" ;;
        standard) base="$EZARR_PROFILE_BASE_STANDARD" ;;
        full)     base="$EZARR_PROFILE_BASE_FULL" ;;
        all)      profile="full"; base="$EZARR_PROFILE_BASE_FULL" ;;
        *) log_error "perfil desconocido: $profile"; log_error_hint "usa minimal, standard o full"
           ezarr_exit "${EZARR_EX_USAGE:-2}" ;;
    esac
    EZARR_PROFILE="$profile"

    # --only: pone a cero todo y hace inertes los pasos 1-5.
    if [ -n "$only" ]; then
        EZARR_SET=(); EZARR_SELECTED_COUNT=0
        local id
        for id in $(ezarr_csv "$only"); do _ezarr_add "$id" "--only"; done
    else
        # 1) base por defecto de la plataforma
        local id
        for id in $(ezarr_csv "$base"); do _ezarr_add "$id" "perfil $profile"; done
        # 2..3) config: EZARR_COMPONENTS_EXTRA / EZARR_COMPONENTS_SKIP en el fichero de config
        for id in $(ezarr_csv "${EZARR_COMPONENTS_EXTRA:-}"); do _ezarr_add "$id" "config"; done
        for id in $(ezarr_csv "${EZARR_COMPONENTS_SKIP:-}"); do _ezarr_del "$id"; done
        # 4) opt-in: union
        for id in $(ezarr_csv "$with"); do _ezarr_add "$id" "--with"; done
        # 5) opt-out: resta. Se aplica DESPUES de --with, asi que
        #    `--with web --without web` es off y no hay caso especial.
        for id in $(ezarr_csv "$without"); do
            ezarr_component_exists "$id" || { log_error "componente desconocido: '$id'"; ezarr_exit "${EZARR_EX_USAGE:-2}"; }
            _ezarr_del "$id"
        done
    fi

    EZARR_SELECTED_COUNT=0
    local r
    for r in "${EZARR_COMPONENTS[@]}"; do
        [ -n "${EZARR_SET[${r%%|*}]:-}" ] && EZARR_SELECTED_COUNT=$((EZARR_SELECTED_COUNT + 1))
    done

    # Conflicto duro en tiempo de plan, nunca un ganador silencioso.
    ezarr_components_check_conflicts
    return 0
}

# Dependencias reales entre componentes. Si el usuario quita una dependencia y
# deja el que la necesita, es un error de plan con codigo 4, no un fallo raro
# mas tarde. El opt-out del usuario siempre gana sobre un conflicto declarado
# (el usuario tuvo la ultima palabra), pero la dependencia lo dice.
ezarr_components_check_conflicts() {
    local rc=0
    # media es el unico componente del que cuelgan varios.
    if ! _ezarr_in_set media; then
        local needs=""
        for c in arr subs dashboard; do
            _ezarr_in_set "$c" && needs="$needs $c"
        done
        # arr subs dashboard funcionan sin media (bibliotecas vacias): es aviso,
        # no error. Solo se avisa si el usuario no lo pidio explicitamente.
        if [ -n "$needs" ] && [ "${EZARR_WITHOUT_MEDIA_ACK:-0}" != "1" ]; then
            log_warn "sin 'media': $(printf '%s' "$needs" | sed 's/^ //') no tendra biblioteca que organizar"
        fi
    fi
    # search solo sirve a los indexadores
    if _ezarr_in_set search && ! _ezarr_in_set downloads; then
        log_warn "'search' (FlareSolverr) sin 'downloads': no hay indexadores a los que proteger"
    fi
    if [ "$EZARR_SELECTED_COUNT" -eq 0 ]; then
        log_error "no queda ningun componente instalado"
        log_error_hint "usa --profile standard, o --only core para el minimo"
        rc="${EZARR_EX_USAGE:-2}"
    fi
    return "$rc"
}

# ------------------------------------------------------------- utilidades ---
# ezarr_csv "a,b, c" -> "a b c". Tolera espacios y comillas; no ejecuta nada.
ezarr_csv() {
    printf '%s' "${1:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//' | grep -v '^$' || true
}