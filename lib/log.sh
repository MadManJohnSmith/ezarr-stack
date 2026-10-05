#!/bin/bash
# lib/log.sh — Logging con niveles de verbosidad, formato uniforme y color condicional.
#
# Reglas del modulo (se respetan en todo el stack):
#   * Progreso, avisos y errores van SIEMPRE a stderr. stdout solo lleva datos.
#     Asi `ezarr.sh --dry-run > plan.txt` deja stdout limpio y `... | tee log` funciona.
#   * Sin TTY no hay ANSI, no hay \r: una linea por paso.
#   * Todo error lleva remedio accionable. Un error sin siguiente paso es un bug.
#
# Uso tipico:
#   EZARR_VERBOSITY=2   # 0=error · 1=normal · 2=verboso · 3=debug · 4=trace
#
# Sin efectos secundarios salvo inicializar contadores. Idempotente.

# ---------------------------------------------------------------- verbosidad --
# 0: solo errores + linea de resultado final
# 1: una linea por paso (por defecto)
# 2: cada accion, cada URL, cada fichero escrito
# 3: lo anterior + diagnostico (cabeceras HTTP, timers, plan en JSON)
EZARR_VERBOSITY="${EZARR_VERBOSITY:-1}"

# --------------------------------------------------------------------- color --
# Se resuelve una sola vez. NEVER gana sobre todo; AUTO cae a NEVER sin TTY.
ezarr_log_init() {
    EZARR_T0="${EZARR_T0:-$(date +%s%N 2>/dev/null || echo 0)}"

    local want="${EZARR_COLOR:-auto}"
    case "$want" in
        never) EZARR_USE_COLOR=0 ;;
        always) EZARR_USE_COLOR=1 ;;
        auto)
            # stderr es el canal de progreso: si stderr no es TTY, no hay color.
            if [ -t 2 ] && [ -z "${EZARR_NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
                EZARR_USE_COLOR=1
            else
                EZARR_USE_COLOR=0
            fi
            ;;
        *) ezarr_die "valor invalido para --color: $want (usa auto|always|never)" ;;
    esac

    if [ "$EZARR_USE_COLOR" = "1" ]; then
        EZARR_C_RESET=$'\033[0m'
        EZARR_C_DIM=$'\033[2m'
        EZARR_C_BOLD=$'\033[1m'
        EZARR_C_RED=$'\033[31m'
        EZARR_C_GREEN=$'\033[32m'
        EZARR_C_YELLOW=$'\033[33m'
        EZARR_C_BLUE=$'\033[34m'
        EZARR_C_CYAN=$'\033[36m'
    else
        EZARR_C_RESET='' EZARR_C_DIM='' EZARR_C_BOLD=''
        EZARR_C_RED='' EZARR_C_GREEN='' EZARR_C_YELLOW=''
        EZARR_C_BLUE='' EZARR_C_CYAN=''
    fi
    return 0
}

# ------------------------------------------------------------------ helpers --
ezarr_elapsed() {
    local now t0
    t0="${EZARR_T0:-0}"
    now="$(date +%s%N 2>/dev/null || echo 0)"
    # Un date sin soporte de %N devuelve la cadena literal: caemos a 0.
    case "$now" in *N*|'') echo "0.0"; return 0 ;; esac
    awk -v a="$t0" -v b="$now" 'BEGIN{printf "%.1f", (b-a)/1000000000}'
}

ezarr_human_bytes() {
    local b="${1:-0}"
    case "$b" in *[!0-9]*) echo "$b"; return 0 ;; esac
    if   [ "$b" -lt 1024 ];        then printf '%d B' "$b"
    elif [ "$b" -lt 1048576 ];     then awk -v b="$b" 'BEGIN{printf "%.1f KB", b/1024}'
    elif [ "$b" -lt 1073741824 ];  then awk -v b="$b" 'BEGIN{printf "%.1f MB", b/1048576}'
    else                                awk -v b="$b" 'BEGIN{printf "%.1f GB", b/1073741824}'
    fi
}

# ------------------------------------------------------- primitivas de salida --
# _emit <color> <prefijo> <mensaje>
_emit() {
    local color="$1" prefix="$2"; shift 2
    printf '%s%s%s %s\n' "$color" "$prefix" "$EZARR_C_RESET" "$*" >&2
}

# Nivel 1: pasos. Es lo que se ve en el uso diario.
log_step() { [ "$EZARR_VERBOSITY" -ge 1 ] && _emit "${EZARR_C_CYAN}" "->" "$*" || true; return 0; }
log_ok()   { [ "$EZARR_VERBOSITY" -ge 1 ] && _emit "${EZARR_C_GREEN}" "OK" "$*" || true; return 0; }
log_info() { [ "$EZARR_VERBOSITY" -ge 1 ] && _emit "$EZARR_C_DIM" "  " "$*" || true; return 0; }

# Nivel 2: acciones concretas.
# En dry-run se muestran tambien con el nivel normal: es el UNICO momento en que
# esta bien ver cada operacion prevista, porque es cuando no se ejecuta nada.
# Por eso el dry-run no necesita -v para ser util.
log_v() {
    if [ "$EZARR_VERBOSITY" -ge 2 ] || [ "${EZARR_DRY_RUN:-0}" = "1" ]; then
        _emit "${EZARR_C_BLUE}" "   " "$*"
    fi
    return 0
}

# Nivel 3: diagnostico.
log_debug(){ [ "$EZARR_VERBOSITY" -ge 3 ] && _emit "$EZARR_C_DIM" "  ." "$*" || true; return 0; }
log_trace(){ [ "$EZARR_VERBOSITY" -ge 4 ] && _emit "$EZARR_C_DIM" "  :" "$*" || true; return 0; }

# Avisos: nunca abortan, van a stderr con prefijo explicito.
log_warn() {
    [ "$EZARR_VERBOSITY" -ge 1 ] || return 0
    printf '%swarning:%s %s\n' "$EZARR_C_YELLOW" "$EZARR_C_RESET" "$*" >&2
    return 0
}

# El detalle del error va indentado bajo el error, nunca en la misma linea.
log_error_hint() { printf '%s  -> %s%s\n' "$EZARR_C_DIM" "$*" "$EZARR_C_RESET" >&2; }

log_error() {
    printf '%serror:%s %s\n' "$EZARR_C_RED" "$EZARR_C_RESET" "$*" >&2
    return 0
}

# -------------------------------------------------------------------- salida --
# ezarr_exit <codigo> — punto de salida unico: imprime resumen de pasos y sale.
ezarr_exit() {
    local code="${1:-0}"
    if [ "${EZARR_PLAN_TOTAL:-0}" -gt 0 ]; then
        if [ "$code" -eq 0 ]; then
            if [ "${EZARR_DRY_RUN:-0}" = "1" ]; then
                log_ok "plan correcto: ${EZARR_PLAN_TOTAL} pasos, ${EZARR_FS_ATTEMPTS:-0} operaciones previstas"
            else
                log_ok "completado: ${EZARR_PLAN_DONE:-0}/${EZARR_PLAN_TOTAL} pasos"
            fi
        else
            # Decir "N pasos aplicados" cuando N son pasos de solo lectura
            # (un preflight, un chequeo de red) hace creer que se instalo algo.
            # El numero que responde a "¿quedo el sistema tocado?" es el de
            # escrituras REALES, no el de pasos completados.
            if [ "${EZARR_FS_PERFORMED:-0}" -eq 0 ]; then
                log_warn "interrumpido en el paso ${EZARR_PLAN_IDX:-?}/${EZARR_PLAN_TOTAL}: nada se ha modificado"
            else
                log_warn "interrumpido en el paso ${EZARR_PLAN_IDX:-?}/${EZARR_PLAN_TOTAL}: ${EZARR_PLAN_DONE:-0} pasos aplicados, ${EZARR_FS_PERFORMED} escrituras hechas"
            fi
        fi
    fi
    exit "$code"
}

# ezarr_die <mensaje> [remedio...]
# Error con remedio obligatorio. Si no hay remedio, el propio mensaje lo dice.
ezarr_die() {
    local msg="$1"; shift
    log_error "$msg"
    local hint
    for hint in "$@"; do log_error_hint "$hint"; done
    ezarr_exit 1
}

# --------------------------------------------------------- normalizacion ---
# Convierte `--opcion=valor` en `--opcion valor` para las opciones que llevan
# argumento. Es la convencion GNU y la que la gente teclea por reflejo: escribir
# un parser que solo acepte `--color always` y no `--color=always` convierte un
# error tipografico en un "flag desconocido" que parece que el programa no
# entiende su propia ayuda.
#
# Uso:   ezarr_normalize_args "$@"    ->   EZARR_ARGS=(...)
ezarr_normalize_args() {
    EZARR_ARGS=()
    local a k v needs_value=0
    # Opciones que consumen el argumento siguiente.
    local con_valor=" --config --data-root --release-base --set --with --without --only --profile --color --component --timeout --tail --since --level --keep --output --channel "
    local con_valor_equals=" --config= --data-root= --release-base= --set= --with= --without= --only= --profile= --color= --component= --timeout= --tail= --since= --level= --keep= --output= --channel= "

    for a in "$@"; do
        if [ "$needs_value" = "1" ]; then
            EZARR_ARGS+=("$a"); needs_value=0; continue
        fi
        case "$a" in
            --*=*)
                k="${a%%=*}"; v="${a#*=}"
                case "$con_valor_equals" in
                    *" $k="*) EZARR_ARGS+=("$k" "$v"); continue ;;
                    *)       EZARR_ARGS+=("$a"); continue ;;
                esac
                ;;
            --*)
                case "$con_valor" in *" $a "*) needs_value=1 ;; esac
                EZARR_ARGS+=("$a")
                ;;
            *)
                EZARR_ARGS+=("$a")
                ;;
        esac
    done
    return 0
}

# ---------------------------------------------------------------- confirmacion --
# Lee de /dev/tty, NUNCA de stdin: asi `ezarr.sh | tee log` y `... | less` funcionan.
# s|y|yes|si|S|Y -> si · n|no -> no · q|quit -> abortar con codigo 1
# Cualquier otra cosa, EOF y Ctrl-C abortan. Sale 130 en SIGINT.
ezarr_confirm() {
    local prompt="${1:-¿Continuar?}" ans=""
    if [ "${EZARR_ASSUME_YES:-0}" = "1" ]; then
        _emit "$EZARR_C_GREEN" "OK" "$prompt -> sí (--yes)"
        return 0
    fi
    # OJO: no basta con `[ -e /dev/tty ]`. /dev/tty puede EXISTIR y aun asi no
    # abrirse: es lo que pasa dentro de un contenedor o de un proceso sin
    # terminal controladora, donde abrirlo devuelve "No such device or
    # address" y el read escupe ese error de bash crudo en mitad del resumen.
    # La pregunta que importa no es si existe, es si se puede ABRIR.
    if ! ( : < /dev/tty ) 2>/dev/null; then
        log_error "$prompt: no hay terminal para pedir confirmacion"
        log_error_hint "pasa --yes para instalar sin preguntar, o --dry-run para ver el plan"
        ezarr_exit 1
    fi
    if [ ! -t 0 ] && [ -n "${CI:-}" ]; then
        log_error "$prompt: entrada no interactiva y --yes no indicado"
        log_error_hint "en CI hay que pasar --yes explicitamente"
        ezarr_exit 1
    fi

    printf '%s%s [s/N/q] %s' "$EZARR_C_BOLD" "$prompt" "$EZARR_C_RESET" >&2
    if ! IFS= read -r ans < /dev/tty 2>/dev/null; then
        printf '\n' >&2
        log_error "sin respuesta: abortado sin tocar nada"
        ezarr_exit 1
    fi
    case "$ans" in
        s|S|si|SI|y|Y|yes|YES) return 0 ;;
        n|N|no|NO)            return 1 ;;
        q|Q|quit|QUIT)        log_info "abortado por el usuario"; ezarr_exit 1 ;;
        "")                   return 1 ;;
        *)                    log_error "respuesta no reconocida: '$ans'"; ezarr_exit 1 ;;
    esac
}

# --------------------------------------------------------- codigos de salida --
# Tabla unica y estable. Todo el stack usa estos codigos; estan documentados en
# README y en `ezarrctl help exit-codes`.
EZARR_EX_OK=0        # correcto
EZARR_EX_FAIL=1      # error generico (o `doctor` encontro problemas)
EZARR_EX_USAGE=2     # uso incorrecto: flag o argumento invalido
EZARR_EX_NOTINST=3   # no instalado / estado incompatible con la operacion
EZARR_EX_CONFLICT=4  # conflicto de componentes o requisito no satisfecha
EZARR_EX_NETWORK=5   # fallo de red o descarga
EZARR_EX_VERIFY=6    # verificacion de integridad fallida (checksum o firma)
EZARR_EX_PERM=7      # permisos insuficientes (no root)
EZARR_EX_INTR=130    # interrumpido por el usuario

ezarr_exit_codes_help() {
    cat <<'EOF'
CODIGOS DE SALIDA

  0    correcto
  1    error generico, o `doctor` encontro problemas
  2    uso incorrecto (flag o argumento invalido)
  3    no instalado, o el estado es incompatible con la operacion
  4    conflicto de componentes o requisito no satisfecha
  5    fallo de red o descarga
  6    verificacion de integridad fallida (checksum o firma)
  7    permisos insuficientes (no root)
  130  interrumpido por el usuario (Ctrl-C)

EOF
}