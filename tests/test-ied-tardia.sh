#!/bin/bash
# Guardian 4.17.1 — la rama dracut de instalar-en-disco instala la fase tardía (chroot con
# GUARDIAN_SOLO_TARDIA=1) ANTES de instalar-dracut; install-guardian sale con 0 en ese modo.
# Sin root: se extraen los cuerpos de las ramas dracut y se corren con dobles.
# Uso: bash tests/test-ied-tardia.sh [CARPETA_bin]
B="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin}"
IED="$B/instalar-en-disco"; IG="$B/install-guardian"
[[ -f "$IED" && -f "$IG" ]] || { echo "✖ No encuentro $IED o $IG"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P=0; F=0
si() { echo "  ✔ $1"; P=$((P + 1)); }
no() { echo "  ✖ $1"; F=$((F + 1)); }
espera() { if eval "$2"; then si "$1"; else no "$1"; echo "      registro: $(tr '\n' '|' <"$T/log" 2>/dev/null | cut -c1-300)"; fi; }
# número de la primera línea del registro que contiene $1 (0 si ninguna)
pos() { local n; n=$(grep -n -F -- "$1" "$T/log" 2>/dev/null | head -n 1 | cut -d: -f1); echo "${n:-0}"; }

# ── Cuerpo de la rama dracut de instalar-en-disco (entre el elif y el "else die")
awk '/^elif \[\[ -x "\$MNT\/usr\/bin\/dracut" \]\]; then/{p=1; next} p && /^else die/{exit} p{print}' \
    "$IED" >"$T/ied-cuerpo.sh"
[[ -s "$T/ied-cuerpo.sh" ]] && si "rama dracut de instalar-en-disco extraída" || no "no pude extraer la rama dracut de instalar-en-disco"
cat >"$T/ied.sh" <<'P'
die()     { echo "DIE $*" >>"$LOG"; exit 1; }
cleanup() { echo "CLEANUP" >>"$LOG"; }
install() { echo "INSTALL $*" >>"$LOG"; }
mount()   { echo "MOUNT $*" >>"$LOG"; }
chroot()  { echo "CHROOT $*" >>"$LOG"; return "${D_CHROOT:-0}"; }
P
cat "$T/ied-cuerpo.sh" >>"$T/ied.sh"
bash -n "$T/ied.sh" 2>/dev/null && si "sintaxis de la rama dracut" || no "sintaxis de la rama dracut"

mkdir -p "$T/src" "$T/mnt/root/guardian-src"
cat >"$T/src/instalar-dracut" <<'D'
echo "DRACUT $*" >>"$LOG"
D
for f in guardian guardian-early install-guardian; do echo x >"$T/src/$f"; done

corre_ied() {
    rm -f "$T/log"; : >"$T/log"
    env -i PATH="$PATH" LOG="$T/log" MNT="$T/mnt" SRC="$T/src" DEV=/dev/sdz9 D_CHROOT="$1" \
        bash "$T/ied.sh" >"$T/out" 2>&1
    echo $? >"$T/rc"
}

echo "── instalar-en-disco, sistema con dracut, chroot bien"
corre_ied 0
espera "corre install-guardian en chroot" '(( $(pos "CHROOT") > 0 )) && grep -q "^CHROOT.*install-guardian" "$T/log"'
espera "con GUARDIAN_SOLO_TARDIA=1" 'grep -q "^CHROOT.*GUARDIAN_SOLO_TARDIA=1" "$T/log"'
espera "con GUARDIAN_CHROOT=1" 'grep -q "^CHROOT.*GUARDIAN_CHROOT=1" "$T/log"'
espera "copia los 3 programas antes del chroot" '(( $(grep -c "^INSTALL -m 0755" "$T/log") == 3 && $(pos "INSTALL -m 0755") < $(pos "CHROOT") ))'
espera "monta /dev /proc /sys antes del chroot" '(( $(pos "MOUNT -t proc") > 0 && $(pos "MOUNT -t sysfs") < $(pos "CHROOT") ))'
espera "cleanup DESPUÉS del chroot" '(( $(pos "CLEANUP") > $(pos "CHROOT") ))'
espera "instalar-dracut DESPUÉS de cleanup" '(( $(pos "DRACUT") > $(pos "CLEANUP") ))'
espera "instalar-dracut con DEV --sistema-confiable --early" 'grep -q "^DRACUT /dev/sdz9 --sistema-confiable --early $T/src/guardian-early$" "$T/log"'
espera "borra la copia de Guardian del disco" '[[ ! -e "$T/mnt/root/guardian-src" ]]'
espera "sin DIE" '! grep -q "^DIE" "$T/log"'

echo "── instalar-en-disco, la fase tardía falla"
mkdir -p "$T/mnt/root/guardian-src"
corre_ied 1
espera "se detiene (DIE) con rc≠0" 'grep -q "^DIE La fase tardía falló" "$T/log" && [[ $(cat "$T/rc") != 0 ]]'
espera "NO llama a instalar-dracut" '! grep -q "^DRACUT" "$T/log"'

# ── Cuerpo de la rama dracut de install-guardian (entre "then" de la condición y su "fi")
awk 'p==0 && /^[[:space:]]*&& command -v dracut >\/dev\/null 2>&1; then$/{p=1; next} p && /^fi$/{exit} p{print}' \
    "$IG" >"$T/ig-cuerpo.sh"
[[ -s "$T/ig-cuerpo.sh" ]] && si "rama dracut de install-guardian extraída" || no "no pude extraer la rama dracut de install-guardian"
bash -n "$T/ig-cuerpo.sh" 2>/dev/null && si "sintaxis de la rama dracut (install-guardian)" || no "sintaxis de la rama dracut (install-guardian)"

corre_ig() {   # $1 = SOLO_TARDIA, $2 = KVER
    rm -f "$T/log"; : >"$T/log"
    env -i PATH="$PATH" LOG="$T/log" SRC="$T/src" GUARDIAN_SOLO_TARDIA="$1" GUARDIAN_KVER="$2" \
        bash "$T/ig-cuerpo.sh" >"$T/out" 2>&1
    echo $? >"$T/rc"
}
echo "── install-guardian, rama dracut"
corre_ig 1 ""
espera "SOLO_TARDIA=1 → rc=0" '[[ $(cat "$T/rc") == 0 ]]'
espera "SOLO_TARDIA=1 → NO llama a instalar-dracut" '! grep -q "^DRACUT" "$T/log"'
espera "SOLO_TARDIA=1 → lo dice" 'grep -q "la fase early la pone instalar-dracut desde fuera" "$T/out"'
mv "$T/src/instalar-dracut" "$T/idr.aparte"
corre_ig 1 ""
espera "SOLO_TARDIA=1 sale antes de exigir instalar-dracut" '[[ $(cat "$T/rc") == 0 ]]'
corre_ig 0 ""
espera "sin SOLO_TARDIA y sin instalar-dracut → rc≠0" '[[ $(cat "$T/rc") != 0 ]]'
mv "$T/idr.aparte" "$T/src/instalar-dracut"
corre_ig "" ""
espera "sin SOLO_TARDIA → instalar-dracut --early (como 4.17.0)" 'grep -q "^DRACUT --early $T/src/guardian-early$" "$T/log"'
corre_ig "" 7.3.4-1-default
espera "con GUARDIAN_KVER → --kernel" 'grep -q "^DRACUT --early $T/src/guardian-early --kernel 7.3.4-1-default$" "$T/log"'

echo "── Sintaxis"
espera "bash -n instalar-en-disco" 'bash -n "$IED"'
espera "bash -n install-guardian" 'bash -n "$IG"'
espera "1 exec de instalar-dracut en instalar-en-disco" '(( $(grep -c "exec /bin/bash \"\$SRC/instalar-dracut\"" "$IED") == 1 ))'

echo ""
echo "fase tardía en dracut: $P passed, $F failed"
(( F == 0 ))
