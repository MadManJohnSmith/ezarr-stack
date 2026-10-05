#!/bin/bash
# =============================================================================
#  ezarr.sh — instalador de un solo comando del stack ezarr
# =============================================================================
#
#  QUE HACE
#    Detecta si corre dentro del chroot Ubuntu de un telefono (TWRP) o en una
#    maquina normal, comprueba lo que falta, deja elegir que componentes se
#    instalan, MUESTRA UN RESUMEN y pide confirmacion antes de tocar nada.
#    Con --dry-run imprime exactamente lo que haria y no toca nada.
#
#  LO QUE NO HACE
#    * No arranca nada al terminar: la instalacion no es el arranque. Tras
#      instalar, el arranque lo decides tu con `ezarrctl start`.
#    * No inventa valores. Si falta el topic de ntfy o la IP de la camara, lo
#      pide o escribe un placeholder explicito; nunca pone el tuyo por ti.
#
#  SALIDA
#    Progreso y avisos a stderr. Los codigos de salida son los de lib/log.sh
#    (0 ok · 1 error · 2 uso · 3 no instalado · 4 conflicto · 5 red · 6 checksum
#    · 7 permisos · 130 interrumpido).
# =============================================================================

set -euo pipefail

EZARR_APP_NAME="ezarr-stack"
EZARR_STACK_VERSION="${EZARR_STACK_VERSION:-1.0.0}"
EZARR_SELF="$(basename "$0")"

# --- localizacion de lib/ (sigue funcionando desde un symlink) ---------------
ezarr_repo_root() {
    local src="$0" dir
    while [ -L "$src" ]; do
        dir="$(cd -P "$(dirname "$src")" && pwd)"
        src="$(readlink "$src")"
        [ "${src#/}" = "$src" ] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" && pwd
}
EZARR_ROOT="$(ezarr_repo_root)"

# shellcheck source=lib/log.sh
. "$EZARR_ROOT/lib/log.sh"
. "$EZARR_ROOT/lib/env.sh"
. "$EZARR_ROOT/lib/config.sh"
. "$EZARR_ROOT/lib/plan.sh"
. "$EZARR_ROOT/lib/components.sh"
. "$EZARR_ROOT/lib/stack.sh"

EZARR_ASSUME_YES=0

# ============================================================== AYUDA ========
usage() {
    cat <<EOF
${EZARR_C_BOLD}$EZARR_SELF ${EZARR_STACK_VERSION}${EZARR_C_RESET} — instalador del stack ezarr en un comando.

${EZARR_C_BOLD}USO${EZARR_C_RESET}
  $EZARR_SELF [opciones]

  Detecta el entorno (chroot de telefono o maquina normal), comprueba lo que
  falta, deja elegir componentes, y muestra un resumen ANTES de tocar nada.

${EZARR_C_BOLD}SELECCION DE COMPONENTES${EZARR_C_RESET}
      --with <id,...>      opt-in:  anade componentes al conjunto resuelto
      --without <id,...>   opt-out: quita componentes del conjunto resuelto
      --only <id,...>      parte de cero: solo estos, ignorando perfil y config
      --profile <name>     minimal | standard | full   (por defecto: standard)
      --all                atajo de --profile=full

${EZARR_C_BOLD}FLUJO${EZARR_C_RESET}
      --yes                no pedir confirmacion (sin forma corta, a proposito)
  -n, --dry-run            imprimir el plan completo y no tocar nada
      --offline            resolver solo con cache; no usar la red
      --no-progress        sin contadores, conservando las lineas de paso

${EZARR_C_BOLD}CONFIGURACION${EZARR_C_RESET}
  -c, --config <ruta>      fichero de configuracion adicional (se lee en orden)
      --data-root <ruta>   donde viven los datos (por defecto: /data)
      --release-base <url> base de las releases descargadas
      --set <NOMBRE=VALOR>override de una variable, repetible

${EZARR_C_BOLD}GLOBALES${EZARR_C_RESET}
  -q, --quiet              solo errores y la linea de resultado final
  -v, --verbose            mas detalle (acumulativo: -vv)
  -D, --debug              diagnostico: cabeceras, timers, plan en JSON
      --color <when>       auto | always | never        (por defecto: auto)
      --json               salida en JSON por stdout (para CI)
  -h, --help               esta ayuda
      --version            version del instalador (sin forma corta: -v es verbose)

${EZARR_C_BOLD}COMPONENTES DISPONIBLES${EZARR_C_RESET}
$(ezarr_component_list)

${EZARR_C_BOLD}EJEMPLOS${EZARR_C_RESET}
  # Ver el plan sin tocar nada (lo primero que conviene hacer siempre)
  $EZARR_SELF --dry-run

  # Instalacion tipica en el telefono, con biblioteca y descargas
  sudo $EZARR_SELF --profile standard

  # Stack completo, incluida la camara y el acceso remoto
  sudo $EZARR_SELF --all --yes

  # Lo minimo para arrancar, y luego anadir componentes
  sudo $EZARR_SELF --only core --with media,downloads

  # Todo menos camara, para no exponerla
  sudo $EZARR_SELF --all --without camera

${EZARR_C_BOLD}COMO FUNCIONA EL DRY-RUN${EZARR_C_RESET}
  No es una simulacion parecida al instalador: es el MISMO codigo con las
  escrituras desactivadas. Cada paso tiene una funcion plan() que solo calcula,
  y otra apply() que muta. --dry-run ejecuta plan() y se salta apply().
  Ademas, toda escritura pasa por un unico envoltorio que en dry-run registra la
  operacion y devuelve sin hacer nada. Si un paso se saltase el envoltorio, el
  test de auditoria lo detecta.

  --dry-run sale con codigo distinto de 0 si el plan es invalido, con el mismo
  codigo que daria la instalacion real. Por eso sirve como puerta en CI.

${EZARR_C_BOLD}DESPUES DE INSTALAR${EZARR_C_RESET}
  $EZARR_SELF no arranca nada. El arranque es una decision tuya:
      ezarrctl status          que esta vivo
      ezarrctl start           arrancar el stack
      ezarrctl doctor          diagnosticar problemas
EOF
}

version_line() {
    # Una sola linea, parseable por maquinas.
    printf '%s %s (%s/%s) build %s\n' \
        "$EZARR_APP_NAME" "$EZARR_STACK_VERSION" \
        "$(uname -s 2>/dev/null || echo linux)" "${EZARR_ENV_ARCH:-$(uname -m)}" \
        "$(date -u +%Y%m%d)"
}

# =========================================================== ARGUMENTOS ======
SET_OVERRIDES=()
EXTRA_CONF=()

usage_error() {
    log_error "$1"; shift
    local hint
    for hint in "$@"; do log_error_hint "$hint"; done
    printf '\n'
    printf 'Uso: %s [opciones]\n\n' "$EZARR_SELF" >&2
    printf "Ejecuta '%s --help' para la ayuda completa.\n" "$EZARR_SELF" >&2
    ezarr_exit "${EZARR_EX_USAGE:-2}"
}

parse_args() {
    local only="" with="" without="" profile="" js=0
    ezarr_normalize_args "$@"
    # Copia a array local antes de `set --`: un ${arr[@]+"${arr[@]}"} sin
    # comillas alrededor del `set --` parte los valores con espacios.
    local -a argv=()
    argv=(${EZARR_ARGS[@]+"${EZARR_ARGS[@]}"})
    set -- "${argv[@]}"
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)    usage; ezarr_exit 0 ;;
            --version)    ezarr_detect_env; ezarr_log_init; version_line; ezarr_exit 0 ;;
            -n|--dry-run) EZARR_DRY_RUN=1; shift ;;
            --offline)    EZARR_OFFLINE=1; shift ;;
            --no-progress) EZARR_SHOW_CHANGES=0; shift ;;
            --yes)        EZARR_ASSUME_YES=1; shift ;;
            --all)        profile="full"; shift ;;
            --only)       [ $# -ge 2 ] || usage_error "--only necesita una lista de componentes" "ej: --only core,media"; only="$2"; shift 2 ;;
            --with)       [ $# -ge 2 ] || usage_error "--with necesita una lista de componentes"; with="$2"; shift 2 ;;
            --without)    [ $# -ge 2 ] || usage_error "--without necesita una lista de componentes"; without="$2"; shift 2 ;;
            --profile)    [ $# -ge 2 ] || usage_error "--profile necesita un nombre"; profile="$2"; shift 2 ;;
            -c|--config)  [ $# -ge 2 ] || usage_error "--config necesita una ruta"; EXTRA_CONF+=("$2"); shift 2 ;;
            --data-root)  [ $# -ge 2 ] || usage_error "--data-root necesita una ruta"; export EZARR_DATA_ROOT="$2"; shift 2 ;;
            --release-base) [ $# -ge 2 ] || usage_error "--release-base necesita una URL"; export EZARR_RELEASE_BASE="$2"; shift 2 ;;
            --set)        [ $# -ge 2 ] || usage_error "--set necesita NOMBRE=VALOR"; SET_OVERRIDES+=("$2"); shift 2 ;;
            --json)       js=1; shift ;;
            --color)      [ $# -ge 2 ] || usage_error "--color necesita auto|always|never"; export EZARR_COLOR="$2"; shift 2 ;;
            -q|--quiet)   EZARR_VERBOSITY=0; shift ;;
            -v|--verbose) EZARR_VERBOSITY=$((EZARR_VERBOSITY + 1)); shift ;;
            -D|--debug)   EZARR_VERBOSITY=$((EZARR_VERBOSITY + 2)); shift ;;
            -*)           usage_error "flag desconocido: $1" "Ejecuta '$EZARR_SELF --help'." ;;
            *)            usage_error "argumento inesperado: $1" "Este instalador no acepta argumentos posicionales." ;;
        esac
    done
    ARGS_ONLY="$only"; ARGS_WITH="$with"; ARGS_WITHOUT="$without"
    ARGS_PROFILE="$profile"; ARGS_JSON="$js"
    return 0
}

# Los --set se aplican al final, con maxima precedencia, SIN|sourcear nada.
apply_set_overrides() {
    local kv name value
    for kv in ${SET_OVERRIDES+"${SET_OVERRIDES[@]}"}; do
        name="${kv%%=*}"; value="${kv#*=}"
        if ! printf '%s' "$name" | grep -qE '^[A-Z0-9_]+$'; then
            usage_error "--set con nombre invalido: $name" "solo [A-Z0-9_]"
        fi
        printf -v "$name" '%s' "$value"
        export "$name"
    done
}

# ============================================================== MAIN =========
main() {
    # 1a. color antes de parsear: los errores de uso necesitan poder imprimirse
    #     aunque el usuario haya pasado un --color equivocado.
    ezarr_log_init
    parse_args "$@"
    # 1b. y otra vez despues: --color/-v/-q solo se conocen al terminar de
    #     parsear. ezarr_log_init es idempotente.
    ezarr_log_init

    # --- 1. entorno ---------------------------------------------------------
    ezarr_detect_env
    log_v "entorno detectado: ${EZARR_ENV_KIND} (init=${EZARR_ENV_INIT}, android=${EZARR_ENV_ANDROID})"

    # --- 2. configuracion: fichero, no codigo --------------------------------
    ezarr_conf_defaults
    if [ "${#EXTRA_CONF[@]}" -gt 0 ]; then
        EZARR_CONF_FILES+=("${EXTRA_CONF[@]}")
    fi
    ezarr_config_load
    apply_set_overrides
    # --data-root / --release-base llegan despues de la carga: el flag gana
    EZARR_DATA_ROOT="${EZARR_DATA_ROOT:-/data}"
    ezarr_detect_resources   # recalcula el disco libre con la raiz definitiva

    # --- 3. componentes ------------------------------------------------------
    if [ -n "${ARGS_PROFILE:-}" ]; then EZARR_PROFILE="$ARGS_PROFILE"; fi
    ezarr_components_resolve --with "${ARGS_WITH:-}" --without "${ARGS_WITHOUT:-}" \
                             --only "${ARGS_ONLY:-}" --profile "$EZARR_PROFILE" \
        || ezarr_exit "${EZARR_EX_USAGE:-2}"

    # --- 4. el plan ----------------------------------------------------------
    ezarr_plan_begin "instalacion"

    if [ "$ARGS_JSON" = "1" ]; then
        json_plan
        return 0
    fi

    log_step "entorno"
    ezarr_env_summary

    # Los pasos se registran con su par plan_/apply_.
    ezarr_step_add "verificar requisitos"           plan_requisitos   apply_requisitos
    ezarr_step_add "estructura de directorios"      plan_directorios  apply_directorios
    ezarr_step_add "escribir configuracion"         plan_configuracion apply_configuracion
    ezarr_step_add "paquetes base"                  plan_paquetes     apply_paquetes
    ezarr_step_add "descargas verificadas"          plan_descargas    apply_descargas
    ezarr_step_add "scripts de operacion"           plan_scripts      apply_scripts
    ezarr_step_add "activar servicios"              plan_activar      apply_activar
    ezarr_step_add "registrar estado"               plan_estado       apply_estado

    ezarr_plan_run

    # --- 5. el mismo plan, resumido -----------------------------------------
    local plan_rc=0
    ezarr_plan_render || plan_rc="${EZARR_PLAN_PROBLEMS[0]%%:*}"
    plan_rc="${plan_rc:-${EZARR_EX_FAIL:-1}}"

    if [ "${#EZARR_PLAN_PROBLEMS[@]}" -gt 0 ]; then
        if [ "$EZARR_DRY_RUN" = "1" ]; then
            log_error "--dry-run: el plan NO es valido (codigo $plan_rc). No se ha tocado nada."
        else
            log_error "el plan no es valido: no se ha instalado nada (codigo $plan_rc)."
        fi
        ezarr_exit "$plan_rc"
    fi

    # --- 6. dry-run: aqui se acaba -------------------------------------------
    if [ "$EZARR_DRY_RUN" = "1" ]; then
        ezarr_fs_assert_clean || ezarr_exit "${EZARR_EX_FAIL:-1}"
        log_info "sin escrituras. Repite sin --dry-run cuando el plan te cuadre."
        ezarr_exit 0
    fi

    # --- 7. confirmacion ------------------------------------------------------
    # Antes de aplicar NADA. El prompt va a /dev/tty para no romper los pipes.
    if ! ezarr_confirm "¿Aplicar el plan? (${EZARR_PLAN_TOTAL} pasos)"; then
        log_info "cancelado: no se ha modificado nada"
        ezarr_exit 0
    fi

    # --- 8. aplicar -----------------------------------------------------------
    ezarr_plan_run
    ezarr_fs_assert_clean || ezarr_exit "${EZARR_EX_FAIL:-1}"

    # Se revisan TODOS los pasos, no solo el ultimo: un fallo en el paso 3 con
    # los pasos 4-8 correctos es un fallo de la instalacion, y anunciarla como
    # terminada seria la peor forma de mentir.
    local fallidos="" i
    for (( i = 0; i < EZARR_PLAN_TOTAL; i++ )); do
        [ "${EZARR_STEP_STATE[$i]}" = "problem" ] && fallidos="$fallidos $((i + 1)):${EZARR_STEP_DESC[$i]}"
    done
    if [ -n "$fallidos" ]; then
        log_error "la instalacion fallo en:$fallidos"
        log_error_hint "lo aplicado hasta ahi se queda; no se ha deshecho nada"
        log_error_hint "para ver que quedo vivo: ezarrctl status"
        log_error_hint "para reintentar sin romper lo hecho: vuelve a ejecutar el instalador"
        ezarr_exit "${EZARR_EX_FAIL:-1}"
    fi

    log_ok "instalacion terminada en $(ezarr_elapsed)s"
    log_info "NO se ha arrancado nada. El arranque lo decides tu:"
    log_info "  ezarrctl status   y luego   ezarrctl start"
    ezarr_exit 0
}

# Salida JSON por stdout: progreso y avisos siguen yendo a stderr, asi que esto
# se puede canalizar sin ensuciar el stream de datos.
json_plan() {
    local first=1 row id s
    printf '{ "app": "%s", "version": "%s", "env": "%s", "arch": "%s", "ram_mb": %s, "disk_free_mb": %s, "profile": "%s", "channel": "%s", "dry_run": %s, "components": [' \
        "$EZARR_APP_NAME" "$EZARR_STACK_VERSION" "$EZARR_ENV_KIND" "$EZARR_ENV_ARCH" \
        "${EZARR_ENV_RAM_MB:-0}" "${EZARR_ENV_DISK_FREE_MB:-0}" "$EZARR_PROFILE" \
        "${EZARR_CHANNEL:-stable}" "$EZARR_DRY_RUN"
    # Solo el conjunto RESUELTO, que es lo que se instalaria.
    for row in "${EZARR_COMPONENTS[@]}"; do
        id="${row%%|*}"
        [ -n "${EZARR_SET[$id]:-}" ] || continue
        [ "$first" = "1" ] || printf ', '
        first=0
        printf '"%s"' "$id"
    done
    printf '], "excluded": ['
    first=1
    for row in "${EZARR_COMPONENTS[@]}"; do
        id="${row%%|*}"
        [ -n "${EZARR_SET[$id]:-}" ] && continue
        [ "$first" = "1" ] || printf ', '
        first=0
        printf '"%s"' "$id"
    done
    printf '], "services": ['
    first=1
    for s in $(ezarr_selected_services); do
        [ "$first" = "1" ] || printf ', '
        first=0
        printf '"%s"' "$s"
    done
    printf '], "data_root": "%s", "state_dir": "%s", "plan_valid": %s }\n' \
        "$EZARR_DATA_ROOT" "$EZARR_STATE_DIR" "$([ "${#EZARR_PLAN_PROBLEMS[@]}" -eq 0 ] && echo true || echo false)"
    return 0
}

# Ctrl-C: 130, como todo el mundo. Nunca un estado a medias en silencio.
trap 'echo "" >&2; log_error "interrumpido por el usuario"; ezarr_exit 130' INT TERM

main "$@"