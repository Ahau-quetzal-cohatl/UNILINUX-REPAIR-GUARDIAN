#!/bin/bash
# Pruebas de la red de emergencia "reiniciar UNA vez" de guardian-early (4.16)
# El bloque se prueba aislado con cada shell real de initramfs que haya:
#   klibc (Debian sin busybox), dash, bash (dracut), busybox (mkinitcpio).
# Uso: bash tests/test-red-emergencia.sh [ruta/a/guardian-early]
export LC_ALL=C
EARLY=${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/guardian-early}
KSH=${GUARDIAN_KLIBC_SH:-}
if [ -z "$KSH" ]; then
    for a in /usr/lib/klibc/bin/sh /usr/lib/klibc/bin/sh.shared; do [ -x "$a" ] && { KSH=$a; break; }; done
fi
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✔ $1"; }
no() { FAIL=$((FAIL+1)); echo "  ✖ $1"; }
bloque() { awk '/^# --- v4.16: red de emergencia/{f=1} f{print} /^# --- fin v4.16/{f=0}' "$EARLY"; }
echo "=== Tests red de emergencia (reiniciar una vez) ==="
[ -f "$EARLY" ] || { no "no existe $EARLY"; echo "Resultado: $PASS pasaron, $FAIL fallaron"; exit 1; }
nb=$(bloque | wc -l)
if [ "$nb" -gt 20 ]; then ok "bloque v4.16 presente ($nb lineas)"; else no "bloque v4.16 ausente ($nb lineas)"; fi
if [ "$(grep -c -x -F 'trap g416_red_una_vez 0' "$EARLY")" = 1 ]; then ok "trap ... 0 (forma que acepta klibc)"; else no "falta trap g416_red_una_vez 0"; fi
if bloque | grep -q 'EXIT'; then no "regla: queda EXIT en el bloque"; else ok "regla: sin EXIT"; fi
if bloque | grep -nE '\[\[|declare -|local ' >/dev/null; then no "regla: bashismos"; else ok "regla: sin bashismos"; fi
if bloque | grep -nE '(^|[;&|({] *|then +|do +)(cp|grep|sed|awk|head|tail|tr|cut|wc|ls|find|touch|mv|date|cat) ' | grep -v '^[0-9]*: *#' >/dev/null; then no "regla: comandos fuera de klibc"; else ok "regla: solo klibc"; fi

caso() { # sh nombre estado esperado(0/1) [variante]
    local shx="$1" nombre="$2" estado="$3" esp="$4" var="${5:-}" T h r rc extra
    T=$(mktemp -d) || return 1
    mkdir -p "$T/run" "$T/bk"
    h="$T/h.sh"
    {
        echo "RUN=$T/run; LOG=\$RUN/early.log; STATUS=\$RUN/early_status"
        echo 'log() { echo "$*" >>"$LOG"; }'
        echo 'set_status() { echo "$1" >"$STATUS" 2>/dev/null; }'
        bloque
        [ "$var" = sinfuncion ] || echo 'find_backup_dir() { bkdir="${GUARDIAN_BACKUP_DIR:-}"; BKMNT=""; return 0; }'
        echo 'dev=/dev/prueba'
        echo "set_status $estado"
        if [ "$var" = enfuncion ]; then echo 'g() { exit 0; }'; echo 'g'
        elif [ "$var" = sinexit ]; then echo ':'
        else echo 'exit 0'; fi
    } >"$h"
    local bk="$T/bk" cmd="touch $T/reinicio" er=""
    case "$var" in
        segundo) mkdir -p "$bk/guardian-backups"; echo "epoch=$(date +%s)" >"$bk/guardian-backups/emergencia-reinicio.txt" ;;
        viejo)   mkdir -p "$bk/guardian-backups"; echo "epoch=$(( $(date +%s) - 7200 ))" >"$bk/guardian-backups/emergencia-reinicio.txt" ;;
        roto)    mkdir -p "$bk/guardian-backups"; echo "basura" >"$bk/guardian-backups/emergencia-reinicio.txt" ;;
        sindisco) bk="" ;;
        apagada) er=no ;;
        sinhook) cmd="" ;;
    esac
    GUARDIAN_NOW="$(date +%s)" GUARDIAN_BACKUP_DIR="$bk" GUARDIAN_REBOOT_CMD="$cmd" EMERGENCY_REBOOT="${er:-once}" "$shx" "$h" >"$T/out" 2>&1
    rc=$?
    r=0; [ -e "$T/reinicio" ] && r=1
    extra=ok
    [ "$rc" = 0 ] || extra="rc=$rc"
    grep -q 'bad trap' "$T/out" && extra="bad trap"
    case "$var" in ''|enfuncion|sinexit)
        if [ "$estado" = failed ]; then grep -q '^epoch=[0-9]' "$T/bk/guardian-backups/emergencia-reinicio.txt" 2>/dev/null || extra="sin contador"; fi ;;
    esac
    if [ "$var" = segundo ]; then grep -q '^segundo_fallo=' "$T/bk/guardian-backups/emergencia-reinicio.txt" 2>/dev/null || extra="sin segundo_fallo"; fi
    if [ "$estado" != failed ] || [ "$var" = sinhook ]; then [ -e "$T/bk/guardian-backups" ] && extra="escribio sin deber"; fi
    if [ "$r" = "$esp" ] && [ "$extra" = ok ]; then ok "[$NSH] $nombre"; else no "[$NSH] $nombre (reinicio=$r esperado=$esp, $extra)"; fi
    rm -rf "$T"
}
W=$(mktemp -d); SHELLS=""
for NSH in klibc dash bash busybox; do
    case "$NSH" in
        klibc) [ -n "$KSH" ] && [ -x "$KSH" ] || continue; SX="$KSH" ;;
        busybox) command -v busybox >/dev/null 2>&1 && busybox sh -c true 2>/dev/null || continue
                 printf '#!/bin/sh\nexec busybox sh "$@"\n' >"$W/bbsh"; chmod +x "$W/bbsh"; SX="$W/bbsh" ;;
        *) command -v "$NSH" >/dev/null 2>&1 || continue; SX="$NSH" ;;
    esac
    SHELLS="$SHELLS $NSH"
    if "$SX" -n "$EARLY" 2>/dev/null; then ok "[$NSH] sintaxis de guardian-early"; else no "[$NSH] sintaxis de guardian-early"; fi
    caso "$SX" "estado ok: no reinicia"            ok       0
    caso "$SX" "repaired: no reinicia"             repaired 0
    caso "$SX" "forced: no reinicia"               forced   0
    caso "$SX" "failed 1a vez: reinicia"           failed   1
    caso "$SX" "failed, exit en funcion: reinicia" failed   1 enfuncion
    caso "$SX" "failed, fin sin exit: reinicia"    failed   1 sinexit
    caso "$SX" "failed 2a vez: consola"            failed   0 segundo
    caso "$SX" "contador viejo: reinicia"          failed   1 viejo
    caso "$SX" "contador ilegible: consola"        failed   0 roto
    caso "$SX" "sin disco de respaldo: consola"    failed   0 sindisco
    caso "$SX" "EMERGENCY_REBOOT=no: consola"      failed   0 apagada
    caso "$SX" "sin funcion de respaldo: consola"  failed   0 sinfuncion
    caso "$SX" "fuera de initramfs: no hace nada"  failed   0 sinhook
done
rm -rf "$W"
[ -n "$SHELLS" ] || no "ningun shell disponible"
echo "Shells:${SHELLS:- ninguno}"
case "$SHELLS" in *klibc*) ;; *) echo "  (aviso: sin klibc; en Debian: paquete klibc-utils)";; esac
echo "Resultado: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
