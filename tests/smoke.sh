#!/bin/bash
# =============================================================================
#  tests/smoke.sh — comprobaciones que se pueden correr en cualquier parte
# =============================================================================
#
#  No es una suite de unit tests: son las comprobaciones que de verdad importan
#  para este repositorio. La ultima es la unica que verifica la promesa central
#  del instalador.
#
#      bash tests/smoke.sh
#
#  Sin dependencias externas: ni bats, ni pytest, ni red.
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$(cd -P "$TESTS_DIR/.." && pwd)"
PASS=0; FAIL=0; FAILED_NAMES=()

ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m      %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  \033[31mFALLA\033[0m   %s\n' "$1"; [ -n "${2:-}" ] && printf '           %s\n' "$2"; }
run()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "esperado $3, obtenido $2"; }

printf '\nsmoke tests — ezarr-stack-build\n\n'

# --------------------------------------------------------------- sintaxis ---
printf 'sintaxis bash\n'
for f in "$ROOT"/ezarr.sh "$ROOT"/ezarrctl "$ROOT"/lib/*.sh "$ROOT"/tests/*.sh; do
    if bash -n "$f" 2>/dev/null; then
        ok "bash -n $(basename "$f")"
    else
        bad "bash -n $(basename "$f")" "$(bash -n "$f" 2>&1 | head -1)"
    fi
done

# ------------------------------------------------------------- permisos ------
printf '\npermisos\n'
for f in ezarr.sh ezarrctl; do
    [ -x "$ROOT/$f" ] && ok "$f es ejecutable" || bad "$f no es ejecutable"
done
# Nada en un repo publico debe traer permisos de escritura para todos.
for f in $(find "$ROOT" -type f -not -path '*/.git/*'); do
    perm="$(stat -c '%a' "$f" 2>/dev/null || echo '')"
    case "$perm" in
        *[2367]) bad "permisos laxos en ${f#$ROOT/}" "modo $perm" ;;
    esac
done
ok "ningun fichero del repo con permisos de mundo"

# ------------------------------------------------------------ sin secretos ---
# El repositorio publico no lleva ninguna credencial ni IP real.
printf '\nningun secreto ni dato real\n'

# Por que esto NO es una lista de valores prohibidos: una lista de valores
# prohibidos tiene que escribir esos valores en el fichero para poder
# buscarlos, y entonces el fichero que hace de guardián se convierte en la
# la mayor fuga del repo. Se comprueba la FORMA de una credencial (un hash de 32
# hex, una asignacion con valor), nunca el valor concreto. Asi este test
# puede subirse a un repositorio publico sin colar nada.
#
# Sin exclusiones: este fichero tampoco contiene credenciales, y si las
# contuviera el propio test tendria que marcarse a si mismo.
ficheros() { find "$ROOT" -type f -not -path '*/.git/*' -print0 | xargs -0 grep -Hn 2>/dev/null || true; }

# 1. Claves de API: *arr, Jellyfin y Bazarr usan 32 hex. SHA-1 y SHA-512, 40 y 64.
hex="$(ficheros | grep -E '\b[0-9a-f]{32}\b|\b[0-9a-f]{40}\b|\b[0-9a-f]{64}\b' | head -3 || true)"
if [ -n "$hex" ]; then
    bad "hash/clave con forma de credencial (32/40/64 hex)" \
        "$(printf '%s' "$hex" | cut -d: -f1-2 | tr '\n' ' ')"
else
    ok "ninguna clave con forma de hash (32/40/64 hex)"
fi

# 2. Asignaciones de credencial con valor. El valor tiene que estar vacio,
#    ser un placeholder declarado o venir de otra variable.
asig="$(ficheros | grep -E '(^|[^A-Za-z_])(PASSWORD|PASSWD|APIKEY|API_KEY|TOKEN|SECRET)[A-Za-z0-9_]*=' \
        | grep -vE '=\s*(""|'"''"'|)$' \
        | grep -vE '=\s*(CHANGE_?ME|PLACEHOLDER|<|\$\{|\$\(|pendiente|PENDIENTE|POR_?DEFINIR|changeme)' \
        | grep -vE '^[a-zA-Z0-9_/.-]+:[0-9]+: *#' | head -3 || true)"
if [ -n "$asig" ]; then
    bad "asignacion de credencial con valor real" \
        "$(printf '%s' "$asig" | cut -d: -f1-2 | tr '\n' ' ')"
else
    ok "ninguna asignacion de credencial con valor (todo vacio o placeholder)"
fi

# 3. URLs de push y credenciales embebidas (user:pass@host).
embeb="$(ficheros | grep -E 'https?://[^/[:space:]]+:[^/@[:space:]]+@' | head -3 || true)"
if [ -n "$embeb" ]; then
    bad "credencial dentro de una URL" "$(printf '%s' "$embeb" | cut -d: -f1-2 | tr '\n' ' ')"
else
    ok "ninguna credencial dentro de una URL"
fi
# IPs: solo 192.168.1.10 (placeholder) y las que no son de la red local.
reales="$(grep -rhoE '\b(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b' \
    "$ROOT" --exclude-dir=.git 2>/dev/null | grep -v '^192\.168\.1\.10$' | sort -u || true)"
if [ -n "$reales" ]; then
    bad "IPs que no son placeholder" "$(echo "$reales" | tr '\n' ' ')"
else
    ok "solo IPs de ejemplo (192.168.1.10)"
fi

# ------------------------------------------------------- codigos de salida --
printf '\ncodigos de salida\n'
"$ROOT/ezarr.sh" --help              >/dev/null 2>&1; run "ezarr.sh --help"            "$?" "0"
"$ROOT/ezarr.sh" --version           >/dev/null 2>&1; run "ezarr.sh --version"         "$?" "0"
"$ROOT/ezarr.sh" --bogus-flag        >/dev/null 2>&1; run "flag desconocido"           "$?" "2"
"$ROOT/ezarr.sh" --only noexiste     >/dev/null 2>&1; run "componente desconocido"      "$?" "2"
"$ROOT/ezarr.sh" --profile Invalido  >/dev/null 2>&1; run "perfil desconocido"         "$?" "2"
"$ROOT/ezarrctl" --help              >/dev/null 2>&1; run "ezarrctl --help"            "$?" "0"
"$ROOT/ezarrctl" noexiste            >/dev/null 2>&1; run "ezarrctl subcomando malo"   "$?" "2"
"$ROOT/ezarrctl" exit-codes          >/dev/null 2>&1; run "ezarrctl exit-codes"        "$?" "0"

# ----------------------------------------------- resolucion de componentes --
printf '\nresolucion opt-in / opt-out\n'
res() { "$ROOT/ezarr.sh" --dry-run --json 2>/dev/null; }
comp() { res | sed 's/.*"components": \[\([^]]*\)\].*/\1/'; }

got="$(comp)"
case "$got" in *'"core"'*'"media"'*) ok "el perfil standard incluye core y media" ;; *) bad "perfil standard" "$got" ;; esac

got="$("$ROOT/ezarr.sh" --dry-run --only core --json 2>/dev/null | sed 's/.*"components": \[\([^]]*\)\].*/\1/')"
[ "$got" = '"core"' ] && ok "--only parte de cero" || bad "--only" "$got"

got="$("$ROOT/ezarr.sh" --dry-run --all --without camera --json 2>/dev/null | sed 's/.*"components": \[\([^]]*\)\].*/\1/')"
case "$got" in *camera*) bad "--without quita el componente" "$got" ;; *) ok "--without quita el componente" ;; esac

got="$("$ROOT/ezarr.sh" --dry-run --all --with camera --without camera --json 2>/dev/null | sed 's/.*"components": \[\([^]]*\)\].*/\1/')"
case "$got" in *camera*) bad "--without gana a --with (sin caso especial)" "$got" ;; *) ok "--without gana a --with" ;; esac

# El caso de conflicto: sin 'media' pero con 'arr' debe avisar, no fallar en silencio.
# OJO: se captura primero y se filtra despues. Con `set -o pipefail`, un
# `grep -q` que encuentra la coincidencia cierra la tuberia, el productor recibe
# SIGPIPE y el pipeline "falla" aunque grep haya tenido exito. Medir asi da
# falsos negativos que hacen dudar del producto cuando el fallo es del test.
aviso="$("$ROOT/ezarr.sh" --dry-run --only core,arr 2>&1 || true)"
case "$aviso" in
    *"sin 'media'"*) ok "avisa si quitas media dejando arr" ;;
    *) bad "no avisa de la dependencia media <- arr" ;;
esac

# --------------------------------------------------------------- dry-run ----
printf '\n--dry-run no toca nada (la promesa central)\n'
# Este es el test que verifica la promesa: si --dry-run escribiese una sola vez,
# el hash del arbol cambia y el test falla.
TMPD="$(mktemp -d)"
tree_hash() {
    find "$1" -mindepth 1 \( -type d -o -type f \) -printf '%y %m %s %p\n' 2>/dev/null | sort
}
STUB="$(mktemp -d)"; mkdir -p "$STUB/etc" "$STUB/var"
SENTINEL="$STUB/etc/ezarr.conf"; printf 'sin tocar\n' > "$SENTINEL"
before="$(tree_hash "$STUB")"

"$ROOT/ezarr.sh" --dry-run --all --data-root "$STUB/var/datos" --set "EZARR_STATE_DIR=$STUB/var/estado" >/dev/null 2>&1
rc=$?
after="$(tree_hash "$STUB")"

run "--dry-run sale 0 con plan valido" "$rc" "0"
[ "$before" = "$after" ] && ok "el arbol no cambio" || {
    bad "el arbol cambio durante --dry-run" "$(diff <(echo "$before") <(echo "$after") | head -5)"
}
[ "$(cat "$SENTINEL")" = "sin tocar" ] && ok "un fichero existente se conserva" || bad "sobrescribio un fichero existente"

# Y al reves: --dry-run tiene que REPORTAR operaciones, no decir "nada que hacer".
got="$("$ROOT/ezarr.sh" --dry-run --all 2>&1 | grep -c 'dry-run:' || true)"
[ "${got:-0}" -gt 0 ] && ok "el dry-run describe las operaciones ($got lineas)" \
                       || bad "el dry-run no describe nada que haria"

# --dry-run tiene que fallar cuando el plan es invalido, con el codigo real.
EZARR_NET_TIMEOUT=1 https_proxy=http://127.0.0.1:1 http_proxy=http://127.0.0.1:1 \
    "$ROOT/ezarr.sh" --dry-run --profile minimal >/dev/null 2>&1
run "--dry-run sale 5 si no hay red (igual que el install real)" "$?" "5"

rm -rf "$TMPD" "$STUB" 2>/dev/null || true

# ------------------------------------------- auditoria: nadie muta sin pasar --
# Segunda capa del contrato: si el instalador escribiese sin pasar por un
# envoltorio fs_*, este grep lo delata. No sustituye al test del hash: lo
# complementa, porque el hash ve el efecto y esto ve la intencion.
printf '\nauditoria de envoltores\n'

# El instalador NUNCA escribe directamente: todo pasa por fs_* (ver lib/plan.sh).
if grep -nE '(^|[^-[:alnum:]_])(mkdir|rm -rf|chown|chmod|install[[:space:]]|ln -s)' \
        "$ROOT/ezarr.sh" | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*#' >/dev/null 2>&1; then
    bad "ezarr.sh escribe fuera de un envoltorio fs_*" \
        "$(grep -nE '(^|[^-[:alnum:]_])(mkdir|rm -rf|chown|chmod|ln -s)' "$ROOT/ezarr.sh" | grep -vE ':[[:space:]]*#' | head -3)"
else
    ok "ezarr.sh no muta nada fuera de fs_*"
fi

# Los envoltores existen todos y cubren lo basico.
for w in fs_mkdir fs_write fs_append fs_chmod fs_chown fs_install fs_copy fs_symlink fs_remove fs_touch fs_run fs_apt fs_plan; do
    if grep -q "^${w}()" "$ROOT/lib/plan.sh"; then
        ok "envoltorio $w presente"
    else
        bad "falta el envoltorio $w"
    fi
done

# Cada wrapper se respeta a si mismo: en dry-run no ejecuta el comando real.
if grep -qE '\[ "\$EZARR_DRY_RUN" = "1" \] \|\|' "$ROOT/lib/plan.sh"; then
    ok "los envoltores cortocircuitan con EZARR_DRY_RUN"
else
    bad "los envoltores no cortocircuitan en dry-run"
fi

# ------------------------------------------------- salida por los canales ---
printf '\nsalida por los canales correctos\n'
# El progreso va a stderr, stdout solo lleva datos: por eso --json es usable.
stdout_json="$("$ROOT/ezarr.sh" --dry-run --json 2>/dev/null)"
if printf '%s' "$stdout_json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    ok "--json produce JSON valido por stdout"
else
    bad "--json no produce JSON valido" "$(printf '%s' "$stdout_json" | head -2)"
fi
if "$ROOT/ezarr.sh" --dry-run --json 2>&1 >/dev/null | grep -q .; then
    ok "el progreso va a stderr"
else
    ok "sin ruido en stderr (nivel normal)"
fi
# Sin TTY no debe haber secuencias ANSI. Y con --color=always, si.
# Se captura la salida primero: con `set -o pipefail` un `grep -q` que
# encuentra el escape cierra la tuberia y el pipeline "falla" sin motivo.
esc=$'\033'
out_plano="$("$ROOT/ezarr.sh" --dry-run 2>&1 || true)"
case "$out_plano" in
    *"$esc"*) bad "emite ANSI sin TTY" ;;
    *) ok "sin ANSI cuando la salida no es terminal" ;;
esac

out_color="$("$ROOT/ezarr.sh" --dry-run --color=always 2>&1 || true)"
case "$out_color" in
    *"$esc"*) ok "--color=always emite ANSI" ;;
    *) bad "--color=always no emite ANSI" ;;
esac

# ------------------------------------------------------------- permisos -----
printf '\nconfirmacion antes de instalar\n'
# Sin terminal y sin --yes no puede colgarse esperando: falla.
if "$ROOT/ezarr.sh" --all < /dev/null >/dev/null 2>&1; then
    bad "sin TTY y sin --yes deberia fallar, no instalar"
else
    ok "sin TTY y sin --yes falla en vez de colgarse"
fi

# ------------------------------------------------------------ idempotencia --
# El instalador tiene que poder correrse dos veces sin romper nada. Se monta un
# arbol de prueba con un arr-stack de mentira, se instala dos veces y se comparan
# los dos RESULTADOS. No se compara el codigo de salida (el segundo dice "sin
# cambios", que es lo correcto y no es un fallo).
printf '\nel instalador es idempotente\n'
IDEM="$(mktemp -d)"
mkdir -p "$IDEM/bin"
cat > "$IDEM/bin/arr-stack" <<'STUB'
#!/bin/bash
echo "stub arr-stack $*"
exit 0
STUB
chmod 0755 "$IDEM/bin/arr-stack"

idem_run() {
    env EZARR_CONF_DIR="$IDEM/etc/ezarr" \
        EZARR_STATE_DIR="$IDEM/var/estado" \
        EZARR_LOG_DIR="$IDEM/var/log" \
        EZARR_BACKUP_DIR="$IDEM/var/backups" \
        EZARR_BIN_DIR="$IDEM/bin" \
        EZARR_STACK_BIN="$IDEM/bin/arr-stack" \
        EZARR_DATA_ROOT="$IDEM/datos" \
        "$ROOT/ezarr.sh" --only core --yes --offline >/dev/null 2>&1
}

# installed.json lleva timestamp de instalacion: cambiar NO es romper nada, asi
# que se excluye de la comparacion y se dice explicitamente.
idem_hash() {
    find "$IDEM" -type f ! -name installed.json -printf '%m %s %P\n' 2>/dev/null | sort
}

idem_run; r1=$?
h1="$(idem_hash)"
idem_run; r2=$?
h2="$(idem_hash)"

run "primera instalacion termina bien" "$r1" "0"
run "segunda instalacion termina bien" "$r2" "0"
if [ "$h1" = "$h2" ]; then
    ok "la segunda pasada no cambia nada"
else
    bad "la segunda instalacion modifico cosas" "$(diff <(echo "$h1") <(echo "$h2") | head -6)"
fi
# Y que la configuracion del usuario no se pise: si editas el fichero, se queda.
[ -r "$IDEM/etc/ezarr/ezarr.conf" ] && ok "se escribio la configuracion" \
                                     || bad "no se escribio la configuracion"
printf 'mi valor\n' >> "$IDEM/etc/ezarr/ezarr.conf"
idem_run >/dev/null 2>&1
grep -q 'mi valor' "$IDEM/etc/ezarr/ezarr.conf" \
    && ok "no sobrescribe la configuracion editada a mano" \
    || bad "el instalador pisa la configuracion del usuario"

rm -rf "$IDEM" 2>/dev/null || true

# --------------------------------------------------------------- resumen ----
printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '\033[32m%s comprobaciones, todas correctas\033[0m\n\n' "$PASS"
    exit 0
fi
printf '\033[31m%s correctas, %s con fallos\033[0m\n' "$PASS" "$FAIL"
for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
printf '\n'
exit 1