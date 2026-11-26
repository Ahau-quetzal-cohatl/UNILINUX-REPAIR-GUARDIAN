#!/bin/bash
# Guardian 4.17.4 — /boot en otra partición: instalar-en-disco e instalar-dracut la montan
# desde el fstab del destino, con guardas. Sin root: se extrae el bloque (4.17.4) y se corre
# con dobles. Uso: bash tests/test-boot-aparte.sh [CARPETA_bin]
B="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin}"
IED="$B/instalar-en-disco"; IDR="$B/instalar-dracut"
[[ -f "$IED" && -f "$IDR" ]] || { echo "✖ No encuentro $IED o $IDR"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P=0; F=0
si() { echo "  ✔ $1"; P=$((P + 1)); }
no() { echo "  ✖ $1"; F=$((F + 1)); }
espera() { if eval "$2"; then si "$1"; else no "$1"; echo "      registro: $(tr '\n' '|' <"$T/log" 2>/dev/null | cut -c1-300) | $(tr '\n' '|' <"$T/out" 2>/dev/null | cut -c1-200)"; fi; }
pos() { local n; n=$(grep -n -x -F -- "$1" "$T/log" 2>/dev/null | head -n 1 | cut -d: -f1); echo "${n:-0}"; }
hay() { grep -q -x -F -- "$1" "$T/log"; }
lin() { grep -n -E -- "$2" "$1" | head -n 1 | cut -d: -f1; }
extrae() { awk '/^# >>> \(4\.17\.4\)/{p=1} p{print} /^# <<< \(4\.17\.4\)/{exit}' "$1"; }
extrae "$IED" >"$T/b-ied.sh"; extrae "$IDR" >"$T/b-idr.sh"
awk '/^cleanup\(\) \{/{p=1} p{print} p && /^\}/{exit}' "$IDR" >"$T/c-idr.sh"

echo "── Estructura"
espera "ied: bloque 4.17.4 con montar_boot_fstab" 'grep -q "^montar_boot_fstab() {" "$T/b-ied.sh"'
espera "idr: bloque 4.17.4 con montar_boot_fstab" 'grep -q "^montar_boot_fstab() {" "$T/b-idr.sh"'
espera "ied: justo tras el bloque 4.17.2" '(( $(lin "$IED" "^# <<< \(4\.17\.2\)")+0 > 0 && $(lin "$IED" "^# <<< \(4\.17\.2\)")+1 == $(lin "$IED" "^# >>> \(4\.17\.4\)")+0 ))'
espera "ied: antes de la detección del sistema" '(( $(lin "$IED" "^# <<< \(4\.17\.4\)")+0 > 0 && $(lin "$IED" "^# <<< \(4\.17\.4\)")+0 < $(lin "$IED" "^TIPO=\"\"")+0 ))'
espera "idr: tras la comprobación de dracut" '(( $(lin "$IDR" "^\[\[ -x \"\\\$MNT/usr/bin/dracut\"")+0 > 0 && $(lin "$IDR" "^\[\[ -x \"\\\$MNT/usr/bin/dracut\"")+1 == $(lin "$IDR" "^# >>> \(4\.17\.4\)")+0 ))'
espera "idr: antes de buscar el kernel y el initramfs" '(( $(lin "$IDR" "^# <<< \(4\.17\.4\)")+0 > 0 && $(lin "$IDR" "^# <<< \(4\.17\.4\)")+0 < $(lin "$IDR" "^# Kernel: el pedido")+0 && $(lin "$IDR" "^# Kernel: el pedido")+0 < $(lin "$IDR" "^IMGH=")+0 ))'
espera "idr: VERSION 1.7 o más" 'grep -q -E "^VERSION=\"1\.([7-9]|[1-9][0-9])\"" "$IDR"'
espera "el bloque no desmonta nada" '! grep -q umount "$T/b-ied.sh" && ! grep -q umount "$T/b-idr.sh"'

cat >"$T/dobles.sh" <<'P'
blkid()      { case "$1" in -U) [[ "$2" == "$D_BU" ]] && echo "$D_BDEV" ;; -L) [[ "$2" == "$D_BL" ]] && echo "$D_BDEV" ;; esac; return 0; }
readlink()   { echo "${@: -1}"; }
test()       { if [[ "$1" == -b ]]; then [[ " $D_BLOQUES " == *" $2 "* ]]; else builtin test "$@"; fi; }
findmnt()    { [[ -n "$D_HOSTMNT" && " $* " == *" $D_BDEV "* ]] && echo "$D_HOSTMNT"; return 0; }
lsblk()      { local v; if [[ "${@: -1}" == "$D_BDEV" ]]; then v=$D_PK1; elif [[ -n "$D_CADENA" ]]; then printf "%b\n" "$D_CADENA"; return 0; else v=$D_PK2; fi; [[ -n "$v" ]] && echo "$v disk"; return 0; }
dumpe2fs()   { if [[ -n "$D_SUCIO" ]]; then echo "Filesystem state:         not clean"; else echo "Filesystem state:         clean"; fi; }
mount()      { echo "MOUNT $*" >>"$LOG"; [[ -n "$D_FALLA" ]] && return 1; return 0; }
mountpoint() { [[ "$1" == -q ]] && shift; [[ " $D_MONTADOS " == *" $1 "* ]]; }
umount()     { echo "UMOUNT $*" >>"$LOG"; return 0; }
die()        { echo "DIE $*" >>"$LOG"; exit 1; }
SUBVOLS_MONTADOS=()
P
M="$T/mnt"; mkdir -p "$M/etc" "$M/boot"
fstab() { printf '%s\n' "# fstab" "UUID=R1 / btrfs subvol=root 0 0" "$@" >"$M/etc/fstab"; }
corre() {   # $1 bloque ; variables D_* del entorno ; $2 (no vacío) = + cleanup de idr
    : >"$T/log"
    { cat "$T/dobles.sh" "$1"; echo 'echo "N=${#SUBVOLS_MONTADOS[@]}" >>"$LOG"'
      if [[ -n "${2:-}" ]]; then cat "$T/c-idr.sh"; echo cleanup; fi; } >"$T/corre.sh"
    env -i PATH="$PATH" LOG="$T/log" MNT="$M" DEV=/dev/sdz9 \
        D_BU="${D_BU-B1}" D_BL="${D_BL-}" D_BDEV="${D_BDEV-/dev/sdz1}" D_BLOQUES="${D_BLOQUES-/dev/sdz1 /dev/sdz9 /dev/disk/by-partuuid/PP}" \
        D_HOSTMNT="${D_HOSTMNT:-}" D_PK1="${D_PK1-sdz}" D_PK2="${D_PK2-sdz}" D_CADENA="${D_CADENA:-}" D_SUCIO="${D_SUCIO:-}" \
        D_FALLA="${D_FALLA:-}" D_MONTADOS="$M ${D_MONT:-}" bash "$T/corre.sh" >"$T/out" 2>&1
    echo $? >"$T/rc"
}
nomonta() { ! grep -q "^MOUNT" "$T/log" && hay "N=0" && [[ $(cat "$T/rc") == 0 ]]; }

for S in ied idr; do
  BL="$T/b-$S.sh"
  echo "── $S"
  fstab "UUID=B1 /boot ext4 defaults 1 2" "UUID=E1 /boot/efi vfat umask=0077 0 2"
  corre "$BL"
  espera "$S fedora: monta /boot ext4 (UUID=)" 'hay "MOUNT -t ext4 /dev/sdz1 $M/boot" && hay "N=1" && grep -q "/boot (/dev/sdz1, ext4) montado" "$T/out"'
  espera "$S no monta /boot/efi" '! grep -q "boot/efi" "$T/log"'
  fstab "LABEL=arranque /boot ext4 defaults 1 2"
  D_BU="" D_BL=arranque corre "$BL"
  espera "$S LABEL=" 'hay "MOUNT -t ext4 /dev/sdz1 $M/boot"'
  fstab "PARTUUID=PP /boot xfs defaults 0 0"
  D_BDEV=/dev/disk/by-partuuid/PP corre "$BL"
  espera "$S PARTUUID= y xfs (sin dumpe2fs)" 'hay "MOUNT -t xfs /dev/disk/by-partuuid/PP $M/boot"'
  fstab "/dev/sdz1 /boot ext3 defaults 0 0"
  corre "$BL"
  espera "$S /dev/... directo, ext3" 'hay "MOUNT -t ext3 /dev/sdz1 $M/boot"'
  fstab "UUID=B1 /boot vfat umask=0077 0 2"
  corre "$BL"
  espera "$S ESP como /boot (vfat)" 'hay "MOUNT -t vfat /dev/sdz1 $M/boot"'
  fstab "UUID=B1 /boot btrfs compress=zstd,subvol=@boot 0 0"
  corre "$BL"
  espera "$S btrfs de otro dispositivo con subvol=" 'hay "MOUNT -o subvol=@boot -t btrfs /dev/sdz1 $M/boot"'
  fstab "UUID=R1 /boot btrfs subvol=boot 0 0"
  D_BU=R1 D_BDEV=/dev/sdz9 corre "$BL"
  espera "$S mismo dispositivo que la raíz: nada (lo hacen los subvolúmenes)" 'nomonta && [[ ! -s "$T/out" ]]'
  fstab "UUID=B1 /boot ext4 defaults 1 2"
  D_BDEV="" corre "$BL"
  espera "$S dispositivo no encontrado: aviso, nada" 'nomonta && grep -q "no encuentro el dispositivo de /boot" "$T/out"'
  D_BLOQUES="/dev/sdz9" corre "$BL"
  espera "$S no es de bloques: aviso, nada" 'nomonta && grep -q "no encuentro el dispositivo" "$T/out"'
  D_HOSTMNT=/boot corre "$BL"
  espera "$S es el /boot de ESTE equipo: no se toca" 'nomonta && grep -q "montado en ESTE equipo" "$T/out"'
  D_HOSTMNT=/ corre "$BL"
  espera "$S es la raíz de ESTE equipo: no se toca" 'nomonta && grep -q "montado en ESTE equipo" "$T/out"'
  D_HOSTMNT=/media/x/BOOT corre "$BL"
  espera "$S automontado en /media: sí se monta" 'hay "MOUNT -t ext4 /dev/sdz1 $M/boot"'
  D_PK1=sdy corre "$BL"
  espera "$S en otro disco: no se monta" 'nomonta && grep -q "en otro disco" "$T/out"'
  D_PK1="" corre "$BL"
  espera "$S disco desconocido (loop): se monta" 'hay "MOUNT -t ext4 /dev/sdz1 $M/boot"'
  D_CADENA="vg-raiz lvm\ngroot-crypt crypt\nsdz3 part\nsdz disk" corre "$BL"
  espera "$S raíz en LVM sobre LUKS (cadena hasta sdz): se monta" 'hay "MOUNT -t ext4 /dev/sdz1 $M/boot"'
  D_CADENA="vg-raiz lvm\ngroot-crypt crypt\nsdy3 part\nsdy disk" corre "$BL"
  espera "$S raíz LVM/LUKS en OTRO disco: no se monta" 'nomonta && grep -q "en otro disco" "$T/out"'
  D_SUCIO=1 corre "$BL"
  espera "$S ext4 sucio: no se monta, pide e2fsck" 'nomonta && grep -q "e2fsck -p /dev/sdz1" "$T/out"'
  D_MONT="$M/boot" corre "$BL"
  espera "$S ya montado: nada" 'nomonta'
  D_FALLA=1 corre "$BL"
  espera "$S montaje falla: aviso, no se anota, rc=0" 'grep -q "^MOUNT" "$T/log" && hay "N=0" && grep -q "No se pudo montar /boot" "$T/out" && [[ $(cat "$T/rc") == 0 ]]'
  fstab "UUID=B1 /boot ext4 defaults,noauto 1 2"
  corre "$BL"
  espera "$S noauto: no se monta" 'nomonta && grep -q "noauto" "$T/out"'
  fstab "UUID=B1 /boot ext4 defaults 1 2" "UUID=B2 /boot ext4 defaults 1 2"
  corre "$BL"
  espera "$S dos líneas /boot: no se monta" 'nomonta && grep -q "2 líneas para /boot" "$T/out"'
  fstab "srv:/boot /boot nfs defaults 0 0"
  corre "$BL"
  espera "$S nfs: no se monta" 'nomonta && grep -q "es .nfs." "$T/out"'
  fstab "#UUID=B1 /boot ext4 defaults 1 2" "UUID=E1 /boot/efi vfat umask=0077 0 2"
  corre "$BL"
  espera "$S sin línea /boot (comentada): nada, callado" 'nomonta && [[ ! -s "$T/out" ]]'
  fstab "UUID=B1 /boot ext4 defaults 1 2"
  mv "$M/boot" "$M/boot.aparte"; ln -s /tmp "$M/boot"
  corre "$BL"
  espera "$S /boot del destino es un enlace: no se monta" 'nomonta && grep -q "no es un directorio" "$T/out"'
  rm "$M/boot"; mv "$M/boot.aparte" "$M/boot"
  mv "$M/etc/fstab" "$M/etc/fstab.aparte"
  corre "$BL"
  espera "$S sin fstab: nada" 'nomonta && [[ ! -s "$T/out" ]]'
  mv "$M/etc/fstab.aparte" "$M/etc/fstab"
done
echo "── idr: cleanup desmonta /boot antes de \$MNT"
fstab "UUID=B1 /boot ext4 defaults 1 2"
corre "$T/b-idr.sh" cleanup
espera "UMOUNT /boot antes que \$MNT" '(( $(pos "UMOUNT $M/boot") > 0 && $(pos "UMOUNT $M/boot") < $(pos "UMOUNT $M") ))'
echo "── Sintaxis"
espera "bash -n instalar-en-disco" 'bash -n "$IED"'
espera "bash -n instalar-dracut" 'bash -n "$IDR"'
echo ""
echo "/boot aparte: $P passed, $F failed"
(( F == 0 ))
