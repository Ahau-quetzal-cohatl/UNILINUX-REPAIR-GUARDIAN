#!/bin/bash
# Guardian 4.17.3 — raíz btrfs en un subvolumen que no es el de por defecto (instalar-en-disco
# e instalar-dracut) y subvolúmenes del fstab en instalar-dracut. Sin root: se extraen los
# bloques (4.17.3) y cleanup y se corren con dobles. Uso: bash tests/test-subvol-raiz.sh [bin]
B="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin}"
IED="$B/instalar-en-disco"; IDR="$B/instalar-dracut"
[[ -f "$IED" && -f "$IDR" ]] || { echo "✖ No encuentro $IED o $IDR"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P=0; F=0
si() { echo "  ✔ $1"; P=$((P + 1)); }
no() { echo "  ✖ $1"; F=$((F + 1)); }
espera() { if eval "$2"; then si "$1"; else no "$1"; echo "      registro: $(tr '\n' '|' <"$T/log" 2>/dev/null | cut -c1-400)"; fi; }
pos() { local n; n=$(grep -n -x -F -- "$1" "$T/log" 2>/dev/null | head -n 1 | cut -d: -f1); echo "${n:-0}"; }
hay() { grep -q -x -F -- "$1" "$T/log"; }
lin() { grep -n -E -- "$2" "$1" | head -n 1 | cut -d: -f1; }

extrae() { awk '/^# >>> \(4\.17\.3\)/{p=1} p{print} /^# <<< \(4\.17\.3\)/{exit}' "$1"; }
extrae "$IED" >"$T/b-ied.sh"; extrae "$IDR" >"$T/b-idr.sh"
awk '/^cleanup\(\) \{/{p=1} p{print} p && /^\}/{exit}' "$IDR" >"$T/c-idr.sh"
echo "── Estructura"
espera "ied: bloque 4.17.3 con raiz_subvol_btrfs" 'grep -q "^raiz_subvol_btrfs() {" "$T/b-ied.sh"'
espera "idr: bloque 4.17.3 con raiz_subvol_btrfs" 'grep -q "^raiz_subvol_btrfs() {" "$T/b-idr.sh"'
espera "idr: bloque 4.17.3 con montar_subvols_fstab" 'grep -q "^montar_subvols_fstab() {" "$T/b-idr.sh"'
espera "idr: cleanup desmonta SUBVOLS_MONTADOS" 'grep -q "SUBVOLS_MONTADOS" "$T/c-idr.sh"'
espera "idr: SUBVOLS_MONTADOS=() antes de cleanup" '(( $(lin "$IDR" "^SUBVOLS_MONTADOS=\(\)")+0 > 0 && $(lin "$IDR" "^SUBVOLS_MONTADOS=\(\)")+0 < $(lin "$IDR" "^cleanup\(\) \{")+0 ))'
for S in IED IDR; do
  f=${!S}
  espera "$S: bloque justo después del mount del disco" '(( $(lin "$f" "^mount \"\\\$DEV\" \"\\\$MNT\" \|\| die")+0 > 0 && $(lin "$f" "^mount \"\\\$DEV\" \"\\\$MNT\" \|\| die")+1 == $(lin "$f" "^# >>> \(4\.17\.3\)")+0 ))'
done
espera "ied: bloque 4.17.3 antes del 4.17.2" '(( $(lin "$IED" "^# <<< \(4\.17\.3\)")+0 > 0 && $(lin "$IED" "^# <<< \(4\.17\.3\)")+1 == $(lin "$IED" "^# >>> \(4\.17\.2\)")+0 ))'
espera "idr: bloque antes de la comprobación de os-release" '(( $(lin "$IDR" "^# <<< \(4\.17\.3\)")+1 == $(lin "$IDR" "^\[\[ -f \"\\\$MNT/etc/os-release\" \]\]")+0 ))'
espera "idr: borra guardian-src tras el chroot y antes de mirar rc" '(( $(lin "$IDR" "^chroot \"\\\$MNT\"")+0 > 0 && $(lin "$IDR" "^chroot \"\\\$MNT\"")+0 < $(lin "$IDR" "^rm -rf -- \"\\\$MNT/root/guardian-src\"")+0 && $(lin "$IDR" "^rm -rf -- \"\\\$MNT/root/guardian-src\"")+0 < $(lin "$IDR" "^if \(\( rc != 0 \)\); then")+0 ))'
espera "idr: VERSION 1.6 o más" 'grep -q -E "^VERSION=\"1\.([6-9]|[1-9][0-9])\"" "$IDR"'

cat >"$T/dobles.sh" <<'P'
blkid()      { echo "$D_UUID"; }
mount()      { echo "MOUNT $*" >>"$LOG"; [[ -n "$D_FALLA" && " $* " == *" $D_FALLA "* ]] && return 1; return 0; }
mountpoint() { [[ "$1" == -q ]] && shift; [[ " $D_MONTADOS " == *" $1 "* ]]; }
umount()     { echo "UMOUNT $*" >>"$LOG"; [[ -n "$D_UMFALLA" ]] && return 1; return 0; }
die()        { echo "DIE $*" >>"$LOG"; exit 1; }
SUBVOLS_MONTADOS=()
P
corre() {   # $1 bloque, $2 FSTIPO, $3 UUID, $4 MNT, $5 (si no vacío) + cleanup de idr
    : >"$T/log"
    { cat "$T/dobles.sh" "$1"; echo 'echo "N=${#SUBVOLS_MONTADOS[@]}" >>"$LOG"'
      if [[ -n "${5:-}" ]]; then cat "$T/c-idr.sh"; echo cleanup; fi; } >"$T/corre.sh"
    env -i PATH="$PATH" LOG="$T/log" MNT="$4" DEV=/dev/sdz9 FSTIPO="$2" FST="$2" D_UUID="$3" \
        D_FALLA="${D_FALLA:-}" D_UMFALLA="${D_UMFALLA:-}" D_MONTADOS="$4" bash "$T/corre.sh" >"$T/out" 2>&1
    echo $? >"$T/rc"
}
sistema() {   # $1 dir, $2 subvol, $3 línea "/" del fstab
    mkdir -p "$1/$2/etc"; echo 'NAME=x' >"$1/$2/etc/os-release"; printf '%s\n' "# fstab" "$3" >"$1/$2/etc/fstab"
}
sistema "$T/fed" root "UUID=U1 / btrfs subvol=root,compress=zstd:1 0 0"
echo "UUID=U1 /home btrfs subvol=home,compress=zstd:1 0 0" >>"$T/fed/root/etc/fstab"; mkdir -p "$T/fed/home"
sistema "$T/ubu" @ "UUID=U1 / btrfs defaults,subvol=@ 0 1"; mkdir -p "$T/ubu/@home"
sistema "$T/arch" @ "UUID=U1 / btrfs rw,relatime,ssd,subvolid=256,subvol=/@ 0 0"
sistema "$T/byid" root "/dev/disk/by-uuid/U1 / btrfs subvol=root 0 0"
sistema "$T/dos" @ "UUID=U1 / btrfs subvol=@ 0 0"; sistema "$T/dos" root "UUID=U1 / btrfs subvol=root 0 0"
sistema "$T/mal" root "UUID=U1 / btrfs subvol=@ 0 0"
sistema "$T/otro" root "UUID=U9 / btrfs subvol=root 0 0"
sistema "$T/coment" root "#UUID=U1 / btrfs subvol=root 0 0"
sistema "$T/sinsub" root "UUID=U1 / btrfs defaults 0 0"
mkdir -p "$T/enl/x/etc"; echo 'NAME=x' >"$T/enl/x/etc/os-release"; echo "UUID=U1 / btrfs subvol=root 0 0" >"$T/enl/x/etc/fstab"; ln -s "$T/enl/x" "$T/enl/root"
mkdir -p "$T/vacio/@home"

for S in ied idr; do
  BL="$T/b-$S.sh"
  echo "── $S: raíz en subvolumen"
  corre "$BL" btrfs U1 "$T/fed"
  espera "$S fedora: desmonta y monta subvol=root" 'hay "UMOUNT $T/fed" && hay "MOUNT -o subvol=root /dev/sdz9 $T/fed" && (( $(pos "UMOUNT $T/fed") < $(pos "MOUNT -o subvol=root /dev/sdz9 $T/fed") ))'
  espera "$S fedora: lo dice y rc=0" 'grep -q "Raíz en el subvolumen root" "$T/out" && [[ $(cat "$T/rc") == 0 ]]'
  corre "$BL" btrfs U1 "$T/ubu"
  espera "$S ubuntu: subvol=@" 'hay "MOUNT -o subvol=@ /dev/sdz9 $T/ubu"'
  corre "$BL" btrfs U1 "$T/arch"
  espera "$S arch: subvol=/@ → @ (con subvolid antes)" 'hay "MOUNT -o subvol=@ /dev/sdz9 $T/arch"'
  corre "$BL" btrfs U1 "$T/byid"
  espera "$S acepta /dev/disk/by-uuid/" 'hay "MOUNT -o subvol=root /dev/sdz9 $T/byid"'
  for c in dos mal otro coment sinsub enl vacio; do
    corre "$BL" btrfs U1 "$T/$c"
    espera "$S $c: no desmonta ni monta, aviso, rc=0" '! grep -q "MOUNT" "$T/log" && grep -q "no hay una raíz única" "$T/out" && [[ $(cat "$T/rc") == 0 ]]'
  done
  corre "$BL" ext4 U1 "$T/fed"
  espera "$S ext4: nada" '! grep -q "MOUNT" "$T/log" && [[ $(cat "$T/rc") == 0 ]]'
  corre "$BL" btrfs "" "$T/fed"
  espera "$S sin UUID: aviso, nada" '! grep -q "MOUNT" "$T/log" && grep -q "sin UUID" "$T/out"'
  D_UMFALLA=1 corre "$BL" btrfs U1 "$T/fed"
  espera "$S no desmonta: DIE, no monta subvol" 'grep -q "^DIE No pude desmontar" "$T/log" && ! grep -q "^MOUNT" "$T/log" && [[ $(cat "$T/rc") != 0 ]]'
  D_FALLA="$T/fed" corre "$BL" btrfs U1 "$T/fed"
  espera "$S no monta subvol: DIE" 'grep -q "^DIE No se pudo montar el subvolumen root" "$T/log" && [[ $(cat "$T/rc") != 0 ]]'
done

echo "── idr: sistema con raíz por defecto (openSUSE) y subvolúmenes del fstab"
M="$T/suse"
mkdir -p "$M/etc" "$M/var" "$M/usr/local" "$M/root" "$M/home" "$M/fail"; echo 'NAME=s' >"$M/etc/os-release"
cat >"$M/etc/fstab" <<'FS'
UUID=U1  /            btrfs  defaults                   0 0
UUID=U1  /var         btrfs  subvol=/@/var              0 0
UUID=U1  /usr/local   btrfs  subvol=/@/usr/local        0 0
UUID=U1  /usr         btrfs  compress=zstd,subvol=@usr  0 0
UUID=U1  /root        btrfs  subvol=/@/root             0 0
UUID=U1  /home        btrfs  subvol=/@/home,noauto      0 0
UUID=U2  /data        btrfs  subvol=@data               0 0
UUID=U1  /opt         btrfs  subvol=/@/opt              0 0
UUID=U1  /fail        btrfs  subvol=/@/fail             0 0
UUID=E1  /boot/efi    vfat   utf8                       0 2
FS
D_FALLA="$M/fail" corre "$T/b-idr.sh" btrfs U1 "$M" cleanup
espera "no desmonta ni remonta la raíz" '! hay "UMOUNT $M" || (( $(pos "UMOUNT $M") > $(pos "N=4") ))'
espera "monta /var /usr /usr/local /root" 'hay "MOUNT -o subvol=/@/var /dev/sdz9 $M/var" && hay "MOUNT -o subvol=@usr /dev/sdz9 $M/usr" && hay "MOUNT -o subvol=/@/usr/local /dev/sdz9 $M/usr/local" && hay "MOUNT -o subvol=/@/root /dev/sdz9 $M/root"'
espera "/usr antes de /usr/local" '(( $(pos "MOUNT -o subvol=@usr /dev/sdz9 $M/usr") < $(pos "MOUNT -o subvol=/@/usr/local /dev/sdz9 $M/usr/local") ))'
espera "no monta noauto, otro disco, sin dir, vfat" '! grep -q -E "$M/(home|data|opt|boot)" "$T/log"'
espera "montaje fallido: aviso y sigue; 4 anotados" 'grep -q "No se pudo montar el subvolumen /@/fail" "$T/out" && hay "N=4"'
espera "cleanup: /usr/local antes de /usr" '(( $(pos "UMOUNT $M/usr/local") > 0 && $(pos "UMOUNT $M/usr/local") < $(pos "UMOUNT $M/usr") ))'
espera "cleanup: subvolúmenes antes de \$MNT" '(( $(pos "UMOUNT $M/var") > 0 && $(pos "UMOUNT $M/var") < $(pos "UMOUNT $M") ))'
espera "cleanup no desmonta el fallido" '! hay "UMOUNT $M/fail"'
espera "rc=0, sin DIE" '[[ $(cat "$T/rc") == 0 ]] && ! grep -q "^DIE" "$T/log"'
corre "$T/b-idr.sh" ext4 U1 "$M" cleanup
espera "idr ext4: ningún subvolumen, cleanup desmonta \$MNT" '! grep -q "^MOUNT" "$T/log" && hay "UMOUNT $M" && hay "N=0"'

echo "── Sintaxis"
espera "bash -n instalar-en-disco" 'bash -n "$IED"'
espera "bash -n instalar-dracut" 'bash -n "$IDR"'
espera "idr: tras el mount, umount solo en cleanup o en el bloque" '(( $(awk "/^cleanup\\(\\) \\{/{p=1} p&&/^\\}/{p=0} /^# >>> \\(4\\.17\\.3\\)/{q=1} /^# <<< \\(4\\.17\\.3\\)/{q=0} /^mount \"\\\$DEV\" \"\\\$MNT\" \\|\\| die/{d=1; next} d&&!p&&!q&&/umount/{n++} END{print n+0}" "$IDR") == 0 ))'
echo ""
echo "raíz en subvolumen y subvolúmenes en instalar-dracut: $P passed, $F failed"
(( F == 0 ))
