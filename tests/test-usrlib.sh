#!/bin/bash
# Pruebas 4.16.2: install-guardian con /usr/local tapado (otro subvolumen o particion)
#  - guardian-early y guardian tambien en /usr/lib/guardian; ExecStart de la fase tardia ahi
#  - ganchos de initramfs-tools y mkinitcpio: ruta nueva y, si falta, la vieja
#  - unidad initrd de Arch en /usr/lib/guardian
# Uso: bash tests/test-usrlib.sh [ruta/a/install-guardian]
export LC_ALL=C
IG=${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/install-guardian}
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✔ $1"; }
no() { FAIL=$((FAIL+1)); echo "  ✖ $1"; }
echo "=== Tests install-guardian con /usr/local tapado (4.16.2) ==="
[ -f "$IG" ] || { no "no existe $IG"; echo "Resultado: $PASS pasaron, $FAIL fallaron"; exit 1; }
if bash -n "$IG"; then ok "sintaxis de install-guardian"; else no "sintaxis de install-guardian"; fi
W=$(mktemp -d) || exit 1
trap 'rm -rf "$W"' 0
NUEVA=/usr/lib/guardian/guardian-early
VIEJA=/usr/local/sbin/guardian-early

# A) fase tardia
if grep -E -q '^[[:space:]]*ExecStart=/usr/lib/guardian/guardian --no-music --no-packages' "$IG"; then
    ok "A ExecStart de la fase tardia en /usr/lib/guardian"; else no "A ExecStart no esta en /usr/lib/guardian"; fi
if ! grep -E -q '^[[:space:]]*ExecStart=/usr/local/' "$IG"; then ok "A ningun ExecStart en /usr/local"
else no "A queda un ExecStart en /usr/local"; fi

# B) copias en /usr/lib/guardian
if grep -F -q 'install -d -m 0755 -o root -g root /usr/lib/guardian' "$IG"; then ok "B crea /usr/lib/guardian"; else no "B no crea /usr/lib/guardian"; fi
if grep -F -q '"$SRC/guardian-early" /usr/lib/guardian/guardian-early' "$IG"; then ok "B copia guardian-early a /usr/lib/guardian"; else no "B no copia guardian-early a /usr/lib/guardian"; fi
if grep -E -q '"\$SRC/guardian" +/usr/lib/guardian/guardian$' "$IG"; then ok "B copia guardian a /usr/lib/guardian"; else no "B no copia guardian a /usr/lib/guardian"; fi

# C) unidad initrd de Arch fuera de /usr/local
n=$(grep -c -F /usr/lib/guardian/guardian-early-initrd.service "$IG")
if [ "$n" = 4 ]; then ok "C unidad de Arch en /usr/lib/guardian (4 lineas)"; else no "C unidad de Arch en /usr/lib/guardian: $n lineas (esperadas 4)"; fi
if ! grep -F -q /usr/local/share/guardian/guardian-early-initrd.service "$IG"; then ok "C nada de la unidad en /usr/local/share"
else no "C la unidad sigue en /usr/local/share"; fi
if grep -F -q '"$D/usr/lib/guardian"' "$IG"; then ok "C crea \$D/usr/lib/guardian"; else no "C no crea \$D/usr/lib/guardian"; fi

# D/E) los ganchos: se ejecuta la linea real con rutas desviadas a una raiz falsa
n=0
caso() { # $1 etiqueta, $2 shell, $3 definicion del doble, $4 linea, $5 nueva(0/1), $6 vieja(0/1), $7 esperado(nueva|vieja)
    n=$((n+1)); local M="$W/c$n" c o e
    mkdir -p "$M/usr/lib/guardian" "$M/usr/local/sbin"
    [ "$5" = 1 ] && { : >"$M$NUEVA"; chmod 755 "$M$NUEVA"; }
    [ "$6" = 1 ] && { : >"$M$VIEJA"; chmod 755 "$M$VIEJA"; }
    c=$(printf '%s\n' "$4" | sed -e "s#$NUEVA#$M$NUEVA#g" -e "s#$VIEJA#$M$VIEJA#g")
    o=$("$2" -c "$3
$c" 2>&1)
    case "$7" in nueva) e="$M$NUEVA" ;; *) e="$M$VIEJA" ;; esac
    if [ "$o" = "X $e -> $8" ]; then ok "$1"; else no "$1 (salio: ${o#X $M})"; fi
}
citado() { # la linea $1 (numero) esta dentro de un heredoc con comillas (no se expande al escribirlo)
    awk -v L="$1" 'NR<L && /<</ && !/<<</ {u=$0} END{print u}' "$IG" | grep -E -q "<<-?[[:space:]]*['\"][A-Za-z_]+['\"]"
}
for fam in it mk; do
    if [ "$fam" = it ]; then
        P='^[[:space:]]*(if .*)?copy_exec .*guardian-early /sbin/guardian-early'; SH=sh
        DEF='copy_exec() { echo "X $1 -> $2"; }'; DST=/sbin/guardian-early; NOM="D initramfs-tools"
    else
        P='^[[:space:]]*add_file .*[ "]/usr/bin/guardian-early 755'; SH=bash
        DEF='add_file() { echo "X $1 -> $2"; }'; DST=/usr/bin/guardian-early; NOM="E mkinitcpio"
    fi
    k=$(grep -c -E "$P" "$IG")
    if [ "$k" = 1 ]; then ok "$NOM: una linea que copia guardian-early"
    else no "$NOM: $k lineas que copian guardian-early (esperada 1)"; continue; fi
    L=$(grep -E "$P" "$IG"); ln=$(grep -n -E "$P" "$IG" | cut -d: -f1)
    if citado "$ln"; then ok "$NOM: dentro de un heredoc con comillas"; else no "$NOM: heredoc sin comillas (se expandiria)"; fi
    caso "$NOM: solo la nueva -> copia la nueva"           "$SH" "$DEF" "$L" 1 0 nueva "$DST"
    caso "$NOM: las dos -> copia la nueva"                 "$SH" "$DEF" "$L" 1 1 nueva "$DST"
    caso "$NOM: solo la vieja (ya instalado) -> la vieja"  "$SH" "$DEF" "$L" 0 1 vieja "$DST"
done

echo "Resultado: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
