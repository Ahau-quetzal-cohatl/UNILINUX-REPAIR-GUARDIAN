#!/bin/bash
# Guardian 4.17.5 — guardian-early: (5) meta_cabe y (7) hibernación con resume= de la línea
# del kernel y resume_offset (swapfile). Se extraen los trozos y se corren con dobles en cada
# shell disponible (klibc, dash, bash, busybox). Uso: bash tests/test-early-4175.sh [bin]
B="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin}"
GE="$B/guardian-early"
[[ -f "$GE" ]] || { echo "✖ No encuentro $GE"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P=0; F=0
si() { echo "  ✔ $1"; P=$((P + 1)); }
no() { echo "  ✖ $1"; F=$((F + 1)); }
espera() { if eval "$2"; then si "$1"; else no "$1"; echo "      salida: $(tr '\n' '|' <"$T/out" 2>/dev/null | cut -c1-300)"; fi; }
# trozos
awk '{s=$0; sub(/^[ \t]+/,"",s)}
  !p && s=="RESUME=\"\"" {p=1; ind=$0; sub(/[^ \t].*$/,"",ind)}
  p {print}
  p && s ~ /^if \[ -n "\$RESUME" \]/ {seen=1}
  p && seen && $0==ind "fi" {exit}' "$GE" >"$T/hib.sh"
awk '/^[ \t]*meta_cabe\(\) \{/{p=1} p{print} p && /^[ \t]*\}[ \t]*$/{exit}' "$GE" >"$T/meta.sh"
echo "── Estructura"
espera "trozo de hibernación extraído (con resume_offset)" 'grep -q "resume_offset=" "$T/hib.sh" && grep -q "set_status skipped" "$T/hib.sh" && [[ "$(tail -n 1 "$T/hib.sh" | tr -d " \t")" == fi ]]'
espera "meta_cabe extraída" 'grep -q "^[[:space:]]*meta_cabe() {" "$T/meta.sh" && grep -q "META_PCT" "$T/meta.sh"'
espera "las 2 imágenes de metadatos pasan por meta_cabe" '(( $(grep -c "META_MIN_MB:-2048}\" \] && meta_cabe \"\$dev\" \"\$_f\"; then" "$GE") == 2 ))'
espera "meta_cabe definida antes de usarse" '(( $(grep -n "^[[:space:]]*meta_cabe() {" "$GE" | cut -d: -f1) < $(grep -n "&& meta_cabe" "$GE" | head -n1 | cut -d: -f1) ))'
espera "sin órdenes prohibidas en el initramfs (grep sed awk head cut tr wc)" '! grep -E "(^|[;|&(\` ])(grep|sed|awk|head|cut|tr|wc)( |$)" "$T/hib.sh" "$T/meta.sh"'
SHS=""
for s in /usr/lib/klibc/bin/sh /usr/lib/klibc/bin/sh.shared dash bash busybox; do
  if [[ "$s" == busybox ]]; then command -v busybox >/dev/null && SHS="$SHS busybox"
  elif [[ "$s" == /* ]]; then [[ -x "$s" ]] && [[ "$SHS" != *klibc* ]] && SHS="$SHS $s"
  else command -v "$s" >/dev/null && SHS="$SHS $s"; fi
done
echo "Shells:$(echo "$SHS" | sed 's#/usr/lib/klibc/bin/sh[a-z.]*#klibc#')"
cat >"$T/dobles.sh" <<'D'
log() { echo "LOG $*"; }
set_status() { echo "STATUS $1"; }
resolve_spec() { echo "$1"; }
blkid() { echo "$D_TYPE"; }
D
# swapfile de prueba: 8 páginas; firma en la página 3 (resume_offset=3)
mkswapf() { dd if=/dev/zero of="$T/swapf" bs=4096 count=8 2>/dev/null; printf '%s' "$1" | dd of="$T/swapf" bs=1 seek=$((3 * 4096 + 4086)) conv=notrunc 2>/dev/null; }
corre() {   # $1 shell, $2 cmdline, $3 TYPE de blkid
  printf '%s\n' "$2" >"$T/cmdline"
  { echo 'RUN="$TRUN"'; cat "$T/dobles.sh" "$T/hib.sh"; echo 'echo CONTINUA'; } >"$T/c.sh"
  mkdir -p "$T/run"
  if [[ "$1" == busybox ]]; then set -- busybox\ sh "$2" "$3"; fi
  env -i PATH="$PATH" TRUN="$T/run" GUARDIAN_CMDLINE="$T/cmdline" D_TYPE="$3" $1 "$T/c.sh" >"$T/out" 2>&1
}
for S in $SHS; do
  n=$(echo "$S" | sed 's#.*/##; s#sh.shared#klibc#; s#^sh$#klibc#')
  echo "── hibernación ($n)"
  mkswapf SWAPSPACE2
  corre "$S" "BOOT_IMAGE=/vmlinuz root=UUID=R1 ro quiet" swap
  espera "$n sin resume=: sigue" 'grep -qx CONTINUA "$T/out" && ! grep -q STATUS "$T/out"'
  corre "$S" "ro resume=$T/swapf quiet" swsuspend
  espera "$n resume= de la línea del kernel + swsuspend: skipped" 'grep -qx "STATUS skipped" "$T/out" && ! grep -q CONTINUA "$T/out"'
  corre "$S" "ro resume=$T/swapf" swap
  espera "$n resume= y swap normal: sigue" 'grep -qx CONTINUA "$T/out"'
  corre "$S" "ro resume=none" swsuspend
  espera "$n resume=none: sigue" 'grep -qx CONTINUA "$T/out"'
  mkswapf S1SUSPEND
  corre "$S" "ro resume=$T/swapf resume_offset=3" ext4
  espera "$n swapfile con S1SUSPEND en resume_offset: skipped" 'grep -qx "STATUS skipped" "$T/out"'
  mkswapf SWAPSPACE2
  corre "$S" "ro resume=$T/swapf resume_offset=3" ext4
  espera "$n swapfile con SWAPSPACE2: sigue" 'grep -qx CONTINUA "$T/out"'
  mkswapf LINHIB0001
  corre "$S" "ro resume=$T/swapf resume_offset=3" ext4
  espera "$n swapfile con LINHIB0001: skipped" 'grep -qx "STATUS skipped" "$T/out"'
  mkswapf S1SUSPEND
  corre "$S" "ro resume=$T/swapf resume_offset=3x" ext4
  espera "$n resume_offset no numérico: no mira, sigue" 'grep -qx CONTINUA "$T/out"'
  corre "$S" "ro resume=$T/no-existe resume_offset=3" ext4
  espera "$n resume= a algo que no existe: sigue" 'grep -qx CONTINUA "$T/out"'
  espera "$n no deja la página copiada en run" '[[ ! -e "$T/run/resume-pagina" ]]'
  echo "── meta_cabe ($n)"
  mkdir -p "$T/sys/sdz2" "$T/sys/sdz3"
  echo 209715200 >"$T/sys/sdz2/size"     # 100 GiB = 102400 MB
  echo abc >"$T/sys/sdz3/size"
  mc() {   # $1 dev $2 libres  [META_PCT]
    { cat "$T/dobles.sh" "$T/meta.sh"; echo 'meta_cabe "$1" "$2"; echo "RC=$?"'; } >"$T/m.sh"
    local sh="$S"; [[ "$S" == busybox ]] && sh="busybox sh"
    env -i PATH="$PATH" GUARDIAN_SYSBLK="$T/sys" BACKUP_MIN_MB=512 ${3:+META_PCT=$3} $sh "$T/m.sh" "$1" "$2" >"$T/out" 2>&1
  }
  mc /dev/sdz2 6000
  espera "$n raíz 100 GiB, 6000 MB libres (5 % + 512 = 5632): cabe" 'grep -qx "RC=0" "$T/out"'
  mc /dev/sdz2 5000
  espera "$n raíz 100 GiB, 5000 MB libres: no cabe y lo dice" 'grep -qx "RC=1" "$T/out" && grep -q "harían falta 5632 MB y hay 5000" "$T/out"'
  mc /dev/sdz2 3000 2
  espera "$n META_PCT=2: 2560 MB bastan" 'grep -qx "RC=0" "$T/out"'
  mc /dev/sdz2 5000 xx
  espera "$n META_PCT no numérico → 5" 'grep -qx "RC=1" "$T/out"'
  mc /dev/mapper/raiz 100
  espera "$n tamaño desconocido: como antes (RC=0) y lo dice" 'grep -qx "RC=0" "$T/out" && grep -q "no sé el tamaño" "$T/out"'
  mc /dev/sdz3 100
  espera "$n tamaño no numérico: como antes" 'grep -qx "RC=0" "$T/out"'
done
echo "── Sintaxis"
for S in $SHS; do
  sh="$S"; [[ "$S" == busybox ]] && sh="busybox sh"
  espera "$(echo "$S" | sed 's#.*/##') -n guardian-early" '$sh -n "$GE"'
done
espera "instalar-dracut mete dd" 'grep -q "inst_multiple -o cat mkdir rmdir readlink mount umount sleep sync date dd" "$B/instalar-dracut"'
echo ""
echo "guardian-early 4.17.5: $P passed, $F failed"
(( F == 0 ))
