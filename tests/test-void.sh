#!/bin/bash
# test-void.sh (4.18.1): instalar-dracut-sinsd (dracut SIN systemd: gancho pre-mount + runit/OpenRC),
# la revisión de paquetes con xbps (v2)
# y la rama de instalar-en-disco. Uso: bash tests/test-void.sh [directorio bin]  (contra 4.18.0 FALLA)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
I=$B/instalar-dracut-sinsd
espera "instalar-dracut-sinsd existe y pasa bash -n" '[[ -f "$I" ]] && bash -n "$I"'
FS=$(sed -n '/^# >>> sinsd/,/^# <<< sinsd/p' "$I" 2>/dev/null)
espera "bloque sinsd" '[[ -n "$FS" ]]'
R=""; GEI=/usr/local/sbin/guardian-early; MOD=/usr/lib/dracut/modules.d/70guardian-sinsd
eval "$FS"
# --- módulo dracut
sinsd_modulo >"$T/ms.sh" 2>/dev/null
espera "module-setup: bash -n" '[[ -s "$T/ms.sh" ]] && bash -n "$T/ms.sh"'
espera "module-setup: gancho pre-mount 10" 'grep -q "inst_hook pre-mount 10 \"\$moddir/guardian-early-hook.sh\"" "$T/ms.sh"'
espera "module-setup: sin unidades de systemd" '! grep -Eq "\.service|systemdsystemunitdir|target\.wants" "$T/ms.sh"'
cat >"$T/fd.sh" <<'FD'
L=$T/inst.log
inst_multiple() { echo "inst_multiple $*" >>"$L"; }
inst_simple() { echo "inst_simple $*" >>"$L"; }
inst() { echo "inst $*" >>"$L"; }
inst_hook() { echo "inst_hook $*" >>"$L"; }
FD
mkdir -p "$T/initdir/usr/bin"; : >"$T/initdir/usr/bin/guardian-early"
( T=$T; . "$T/fd.sh"; . "$T/ms.sh"; moddir=/m; initdir=$T/initdir; install ) 2>"$T/ierr"
espera "install(): guardian-early en /usr/bin" 'grep -qx "inst_simple /usr/local/sbin/guardian-early /usr/bin/guardian-early" "$T/inst.log"'
espera "install(): e2fsck blkid e2image" 'grep -qx "inst_multiple e2fsck blkid e2image" "$T/inst.log"'
espera "install(): gancho desde \$moddir" 'grep -qx "inst_hook pre-mount 10 /m/guardian-early-hook.sh" "$T/inst.log"'
espera "install(): guardian-df" 'grep -q "^inst .*/df /usr/bin/guardian-df$" "$T/inst.log"'
# --- gancho (lo lee el init de dracut con «.»)
sinsd_gancho >"$T/g.sh"
espera "gancho: sin exit" '! grep -Eq "(^|[;&|[:space:]])exit([[:space:];]|$)" "$T/g.sh"'
sed "s|/usr/bin/guardian-early|$T/ge|g" "$T/g.sh" >"$T/g2.sh"
SHS=""
for s in dash bash "busybox sh" /usr/lib/klibc/bin/sh; do set -- $s; a=$(command -v "$1" 2>/dev/null) && SHS="$SHS|$a${2:+ $2}"; done
espera "hay al menos dash o bash" '[[ "$SHS" == *dash* || "$SHS" == *bash* ]]'
echo "shells: ${SHS#|}"
IFS='|' read -r -a LS <<<"${SHS#|}"
for s in "${LS[@]}"; do
    n=${s##*/}; n=${n// /-}
    espera "[$n] gancho: -n" '$s -n "$T/g.sh"'
    printf '#!/bin/sh\necho corrio >>%s/ge.log\nexit 4\n' "$T" >"$T/ge"; chmod +x "$T/ge"; rm -f "$T/ge.log"
    o=$($s -c ". $T/g2.sh; echo SIGUE" 2>&1)
    espera "[$n] gancho: guardian-early falla (rc 4) y el init sigue" '[[ "$o" == SIGUE ]] && grep -q corrio "$T/ge.log"'
    rm -f "$T/ge"
    o=$($s -c ". $T/g2.sh; echo SIGUE" 2>&1)
    espera "[$n] gancho: sin guardian-early, sigue sin error" '[[ "$o" == SIGUE ]]'
done
# --- ¿systemd?
espera "es_systemd: unidad initrd-root-fs.target" 'sinsd_es_systemd "-rw-r--r--   1 root root 0 Jan 1 usr/lib/systemd/system/initrd-root-fs.target"'
espera "es_systemd: binario systemd" 'sinsd_es_systemd "-rwxr-xr-x   1 root root 9 Jan 1 usr/lib/systemd/systemd"'
espera "es_systemd: dracut sin systemd (udevd, systemd-udevd no) → no" '! sinsd_es_systemd "$(printf "%s\n" "-rwxr-xr-x 1 root root 9 Jan 1 usr/bin/udevd" "-rwxr-xr-x 1 root root 9 Jan 1 usr/lib/systemd/systemd-udevd" "-rw-r--r-- 1 root root 9 Jan 1 usr/lib/dracut/hooks/pre-mount/10-x.sh")"'
# --- verificación con un lsinitrd falso
R=$T/r; mkdir -p "$R/usr/local/sbin" "$R/etc/guardian" "$T/fb" "$T/img"
echo early-v >"$R$GEI"; echo conf-v >"$R/etc/guardian/early.conf"
arma() {   # $1 = gancho en la lista (1/0), $2 = contenido de guardian-early, $3 = init con pre-mount (1/0), $4 = systemd (1/0)
    rm -rf "$T/img"; mkdir -p "$T/img/usr/bin" "$T/img/etc" "$T/img/usr/lib/dracut/hooks/pre-mount"
    { echo "-rwxr-xr-x 1 root root 1 Jan 1 init"
      for p in usr/bin/guardian-early usr/bin/e2fsck usr/bin/blkid usr/bin/e2image usr/bin/guardian-df etc/guardian-early.conf usr/bin/mount usr/bin/umount usr/bin/sync; do
          echo "-rwxr-xr-x 1 root root 1 Jan 1 $p"; done
      [[ $1 == 1 ]] && echo "-rwxr-xr-x 1 root root 1 Jan 1 usr/lib/dracut/hooks/pre-mount/10-guardian-early-hook.sh"
      [[ $4 == 1 ]] && echo "-rwxr-xr-x 1 root root 1 Jan 1 usr/lib/systemd/systemd"
    } >"$T/lista"
    echo "$2" >"$T/img/usr/bin/guardian-early"; echo conf-v >"$T/img/etc/guardian-early.conf"
    sinsd_gancho >"$T/img/usr/lib/dracut/hooks/pre-mount/10-guardian-early-hook.sh"
    if [[ $3 == 1 ]]; then printf 'source_hook pre-mount\n' >"$T/img/init"; else printf 'echo nada\n' >"$T/img/init"; fi
}
cat >"$T/fb/lsinitrd" <<LS
#!/bin/bash
[[ \$# -le 1 ]] && { cat "$T/lista"; exit 0; }
cat "$T/img/\$2" 2>/dev/null; exit 0
LS
chmod +x "$T/fb/lsinitrd"
ver() { PATH="$T/fb:$PATH" sinsd_verificar /x >"$T/vout"; VRC=$?; }
arma 1 early-v 1 0; ver
espera "verificar: imagen completa → 0" '(( VRC == 0 )) && grep -q "gancho de dentro = el del módulo" "$T/vout" && grep -q "lee los ganchos pre-mount" "$T/vout"'
arma 0 early-v 1 0; ver
espera "verificar: sin gancho pre-mount → falla" '(( VRC > 0 )) && grep -q "NO contiene gancho pre-mount" "$T/vout"'
arma 1 otro 1 0; ver
espera "verificar: guardian-early distinto → falla" '(( VRC > 0 )) && grep -q "guardian-early de dentro NO coincide" "$T/vout"'
arma 1 early-v 0 0; ver
espera "verificar: init sin pre-mount → falla" '(( VRC > 0 )) && grep -q "NO lee pre-mount" "$T/vout"'
arma 1 early-v 1 1; ver
espera "verificar: imagen de systemd → falla" '(( VRC > 0 )) && grep -q "es de systemd" "$T/vout"'
# --- runit: una vez por arranque
sinsd_runit_run >"$T/run"
espera "runit run: sh -n, --no-music --no-packages, pause" 'sh -n "$T/run" && grep -q "timeout 300 /usr/lib/guardian/guardian --no-music --no-packages" "$T/run" && grep -q "exec pause" "$T/run"'
mkdir -p "$T/vrun" "$T/vlog"
printf '#!/bin/sh\necho g >>%s/gcount\nexit 3\n' "$T" >"$T/gg"; chmod +x "$T/gg"
sed -e "s|/usr/lib/guardian/guardian|$T/gg|; s|/run/|$T/vrun/|g; s|/var/log/|$T/vlog/|g; s|exec pause|exit 0|; s|exec sleep 2147483647|exit 0|" "$T/run" >"$T/run2"
sh "$T/run2" >/dev/null 2>&1
espera "runit: 1.ª vez corre guardian y anota rc" '[[ "$(wc -l <"$T/gcount")" == 1 ]] && grep -qx "rc=3" "$T/vlog/guardian-late.log"'
sh "$T/run2" >/dev/null 2>&1
espera "runit: reinicio del servicio → no repite" '[[ "$(wc -l <"$T/gcount")" == 1 ]]'
rm -f "$T/vrun/guardian-late.hecho" "$T/gcount"; : >"$T/vrun/guardian.skip"
sh "$T/run2" >/dev/null 2>&1
espera "runit: guardian.skip → no corre" '[[ ! -e "$T/gcount" ]] && grep -q guardian.skip "$T/vlog/guardian-late.log"'
sinsd_openrc >"$T/orc"
espera "openrc: lo esencial" 'grep -q "need localmount" "$T/orc" && grep -q "eend 0" "$T/orc" && grep -q "/run/guardian.skip" "$T/orc"'
# --- fase tardía según el init del sistema
echo guard >"$T/guard"
R=$T/void; mkdir -p "$R/etc/sv/sshd" "$R/usr/bin" "$R/etc/runit/runsvdir/default"; : >"$R/usr/bin/runsvdir"
ln -s /run/runit/supervise.sshd "$R/etc/sv/sshd/supervise"
sinsd_tardia "$T/guard" >"$T/tout"; rc=$?
espera "tardía Void: guardian, run, supervise y enlace default" '(( rc == 0 )) && cmp -s "$T/guard" "$R/usr/lib/guardian/guardian" && [[ -x "$R/etc/sv/guardian-late/run" ]] && [[ "$(readlink "$R/etc/sv/guardian-late/supervise")" == /run/runit/supervise.guardian-late ]] && [[ "$(readlink "$R/etc/runit/runsvdir/default/guardian-late")" == /etc/sv/guardian-late ]]'
sinsd_tardia "$R/usr/lib/guardian/guardian" >/dev/null; rc=$?
espera "tardía Void: repetir (mismo archivo) no falla" '(( rc == 0 ))'
R=$T/rv2; mkdir -p "$R/etc/sv" "$R/sbin"; : >"$R/sbin/runsvdir"
sinsd_tardia "$T/guard" >/dev/null; rc=$?
espera "tardía runit sin runsvdir/default ni convención: /etc/service, sin supervise" '(( rc == 0 )) && [[ "$(readlink "$R/etc/service/guardian-late")" == /etc/sv/guardian-late ]] && [[ ! -e "$R/etc/sv/guardian-late/supervise" && ! -L "$R/etc/sv/guardian-late/supervise" ]]'
R=$T/gen; mkdir -p "$R/etc/init.d" "$R/sbin"; : >"$R/sbin/openrc-run"
sinsd_tardia "$T/guard" >/dev/null; rc=$?
espera "tardía OpenRC (Gentoo): init.d y nivel default" '(( rc == 0 )) && [[ -x "$R/etc/init.d/guardian-late" ]] && [[ "$(readlink "$R/etc/runlevels/default/guardian-late")" == /etc/init.d/guardian-late ]]'
R=$T/nada; mkdir -p "$R/etc"
sinsd_tardia "$T/guard" >"$T/tout"; rc=$?
espera "tardía: sin runit ni OpenRC → avisa, no instala" '(( rc == 0 )) && grep -q "sin runit ni OpenRC" "$T/tout" && [[ ! -e "$R/usr/lib/guardian/guardian" ]]'
R=""
# --- main: lo que debe hacer
M=$(sed -n '/^main() {/,/^}/p' "$I")
espera "main: se niega con initramfs de systemd (apunta a instalar-dracut)" 'grep -q "sinsd_es_systemd \"\$lst0\"" <<<"$M" && grep -q "es de systemd: usa instalar-dracut" <<<"$M"'
espera "main: respaldo, dracut -f de un kernel, verificar, restaurar" 'grep -q "cp -a \"\$IMG\" \"\$BKF\"" <<<"$M" && grep -q "dracut -f --kver \"\$KVER\"" <<<"$M" && grep -q "sinsd_verificar \"\$IMG\"" <<<"$M" && grep -c restaurar <<<"$M" | grep -qv "^[0-3]$"'
espera "main: módulo en dracut.conf.d (persiste en cada dracut)" 'grep -qx "DCONF=/etc/dracut.conf.d/20-guardian-sinsd.conf" "$I" && grep -q "add_dracutmodules+=\" guardian-sinsd \"" <<<"$M"'
espera "main: fase tardía" 'grep -q "sinsd_tardia \"\$GUARD\"" <<<"$M"'
GUARDIAN_SINSD_FUNCIONES=1 bash -c ". $I; sinsd_en_disco /dev/no-existe --sistema-confiable" >/dev/null 2>"$T/derr"; rc=$?
espera "modo disco: dispositivo inexistente → se niega" '(( rc != 0 )) && grep -q "no es un dispositivo de bloques" "$T/derr"'
espera "modo disco: exige --sistema-confiable y no sirve con systemd" 'grep -q "requiere --sistema-confiable" "$I" && grep -q "usa systemd: usa instalar-dracut" "$I"'
GUARDIAN_ROOT=$T/vacio bash "$I" --opcion-mala >/dev/null 2>&1; rc=$?
espera "opción desconocida → se niega" '(( rc != 0 ))'
# --- instalar-en-disco: rama dracut sin systemd entre la de mkinitfs y la de dracut
D=$B/instalar-en-disco
a=$(grep -n '^elif \[\[ -x "$MNT/usr/bin/dracut" \]\]; then$' "$D" | head -n1 | cut -d: -f1)
b=$(grep -n 'elif \[\[ -x "$MNT/sbin/mkinitfs" || -x "$MNT/usr/sbin/mkinitfs" \]\]; then' "$D" | head -n1 | cut -d: -f1)
c=$(grep -n '^elif \[\[ -x "$MNT/usr/bin/dracut" || -x "$MNT/usr/sbin/dracut" || -x "$MNT/sbin/dracut" \]\] && ! \[\[ -e "$MNT/usr/lib/systemd/systemd" \]\]; then$' "$D" | head -n1 | cut -d: -f1)
espera "ied: rama sinsd después de mkinitfs y antes de dracut" '[[ -n "$a" && -n "$b" && -n "$c" ]] && (( b < c && c < a ))'
espera "ied: llama a instalar-dracut-sinsd en modo disco" 'grep -q "exec /bin/bash \"\$SRC/instalar-dracut-sinsd\" \"\$DEV\" --sistema-confiable --early \"\$SRC/guardian-early\" --guardian \"\$SRC/guardian\"" "$D"'
espera "ied: pasa bash -n" 'bash -n "$D"'
# la condición de la rama, con un árbol de Void y uno de Fedora
cat >"$T/cond.sh" <<'CO'
MNT=$1
if [[ -x "$MNT/usr/bin/dracut" || -x "$MNT/usr/sbin/dracut" || -x "$MNT/sbin/dracut" ]] && ! [[ -e "$MNT/usr/lib/systemd/systemd" ]]; then echo sinsd; else echo otro; fi
CO
mkdir -p "$T/mv/usr/bin" "$T/mf/usr/bin" "$T/mf/usr/lib/systemd"; for m in mv mf; do printf '#!/bin/sh\n' >"$T/$m/usr/bin/dracut"; chmod +x "$T/$m/usr/bin/dracut"; done
: >"$T/mf/usr/lib/systemd/systemd"
espera "ied: condición — Void → sinsd, Fedora → rama de siempre" '[[ "$(bash "$T/cond.sh" "$T/mv")" == sinsd && "$(bash "$T/cond.sh" "$T/mf")" == otro ]]'
espera "ied: la condición del árbol = la de la prueba" 'grep -qF "$(sed -n 2p "$T/cond.sh" | cut -d";" -f1)" "$D"'
# --- guardian: paquetes con xbps (formato medido en void-lab2 con el xbps real)
GU=$B/guardian
FX=$(sed -n '/^diagnosticar_xbps() {/,/^}/p' "$GU" 2>/dev/null); FG=$(sed -n '/^gestor_paquetes() {/,/^}/p' "$GU" 2>/dev/null)
espera "guardian: diagnosticar_xbps y xbps en gestor_paquetes" '[[ -n "$FX" ]] && grep -q "echo xbps" <<<"$FG"'
espera "guardian: caso xbps en diagnosticar_paquetes" 'sed -n "/^diagnosticar_paquetes() {/,/^}/p" "$GU" | grep -q "xbps) diagnosticar_xbps; return 0 ;;"'
mkdir -p "$T/xbin" "$T/xdb"
cat >"$T/xbin/xbps-query" <<'XQ'
#!/bin/bash
[[ "${MODO:-}" == nodb ]] && { echo "ERROR: failed to initialize libxbps: Permission denied"; exit 1; }
[[ "$1" == -l ]] && printf 'ii e2fsprogs-1.47.1_1 Ext2/3/4 utilities\nii bash-5.2.37_1 GNU shell\nii runit-void-20250131_1 runit\n'
exit 0
XQ
cat >"$T/xbin/xbps-pkgdb" <<'XP'
#!/bin/bash
case "${MODO:-}" in
  borrado)  echo "ERROR: e2fsprogs: unexistent file /usr/bin/lsattr."; echo "ERROR: e2fsprogs: files check FAILED."; exit 1 ;;
  alterado) echo "ERROR: e2fsprogs: hash mismatch for /usr/bin/lsattr."; echo "ERROR: e2fsprogs: files check FAILED."; exit 1 ;;
  dos)      echo "ERROR: e2fsprogs: unexistent file /usr/bin/lsattr."; echo "ERROR: e2fsprogs: files check FAILED."
            echo "ERROR: bash: hash mismatch for /usr/bin/bash."; echo "ERROR: bash: files check FAILED."; exit 1 ;;
esac
exit 0
XP
printf '#!/bin/sh\n[ "${XBPS_OCUPADO:-0}" = 1 ]\n' >"$T/xbin/pgrep"; chmod +x "$T/xbin/"*
cat >"$T/gx.sh" <<GX
ok() { echo "OK \$*"; }; warn() { echo "WARN \$*"; }; info() { echo "INFO \$*"; }; log() { :; }
rpm_db_presente() { false; }
LISTA_AVISOS=()
$FG
$FX
GX
BA=$(command -v bash)
dx() { env -i PATH="$T/xbin:/usr/bin:/bin" MODO="${MODO:-}" XBPS_OCUPADO="${XBPS_OCUPADO:-0}" GUARDIAN_XBPSDB="$T/xdb" GUARDIAN_APKDB="$T/no" "$BA" -c ". $T/gx.sh; $1"; }
espera "gestor: xbps con su base → xbps" '[[ "$(env -i PATH="$T/xbin" GUARDIAN_XBPSDB="$T/xdb" GUARDIAN_APKDB="$T/no" "$BA" -c ". $T/gx.sh; gestor_paquetes")" == xbps ]]'
espera "gestor: xbps sin base → no es xbps" '[[ "$(env -i PATH="$T/xbin" GUARDIAN_XBPSDB="$T/no" GUARDIAN_APKDB="$T/no" "$BA" -c ". $T/gx.sh; gestor_paquetes")" != xbps ]]'
o=$(MODO= dx diagnosticar_xbps)
espera "xbps sano: 2 OK, ningún WARN, 3 paquetes" '[[ "$(grep -c ^OK <<<"$o")" == 2 ]] && ! grep -q ^WARN <<<"$o" && grep -q "legible (3 paquetes)" <<<"$o"'
o=$(MODO=borrado dx diagnosticar_xbps)
espera "xbps: archivo borrado → WARN 1 problema en e2fsprogs" 'grep -q "^WARN xbps-pkgdb -a: 1 problema(s) en: e2fsprogs$" <<<"$o"'
o=$(MODO=alterado dx diagnosticar_xbps)
espera "xbps: archivo alterado → WARN 1 problema en e2fsprogs" 'grep -q "^WARN xbps-pkgdb -a: 1 problema(s) en: e2fsprogs$" <<<"$o"'
o=$(MODO=dos dx diagnosticar_xbps)
espera "xbps: dos paquetes → WARN 2 problemas en bash e2fsprogs" 'grep -q "^WARN xbps-pkgdb -a: 2 problema(s) en: bash e2fsprogs$" <<<"$o"'
o=$(MODO=dos dx 'diagnosticar_xbps >/dev/null; printf "%s\n" "${LISTA_AVISOS[@]}"')
espera "xbps: aviso en la lista con el arreglo" 'grep -q "xbps-install -f" <<<"$o"'
o=$(MODO=nodb dx diagnosticar_xbps)
espera "xbps: base ilegible → WARN y no sigue" 'grep -q "^WARN No se puede leer la base de datos de xbps" <<<"$o" && ! grep -q pkgdb <<<"$o"'
o=$(XBPS_OCUPADO=1 dx diagnosticar_xbps)
espera "xbps trabajando → INFO, no revisa" 'grep -q "^INFO Hay un xbps trabajando" <<<"$o" && ! grep -q ^OK <<<"$o"'
echo "$P passed, $F failed"
(( F == 0 ))
