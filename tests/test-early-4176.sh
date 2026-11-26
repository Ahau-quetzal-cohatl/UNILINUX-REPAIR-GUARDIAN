#!/bin/bash
# Guardian 4.17.6 — meta_cabe conoce el tamaño de /dev/mapper/* (enlace a dm-N o dm/name).
# Se extrae meta_cabe y se corre con dobles en cada shell disponible. Uso: bash tests/test-early-4176.sh [bin]
B="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin}"
GE="$B/guardian-early"
[[ -f "$GE" ]] || { echo "✖ No encuentro $GE"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P=0; F=0
si() { echo "  ✔ $1"; P=$((P + 1)); }
no() { echo "  ✖ $1"; F=$((F + 1)); }
espera() { if eval "$2"; then si "$1"; else no "$1"; echo "      salida: $(tr '\n' '|' <"$T/out" 2>/dev/null | cut -c1-300)"; fi; }
awk '/^[ \t]*meta_cabe\(\) \{/{p=1} p{print} p && /^[ \t]*\}[ \t]*$/{exit}' "$GE" >"$T/meta.sh"
espera "meta_cabe con el arreglo 4.17.6" 'grep -q "(4.17.6)" "$T/meta.sh" && grep -q "dm/name" "$T/meta.sh"'
espera "sin órdenes prohibidas (grep sed awk head cut tr wc ls)" '! grep -E "(^|[;|&(\` ])(grep|sed|awk|head|cut|tr|wc|ls)( |$)" "$T/meta.sh"'
SHS=""
for s in /usr/lib/klibc/bin/sh /usr/lib/klibc/bin/sh.shared dash bash busybox; do
  if [[ "$s" == busybox ]]; then command -v busybox >/dev/null && SHS="$SHS busybox"
  elif [[ "$s" == /* ]]; then [[ -x "$s" ]] && [[ "$SHS" != *klibc* ]] && SHS="$SHS $s"
  else command -v "$s" >/dev/null && SHS="$SHS $s"; fi
done
echo "Shells:$(echo "$SHS" | sed 's#/usr/lib/klibc/bin/sh[a-z.]*#klibc#')"
SB="$T/sys"; mkdir -p "$SB/sdz2" "$SB/dm-7/dm" "$SB/dm-3/dm" "$T/dev/mapper" "$T/dev/vg"
echo 209715200 >"$SB/sdz2/size"                    # 100 GiB
echo 209715200 >"$SB/dm-7/size"; echo vg-raiz >"$SB/dm-7/dm/name"
echo 41943040  >"$SB/dm-3/size"; echo luks-1234 >"$SB/dm-3/dm/name"   # 20 GiB
ln -s ../dm-7 "$T/dev/mapper/vg-raiz"; ln -s ../dm-7 "$T/dev/vg/raiz"
: >"$T/dev/mapper/luks-1234"                        # nodo sin enlace (sin udev)
for S in $SHS; do
  n=$(echo "$S" | sed 's#.*/##; s#sh.shared#klibc#; s#^sh$#klibc#'); sh="$S"; [[ "$S" == busybox ]] && sh="busybox sh"
  echo "── meta_cabe ($n)"
  mc() { { echo 'log() { echo "LOG $*"; }'; cat "$T/meta.sh"; echo 'meta_cabe "$1" "$2"; echo "RC=$?"'; } >"$T/m.sh"
         env -i PATH="$PATH" GUARDIAN_SYSBLK="$SB" BACKUP_MIN_MB=512 $sh "$T/m.sh" "$1" "$2" >"$T/out" 2>&1; }
  mc /dev/sdz2 5000
  espera "$n disco normal sigue igual (100 GiB, 5000 MB: no cabe)" 'grep -qx RC=1 "$T/out" && grep -q "mide 102400 MB" "$T/out"'
  mc "$T/dev/mapper/vg-raiz" 5000
  espera "$n /dev/mapper/vg-raiz por enlace a dm-7: mide 102400 MB" 'grep -qx RC=1 "$T/out" && grep -q "mide 102400 MB" "$T/out"'
  mc "$T/dev/vg/raiz" 6000
  espera "$n /dev/vg/raiz (enlace): cabe con 6000 MB" 'grep -qx RC=0 "$T/out" && ! grep -q "no sé" "$T/out"'
  mc "$T/dev/mapper/luks-1234" 1000
  espera "$n luks-1234 sin enlace: por dm/name, 20 GiB → 1536 MB, no cabe con 1000" 'grep -qx RC=1 "$T/out" && grep -q "mide 20480 MB" "$T/out"'
  mc "$T/dev/mapper/luks-1234" 2000
  espera "$n luks-1234 cabe con 2000 MB" 'grep -qx RC=0 "$T/out"'
  mc /dev/mapper/otro 100
  espera "$n dm desconocido: como antes (no sé, RC=0)" 'grep -qx RC=0 "$T/out" && grep -q "no sé el tamaño" "$T/out"'
done
echo ""
echo "meta_cabe 4.17.6: $P passed, $F failed"
(( F == 0 ))
