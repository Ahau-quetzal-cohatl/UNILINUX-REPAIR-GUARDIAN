#!/bin/bash
# test-ubuntu.sh (4.18.4): instalar-dracut en Ubuntu 25.10+/26.04 (dracut con systemd, imagen /boot/initrd.img-K,
# coreutils con enlaces: df -> gnudf, sync -> uutils). Formatos medidos en ubuntu-lab1 (24 nov 2026).
# Uso: bash tests/test-ubuntu.sh [directorio bin]   (contra 4.18.3 FALLA)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ID=$B/instalar-dracut; K=7.0.0-44-generic
mkdir -p "$T/pbin"
# dracut falso: escribe la imagen pedida (último argumento) dentro de GUARDIAN_ROOT y anota los argumentos
cat >"$T/pbin/dracut" <<'DR'
#!/bin/bash
img=${!#}; [[ "$img" == /boot/* ]] || { echo "dracut falso: sin ruta de imagen ($*)" >&2; exit 9; }
echo "$*" >>"$GUARDIAN_ROOT/../dracut.args"
head -c 8192 /dev/zero >"$GUARDIAN_ROOT$img"
DR
# lsinitrd falso con el formato largo real: los enlaces salen como «ruta -> destino»
cat >"$T/pbin/lsinitrd" <<'LS'
#!/bin/bash
R=$GUARDIAN_ROOT; img=""; f=""
while (( $# )); do
    case "$1" in -f) f=$2; shift ;; -*) ;; *) if [[ -z "$img" ]]; then img=$1; else f=$1; fi ;; esac; shift
done
[[ -f "$img" ]] || exit 1
case "$f" in
    usr/bin/guardian-early) for c in usr/lib/guardian/guardian-early usr/local/sbin/guardian-early; do
                                [[ -f "$R/$c" ]] && { cat "$R/$c"; exit 0; }; done; exit 1 ;;
    etc/guardian-early.conf) cat "$R/etc/guardian/early.conf"; exit 0 ;;
    "") ;;
    *) exit 1 ;;
esac
l() { printf '%s   1 root     root     %8s Nov 24 12:00 %s\n' "$1" "$2" "$3"; }
echo "Image: $img: 40M"; echo "========"; echo "Version: dracut-110-11ubuntu0.1"; echo "========"
l -rwxr-xr-x 41234 usr/bin/guardian-early
if [[ "${LS_MODO:-}" == multi ]]; then
    l lrwxrwxrwx 30 'usr/bin/df -> ../lib/cargo/bin/coreutils/df'
    l -rwxr-xr-x 30 usr/bin/guardian-df
else
    l lrwxrwxrwx 5 'usr/bin/guardian-df -> gnudf'
    l -rwxr-xr-x 93256 usr/bin/gnudf
fi
l -rwxr-xr-x 360000 usr/sbin/e2fsck
l -rwxr-xr-x 90000 usr/sbin/blkid
l -rwxr-xr-x 50000 usr/sbin/e2image
l -rw-r--r-- 500 usr/lib/systemd/system/guardian-early.service
l -rw-r--r-- 600 usr/lib/systemd/system/initrd-root-fs.target
l lrwxrwxrwx 25 'usr/lib/systemd/system/initrd-root-fs.target.wants/guardian-early.service -> ../guardian-early.service'
l -rw-r--r-- 90 etc/guardian-early.conf
l -rwxr-xr-x 60000 usr/bin/mount
l -rwxr-xr-x 40000 usr/bin/umount
l lrwxrwxrwx 30 'usr/bin/sync -> ../lib/cargo/bin/coreutils/sync'
l lrwxrwxrwx 30 'usr/bin/cat -> ../lib/cargo/bin/coreutils/cat'
l lrwxrwxrwx 30 'usr/bin/date -> ../lib/cargo/bin/coreutils/date'
LS
chmod +x "$T/pbin/"*
printf '#!/bin/sh\necho guardian-early falso\n' >"$T/ge"
corre() {   # $1 = nombre de la imagen en /boot
    rm -rf "$T/r" "$T/dracut.args"; mkdir -p "$T/r/boot" "$T/r/usr/lib/modules/$K" "$T/r/etc/guardian"
    echo ON_FAIL=nada >"$T/r/etc/guardian/early.conf"
    head -c 8192 /dev/zero >"$T/r/boot/$1"
    env PATH="$T/pbin:$PATH" GUARDIAN_ROOT="$T/r" GUARDIAN_MIN_IMG=100 LS_MODO="${LS_MODO:-}" \
        bash "$ID" --kernel "$K" --early "$T/ge" </dev/null 2>&1
}
o=$(corre "initrd.img-$K"); rc=$?
espera "Ubuntu: /boot/initrd.img-K → instalado (rc=$rc)" '(( rc == 0 )) && ! grep -q "Restaurando" <<<"$o"'
espera "Ubuntu: dracut recibió /boot/initrd.img-K" 'grep -q "/boot/initrd.img-$K\$" "$T/dracut.args" 2>/dev/null'
o=$(corre "initramfs-$K.img"); rc=$?
espera "piezas que son enlaces (guardian-df -> gnudf, sync -> uutils): rc=$rc" '(( rc == 0 ))'
espera "… y ninguna pieza con ✖" '! grep -q "✖" <<<"$o"'
o=$(LS_MODO=multi corre "initrd.img-$K"); rc=$?
espera "df multillamada en la imagen (sin guardian-df): rc=$rc" '(( rc == 0 ))'
espera "disco: los 3 sitios buscan initrd.img-K" '[[ "$(grep -c "initrd\.img-\\$" "$ID")" -ge 3 ]]'
# módulo: cómo se instala df
sed -n "/module-setup.sh\" << 'MODULO'/,/^MODULO\$/p" "$ID" | sed '1d;$d' >"$T/ms.sh"
espera "módulo de dracut extraído" 'grep -q "^install() {" "$T/ms.sh"'
mkdir -p "$T/c1" "$T/c2/lib"
cp "$(type -P true)" "$T/c1/gnudf"; ln -s gnudf "$T/c1/df"
cp "$(type -P true)" "$T/c2/lib/coreutils"; ln -s lib/coreutils "$T/c2/df"
md() { rm -rf "$T/id"; mkdir -p "$T/id"; env -i PATH="$1:/usr/bin:/bin" bash -c '
    inst_multiple() { echo "inst_multiple $*"; }; inst() { echo "inst $*"; }
    inst_simple() { :; }; inst_hook() { :; }; ln_r() { :; }
    initdir=$1; moddir=/no-existe; systemdsystemunitdir=/usr/lib/systemd/system
    . "$0"; install 2>/dev/null' "$T/ms.sh" "$T/id"; }
o=$(md "$T/c1")
espera "df -> gnudf: se copia como guardian-df" 'grep -q "^inst $T/c1/df /usr/bin/guardian-df$" <<<"$o" && [[ ! -e "$T/id/usr/bin/guardian-df" ]]'
o=$(md "$T/c2")
espera "df multillamada: df con su nombre, sin copiarlo como guardian-df" '! grep -q "^inst .*guardian-df" <<<"$o" && grep -q "^inst_multiple df$" <<<"$o"'
espera "df multillamada: guardian-df = guion «exec df»" '[[ -x "$T/id/usr/bin/guardian-df" ]] && grep -qx "exec df \"\$@\"" "$T/id/usr/bin/guardian-df"'
r=$(env -i PATH="$T/c2:/usr/bin:/bin" sh "$T/id/usr/bin/guardian-df" -P / 2>&1; echo "rc=$?")
espera "df multillamada: el guion corre (rc=0)" 'grep -q "^rc=0$" <<<"$r"'
espera "instalar-dracut pasa bash -n" 'bash -n "$ID"'
echo "$P passed, $F failed"
(( F == 0 ))
