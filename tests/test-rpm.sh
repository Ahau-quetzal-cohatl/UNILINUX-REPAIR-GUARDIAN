#!/bin/bash
# Guardian 4.17.0 — pruebas de la fase tardía con rpm, snapper y GRUB en /boot/grub2,
# y del texto del respaldo tras "forced" en btrfs/xfs. Sin root. Con dobles: no lee
# rutas del anfitrión (dpkg/pacman/rpm del equipo no cuentan: PATH mínimo).
# Uso: bash tests/test-rpm.sh [RUTA/guardian]
G="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/guardian}"
[[ -f "$G" ]] || { echo "✖ No encuentro $G"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P=0; F=0
si() { echo "  ✔ $1"; P=$((P + 1)); }
no() { echo "  ✖ $1"; F=$((F + 1)); }
espera() { if eval "$2"; then si "$1"; else no "$1"; echo "      salida: $(tr '\n' '|' <"$T/out" | cut -c1-300)"; fi; }

# ── Funciones de guardian (desde la línea "nombre() {" hasta la primera "}" en columna 0)
ext() { awk -v n="$1" 'index($0, n"() {")==1 {p=1} p {print} p && /^}[[:space:]]*$/ {exit}' "$G"; }
for f in rpm_db_presente diagnosticar_rpm diagnosticar_snapper gestor_paquetes \
         diagnosticar_paquetes grub_dir_detectar grub_regen diagnosticar_early; do
    ext "$f" >"$T/$f.fn"
    if [[ -s "$T/$f.fn" ]] && bash -n "$T/$f.fn" 2>/dev/null; then :; else no "no pude extraer $f"; fi
done

# ── PATH mínimo: dobles + herramientas reales imprescindibles
mkdir -p "$T/bin" "$T/sys" "$T/rpmdb" "$T/run"
for t in grep sed head cat tr wc cut timeout sort; do
    r=$(command -v "$t") && ln -s "$r" "$T/sys/$t"
done
cat >"$T/bin/rpm" <<'D'
#!/bin/sh
echo "rpm $*" >>"$DT/llamadas"
case "$1" in
  -q) if [ "${D_RPMQ:-0}" = 0 ]; then echo rpm-4.20.1-1.1.x86_64; exit 0; fi
      echo "error: cannot open Packages database in /usr/lib/sysimage/rpm"; exit 1 ;;
  --verifydb) exit "${D_VDB:-0}" ;;
  -Va) [ "${D_VA:-0}" = 0 ] && exit 0
       echo "Unsatisfied dependencies for foo-1-1.x86_64:"
       echo "	libbar.so.1()(64bit) is needed by foo-1-1.x86_64"; exit 1 ;;
esac
exit 0
D
cat >"$T/bin/rpmdb" <<'D'
#!/bin/sh
echo "rpmdb $*" >>"$DT/llamadas"
[ "$1" = --verifydb ] && exit "${D_VDB:-0}"
exit 0
D
cat >"$T/bin/pgrep" <<'D'
#!/bin/sh
exit "${D_PGREP:-1}"
D
cat >"$T/bin/findmnt" <<'D'
#!/bin/sh
case "$*" in
  *FSTYPE*) echo "${D_FS:-btrfs}" ;;
  *OPTIONS*) echo "${D_OPTS:-rw,relatime,ssd,space_cache=v2,subvol=/@/.snapshots/1/snapshot}" ;;
esac
D
cat >"$T/bin/snapper" <<'D'
#!/bin/sh
echo "snapper $*" >>"$DT/llamadas"
[ "${D_SNAPRC:-0}" = 0 ] || exit 1
echo number; echo 0
i=1; while [ "$i" -le "${D_SNAPN:-2}" ]; do echo "$i"; i=$((i + 1)); done
D
cat >"$T/bin/grub2-mkconfig" <<'D'
#!/bin/sh
exit 0
D
chmod 755 "$T"/bin/*
mkdir -p "$T/alt"   # dobles que solo se ponen en algunas pruebas
printf '#!/bin/sh\nexit 0\n' >"$T/alt/transactional-update"
printf '#!/bin/sh\nexit 0\n' >"$T/alt/grub-mkconfig"
chmod 755 "$T"/alt/*

cat >"$T/base.sh" <<'B'
log()  { echo "LOG $*"; }
ok()   { echo "OK $*"; }
warn() { echo "WARN $*"; }
err()  { echo "ERR $*"; }
info() { echo "INFO $*"; }
hdr()  { echo "HDR $*"; }
guardar_informe_early() { :; }
declare -A PEND=()
LISTA_AVISOS=(); LISTA_REPARADOS=()
NO_PACKAGES=${NO_PACKAGES:-false}
GRUB_DIR=${GRUB_DIR:-/boot/grub}
for f in "$DT"/*.fn; do . "$f"; done
avisos() { local a; for a in "${LISTA_AVISOS[@]}"; do echo "AVISO $a"; done; }
B
BASH_REAL=$(command -v bash)
# corre "variables" "orden"   → salida en $T/out
corre() {
    rm -f "$T/llamadas"; : >"$T/llamadas"
    env -i DT="$T" HOME="$T" PATH="${XPATH:-$T/bin:$T/sys}" RUN_DIR="$T/run" $1 \
        "$BASH_REAL" -c ". \"\$DT/base.sh\"; $2; avisos" >"$T/out" 2>&1
}
hay()   { grep -q -- "$1" "$T/out"; }
nohay() { ! grep -q -- "$1" "$T/out"; }
llamo() { grep -q -- "$1" "$T/llamadas"; }

echo "── rpm: detección del gestor"
corre "GUARDIAN_RPMDB_DIRS=$T/rpmdb" 'echo "PKG=$(gestor_paquetes)"'
espera "rpm + base de datos → gestor rpm" 'hay "PKG=rpm"'
corre "GUARDIAN_RPMDB_DIRS=$T/no-existe" 'echo "PKG=$(gestor_paquetes)"'
espera "rpm sin base de datos → no es rpm" 'hay "PKG=$"'
corre "" "GUARDIAN_RPMDB_DIRS='$T/no-existe $T/rpmdb'; rpm_db_presente && echo SI"
espera "rpm_db_presente mira todas las rutas" 'hay "^SI$"'

echo "── rpm: diagnóstico (solo lectura)"
corre "" 'diagnosticar_rpm'
espera "sano → OK íntegra, sin avisos" 'hay "OK Base de datos de rpm íntegra" && nohay "^AVISO" && nohay "^WARN"'
espera "sano → usa rpmdb --verifydb si existe" 'llamo "rpmdb --verifydb"'
espera "sano → comprueba dependencias (rpm -Va --nofiles)" 'llamo "rpm -Va --nofiles"'
espera "nunca reconstruye la base (sin --rebuilddb)" '! llamo "rebuilddb"'
corre "D_RPMQ=1" 'diagnosticar_rpm'
espera "base ilegible → WARN + 1 aviso" 'hay "WARN No se puede leer la base de datos de rpm" && [[ $(grep -c "^AVISO" "$T/out") == 1 ]]'
espera "base ilegible → no sigue con verifydb" '! llamo "verifydb"'
corre "D_VDB=1" 'diagnosticar_rpm'
espera "verifydb falla → WARN + aviso con la orden" 'hay "^WARN rpmdb --verifydb encontró" && hay "^AVISO.*rpmdb --verifydb"'
corre "D_VA=1" 'diagnosticar_rpm'
espera "dependencias rotas → WARN con número" 'hay "^WARN rpm -Va --nofiles encontró 1 " && hay "^AVISO.*dependencias"'
corre "D_PGREP=0" 'diagnosticar_rpm'
espera "zypper/dnf trabajando → no se toca nada" 'hay "^INFO .*trabajando" && [[ ! -s "$T/llamadas" ]]'
mv "$T/bin/rpmdb" "$T/rpmdb.aparte"
corre "" 'diagnosticar_rpm'
espera "sin rpmdb → usa rpm --verifydb" 'llamo "rpm --verifydb" && hay "íntegra (rpm --verifydb)"'
mv "$T/rpmdb.aparte" "$T/bin/rpmdb"

echo "── rpm: dentro de diagnosticar_paquetes"
corre "GUARDIAN_PKG=rpm" 'diagnosticar_paquetes'
espera "GUARDIAN_PKG=rpm → diagnóstico rpm" 'hay "OK Base de datos de rpm íntegra"'
corre "GUARDIAN_PKG=rpm NO_PACKAGES=true" 'diagnosticar_paquetes'
espera "--no-packages → rpm omitido" 'hay "omitidos" && [[ ! -s "$T/llamadas" ]]'
corre "GUARDIAN_PKG=otro" 'diagnosticar_paquetes'
espera "gestor desconocido → menciona rpm en el texto" 'hay "dpkg, pacman o rpm"'

echo "── snapper"
corre "" 'diagnosticar_snapper'
espera "btrfs rw con 2 snapshots → OK" 'hay "^OK snapper: 2 snapshot" && nohay "^WARN"'
corre "D_OPTS=ro,relatime,subvol=/@/.snapshots/5/snapshot" 'diagnosticar_snapper'
espera "arranque desde snapshot ro → WARN + aviso rollback" 'hay "^WARN .*solo lectura" && hay "^AVISO.*snapper rollback"'
XPATH="$T/bin:$T/alt:$T/sys" corre "D_OPTS=ro,relatime" 'diagnosticar_snapper'
espera "raíz ro de sistema transaccional → sin aviso" 'nohay "solo lectura"'
corre "D_SNAPN=0" 'diagnosticar_snapper'
espera "sin snapshots → WARN + aviso" 'hay "^WARN snapper no tiene snapshots" && hay "^AVISO.*snapper create"'
corre "D_SNAPRC=1" 'diagnosticar_snapper'
espera "snapper falla → solo INFO" 'hay "^INFO No se pudo leer" && nohay "^WARN"'
corre "D_FS=ext4" 'diagnosticar_snapper'
espera "raíz ext4 → no dice nada" '[[ ! -s "$T/out" ]]'
mv "$T/bin/snapper" "$T/snapper.aparte"
corre "" 'diagnosticar_snapper'
espera "sin snapper → no dice nada" '[[ ! -s "$T/out" ]]'
mv "$T/snapper.aparte" "$T/bin/snapper"

echo "── GRUB en /boot/grub o /boot/grub2"
mkdir -p "$T/b1/grub2" "$T/b2/grub" "$T/b3/grub" "$T/b3/grub2" "$T/b4"
corre "" "echo D1=\$(grub_dir_detectar $T/b1); echo D2=\$(grub_dir_detectar $T/b2); echo D3=\$(grub_dir_detectar $T/b3); echo D4=\$(grub_dir_detectar $T/b4)"
espera "solo grub2 → /boot/grub2" "hay \"D1=$T/b1/grub2\""
espera "solo grub → /boot/grub" "hay \"D2=$T/b2/grub\""
espera "los dos → /boot/grub (como hasta ahora)" "hay \"D3=$T/b3/grub\""
espera "ninguno → /boot/grub (como hasta ahora)" "hay \"D4=$T/b4/grub\""
corre "GRUB_DIR=/boot/grub2" 'grub_regen'
espera "openSUSE/Fedora → grub2-mkconfig -o /boot/grub2/grub.cfg" 'hay "^grub2-mkconfig -o /boot/grub2/grub.cfg$"'
XPATH="$T/bin:$T/alt:$T/sys" corre "GRUB_DIR=/boot/grub" 'grub_regen'
espera "Arch (grub-mkconfig) sigue igual" 'hay "^grub-mkconfig -o /boot/grub/grub.cfg$"'
n=$(grep -v '^[[:space:]]*#' "$G" | grep -c '/boot/grub[^2]')
espera "ninguna ruta /boot/grub fija fuera de comentarios" '[[ "$n" == 0 ]]'

echo "── Texto del respaldo tras forced"
printf 'BACKUP_DEV=15fce3a4\nMETA_FILE=/guardian-backups/root-meta-1.btrfs\nFSCK_LOG=/guardian-backups/root-btrfs-1.log\n' >"$T/run/early_backup"
corre "EARLY_STATUS=forced" 'diagnosticar_early'
espera "btrfs/xfs (solo metadatos) → NO dice SIN respaldo" 'nohay "SIN respaldo" && hay "^AVISO.*metadatos=/guardian-backups/root-meta-1.btrfs" && nohay "deshacer="'
printf 'BACKUP_DEV=15fce3a4\nBACKUP_FILE=/g/root.e2undo\nMETA_FILE=/g/root.e2i\nFSCK_LOG=/g/fsck.log\n' >"$T/run/early_backup"
corre "EARLY_STATUS=forced" 'diagnosticar_early'
espera "ext4 → deshacer + metadatos como antes" 'hay "^AVISO.*deshacer=/g/root.e2undo, metadatos=/g/root.e2i, informe=/g/fsck.log"'
rm -f "$T/run/early_backup"
corre "EARLY_STATUS=forced" 'diagnosticar_early'
espera "sin respaldo de verdad → SIN respaldo" 'hay "^AVISO.*SIN respaldo"'

echo "── Sintaxis"
espera "bash -n guardian" 'bash -n "$G"'

echo ""
echo "rpm/snapper/grub2: $P passed, $F failed"
(( F == 0 ))
