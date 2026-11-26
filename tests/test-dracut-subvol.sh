#!/bin/bash
# Pruebas 4.16.1: instalar-dracut con /var y /usr/local como subvolumenes aparte (openSUSE)
#  - sin /var/tmp en el destino: dracut recibe un --tmpdir propio, que se borra despues
#  - guardian-early va a /usr/lib/guardian (dentro del snapshot), nada en /usr/local
#  - el modulo dracut prefiere la ruta nueva y acepta la vieja (equipos ya instalados)
# Uso: bash tests/test-dracut-subvol.sh [ruta/a/instalar-dracut]
export LC_ALL=C
ID=${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/instalar-dracut}
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✔ $1"; }
no() { FAIL=$((FAIL+1)); echo "  ✖ $1"; }
echo "=== Tests instalar-dracut con subvolumenes (4.16.1) ==="
[ -f "$ID" ] || { no "no existe $ID"; echo "Resultado: $PASS pasaron, $FAIL fallaron"; exit 1; }
if bash -n "$ID"; then ok "sintaxis de instalar-dracut"; else no "sintaxis de instalar-dracut"; fi
W=$(mktemp -d) || exit 1
trap 'rm -rf "$W"' 0
K=7.3.4-1-default
NUEVA=usr/lib/guardian/guardian-early
VIEJA=usr/local/sbin/guardian-early

# --- dobles de dracut y lsinitrd ---
mkdir -p "$W/fb"
cat >"$W/fb/dracut" <<'DOBLE'
#!/bin/bash
# doble: como dracut real, exige un tmpdir existente (por defecto /var/tmp del sistema destino)
td=/var/tmp; img=""; kv=""
while [ $# -gt 0 ]; do
    case "$1" in
        --tmpdir) shift; td="$1" ;;
        --tmpdir=*) td="${1#*=}" ;;
        --kver) shift; kv="$1" ;;
        -*) ;;
        *) img="$1" ;;
    esac
    shift
done
echo "tmpdir=$td kver=$kv img=$img" >>"$FAKE_LOG"
[ "$td" = /var/tmp ] && td="$FAKE_R/var/tmp"
if [ ! -d "$td" ] || [ ! -w "$td" ]; then echo "dracut[F]: Invalid tmpdir '$td'" >&2; exit 1; fi
[ "${FAKE_FAIL:-0}" = 1 ] && { echo "dracut[F]: fallo simulado" >&2; exit 1; }
head -c 4096 /dev/zero >"$FAKE_R$img"
DOBLE
cat >"$W/fb/lsinitrd" <<'DOBLE'
#!/bin/bash
f="${2:-}"
case "$f" in
    "") cat "$FAKE_LISTA" ;;
    usr/bin/guardian-early)
        if [ -f "$FAKE_R/usr/lib/guardian/guardian-early" ]; then cat "$FAKE_R/usr/lib/guardian/guardian-early"
        elif [ -f "$FAKE_R/usr/local/sbin/guardian-early" ]; then cat "$FAKE_R/usr/local/sbin/guardian-early"; fi ;;
    etc/guardian-early.conf) cat "$FAKE_R/etc/guardian/early.conf" 2>/dev/null ;;
esac
DOBLE
chmod 755 "$W/fb/dracut" "$W/fb/lsinitrd"
# listado falso: una linea por cada pieza que pide el propio instalador
{
    awk '/^PIEZAS=\(/{f=1;next} f&&/^\)/{f=0} f' "$ID" | while IFS= read -r l; do
        l=${l#*\'}; l=${l%\'*}; p=${l%|*}
        p=${p//'( -> .*)?'/}; p=${p%\$}; p=${p//\\./.}
        echo "-rwxr-xr-x   1 root root 0 Jan  1 00:00 usr/lib/$p"
    done
    echo "-rw-r--r--   1 root root 0 Jan  1 00:00 usr/lib/systemd/system/initrd-root-fs.target"
} >"$W/lista"
printf '#!/bin/sh\necho prueba-4.16.1\n' >"$W/guardian-early"

n=0
correr() { # $1 = raiz falsa ; resto = variables extra. Deja rc en RC y salida en $W/out$n
    local r="$1"; shift
    env "$@" PATH="$W/fb:$PATH" GUARDIAN_ROOT="$r" GUARDIAN_MIN_IMG=100 FAKE_R="$r" \
        FAKE_LOG="$W/dlog$n" FAKE_LISTA="$W/lista" TMPDIR="$W/tmp$n" \
        bash "$ID" --kernel "$K" --early "$W/guardian-early" </dev/null >"$W/out$n" 2>&1
    RC=$?
}
raiz() { # raiz falsa estilo snapshot de openSUSE: sin /var/tmp ni /usr/local
    n=$((n+1)); local r="$W/r$n"
    mkdir -p "$r/lib/modules/$K" "$r/boot" "$r/root" "$r/tmp" "$W/tmp$n"
    head -c 2048 /dev/urandom >"$r/boot/initrd-$K"
    cp "$r/boot/initrd-$K" "$W/orig$n"
    : >"$W/dlog$n"
    R="$r"
}

# A) /var aparte (sin /var/tmp en el destino)
raiz
correr "$R"
if [ "$RC" = 0 ]; then ok "A sin /var/tmp: instala (rc=0)"; else no "A sin /var/tmp: rc=$RC ($(grep -m1 -E 'dracut\[F\]|✖' "$W/out$n"))"; fi
t=$(sed -n 's/^tmpdir=\([^ ]*\) .*/\1/p' "$W/dlog$n" | tail -n 1)
case "$t" in
    /var/tmp|"") no "A dracut sin tmpdir propio (${t:-no se llamo})" ;;
    "$W/tmp$n"/*) ok "A dracut recibe --tmpdir propio" ;;
    *) ok "A dracut recibe --tmpdir propio ($t)" ;;
esac
if [ -z "$(ls -A "$W/tmp$n" 2>/dev/null)" ]; then ok "A tmpdir propio borrado al terminar"; else no "A queda basura en el tmpdir"; fi
if [ -f "$R/$NUEVA" ] && cmp -s "$R/$NUEVA" "$W/guardian-early"; then ok "A guardian-early en /$NUEVA"; else no "A falta /$NUEVA"; fi
if [ ! -e "$R/$VIEJA" ]; then ok "A nada escrito en /usr/local"; else no "A escribio en /$VIEJA (lo tapa @/usr/local)"; fi
if [ "$(stat -c %s "$R/boot/initrd-$K" 2>/dev/null)" = 4096 ]; then ok "A initrd regenerado"; else no "A initrd no regenerado"; fi

# B) dracut falla: restaura el initrd, quita la conf y no deja tmpdir
raiz
correr "$R" FAKE_FAIL=1
if [ "$RC" != 0 ] && cmp -s "$R/boot/initrd-$K" "$W/orig$n"; then ok "B dracut falla: initrd original restaurado"; else no "B dracut falla: rc=$RC o initrd distinto"; fi
if [ ! -e "$R/etc/dracut.conf.d/20-guardian.conf" ]; then ok "B dracut falla: modulo desactivado"; else no "B dracut falla: queda 20-guardian.conf"; fi
if [ -z "$(ls -A "$W/tmp$n" 2>/dev/null)" ]; then ok "B dracut falla: tmpdir borrado"; else no "B dracut falla: queda tmpdir"; fi

# C) sistema normal (/var/tmp existe): dracut usa el de siempre
raiz; mkdir -p "$R/var/tmp"; chmod 1777 "$R/var/tmp"
correr "$R"
t=$(sed -n 's/^tmpdir=\([^ ]*\) .*/\1/p' "$W/dlog$n" | tail -n 1)
if [ "$RC" = 0 ] && [ "$t" = /var/tmp ]; then ok "C con /var/tmp: igual que antes (rc=0)"; else no "C con /var/tmp: rc=$RC tmpdir=${t:-?}"; fi

# D) modulo dracut: que ruta usa check() e install()
awk "/<< 'MODULO'/{f=1;next} /^MODULO\$/{f=0} f" "$ID" >"$W/mod.sh"
if [ -s "$W/mod.sh" ] && bash -n "$W/mod.sh"; then ok "D modulo extraido, sintaxis bien"; else no "D modulo no extraible"; fi
modcaso() { # nombre nueva(0/1) vieja(0/1) check_esperado origen_esperado(nueva|vieja|-)
    n=$((n+1)); local M="$W/m$n" o c s
    mkdir -p "$M/usr/lib/guardian" "$M/usr/local/sbin" "$M/initdir/usr/bin"
    [ "$2" = 1 ] && { echo n >"$M/$NUEVA"; chmod 755 "$M/$NUEVA"; }
    [ "$3" = 1 ] && { echo v >"$M/$VIEJA"; chmod 755 "$M/$VIEJA"; }
    sed -e "s#/$NUEVA#$M/$NUEVA#g" -e "s#/$VIEJA#$M/$VIEJA#g" "$W/mod.sh" >"$M/mod.sh"
    o=$(bash -c '
        initdir=$1/initdir; moddir=$1; systemdsystemunitdir=/usr/lib/systemd/system
        require_binaries() { return 0; }; inst_multiple() { :; }; instmods() { :; }
        inst() { :; }; ln_r() { :; }
        inst_simple() { echo "INST $1 -> $2"; }
        . "$1/mod.sh"
        check; echo "CHECK $?"
        install 2>/dev/null
    ' _ "$M")
    c=$(sed -n 's/^CHECK //p' <<<"$o")
    s=$(sed -n 's#^INST \(.*\) -> /usr/bin/guardian-early$#\1#p' <<<"$o")
    case "$5" in nueva) e="$M/$NUEVA" ;; vieja) e="$M/$VIEJA" ;; *) e="" ;; esac
    if [ "$c" = "$4" ] && { [ "$5" = - ] || [ "$s" = "$e" ]; }; then ok "D $1"
    else no "D $1 (check=$c esperado=$4, copia=${s##*/usr/} esperado=$5)"; fi
}
modcaso "solo ruta nueva: incluye y copia la nueva"      1 0 0   nueva
modcaso "las dos: copia la nueva"                         1 1 0   nueva
modcaso "solo la vieja (equipo ya instalado): la acepta"  0 1 0   vieja
modcaso "ninguna: no se incluye"                          0 0 255 -

echo "Resultado: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
