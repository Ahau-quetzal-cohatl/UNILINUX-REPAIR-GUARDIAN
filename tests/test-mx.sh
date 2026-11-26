#!/bin/bash
# test-mx.sh (4.18.5): fase tardía con sysvinit (MX Linux 25 init-diversity, Devuan, antiX) e
# install-guardian en un sistema arrancado SIN systemd. Formas medidas en mx-lab1 (25 nov 2026).
# Sin root. Uso: bash tests/test-mx.sh [directorio bin]   (contra 4.18.4 FALLA)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
IG=$B/install-guardian
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
sed -n '/^# >>> sysvinit (4\.18\.5)/,/^# <<< sysvinit$/p' "$IG" >"$T/bloque.sh"
espera "bloque sysvinit en install-guardian" 'grep -q "^sysv_tardia() {" "$T/bloque.sh" && bash -n "$T/bloque.sh"'
espera "install-guardian llama a sysv_tardia \"\"" 'grep -q "^sysv_tardia \"\" ||" "$IG"'
# raíz con la forma de MX 25 (init-diversity): /usr/lib/sysvinit/init, /etc/init.d, rc2-5.d
mx() { rm -rf "$T/r"; mkdir -p "$T/r/etc/init.d" "$T/r/usr/lib/sysvinit" "$T/r/etc/rcS.d"
       for n in 0 1 2 3 4 5 6; do mkdir -p "$T/r/etc/rc$n.d"; done
       printf '#!/bin/sh\n' >"$T/r/usr/lib/sysvinit/init"; chmod 755 "$T/r/usr/lib/sysvinit/init"; }
mx
o=$(bash -c 'set -euo pipefail; . "$1"; sysv_tardia "$2"' _ "$T/bloque.sh" "$T/r" 2>&1); rc=$?
S=$T/r/etc/init.d/guardian-late
espera "MX: sysv_tardia rc=0 ($rc)" '(( rc == 0 ))'
espera "MX: /etc/init.d/guardian-late ejecutable y sh -n" '[[ -x "$S" ]] && sh -n "$S"'
espera "MX: cabecera LSB (Provides, niveles 2 3 4 5, \$local_fs)" 'grep -q "^# Provides: *guardian-late$" "$S" && grep -q "^# Default-Start: *2 3 4 5$" "$S" && grep -q "^# Required-Start:.*\$local_fs" "$S"'
espera "MX: enlaces S99 en rc2..rc5 y no en rc0/1/6" '[[ -L $T/r/etc/rc2.d/S99guardian-late && -L $T/r/etc/rc5.d/S99guardian-late && "$(readlink $T/r/etc/rc3.d/S99guardian-late)" == ../init.d/guardian-late && -z "$(find $T/r/etc/rc0.d $T/r/etc/rc1.d $T/r/etc/rc6.d -name "*guardian*")" ]]'
espera "MX: mensaje ✔ sysvinit" 'grep -q "✔ fase tardía también para sysvinit" <<<"$o"'
# sin sysvinit (Ubuntu/Pop/Zorin con systemd): no se crea nada
rm -rf "$T/s"; mkdir -p "$T/s/etc/init.d" "$T/s/etc/rc2.d"
bash -c 'set -euo pipefail; . "$1"; sysv_tardia "$2"' _ "$T/bloque.sh" "$T/s" >/dev/null 2>&1; rc=$?
espera "systemd sin sysvinit: rc=0 y sin script ni enlaces" '(( rc == 0 )) && [[ ! -e "$T/s/etc/init.d/guardian-late" && -z "$(ls "$T/s/etc/rc2.d")" ]]'
# el script, corrido como lo arranca sysvinit
cat >"$T/g" <<'G'
#!/bin/sh
echo x >>"$CUENTA"; echo "guardian falso $*"; exit 3
G
chmod 755 "$T/g"
arranca() { env -i PATH=/usr/bin:/bin GUARDIAN_BIN="$T/g" GUARDIAN_RUN="$T/run" GUARDIAN_LATE_LOG="$T/late.log" CUENTA="$T/cuenta" sh "$S" "$1"; }
espera_rc() { local i=0; while (( i < 50 )) && ! grep -q '^rc=' "$T/late.log" 2>/dev/null; do sleep 0.1; i=$((i+1)); done; }
rm -rf "$T/run" "$T/late.log" "$T/cuenta"; mkdir -p "$T/run"
t0=$(date +%s); arranca start; rc=$?; t1=$(date +%s); espera_rc
espera "start: rc=0 y vuelve enseguida (segundo plano)" '(( rc == 0 && t1 - t0 < 3 ))'
espera "start: guardian con --no-music --no-packages, «rc=3» anotado" 'grep -q "guardian falso --no-music --no-packages" "$T/late.log" && grep -qx "rc=3" "$T/late.log"'
arranca start; sleep 0.5
espera "2.º start en el mismo arranque: no repite" '[[ "$(wc -l <"$T/cuenta")" == 1 ]]'
rm -rf "$T/run" "$T/late.log" "$T/cuenta"; mkdir -p "$T/run"; : >"$T/run/guardian.skip"
arranca start; sleep 0.5
espera "guardian.skip: no corre y lo anota" '[[ ! -e "$T/cuenta" ]] && grep -q guardian.skip "$T/late.log"'
rm -rf "$T/run" "$T/late.log" "$T/cuenta"; mkdir -p "$T/run/systemd/system"
arranca start; rc=$?; sleep 0.5
espera "arrancado con systemd: no corre (manda la unidad)" '(( rc == 0 )) && [[ ! -e "$T/cuenta" ]]'
arranca stop; rc=$?
espera "stop: rc=0" '(( rc == 0 ))'
# daemon-reload: en un sistema arrancado sin systemd no debe abortar install-guardian (set -e)
mkdir -p "$T/pb"; printf '#!/bin/sh\necho "Failed to connect to system scope bus" >&2\nexit 1\n' >"$T/pb/systemctl"; chmod 755 "$T/pb/systemctl"
L=$(grep -m1 'systemctl daemon-reload' "$IG")
o=$(env -i PATH="$T/pb:/usr/bin:/bin" IN_CHROOT=0 bash -c 'set -euo pipefail; eval "$1"; echo SIGUE' _ "$L" 2>&1)
espera "daemon-reload sin systemd no aborta (set -e)" 'grep -q "^SIGUE$" <<<"$o"'
espera "daemon-reload solo si /run/systemd/system" 'grep -q "/run/systemd/system" <<<"$L"'
espera "mensaje final cita el registro de sysvinit" 'grep -q "sysvinit: cat /var/log/guardian-late.log" "$IG"'
espera "install-guardian pasa bash -n" 'bash -n "$IG"'
echo "$P passed, $F failed"
(( F == 0 ))
