#!/bin/bash
# test-instaladores-actualizar.sh (4.19.1): los instaladores que no usan install-guardian directo
# (instalar-mkinitfs, instalar-dracut-sinsd) ponen guardian-actualizar en /usr/lib/guardian y
# /usr/local/sbin; instalar-en-disco, instalar-minios y guardian.nix lo llevan consigo.
# Uso: bash tests/test-instaladores-actualizar.sh [directorio bin]   (contra 4.19.0 debe FALLAR)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fn() { sed -n "/^$2() {/,/^}/p" "$1"; }
mkdir -p "$T/src"; printf '#!/bin/bash\n# guardian\n' >"$T/src/guardian"; printf '#!/bin/bash\n# actualizar\n' >"$T/src/guardian-actualizar"
raiz() { rm -rf "$T/r"; mkdir -p "$T/r/etc/init.d" "$T/r/sbin" "$T/r/etc/sv" "$T/r/usr/bin" "$T/r/etc/runit/runsvdir/default"; }
bien() { cmp -s "$T/src/guardian-actualizar" "$T/r/usr/lib/guardian/guardian-actualizar" && cmp -s "$T/src/guardian-actualizar" "$T/r/usr/local/sbin/guardian-actualizar"; }

# instalar-mkinitfs (Alpine, OpenRC)
M=$B/instalar-mkinitfs
{ fn "$M" mkf_copia_early; fn "$M" mkf_actualizador; fn "$M" mkf_tardia; echo 'mkf_servicio() { echo "#!/sbin/openrc-run"; }'; } >"$T/m.sh"
raiz; : >"$T/r/sbin/openrc-run"
o=$(R=$T/r bash -c ". $T/m.sh; mkf_tardia $T/src/guardian" 2>&1); rc=$?
espera "mkinitfs: tardía rc=0" '(( rc == 0 ))'
espera "mkinitfs: guardian-actualizar en lib y sbin" 'bien'
espera "mkinitfs: lo dice" 'grep -q "guardian-actualizar (solo bundles firmados)" <<<"$o"'
# desde el gancho de apk: guardian ya es /usr/lib/guardian/guardian (mismo archivo): no falla
mkdir -p "$T/r/usr/lib/guardian"; cp "$T/src/guardian" "$T/src/guardian-actualizar" "$T/r/usr/lib/guardian/"
rm -f "$T/r/usr/local/sbin/guardian-actualizar"
o=$(R=$T/r bash -c ". $T/m.sh; mkf_tardia $T/r/usr/lib/guardian/guardian" 2>&1); rc=$?
espera "mkinitfs: desde su propia copia rc=0 y repone sbin" '(( rc == 0 )) && bien'
mkdir -p "$T/src2"; cp "$T/src/guardian" "$T/src2/"; raiz; : >"$T/r/sbin/openrc-run"
o=$(R=$T/r bash -c ". $T/m.sh; mkf_tardia $T/src2/guardian" 2>&1); rc=$?
espera "mkinitfs: sin actualizador al lado: avisa y sigue" '(( rc == 0 )) && grep -q "no hay guardian-actualizar" <<<"$o" && [[ -f $T/r/usr/lib/guardian/guardian ]]'
espera "mkinitfs (otro disco): copia el actualizador al chroot" 'grep -qF "\"\$MKF_MNT\$D/guardian-actualizar\"" "$M"'

# instalar-dracut-sinsd (Void runit, Gentoo OpenRC)
S=$B/instalar-dracut-sinsd
{ fn "$S" sinsd_copia; fn "$S" sinsd_actualizador; fn "$S" sinsd_tardia; echo 'sinsd_runit_run() { echo run; }; sinsd_openrc() { echo rc; }'; } >"$T/s.sh"
raiz; : >"$T/r/usr/bin/runsvdir"
o=$(R=$T/r bash -c ". $T/s.sh; sinsd_tardia $T/src/guardian" 2>&1); rc=$?
espera "sinsd runit: rc=0 y actualizador en lib y sbin" '(( rc == 0 )) && bien && grep -q "(runit)" <<<"$o"'
raiz; rm -rf "$T/r/etc/sv"; : >"$T/r/sbin/openrc-run"
o=$(R=$T/r bash -c ". $T/s.sh; sinsd_tardia $T/src/guardian" 2>&1); rc=$?
espera "sinsd OpenRC: rc=0 y actualizador en lib y sbin" '(( rc == 0 )) && bien && grep -q "(OpenRC)" <<<"$o"'
espera "sinsd (otro disco): copia el actualizador al chroot" 'grep -qF "\"\$SD_MNT\$D/guardian-actualizar\"" "$S"'

# aviso si en la raíz faltan xz o ssh-keygen (Void de base no trae xz: medido en void-lab)
raiz; : >"$T/r/usr/bin/runsvdir"; : >"$T/r/usr/bin/ssh-keygen"; chmod +x "$T/r/usr/bin/ssh-keygen"
o=$(R=$T/r bash -c ". $T/s.sh; sinsd_tardia $T/src/guardian" 2>&1); rc=$?
espera "sinsd: sin xz → avisa «necesitará: xz», rc=0" '(( rc == 0 )) && grep -q "necesitará: xz (" <<<"$o"'
: >"$T/r/usr/bin/xz"; chmod +x "$T/r/usr/bin/xz"
o=$(R=$T/r bash -c ". $T/s.sh; sinsd_tardia $T/src/guardian" 2>&1)
espera "sinsd: con xz y ssh-keygen → sin aviso" '! grep -q "necesitará" <<<"$o"'
raiz; : >"$T/r/sbin/openrc-run"
o=$(R=$T/r bash -c ". $T/m.sh; mkf_tardia $T/src/guardian" 2>&1)
espera "mkinitfs: sin xz ni ssh-keygen → avisa los dos" 'grep -q "necesitará: xz ssh-keygen (" <<<"$o"'
# guardian-actualizar: pista de paquete según el gestor
{ sed -n '/^pista() {/,/^}/p' "$B/guardian-actualizar"; } >"$T/p.sh"
mkdir -p "$T/gx"; printf '#!/bin/sh\n' >"$T/gx/xbps-install"; chmod +x "$T/gx/xbps-install"
espera "actualizar: pista en Void «xbps-install xz»" '[[ "$(env -i PATH=$T/gx "$(command -v bash)" -c ". $T/p.sh; pista xz")" == "xbps-install xz" ]]'
espera "actualizar: sin gestor conocido → pista genérica" '[[ "$(env -i PATH=$T/nada "$(command -v bash)" -c ". $T/p.sh; pista xz")" == "instálalo con tu gestor de paquetes" ]]'
espera "actualizar: el NO de programa faltante lleva la pista" 'grep -qF "NO \"falta el programa \$f (\$(pista \"\$f\"))\"" "$B/guardian-actualizar"'

# instalar-en-disco: lo copia junto a install-guardian (dos ramas)
espera "instalar-en-disco: copia guardian-actualizar en las 2 ramas" '[[ $(grep -cF "\"\$MNT/root/guardian-src/guardian-actualizar\"" "$B/instalar-en-disco") -eq 2 ]]'
# instalar-minios: lo pone en la unión y el módulo debe traerlo
. <(sed -n '/^MOS_MOD_PIEZAS=(/,/)$/p' "$B/instalar-minios")
espera "minios: módulo exige lib y sbin/guardian-actualizar" '[[ " ${MOS_MOD_PIEZAS[*]} " == *" usr/lib/guardian/guardian-actualizar "* && " ${MOS_MOD_PIEZAS[*]} " == *" usr/local/sbin/guardian-actualizar "* ]]'
espera "minios: copia el actualizador a la unión" 'grep -qF "\"\$SRC/guardian-actualizar\" \"\$W/u\$GS/guardian-actualizar\"" "$B/instalar-minios"'
# NixOS
espera "guardian.nix: empaqueta guardian-actualizar" 'grep -qF "\$out/bin/guardian-actualizar" "$B/../nixos/guardian.nix"'
for f in instalar-mkinitfs instalar-dracut-sinsd instalar-en-disco instalar-minios guardian-actualizar; do
    espera "bash -n $f" 'bash -n "$B/$f"'
done
echo "$P passed, $F failed"; (( F == 0 ))
