#!/bin/bash
# test-minios.sh (4.18.6): instalar-minios (MiniOS: 2.º initrd con ganchos dracut pre-mount/pre-pivot,
# módulo 90-guardian.sb, .cfg con from=) y la rama MiniOS de instalar-en-disco.
# Uso: bash tests/test-minios.sh [directorio bin]   (contra 4.18.5 FALLA: no existe instalar-minios)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
I=$B/instalar-minios
espera "instalar-minios existe y pasa bash -n" '[[ -f "$I" ]] && bash -n "$I"'
FS=$(sed -n '/^# >>> minios/,/^# <<< minios/p' "$I" 2>/dev/null)
espera "bloque minios" '[[ -n "$FS" ]]'
eval "$FS"
SHS=""
for s in dash bash "busybox sh"; do set -- $s; a=$(command -v "$1" 2>/dev/null) && SHS="$SHS|$a${2:+ $2}"; done
espera "hay dash o bash" '[[ "$SHS" == *dash* || "$SHS" == *bash* ]]'
echo "shells: ${SHS#|}"

# --- gancho pre-mount: ROOT=UUID de datos, espera a blkid -U, sin exit
mos_gancho_pre >"$T/pre.sh" 2>/dev/null
espera "pre-mount: no vacío y sin exit" '[[ -s "$T/pre.sh" ]] && ! grep -Eq "(^|[;&|[:space:]])exit([[:space:];]|$)" "$T/pre.sh"'
espera "pre-mount: lee /etc/guardian-minios.conf" 'grep -q "\. /etc/guardian-minios.conf" "$T/pre.sh"'
espera "pre-mount: espera al disco con blkid -U (máx. 30)" 'grep -q "blkid -U" "$T/pre.sh" && grep -q "\-lt 30" "$T/pre.sh"'
mkdir -p "$T/b"
printf '#!/bin/sh\necho "ROOT=$ROOT" >>%s/ge.log\n' "$T" >"$T/b/ge"
printf '#!/bin/sh\n[ "$1" = -U ] && [ "$2" = 1111-aa ] && echo /dev/sdz9\n' >"$T/b/blkid"
printf 'sleep() { :; }\n' >"$T/b/nosleep"
chmod +x "$T/b/ge" "$T/b/blkid"
printf 'GUARDIAN_DATOS=UUID=1111-aa\n' >"$T/mc"
sed -e "s|/usr/bin/guardian-early|$T/b/ge|g" -e "s|/etc/guardian-minios.conf|$T/mc|g" "$T/pre.sh" >"$T/pre2.sh"
IFS='|' read -ra SL <<<"${SHS#|}"
for sh in "${SL[@]}"; do
    rm -f "$T/ge.log"
    PATH="$T/b:$PATH" $sh -c ". $T/pre2.sh; echo SIGUE" >"$T/out" 2>&1
    espera "pre-mount ($sh): guardian-early con ROOT=UUID=1111-aa" 'grep -qx "ROOT=UUID=1111-aa" "$T/ge.log" 2>/dev/null'
    espera "pre-mount ($sh): el init sigue (sin exit)" 'grep -qx SIGUE "$T/out"'
    $sh -n "$T/pre.sh" 2>/dev/null; espera "pre-mount ($sh -n)" '[[ $? -eq 0 ]]'
done
rm -f "$T/ge.log"
printf 'GUARDIAN_DATOS=\n' >"$T/mc"
PATH="$T/b:$PATH" sh -c ". $T/pre2.sh" >/dev/null 2>&1
espera "pre-mount: sin UUID no llama a guardian-early" '[[ ! -e "$T/ge.log" ]]'

# --- gancho pre-pivot: copia /run/guardian a $NEWROOT/run/guardian
mos_gancho_pivot >"$T/piv.sh" 2>/dev/null
espera "pre-pivot: no vacío y sin exit" '[[ -s "$T/piv.sh" ]] && ! grep -Eq "(^|[;&|[:space:]])exit([[:space:];]|$)" "$T/piv.sh"'
mkdir -p "$T/run/guardian" "$T/nr/run"; echo ok >"$T/run/guardian/early_status"; echo log >"$T/run/guardian/early.log"
sed "s| /run/guardian| $T/run/guardian|g" "$T/piv.sh" >"$T/piv2.sh"   # solo el /run del initrd, no $_g_nr/run
NEWROOT=$T/nr sh -c ". $T/piv2.sh; echo SIGUE" >"$T/out" 2>&1
espera "pre-pivot: early_status llega a \$NEWROOT/run/guardian" '[[ "$(cat "$T/nr/run/guardian/early_status" 2>/dev/null)" == ok && -f "$T/nr/run/guardian/early.log" ]]'
espera "pre-pivot: el init sigue" 'grep -qx SIGUE "$T/out"'
echo otro >"$T/nr/run/guardian/early_status"
NEWROOT=$T/nr sh -c ". $T/piv2.sh" >/dev/null 2>&1
espera "pre-pivot: no pisa un estado ya copiado" '[[ "$(cat "$T/nr/run/guardian/early_status")" == otro ]]'

# --- enlaces dentro de la imagen (forma del initrd de MiniOS 5.1.1)
Bm=$T/base; mkdir -p "$Bm/usr/lib/x86_64-linux-gnu" "$Bm/usr/lib/dracut" "$Bm/var/lib/dracut/hooks/pre-mount" "$Bm/var/lib/dracut/hooks/pre-pivot" "$Bm/usr/sbin"
ln -s usr/lib "$Bm/lib"; ln -s usr/sbin "$Bm/sbin"; ln -s ../../../var/lib/dracut/hooks "$Bm/usr/lib/dracut/hooks"
: >"$Bm/usr/lib/x86_64-linux-gnu/libc.so.6"; ln -s /usr/lib "$Bm/abs"; ln -s ../../../../.. "$Bm/usr/lib/fuga"
espera "resolver: lib/x86_64-linux-gnu/libc.so.6 → usr/lib/…" '[[ "$(mos_resolver "$Bm" lib/x86_64-linux-gnu/libc.so.6)" == usr/lib/x86_64-linux-gnu/libc.so.6 ]]'
espera "resolver: enlace absoluto apunta DENTRO de la imagen" '[[ "$(mos_resolver "$Bm" abs/x86_64-linux-gnu)" == usr/lib/x86_64-linux-gnu ]]'
espera "resolver: .. no sale de la imagen" '[[ "$(mos_resolver "$Bm" usr/lib/fuga/etc)" == etc ]]'
espera "carpeta real de ganchos = var/lib/dracut/hooks" '[[ "$(mos_dir_ganchos "$Bm")" == var/lib/dracut/hooks ]]'
O=$T/ov; mkdir -p "$O/var/lib/dracut/hooks/pre-mount" "$O/usr/bin" "$O/usr/lib/x86_64-linux-gnu"
mos_guarda_enlaces "$Bm" "$O" >/dev/null; espera "guarda: cpio bueno sin choques" '[[ $? -eq 0 ]]'
mkdir -p "$O/usr/lib/dracut/hooks/pre-mount" "$O/lib/x"
mos_guarda_enlaces "$Bm" "$O" >"$T/ch"; n=$?
espera "guarda: usr/lib/dracut/hooks y lib/ detectados (choques=$n)" '(( n >= 3 )) && grep -q "cruza el enlace usr/lib/dracut/hooks" "$T/ch" && grep -q "cruza el enlace lib)" "$T/ch"'

# --- .cfg de MiniOS (forma de grub/main.cfg y syslinux/lang/*.cfg de 5.1.1)
cat >"$T/main.cfg" <<'CFG'
menuentry "Resume" {
    linux /minios/boot/vmlinuz-6.12 boot=live load_ramdisk=1 rw quiet perchdir=resume $lang_utf $extra_params
    initrd /minios/boot/initrfs-6.12.img
}
menuentry "Ya con from" {
    linux /minios/boot/vmlinuz-6.12 boot=live from=/dev/sdb1/minios rw
    initrd /minios/boot/initrfs-6.12.img
}
CFG
printf 'LABEL a\nAPPEND vga=788 initrd=/minios/boot/initrfs-6.12.img boot=live rw quiet\n' >"$T/sl.cfg"
mos_editar_cfg "$T/main.cfg" GMINIOS >"$T/m1"
espera "grub: 2.º initrd en las 2 entradas" '[[ $(grep -c "^ *initrd /minios/boot/initrfs-6.12.img /minios/boot/guardian-early.img$" "$T/m1") -eq 2 ]]'
espera "grub: from= por etiqueta en la que no tenía" '[[ $(grep -c "from=/dev/disk/by-label/GMINIOS/minios" "$T/m1") -eq 1 ]]'
espera "grub: respeta un from= existente" 'grep -q "from=/dev/sdb1/minios rw$" "$T/m1"'
mos_editar_cfg "$T/m1" GMINIOS >"$T/m2"
espera "grub: idempotente" 'cmp -s "$T/m1" "$T/m2"'
mos_editar_cfg "$T/main.cfg" "" >"$T/m3"
espera "grub: sin etiqueta no pone from=" '! grep -q "by-label" "$T/m3" && grep -q guardian-early.img "$T/m3"'
mos_editar_cfg "$T/sl.cfg" GMINIOS >"$T/s1"
espera "syslinux: initrd=…,guardian-early.img y from=" 'grep -q "initrd=/minios/boot/initrfs-6.12.img,/minios/boot/guardian-early.img boot=live" "$T/s1" && grep -q "from=/dev/disk/by-label/GMINIOS/minios$" "$T/s1"'
mos_editar_cfg "$T/s1" GMINIOS | cmp -s - "$T/s1"; espera "syslinux: idempotente" '[[ $? -eq 0 ]]'

# --- piezas y estructura del instalador
espera "PIEZAS del cpio sin «|»" '! printf "%s\n" "${MOS_PIEZAS[@]}" | grep -q "|"'
espera "PIEZAS: guardian-early, e2image, early.conf, minios.conf" '[[ " ${MOS_PIEZAS[*]} " == *" usr/bin/guardian-early "* && " ${MOS_PIEZAS[*]} " == *" usr/bin/e2image "* && " ${MOS_PIEZAS[*]} " == *" etc/guardian-early.conf "* && " ${MOS_PIEZAS[*]} " == *" etc/guardian-minios.conf "* ]]'
espera "módulo: unidad y enlace de guardian-late" '[[ " ${MOS_MOD_PIEZAS[*]} " == *" etc/systemd/system/multi-user.target.wants/guardian-late.service "* ]]'
espera "instalador: tardía REAL con install-guardian solo-tardía en chroot" 'grep -q "GUARDIAN_SOLO_TARDIA=1 /bin/bash \"\$GS/install-guardian\"" "$I"'
espera "instalador: chroot con PATH explícito" 'grep -q "chroot \"\$W/u\" /usr/bin/env -i PATH=" "$I"'
espera "instalador: crea dev/proc/sys que faltan en la unión y los quita" 'grep -q "for pm in dev proc sys" "$I" && grep -q "rmdir \"\$W/up/\$pm\"" "$I"'
espera "instalador: rechaza capa con whiteouts" 'grep -q "find \"\$W/up\" -type c" "$I"'
espera "instalador: from= solo con etiqueta única" 'grep -q "LABEL=\"\$ET\"" "$I" && grep -q "no es única" "$I"'
espera "instalador: no toca el initrd oficial (sin dracut -f)" '! grep -Eq "^[^#]*dracut -f" "$I"'
espera "instalador: guarda las anteriores" 'grep -q "guardian-anterior" "$I"'

# --- rama de instalar-en-disco
E=$B/instalar-en-disco
espera "instalar-en-disco: rama MiniOS antes de exigir os-release" 'awk "/minios\\/boot/{m=NR} /falta \\/etc\\/os-release/{o=NR} END{exit !(m && o && m<o)}" "$E"'
espera "instalar-en-disco: exec instalar-minios --sistema-confiable" 'grep -q "exec /bin/bash \"\$SRC/instalar-minios\" \"\$DEV\" --sistema-confiable" "$E"'
espera "install-guardian: versión 4.19.1" 'grep -q "Instalando Unilinux Guardian v4.19.1" "$B/install-guardian"'

echo "RESULTADO: $P ok, $F fallas"
[[ $F -eq 0 ]]
