#!/bin/bash
# Pruebas de la rama btrfs/xfs de guardian-early con dobles de las herramientas
EARLY=${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/guardian-early}
PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
W=$(mktemp -d); T=$W/tools; ST=$W/st; mkdir -p "$T" "$ST" "$W/bk"
PASS=0; FAIL=0
check() { if eval "$1"; then echo "  ✔ $2"; PASS=$((PASS+1)); else echo "  ✖ $2"; FAIL=$((FAIL+1)); fi; }
# Entorno mínimo (como el initramfs klibc): solo estos comandos reales
for c in cat sleep sync mkdir rmdir readlink e2fsck; do ln -s "$(command -v $c)" "$T/$c"; done
ln -s "$(command -v dash)" "$T/sh"; ln -s "$(command -v df)" "$T/guardian-df"
mk() { printf '#!/bin/sh\n%s\n' "$2" > "$T/$1"; chmod +x "$T/$1"; }
mk blkid 'cat '"$ST"'/fstype'
mk mount 'echo "mount $*" >>'"$ST"'/calls
if [ -e '"$ST"'/fixed ] || [ ! -e '"$ST"'/broken ]; then exit 0; fi
echo "mount: wrong fs type, bad option, bad superblock" >&2; exit 32'
mk umount 'echo "umount $*" >>'"$ST"'/calls; exit 0'
mk xfs_repair 'echo "xfs_repair $*" >>'"$ST"'/calls
for a in "$@"; do [ "$a" = -L ] && L=1; done
if [ "$L" = 1 ]; then [ -e '"$ST"'/L_fixes ] && : >'"$ST"'/fixed; else [ -e '"$ST"'/plain_fixes ] && : >'"$ST"'/fixed; fi
echo "Phase 1 - find and verify superblock..."; exit 0'
mk xfs_db 'echo "xfs_db $*" >>'"$ST"'/calls
[ -e '"$ST"'/meta_fail ] && { echo "xfs_db: cannot init perag data (117)" >&2; exit 1; }
for a in "$@"; do case "$a" in metadump\ *) f=${a#metadump }; echo METADATA >"$f" ;; esac; done; exit 0'
mk btrfs-image 'echo "btrfs-image $*" >>'"$ST"'/calls
[ -e '"$ST"'/meta_fail ] && exit 1
echo META >"$2"; exit 0'
mk btrfs 'echo "btrfs $*" >>'"$ST"'/calls
case "$1 $2" in
 "inspect-internal dump-super") printf "superblock: bytenr=65536, device=x\nnum_devices\t%s\n" "$(cat '"$ST"'/nd 2>/dev/null || echo 1)" ;;
 "rescue super-recover") [ -e '"$ST"'/sr_fixes ] && : >'"$ST"'/fixed ;;
 "rescue zero-log") [ -e '"$ST"'/zl_fixes ] && : >'"$ST"'/fixed ;;
esac; exit 0'
echo dummy >"$W/root.dev"
scen() { rm -rf "$ST"/* "$W/bk" "$W/run"; echo "$1" >"$ST/fstype"; shift; for k in "$@"; do : >"$ST/$k"; done; }
run() { # POLICY [sin_respaldo] [META_MIN]
  printf 'ON_FAIL=%s\nBACKUP_MIN_MB=1\nMETA_MIN_MB=%s\n' "$1" "${3:-1}" >"$W/early.conf"; rm -rf "$W/run"
  if [ "${2:-}" = nobk ]; then unset GUARDIAN_BACKUP_DIR; else export GUARDIAN_BACKUP_DIR="$W/bk"; fi
  ROOT="$W/root.dev" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/early.conf" GUARDIAN_PATH="$T" "$T/sh" "$EARLY" >/dev/null 2>&1
  echo $? >"$W/exit"; cat "$W/run/early_status" 2>/dev/null
}
calls() { cat "$ST/calls" 2>/dev/null; }
echo "=== Tests rama btrfs/xfs (dobles, entorno mínimo) ==="
for fs in xfs btrfs; do
  scen $fs
  check "[[ \$(run respaldo_y_forzar) == ok ]]" "$fs sano: montaje de prueba OK → ok"
  check "! calls | grep -qE 'repair|zero-log|rescue'" "$fs sano: no se invoca ninguna reparación"
  check "calls | grep -q 'umount'" "$fs sano: el montaje de prueba se desmonta"
  check "[[ \$(cat $W/exit) == 0 ]]" "$fs: sale con 0"
done
scen xfs broken plain_fixes
check "[[ \$(run respaldo_y_forzar) == forced ]]" "xfs roto, xfs_repair arregla → forced"
check "calls | grep -q '^xfs_repair /' && ! calls | grep -q -- '-L'" "xfs: usó xfs_repair SIN -L"
check "ls $W/bk/guardian-backups/root-meta-*.xfs >/dev/null 2>&1 && grep -q '^META_FILE=guardian-backups/root-meta-' $W/run/early_backup" "xfs: guardó el respaldo de metadatos y lo anotó"
check "calls | grep -q 'xfs_db -r -p xfs_metadump -c metadump '" "xfs: respaldo con xfs_db -r -p xfs_metadump (comando validado)"
check "grep -q 'montable de nuevo (forced)' $W/run/early.log && ls $W/bk/guardian-backups/root-xfs-*.log >/dev/null 2>&1" "xfs: informe copiado junto al respaldo"
scen xfs broken L_fixes
check "[[ \$(run respaldo_y_forzar) == forced ]] && calls | grep -q -- 'xfs_repair -L'" "xfs: solo -L lo arregla; respaldo_y_forzar lo permite → forced"
scen xfs broken L_fixes
check "[[ \$(run nada) == failed ]] && ! calls | grep -qE 'xfs_repair|xfs_db'" "xfs: política nada → failed y NO toca nada"
scen xfs broken L_fixes
check "[[ \$(run solo_con_respaldo nobk) == failed ]] && ! calls | grep -q xfs_repair" "xfs: solo_con_respaldo sin espacio → failed, no repara"
scen xfs broken L_fixes
check "[[ \$(run solo_con_respaldo) == forced ]]" "xfs: solo_con_respaldo CON metadatos guardados permite -L"
scen xfs broken L_fixes meta_fail
check "[[ \$(run solo_con_respaldo) == failed ]] && ! calls | grep -q -- '-L'" "xfs: solo_con_respaldo sin metadatos (metadump falló) → NO usa -L"
scen xfs broken L_fixes meta_fail
check "[[ \$(run respaldo_y_forzar) == forced ]] && grep -q 'no se pudo guardar el respaldo de metadatos' $W/run/early.log" "xfs: metadump falla (superbloque roto) → se repara igual y lo registra"
scen xfs broken
check "[[ \$(run respaldo_y_forzar) == failed ]]" "xfs: nada lo arregla → failed (sin bloquear)"
scen xfs broken plain_fixes
check "[[ \$(run respaldo_y_forzar nobk) == forced ]] && grep -q 'SIN RESPALDO' $W/run/early.log && grep -q 'BACKUP=ninguno' $W/run/early_backup" "xfs: sin partición de respaldo + respaldo_y_forzar → repara y lo anota"
scen xfs broken plain_fixes
check "[[ \$(run respaldo_y_forzar bk 99999999) == forced ]] && ! ls $W/bk/guardian-backups/root-meta-* >/dev/null 2>&1 && ! calls | grep -q xfs_db" "xfs: sin espacio para metadatos → se omite el respaldo"

scen btrfs broken sr_fixes
check "[[ \$(run respaldo_y_forzar) == repaired ]] && ! calls | grep -q zero-log" "btrfs: super-recover arregla → repaired, sin zero-log"
scen btrfs broken zl_fixes
check "[[ \$(run respaldo_y_forzar) == forced ]] && calls | grep -q 'rescue zero-log'" "btrfs: solo zero-log lo arregla → forced"
scen btrfs broken zl_fixes
printf '2' >"$ST/nd"
check "[[ \$(run respaldo_y_forzar) == failed ]] && ! calls | grep -q zero-log && grep -q 'num_devices' $W/run/early.log" "btrfs: 2 dispositivos → NO zero-log, failed"
scen btrfs broken zl_fixes
check "[[ \$(run nada) == failed ]] && ! calls | grep -qE 'rescue|btrfs-image'" "btrfs: política nada → failed y NO toca nada"
scen btrfs broken zl_fixes
check "[[ \$(run solo_con_respaldo nobk) == failed ]] && ! calls | grep -q rescue" "btrfs: solo_con_respaldo sin espacio → failed, no repara"
scen btrfs broken zl_fixes
check "calls >/dev/null; [[ \$(run respaldo_y_forzar) == forced ]] && ls $W/bk/guardian-backups/root-meta-*.btrfs >/dev/null 2>&1" "btrfs: respaldo de metadatos con btrfs-image antes de actuar"
scen btrfs broken
check "[[ \$(run respaldo_y_forzar) == failed ]]" "btrfs: nada lo arregla → failed"
# Seguridad: nunca --repair, en ningún escenario
for sc in "btrfs broken zl_fixes" "btrfs broken" "btrfs broken sr_fixes" "xfs broken L_fixes"; do scen $sc; run forzar >/dev/null; if calls | grep -q -- '--repair\|check'; then BAD=1; fi; done
check "[[ -z \${BAD:-} ]]" "NUNCA se invoca btrfs check ni --repair"
# Herramienta ausente
scen xfs broken; mv "$T/xfs_repair" "$T/xfs_repair.off"
check "[[ \$(run forzar) == skipped ]] && grep -q 'falta xfs_repair' $W/run/early.log" "xfs: falta xfs_repair en el initramfs → skipped"
mv "$T/xfs_repair.off" "$T/xfs_repair"
scen btrfs broken; mv "$T/btrfs" "$T/btrfs.off"
check "[[ \$(run forzar) == skipped ]]" "btrfs: falta btrfs en el initramfs → skipped"
mv "$T/btrfs.off" "$T/btrfs"
# Hibernación/ya montado: no se evalúa aquí (código previo sin cambios)
# Regresión ext4 con herramientas reales
if command -v mke2fs >/dev/null && command -v blkid >/dev/null; then
  RT=$W/rt; mkdir -p $RT; for c in cat sleep sync mkdir rmdir readlink e2fsck e2image blkid mount umount; do ln -s "$(command -v $c)" "$RT/$c"; done
  ln -s "$(command -v dash)" "$RT/sh"; ln -s "$(command -v df)" "$RT/guardian-df"
  mke2fs -q -F -t ext4 "$W/d.img" 8M >/dev/null 2>&1
  printf 'ON_FAIL=nada\n' >"$W/e.conf"; rm -rf "$W/run"
  ROOT="$W/d.img" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/e.conf" GUARDIAN_PATH="$RT" "$RT/sh" "$EARLY" >/dev/null 2>&1
  check "[[ \$(cat $W/run/early_status) == ok ]]" "REGRESIÓN ext4 limpio → ok (la rama ext sigue igual)"
  debugfs -w -R "clri <2>" "$W/d.img" >/dev/null 2>&1; debugfs -w -R "ssv state 0" "$W/d.img" >/dev/null 2>&1
  rm -rf "$W/run"; ROOT="$W/d.img" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/e.conf" GUARDIAN_PATH="$RT" "$RT/sh" "$EARLY" >/dev/null 2>&1
  check "[[ \$(cat $W/run/early_status) == failed ]] && ! grep -q 'nx_\|NONEXT\|montaje de prueba' $W/run/early.log" "REGRESIÓN ext4 grave + nada → failed (sin pasar por la rama nueva)"
  printf 'ON_FAIL=respaldo_y_forzar\nBACKUP_MIN_MB=1\nMETA_MIN_MB=1\n' >"$W/e.conf"; rm -rf "$W/run" "$W/bk"
  GUARDIAN_BACKUP_DIR="$W/bk" ROOT="$W/d.img" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/e.conf" GUARDIAN_PATH="$RT" "$RT/sh" "$EARLY" >/dev/null 2>&1
  check "[[ \$(cat $W/run/early_status) == forced ]] && ls $W/bk/guardian-backups/root-undo-*.e2undo >/dev/null 2>&1" "REGRESIÓN ext4 grave + respaldo_y_forzar → forced con e2undo"
fi
# Reglas del propio proyecto sobre guardian-early
check "sh -n '$EARLY' && dash -n '$EARLY'" "sintaxis sh y dash"
check "! grep -nE '\[\[|declare -|local ' '$EARLY'" "sin bashismos"
check "! grep -nE '(^|[;&|({] *|then +|do +)(cp|grep|sed|awk|head|tail|tr|cut|wc|ls|find|touch|mv) ' '$EARLY' | grep -v '^[0-9]*: *#'" "no usa comandos que el initramfs (klibc) no trae"
echo "Resultado: $PASS pasaron, $FAIL fallaron"
rm -rf "$W"
[[ $FAIL -eq 0 ]]
