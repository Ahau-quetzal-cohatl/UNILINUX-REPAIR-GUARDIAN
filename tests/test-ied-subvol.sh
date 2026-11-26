#!/bin/bash
# Guardian 4.17.2 — instalar-en-disco monta los subvolúmenes btrfs del fstab del destino
# y cleanup los desmonta en orden inverso antes de $MNT. Sin root: se extraen el bloque
# nuevo y cleanup y se corren con dobles. Uso: bash tests/test-ied-subvol.sh [CARPETA_bin]
B="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin}"
IED="$B/instalar-en-disco"
[[ -f "$IED" ]] || { echo "✖ No encuentro $IED"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P=0; F=0
si() { echo "  ✔ $1"; P=$((P + 1)); }
no() { echo "  ✖ $1"; F=$((F + 1)); }
espera() { if eval "$2"; then si "$1"; else no "$1"; echo "      registro: $(tr '\n' '|' <"$T/log" 2>/dev/null | cut -c1-400)"; fi; }
pos() { local n; n=$(grep -n -x -F -- "$1" "$T/log" 2>/dev/null | head -n 1 | cut -d: -f1); echo "${n:-0}"; }
hay() { grep -q -x -F -- "$1" "$T/log"; }

awk '/^# >>> \(4\.17\.2\)/{p=1} p{print} /^# <<< \(4\.17\.2\)/{exit}' "$IED" >"$T/bloque.sh"
awk '/^cleanup\(\) \{/{p=1} p{print} p && /^\}/{exit}' "$IED" >"$T/cleanup.sh"
grep -q 'montar_subvols_fstab' "$T/bloque.sh" && si "bloque de subvolúmenes extraído" || no "no hay bloque de subvolúmenes"
grep -q 'SUBVOLS_MONTADOS' "$T/cleanup.sh" && si "cleanup desmonta los subvolúmenes" || no "cleanup no desmonta los subvolúmenes"
espera "SUBVOLS_MONTADOS=() antes de cleanup" '(( $(grep -n "^SUBVOLS_MONTADOS=()" "$IED" | head -n1 | cut -d: -f1) + 0 > 0 && $(grep -n "^SUBVOLS_MONTADOS=()" "$IED" | head -n1 | cut -d: -f1) < $(grep -n "^cleanup() {" "$IED" | cut -d: -f1) ))'
espera "bloque DESPUÉS del mount del disco" '(( $(grep -n "^mount \"\$DEV\" \"\$MNT\" || die" "$IED" | cut -d: -f1) + 0 > 0 && $(grep -n "^mount \"\$DEV\" \"\$MNT\" || die" "$IED" | cut -d: -f1) < $(grep -n "^# >>> (4.17.2)" "$IED" | cut -d: -f1)0 / 10 ))'
espera "bloque ANTES de la detección del sistema" '(( $(grep -n "^# <<< (4.17.2)" "$IED" | cut -d: -f1)0 / 10 > 0 && $(grep -n "^# <<< (4.17.2)" "$IED" | cut -d: -f1)0 / 10 < $(grep -n "^TIPO=\"\"" "$IED" | head -n1 | cut -d: -f1)0 / 10 ))'

cat >"$T/dobles.sh" <<'P'
blkid()      { echo "$D_UUID"; }
mount()      { echo "MOUNT $*" >>"$LOG"; [[ -n "$D_FALLA" && " $* " == *" $D_FALLA "* ]] && return 1; return 0; }
mountpoint() { [[ "$1" == -q ]] && shift; [[ " $D_MONTADOS " == *" $1 "* ]]; }
umount()     { echo "UMOUNT $*" >>"$LOG"; return 0; }
die()        { echo "DIE $*" >>"$LOG"; exit 1; }
SUBVOLS_MONTADOS=()
P
M="$T/mnt"
mkdir -p "$M/etc" "$M/var" "$M/usr/local" "$M/root" "$M/home" "$M/.snapshots" "$M/fail" "$M/tmpx" "$M/data"
mkdir -p "$T/otro"; ln -s "$T/otro" "$M/srv"
cat >"$M/etc/fstab" <<'FS'
# fstab de prueba
UUID=U1   /            btrfs  defaults                        0 0
UUID=U1   /var         btrfs  subvol=/@/var                   0 0
UUID=U1   /usr/local   btrfs  subvol=/@/usr/local             0 0
UUID=U1   /usr         btrfs  compress=zstd,subvol=@usr       0 0
UUID=U1   /root        btrfs  subvol=/@/root,compress=zstd:1  0 0
UUID=U1   /home        btrfs  subvol=/@/home,noauto           0 0
UUID=U2   /data        btrfs  subvol=@data                    0 0
UUID=U1   /opt         btrfs  subvol=/@/opt                   0 0
UUID=U1   /srv         btrfs  subvol=/@/srv                   0 0
/dev/disk/by-uuid/U1 /.snapshots btrfs subvol=/@/.snapshots   0 0
UUID=U1   /fail        btrfs  subvol=/@/fail                  0 0
/dev/sdz9 /tmpx        btrfs  subvolid=300                    0 0
UUID=E1   /boot/efi    vfat   utf8                            0 2
UUID=U1   none         swap   defaults                        0 0
FS
corre() {   # $1 FSTIPO, $2 UUID ; corre bloque y luego cleanup
    : >"$T/log"
    { cat "$T/dobles.sh" "$T/bloque.sh"
      echo 'echo "N=${#SUBVOLS_MONTADOS[@]}" >>"$LOG"'
      cat "$T/cleanup.sh"; echo cleanup; } >"$T/corre.sh"
    env -i PATH="$PATH" LOG="$T/log" MNT="$M" DEV=/dev/sdz9 FSTIPO="$1" D_UUID="$2" \
        D_FALLA="$M/fail" D_MONTADOS="$M" bash "$T/corre.sh" >"$T/out" 2>&1
    echo $? >"$T/rc"
}
echo "── btrfs con subvolúmenes en el fstab"
corre btrfs U1
espera "rc=0" '[[ $(cat "$T/rc") == 0 ]]'
espera "monta /var con subvol=/@/var" 'hay "MOUNT -o subvol=/@/var /dev/sdz9 $M/var"'
espera "monta /usr/local" 'hay "MOUNT -o subvol=/@/usr/local /dev/sdz9 $M/usr/local"'
espera "monta /root (subvol= no es la 1.ª opción)" 'hay "MOUNT -o subvol=/@/root /dev/sdz9 $M/root"'
espera "monta /usr (subvol= tras compress=)" 'hay "MOUNT -o subvol=@usr /dev/sdz9 $M/usr"'
espera "acepta /dev/disk/by-uuid/ (/.snapshots)" 'hay "MOUNT -o subvol=/@/.snapshots /dev/sdz9 $M/.snapshots"'
espera "/usr ANTES de /usr/local" '(( $(pos "MOUNT -o subvol=@usr /dev/sdz9 $M/usr") < $(pos "MOUNT -o subvol=/@/usr/local /dev/sdz9 $M/usr/local") ))'
espera "NO monta / otra vez" '! grep -q " $M/\$" "$T/log" && ! grep -q "^MOUNT.* $M\$" "$T/log"'
espera "NO monta noauto (/home)" '! grep -q "$M/home" "$T/log"'
espera "NO monta otro disco (/data)" '! grep -q "$M/data" "$T/log"'
espera "NO monta si falta el directorio (/opt)" '! grep -q "$M/opt" "$T/log" && grep -q "/opt no es un directorio" "$T/out"'
espera "NO monta sobre un enlace (/srv)" '! grep -q "$M/srv" "$T/log" && grep -q "/srv no es un directorio" "$T/out"'
espera "NO monta sin subvol= (subvolid)" '! grep -q "$M/tmpx" "$T/log"'
espera "NO toca vfat ni swap" '! grep -q "boot/efi" "$T/log" && ! grep -q "MOUNT.*none" "$T/log"'
espera "montaje fallido: aviso y sigue" 'grep -q "No se pudo montar el subvolumen /@/fail" "$T/out" && (( $(pos "MOUNT -o subvol=/@/fail /dev/sdz9 $M/fail") > 0 ))'
espera "5 subvolúmenes anotados (el fallido no)" 'hay "N=5"'
espera "cleanup: /usr/local ANTES de /usr" '(( $(pos "UMOUNT $M/usr/local") > 0 && $(pos "UMOUNT $M/usr/local") < $(pos "UMOUNT $M/usr") ))'
espera "cleanup: subvolúmenes ANTES de \$MNT" '(( $(pos "UMOUNT $M/var") > 0 && $(pos "UMOUNT $M/var") < $(grep -n "^UMOUNT.*$M\$" "$T/log" | tail -n1 | cut -d: -f1)0 / 10 ))'
espera "cleanup no desmonta el fallido" '! hay "UMOUNT $M/fail"'
espera "sin DIE" '! grep -q "^DIE" "$T/log"'
echo "── casos sin subvolúmenes"
corre ext4 U1
espera "ext4: ningún montaje" '! grep -q "^MOUNT" "$T/log" && hay "N=0"'
espera "ext4: cleanup sigue desmontando \$MNT" 'grep -q "^UMOUNT.*$M\$" "$T/log" && [[ $(cat "$T/rc") == 0 ]]'
corre btrfs ""
espera "btrfs sin UUID: aviso, ningún montaje" '! grep -q "^MOUNT" "$T/log" && grep -q "sin UUID" "$T/out"'
mv "$M/etc/fstab" "$M/etc/fstab.aparte"
corre btrfs U1
espera "btrfs sin fstab: ningún montaje, rc=0" '! grep -q "^MOUNT" "$T/log" && [[ $(cat "$T/rc") == 0 ]]'
mv "$M/etc/fstab.aparte" "$M/etc/fstab"
echo "── Sintaxis"
espera "bash -n instalar-en-disco" 'bash -n "$IED"'
cat >"$T/umount.awk" <<'AWK'
/^cleanup\(\) \{/{p=1} p&&/^\}/{p=0}
/^# >>> \(4\.17\.3\)/{q=1} /^# <<< \(4\.17\.3\)/{q=0}
/^mount "\$DEV" "\$MNT" \|\| die/{d=1; next}
d&&!p&&!q&&/umount/{n++}
END{print n+0}
AWK
espera "tras montar el disco, umount solo en cleanup (o en el bloque 4.17.3)" '(( $(awk -f "$T/umount.awk" "$IED") == 0 ))'
echo ""
echo "subvolúmenes en instalar-en-disco: $P passed, $F failed"
(( F == 0 ))
