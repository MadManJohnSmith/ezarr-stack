#!/bin/bash
# lib/plan.sh — El instalador es un PLAN.
#
# Esta es la pieza que sostiene todo lo demas:
#
#   Cada paso tiene dos funciones:
#     plan_<algo>()   puro. Pregunta, mide, comprueba. NO escribe nada.
#     apply_<algo>()  ejecuta. Es el unico sitio donde se muta el sistema.
#
#   --dry-run ejecuta EXACTAMENTE el mismo plan() y se salta apply().
#   No es una reimplementacion que "se parece" al instalador: es el mismo
#   codigo con la mitad de las llamadas eliminadas. Esa es la diferencia entre
#   un dry-run que engana y uno en el que se puede confiar en CI.
#
#   Y como un unico punto de contacto puede fallar, hay una segunda capa: TODA
#   mutacion pasa por un wrapper ezarr_fs_* que en dry-run registra la operacion
#   pretendida y devuelve un stub. Si un paso se salta el wrapper, el test de
#   auditoria lo detecta (ver tests/smoke.sh).
#
#   --dry-run sale con codigo distinto de 0 si el plan es invalido, con el mismo
#   codigo que daria el install real. Un dry-run que siempre sale 0 no sirve de
#   puerta en CI.

# ------------------------------------------------------------- estado -------
EZARR_DRY_RUN="${EZARR_DRY_RUN:-0}"     # 1 = no mutar nada
EZARR_FS_ATTEMPTS=0                     # mutaciones pedidas (reales o simuladas)
EZARR_FS_PERFORMED=0                    # mutaciones realmente ejecutadas
EZARR_FS_PENDING=0                      # una escritura esta en curso (la cuenta _fsim)
EZARR_APPLY_ARMED=0                     # 1 = la pasada actual puede aplicar. Lo arma
                                        # ezarr.sh DESPUES de la confirmacion; mientras
                                        # valga 0, apply() no se ejecuta.
EZARR_PLAN_TOTAL=0
EZARR_PLAN_IDX=0
EZARR_PLAN_DONE=0
EZARR_PLAN_TITLE=""

declare -a EZARR_STEP_DESC=()
declare -a EZARR_STEP_PLAN=()
declare -a EZARR_STEP_APPLY=()
declare -a EZARR_STEP_STATE=()    # ok | problem | skipped | planned
declare -a EZARR_STEP_DETAIL=()
declare -a EZARR_PLAN_PROBLEMS=()

ezarr_plan_begin() {
    EZARR_PLAN_TITLE="$1"
    EZARR_PLAN_TOTAL=0; EZARR_PLAN_IDX=0; EZARR_PLAN_DONE=0
    EZARR_FS_ATTEMPTS=0; EZARR_FS_PERFORMED=0
    EZARR_STEP_DESC=(); EZARR_STEP_PLAN=(); EZARR_STEP_APPLY=()
    EZARR_STEP_STATE=(); EZARR_STEP_DETAIL=(); EZARR_PLAN_PROBLEMS=()
    return 0
}

# ezarr_step_add <descripcion> <funcion-plan> <funcion-apply>
ezarr_step_add() {
    EZARR_STEP_DESC+=("$1")
    EZARR_STEP_PLAN+=("$2")
    EZARR_STEP_APPLY+=("$3")
    EZARR_STEP_STATE+=("planned")
    EZARR_STEP_DETAIL+=("")
    EZARR_PLAN_TOTAL=$((EZARR_PLAN_TOTAL + 1))
    return 0
}

# Anota un problema detectado en plan: hace fallar el dry-run con el codigo real.
ezarr_plan_problem() {
    local code="${2:-4}" msg="$1"
    EZARR_PLAN_PROBLEMS+=("$code:$msg")
    log_error "$msg"
    local prev=""; local h
    for h in "${EZARR_PLAN_PROBLEMS[@]:1}"; do prev="${h#*:}"; log_error_hint "$prev"; done
    return 0
}

# ------------------------------------------------- ejecucion del plan -------
# ezarr_plan_run
#   Con --dry-run: solo plan(). apply() no se alcanza.
#   Sin --dry-run: plan() y, si no hay problema, apply().
ezarr_plan_run() {
    local i n="${#EZARR_STEP_DESC[@]}"
    EZARR_PLAN_IDX=0
    # El contador se reinicia en cada pasada: ezarr_plan_run se ejecuta DOS veces
    # (la del plan que se muestra y la que aplica). Sin este reset, el resumen
    # final_contabrera los pasos de las dos y anunciaria "16/8 pasos completados".
    EZARR_PLAN_DONE=0
    for (( i=0; i<n; i++ )); do
        EZARR_STEP_STATE[$i]="planned"
    done
    for (( i=0; i<n; i++ )); do
        EZARR_PLAN_IDX=$((i + 1))
        _ezarr_run_step "$i"
        # Un problema de plan detiene: seguir dibujando pasos que no van a
        # ocurrir solo confunde.
        [ "${EZARR_STEP_STATE[$i]}" = "problem" ] && break
    done
    return 0
}

_ezarr_run_step() {
    local i="$1" desc="${EZARR_STEP_DESC[$i]}"
    local pf="${EZARR_STEP_PLAN[$i]}" af="${EZARR_STEP_APPLY[$i]}"
    local t0 rc=0

    # El flag de fallo es POR PASO: si no se limpia aqui, un fallo del paso 2
    # marcaria como fallido el paso 3 aunque este vaya bien.
    EZARR_FS_FAILED=0

    log_step "[$EZARR_PLAN_IDX/$EZARR_PLAN_TOTAL] $desc"
    t0="$(ezarr_elapsed)"

    # --- 1) plan(): puro, se ejecuta SIEMPRE --------------------------------
    EZARR_STEP_DETAIL_LAST=""
    if declare -F "$pf" >/dev/null 2>&1; then
        if ! "$pf"; then
            rc=$?
            EZARR_STEP_STATE[$i]="problem"
            EZARR_STEP_DETAIL[$i]="comprobacion fallida (rc=$rc)"
            return 0
        fi
    fi
    # lo que el plan aprendio se muestra en el resumen
    [ -n "${EZARR_STEP_DETAIL_LAST:-}" ] && EZARR_STEP_DETAIL[$i]="$EZARR_STEP_DETAIL_LAST"

    # --- 2) apply(): aqui y solo aqui se muta ------------------------------
    # DOS puertas, y tienen que estar las dos:
    #   - --dry-run no aplica nada.
    #   - EZARR_APPLY_ARMED=0 durante la PRIMERA pasada, la que dibuja el
    #     resumen que se enseña antes de preguntar. Si aqui se aplicara, el
    #     instalador instalaria antes de pedir confirmacion y el prompt
    #     decoraria una instalacion ya hecha. Ver el paso 7 de ezarr.sh, que
    #     arma la bandera justo despues de que el usuario diga si.
    if [ "$EZARR_DRY_RUN" = "1" ] || [ "${EZARR_APPLY_ARMED:-0}" != "1" ]; then
        EZARR_STEP_STATE[$i]="planned"
        log_v "dry-run: ${EZARR_STEP_DETAIL[$i]:-sin cambios previstos}"
        return 0
    fi

    if declare -F "$af" >/dev/null 2>&1; then
        if ! "$af"; then
            rc=$?
            EZARR_STEP_STATE[$i]="problem"
            EZARR_STEP_DETAIL[$i]="fallo al aplicar (rc=$rc)"
            log_error "el paso '$desc' fallo"
            return 0
        fi
    fi
    # El paso puede haber devuelto 0 y aun asi haber fallado por dentro: es lo
    # que pasa cuando el apply es una secuencia terminada en `return 0`.
    if [ "$EZARR_FS_FAILED" != "0" ]; then
        EZARR_STEP_STATE[$i]="problem"
        EZARR_STEP_DETAIL[$i]="una escritura del paso fallo (ver el error de arriba)"
        log_error "el paso '$desc' fallo"
        EZARR_FS_FAILED=0
        return 0
    fi

    EZARR_STEP_STATE[$i]="ok"
    EZARR_PLAN_DONE=$((EZARR_PLAN_DONE + 1))
    # OJO: ${t0}s y no $t0s. Bash leeria "t0s" como el nombre de otra variable
    # y, con `set -u`, abortaria el script entero al imprimir el primer paso.
    log_ok "$desc (${t0}s -> $(ezarr_elapsed)s)"
    return 0
}

# --------------------------------------------------- render del plan --------
# El resumen se genera DESDE EL PLAN, la misma estructura que imprime
# --dry-run. Un segundo renderizado seria una segunda implementacion, y
# divergiria. (Aprendido de leer el instalador de Luctia/ezarr: el plan y el
# resumen son el mismo objeto.)
ezarr_plan_render() {
    local i n="${#EZARR_STEP_DESC[@]}"
    local mark color

    printf '\n' >&2
    printf '%sPlan de instalacion%s %s %s\n' "$EZARR_C_BOLD" "$EZARR_C_RESET" \
        "${EZARR_APP_NAME:-ezarr}" "${EZARR_STACK_VERSION:-?}" >&2

    printf '\n  %-12s %s\n' "entorno"    "$(ezarr_env_kind_label)" >&2
    printf '  %-12s %s\n' "perfil"     "${EZARR_PROFILE:-standard}   canal ${EZARR_CHANNEL:-stable}" >&2
    printf '  %-12s %s\n' "raiz datos" "${EZARR_DATA_ROOT:-/data}" >&2
    printf '\n' >&2

    printf '  Componentes (%s de %s)\n' "${EZARR_SELECTED_COUNT:-0}" "${EZARR_CATALOG_COUNT:-0}" >&2
    ezarr_components_render >&2
    printf '\n' >&2

    printf '  Pasos (%s)\n' "$EZARR_PLAN_TOTAL" >&2
    for (( i=0; i<n; i++ )); do
        case "${EZARR_STEP_STATE[$i]}" in
            ok)       mark="[ok]";      color="$EZARR_C_GREEN" ;;
            problem)  mark="[problema]"; color="$EZARR_C_RED" ;;
            planned)  mark="[plan]";    color="$EZARR_C_YELLOW" ;;
            skipped)  mark="[saltado]"; color="$EZARR_C_DIM" ;;
            *)        mark="[?]";       color="$EZARR_C_DIM" ;;
        esac
        printf '    %-9s %s%2d  %s%s\n' "$mark" "$color" "$((i + 1))" \
            "${EZARR_STEP_DESC[$i]}" "$EZARR_C_RESET" >&2
        if [ -n "${EZARR_STEP_DETAIL[$i]}" ] && [ "$EZARR_VERBOSITY" -ge 2 ]; then
            printf '              %s%s%s\n' "$EZARR_C_DIM" "${EZARR_STEP_DETAIL[$i]}" "$EZARR_C_RESET" >&2
        fi
    done
    printf '\n' >&2

    ezarr_plan_changes_render >&2

    if [ "${#EZARR_PLAN_PROBLEMS[@]}" -gt 0 ]; then
        printf '  %sProblemas del plan:%s\n' "$EZARR_C_RED" "$EZARR_C_RESET" >&2
        local p
        for p in "${EZARR_PLAN_PROBLEMS[@]}"; do
            printf '    %s- %s%s\n' "$EZARR_C_RED" "${p#*:}" "$EZARR_C_RESET" >&2
        done
        printf '\n' >&2
        return 1
    fi
    return 0
}

ezarr_plan_changes_render() {
    local i n="${#EZARR_STEP_DESC[@]}" any=0
    if [ "$EZARR_DRY_RUN" = "1" ] || [ "${EZARR_SHOW_CHANGES:-1}" = "1" ]; then
        printf '  Cambios en disco\n' >&2
        for (( i=0; i<n; i++ )); do
            case "${EZARR_STEP_STATE[$i]}" in
                ok|planned)
                    if [ -n "${EZARR_STEP_DETAIL[$i]}" ]; then
                        printf '    %s%s%s\n' "$EZARR_C_YELLOW" "${EZARR_STEP_DETAIL[$i]}" "$EZARR_C_RESET" >&2
                        any=1
                    fi
                    ;;
            esac
        done
        [ "$any" = "0" ] && printf '    (ninguno)\n' >&2
        printf '\n' >&2
    fi
    return 0
}

ezarr_env_kind_label() {
    case "${EZARR_ENV_KIND:-unknown}" in
        chroot)  printf 'chroot de telefono%s' "${EZARR_ENV_TWRP:+ (TWRP)}" ;;
        machine) printf 'maquina normal' ;;
        *)       printf 'desconocido' ;;
    esac
}

# ============================================================== WRAPPERS FS ==
# Unica puerta de salida hacia el sistema de ficheros y la ejecucion de
# procesos. En dry-run: registra y devuelve 0 sin hacer nada.
# En real: cuenta la ejecucion y la hace.
# El contador EZARR_FS_PERFORMED tiene que ser 0 SIEMPRE en dry-run. Es la
# asercion que convierte el contrato en algo verificable.

_fsim() {   # _fsim <descripcion legible>
    EZARR_FS_ATTEMPTS=$((EZARR_FS_ATTEMPTS + 1))
    if [ "$EZARR_DRY_RUN" = "1" ]; then
        log_v "dry-run: $1"
        return 0
    fi
    EZARR_FS_PERFORMED=$((EZARR_FS_PERFORMED + 1))
    EZARR_FS_PENDING=1
    log_v "$1"
    return 0
}

fs_mkdir() {
    [ "$EZARR_DRY_RUN" = "1" ] && { _fsim "mkdir -p $*"; return 0; }
    _fsim "mkdir -p $*"
    mkdir -p -- "$@" || _fs_fail "mkdir -p $*"
}
fs_write() { # fs_write <ruta> <contenido> [modo]
    local path="$1" content="$2" mode="${3:-0644}"
    _fsim "write $path ($(printf '%s' "$content" | wc -c) bytes, modo $mode)"
    [ "$EZARR_DRY_RUN" = "1" ] && return 0
    mkdir -p -- "$(dirname -- "$path")" || { _fs_fail "mkdir $(dirname -- "$path")"; return 1; }
    printf '%s\n' "$content" > "$path" || { _fs_fail "write $path"; return 1; }
    chmod "$mode" "$path" || { _fs_fail "chmod $mode $path"; return 1; }
}
fs_append() { # fs_append <ruta> <contenido> [modo]
    local path="$1" content="$2" mode="${3:-0644}"
    _fsim "append $path"
    [ "$EZARR_DRY_RUN" = "1" ] && return 0
    mkdir -p -- "$(dirname -- "$path")" || { _fs_fail "mkdir $(dirname -- "$path")"; return 1; }
    printf '%s\n' "$content" >> "$path" || { _fs_fail "append $path"; return 1; }
    chmod "$mode" "$path"
}
fs_chmod()  { _fsim "chmod $*";   [ "$EZARR_DRY_RUN" = "1" ] || chmod -- "$@" || _fs_fail "chmod $*"; }
fs_chown()  { _fsim "chown $*";   [ "$EZARR_DRY_RUN" = "1" ] || chown -- "$@" || _fs_fail "chown $*"; }
fs_install(){ _fsim "install $*"; [ "$EZARR_DRY_RUN" = "1" ] || install "$@" || _fs_fail "install $*"; }
fs_copy()   { _fsim "copy -a $*"; [ "$EZARR_DRY_RUN" = "1" ] || cp -a -- "$@" || _fs_fail "copy $*"; }
fs_symlink(){ _fsim "symlink $*"; [ "$EZARR_DRY_RUN" = "1" ] || ln -sfn -- "$@" || _fs_fail "symlink $*"; }
fs_remove() { _fsim "remove $*";  [ "$EZARR_DRY_RUN" = "1" ] || rm -rf -- "$@" || _fs_fail "remove $*"; }
fs_touch()  { _fsim "touch $*";   [ "$EZARR_DRY_RUN" = "1" ] || touch -- "$@" || _fs_fail "touch $*"; }

# _fs_fail <operacion> — registra que una escritura real ha fallado.
#
# Existe porque los pasos de apply son SECUENCIAS: `apply_directorios` mete un
# bucle con `fs_mkdir` y termina con `return 0`. El codigo de salida del ultimo
# comando no es el del paso, y un paso que "termina en 0" mientras sus mkdir
# fallaban seeria un fallo silencioso. Este flag no depende de cual fue el
# ultimo comando, asi que no se puede perder.
EZARR_FS_FAILED=0
_fs_fail() {
    EZARR_FS_FAILED=1
    # _fsim ya habia contado esta escritura como hecha. Si la escritura
    # falla, se descuenta: el contador tiene que responder a "cuanto se toco
    # de verdad", no a "cuanto se intento". Sin esto, un `mkdir` que acaba en
    # "Permission denied" sale en el resumen como una escritura hecha.
    # Un envoltorio llama a _fsim una vez y puede llamar a _fs_fail varias
    # veces (mkdir, write, chmod), asi que la primera descuenta y las
    # siguientes no.
    if [ "${EZARR_FS_PENDING:-0}" = "1" ]; then
        EZARR_FS_PERFORMED=$((EZARR_FS_PERFORMED - 1))
        EZARR_FS_PENDING=0
    fi
    log_error "no se pudo: $1"
    return 0
}

# fs_plan <descripcion> — declara una mutacion que apply() hara.
# Es la segunda capa de garantia, y la que hace que el dry-run sea informativo:
# apply() NO se alcanza, asi que sin esto el contador de operaciones prevista
# seria siempre 0 y el resumen no diria nada. Aqui queda escrito lo que el paso
# va a hacer, y el contador permite auditarlo desde los tests.
fs_plan() {
    EZARR_FS_ATTEMPTS=$((EZARR_FS_ATTEMPTS + 1))
    EZARR_STEP_DETAIL_LAST="$1"
    log_v "dry-run: $1"
    return 0
}

# fs_run <argv...> — ejecutar un comando. Sin shell: nunca se concatena una
# cadena con el comando, asi que un valor con espacios o metacarácteres no
# puede convertirse en inyeccion. Es el error que arrastra el codigo real del
# stack cuando hace `os.system(f'... {var} ...')`.
fs_run() {
    _fsim "exec$(printf ' %q' "$@")"
    if [ "$EZARR_DRY_RUN" = "1" ]; then
        # en dry-run no se puede saber el rc; se asume exito para no cortar el plan
        return 0
    fi
    log_trace "exec argv: $(printf '%q ' "$@")"
    "$@"
}

# fs_apt <paquetes...> — instalar paquetes.
# Idempotente de verdad: si TODOS los paquetes ya estan instalados, no se llama
# a apt-get. No es una optimizacion estetica: instalar el stack dos veces no
# debe tardar 40 segundos en un `apt-get install -y` que no cambia nada, y en
# un telefono ese tiempo es tiempo que el stack esta parado.
fs_apt() {
    local pkgs="$*" tool p faltan=""
    [ -n "$pkgs" ] || return 0
    have dpkg-query || return 0
    for p in $pkgs; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || faltan="$faltan $p"
    done
    [ -z "$faltan" ] && { log_v "todos los paquetes ya instalados"; return 0; }

    # --offline / EZARR_OFFLINE=1 significa "instala lo que puedas SIN red": se
    # sigue con el resto del plan y se dice en voz alta que paquetes quedan
    # sin instalar. Antes este caso solo miraba el flag --offline de la linea de
    # ordenes, asi que la variable de entorno se ignoraba: en un runner donde
    # los paquetes base no estan (CI, contenedor limpio) el instalador intentaba
    # apt-get, fallaba y abortaba con 1 en vez de instalar lo que si dependia de
    # el. Los dos caminos llegan aqui: el flag pone EZARR_OFFLINE=1 en el shell,
    # y el entorno la exporta. Leer la variable cubre ambos.
    if [ "${EZARR_OFFLINE:-0}" = "1" ]; then
        log_info "modo offline: no se instalan paquetes; faltan:$faltan"
        return 0
    fi

    tool="$(tool_path apt-get)" || { log_warn "apt-get no disponible: no se instalan ($faltan)"; return 0; }
    _fsim "apt-get install -y $(printf '%s' "$faltan" | xargs)"
    [ "$EZARR_DRY_RUN" = "1" ] && return 0
    log_v "instalando:$faltan"
    DEBIAN_FRONTEND=noninteractive "$tool" install -y -qq $faltan
}

# --------------------------------------------------------------- aserciones --
# Se usan desde los tests. Si el dry-run dejo pasar una mutacion, el contrato
# esta roto y hay que enterarse, no seguir.
ezarr_fs_assert_clean() {
    if [ "$EZARR_DRY_RUN" = "1" ] && [ "$EZARR_FS_PERFORMED" -ne 0 ]; then
        log_error "CONTRATO ROTO: --dry-run ejecuto $EZARR_FS_PERFORMED mutaciones"
        return 1
    fi
    return 0
}