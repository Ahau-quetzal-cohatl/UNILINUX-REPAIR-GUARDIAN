#!/bin/bash
# test-alpine.sh (4.18.0): resolve_spec sin udev (guardian-early) en varios shells, y las piezas de
# instalar-mkinitfs (copia del init, mkinitfs.conf, lista del feature, desempaquetado).
# Uso: bash tests/test-alpine.sh [directorio bin]   (contra 4.17.9 debe FALLAR)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
G=$B/guardian-early
FR=$(sed -n '/^# >>> resolve_spec/,/^# <<< resolve_spec/p' "$G")
FU=$(sed -n '/^resolve_spec_udev() {/,/^}/p' "$G")
FB=$(sed -n '/^# >>> blkid/,/^# <<< blkid/p' "$G")
espera "guardian-early: bloque resolve_spec 4.18.0" '[[ -n "$FR" && -n "$FU" ]]'
espera "guardian-early: bloque blkid 4.18.0" '[[ -n "$FB" ]]'
printf '%s\n%s\n%s\n' "$FU" "$FR" "$FB" >"$T/fn.sh"
mkdir -p "$T/bin" "$T/dev"; : >"$T/dev/sdz1"; : >"$T/dev/sdz2"
for x in sed cat; do ln -sf "$(command -v $x)" "$T/bin/$x"; done
fk() { printf '#!/bin/sh\n%s\n' "$2" >"$T/bin/$1"; chmod +x "$T/bin/$1"; }
SHS=""
for s in dash bash "busybox sh" /usr/lib/klibc/bin/sh mksh; do
    set -- $s; a=$(command -v "$1" 2>/dev/null) && SHS="$SHS|$a${2:+ $2}"
done
espera "hay al menos dash o bash" '[[ "$SHS" == *dash* || "$SHS" == *bash* ]]'
echo "shells: ${SHS#|}"
rs() { env -i PATH="$T/bin" $1 -c ". $T/fn.sh; resolve_spec '$2'"; }
bk() { local s=$1; shift; env -i PATH="$T/bin" $s -c ". $T/fn.sh; blkid $*"; }
IFS='|' read -r -a LS <<<"${SHS#|}"
for s in "${LS[@]}"; do
    n=${s##*/}; n=${n// /-}
    rm -f "$T/bin/findfs" "$T/bin/blkid"
    espera "[$n] sin findfs ni blkid: ruta de siempre" '[[ "$(rs "$s" UUID=abcd)" == /dev/disk/by-uuid/abcd ]]'
    espera "[$n] ruta /dev/x tal cual" '[[ "$(rs "$s" /dev/x)" == /dev/x ]]'
    espera "[$n] spec rara: vacío" '[[ -z "$(rs "$s" raro)" ]]'
    fk findfs "[ \"\$1\" = UUID=abcd ] && echo $T/dev/sdz1; [ \"\$1\" = LABEL=raiz ] && echo $T/dev/sdz2; exit 0"
    espera "[$n] findfs UUID → dispositivo" '[[ "$(rs "$s" UUID=abcd)" == "$T/dev/sdz1" ]]'
    espera "[$n] findfs LABEL → dispositivo" '[[ "$(rs "$s" LABEL=raiz)" == "$T/dev/sdz2" ]]'
    espera "[$n] findfs sin respuesta: ruta de siempre" '[[ "$(rs "$s" UUID=otra)" == /dev/disk/by-uuid/otra ]]'
    fk findfs "echo $T/dev/no-existe"
    espera "[$n] findfs da algo inexistente: ruta de siempre" '[[ "$(rs "$s" UUID=abcd)" == /dev/disk/by-uuid/abcd ]]'
    rm -f "$T/bin/findfs"
    fk blkid "[ \"\$4\" = PARTUUID=p1 ] && { echo $T/dev/sdz2; echo $T/dev/sdz1; }; exit 0"
    espera "[$n] blkid -t PARTUUID → el primero" '[[ "$(rs "$s" PARTUUID=p1)" == "$T/dev/sdz2" ]]'
    fk blkid "echo ext4"
    espera "[$n] blkid util-linux: salida tal cual" '[[ "$(bk "$s" -o value -s TYPE /dev/x)" == ext4 ]]'
    # blkid como el busybox REAL: sin opciones; toda palabra que no empiece por «-» es un dispositivo;
    # sin ninguna, lista todos; nombre desconocido → nada. blkid es un enlace a «busybox».
    cat >"$T/bin/busybox" <<BB
#!/bin/sh
L1='$T/dev/sdz1: LABEL="GLAB" UUID="u1" TYPE="ext4"'
L2='$T/dev/sdz2: UUID="u2" TYPE="vfat" PARTUUID="p2"'
n=0; for a; do case "\$a" in -*) ;; *) n=\$((n+1)) ;; esac; done
[ \$n = 0 ] && { echo "\$L1"; echo "\$L2"; exit 0; }
for a; do case "\$a" in $T/dev/sdz1) echo "\$L1" ;; $T/dev/sdz2) echo "\$L2" ;; esac; done
exit 0
BB
    chmod +x "$T/bin/busybox"; rm -f "$T/bin/blkid"; ln -s busybox "$T/bin/blkid"; ln -sf "$(command -v readlink)" "$T/bin/readlink"
    espera "[$n] busybox: -o value -s TYPE → ext4" '[[ "$(bk "$s" -o value -s TYPE $T/dev/sdz1)" == ext4 ]]'
    espera "[$n] busybox: -o value -s UUID → u2" '[[ "$(bk "$s" -o value -s UUID $T/dev/sdz2)" == u2 ]]'
    espera "[$n] busybox: etiqueta ausente → vacío" '[[ -z "$(bk "$s" -o value -s PART_ENTRY_TYPE $T/dev/sdz1)" ]]'
    espera "[$n] busybox: -o device (sin rutas) → los dos" '[[ "$(bk "$s" -o device)" == "$T/dev/sdz1"$'"'"'\n'"'"'"$T/dev/sdz2" ]]'
    espera "[$n] busybox: -o device -t UUID=u2" '[[ "$(bk "$s" -o device -t UUID=u2)" == "$T/dev/sdz2" ]]'
    espera "[$n] busybox: -t sin coincidencia → vacío" '[[ -z "$(bk "$s" -o device -t UUID=zz)" ]]'
    espera "[$n] resolve_spec PARTUUID con blkid busybox" '[[ "$(rs "$s" PARTUUID=p2)" == "$T/dev/sdz2" ]]'
    rm -f "$T/bin/blkid" "$T/bin/busybox"
    # otro blkid (no busybox) con salida «dev: TAG=…»: se filtra igual
    cat >"$T/bin/blkid" <<BB
#!/bin/sh
echo '$T/dev/sdz1: UUID="u1" TYPE="ext4"'
BB
    chmod +x "$T/bin/blkid"
    espera "[$n] otro blkid con formato busybox: TYPE" '[[ "$(bk "$s" -o value -s TYPE $T/dev/sdz1)" == ext4 ]]'
    rm -f "$T/bin/blkid"
    espera "[$n] sin blkid: no hay función blkid" '! env -i PATH="$T/bin" $s -c ". $T/fn.sh; command -v blkid" >/dev/null 2>&1'
done
espera "guardian-early: sh -n (dash)" 'dash -n "$G" 2>/dev/null || ! command -v dash >/dev/null'
# instalar-mkinitfs
I=$B/instalar-mkinitfs
espera "instalar-mkinitfs existe y pasa bash -n" '[[ -f "$I" ]] && bash -n "$I"'
FM=$(sed -n '/^# >>> mkinitfs/,/^# <<< mkinitfs/p' "$I" 2>/dev/null)
espera "bloque mkinitfs" '[[ -n "$FM" ]]'
GE=/usr/lib/guardian/guardian-early; INITC=/etc/guardian/mkinitfs/initramfs-init; R=""
eval "$FM"
# init1 = como el real de Alpine 3.24: dos llamadas (root= y diskless), solo la de root= va seguida del overlaytmpfs
printf '#!/bin/sh\nresume_from_disk() {\n\t:\n}\nif [ -n "$KOPT_root" ]; then\n\tebegin "Mounting root"\n\tresume_from_disk\n\n\tif [ "$KOPT_overlaytmpfs" = "yes" ]; then\n\t\tmount o\n\telse\n\t\tmount x\n\tfi\nfi\n\nresume_from_disk\n\nif $do_networking; then\n\t:\nfi\n' >"$T/init1"
# init2 = dos llamadas seguidas del overlaytmpfs → ambiguo
printf '#!/bin/sh\nif [ a ]; then\n\tresume_from_disk\n\tif [ "$KOPT_overlaytmpfs" = "yes" ]; then :; fi\nfi\nif [ b ]; then\n\tresume_from_disk\n\tif [ "$KOPT_overlaytmpfs" = "yes" ]; then :; fi\nfi\n' >"$T/init2"
mkf_init_copia "$T/init1" "$T/out1" 2>"$T/err"; rc=$?
espera "init: ancla única → copia" '(( rc == 0 )) && [[ -s "$T/out1" ]]'
espera "init: Guardian justo tras el resume_from_disk de root=" '[[ "$(grep -n ">>> guardian" "$T/out1" | cut -d: -f1)" == 8 ]] && sed -n 7p "$T/out1" | grep -qx "	resume_from_disk"'
espera "init: una sola inserción (diskless sin tocar)" '[[ "$(grep -c ">>> guardian" "$T/out1")" == 1 ]] && [[ "$(grep -A1 -x "resume_from_disk" "$T/out1" | tail -n1)" == "" ]]'
espera "init: Guardian antes del montaje" '(( $(grep -n ">>> guardian" "$T/out1" | cut -d: -f1) < $(grep -n "mount o" "$T/out1" | cut -d: -f1) ))'
espera "init: llama a $GE con early.conf" 'grep -q "GUARDIAN_EARLY_CONF=/etc/guardian/early.conf $GE || :" "$T/out1"'
espera "init: monta /run como tmpfs si no lo está (antes de guardian-early)" '[[ "$(grep -n "mount -t tmpfs -o nosuid,nodev,mode=0755 run /run" "$T/out1" | cut -d: -f1)" == 10 ]] && grep -q "grep -q \" /run \" /proc/mounts" "$T/out1"'
espera "init: misma sangría (tab)" 'grep -q "^	# >>> guardian" "$T/out1"'
espera "init: copia pasa sh -n" 'sh -n "$T/out1"'
espera "init: el resto igual" '[[ "$(sed 8,14d "$T/out1")" == "$(cat "$T/init1")" ]]'
mkf_init_copia "$T/init2" "$T/out2" 2>"$T/err"; rc=$?
espera "init: dos anclas válidas → se niega" '(( rc == 1 )) && grep -q "2 llamadas" "$T/err"'
printf '#!/bin/sh\nmount x\n' >"$T/init0"; mkf_init_copia "$T/init0" "$T/out0" 2>/dev/null; rc=$?
espera "init: sin llamada → se niega" '(( rc == 1 ))'
printf '# conf\nfeatures="ata base ext4 keymap"\n#init="/usr/share/mkinitfs/initramfs-init"\n' >"$T/c1"; mkf_conf "$T/c1"
espera "conf: guardian añadido a features" 'grep -qx "features=\"ata base ext4 keymap guardian\"" "$T/c1"'
espera "conf: init= a la copia (una vez)" '[[ "$(grep -c "^init=" "$T/c1")" == 1 ]] && grep -qx "init=\"$INITC\"" "$T/c1"'
espera "conf: init comentado quitado" '! grep -q "^#init=" "$T/c1"'
mkf_conf "$T/c1"
espera "conf: idempotente" '[[ "$(grep -c guardian "$T/c1")" == 2 ]] && grep -qx "features=\"ata base ext4 keymap guardian\"" "$T/c1"'
printf 'init="/otro"\n' >"$T/c2"; mkf_conf "$T/c2"
espera "conf: sin features → base guardian; init reemplazado" 'grep -qx "features=\"base guardian\"" "$T/c2" && ! grep -q /otro "$T/c2"'
R=$T/r; mkdir -p "$R/sbin" "$R/usr/sbin"; printf '#!/bin/sh\n' >"$R/sbin/e2fsck"; chmod +x "$R/sbin/e2fsck"
L=$(mkf_lista 2>"$T/err"); rc=$?
ESP=$(printf '%s\n' "$GE" /sbin/e2fsck /etc/guardian/early.conf)
espera "lista: guardian-early, /sbin/e2fsck, early.conf" '(( rc == 0 )) && [[ "$L" == "$ESP" ]]'
espera "lista: avisa si falta e2image" 'grep -q e2image "$T/err"'
printf '#!/bin/sh\n' >"$R/usr/sbin/e2image"; chmod +x "$R/usr/sbin/e2image"
espera "lista: con e2image" 'mkf_lista 2>/dev/null | grep -qx /usr/sbin/e2image'
rm -f "$R/sbin/e2fsck"; mkf_lista >/dev/null 2>&1; rc=$?
espera "lista: sin e2fsck falla" '(( rc != 0 ))'
# gancho de apk (post-commit)
R=$T/h; mkdir -p "$R/usr/share/mkinitfs" "$R/etc/guardian/mkinitfs" "$R/usr/lib/guardian" "$R/lib/modules/6.18.1-0-lts" "$R/lib/modules/6.1.0-0-virt" "$R/boot"
echo init-v1 >"$R/usr/share/mkinitfs/initramfs-init"; echo copia >"$R/etc/guardian/mkinitfs/initramfs-init"
: >"$R/boot/initramfs-lts"; : >"$R/usr/lib/guardian/guardian-early"
printf '#!/bin/bash\necho "$*" >> %s/llamadas; exit ${FALLA:-0}\n' "$T" >"$R/usr/lib/guardian/instalar-mkinitfs"
mkf_gancho >"$T/gancho"; chmod +x "$T/gancho"
espera "gancho: pasa sh -n" 'sh -n "$T/gancho"'
gan() { rm -f "$T/llamadas"; GUARDIAN_ROOT=$R FALLA=${FALLA:-0} sh "$T/gancho" "$1" >"$T/gout" 2>&1; GRC=$?; }
sha256sum "$R/usr/share/mkinitfs/initramfs-init" | cut -d' ' -f1 >"$R/etc/guardian/mkinitfs/origen.sha256"
gan pre-commit;  espera "gancho: pre-commit no hace nada" '(( GRC == 0 )) && [[ ! -e "$T/llamadas" ]]'
gan post-commit; espera "gancho: init igual → no hace nada" '(( GRC == 0 )) && [[ ! -e "$T/llamadas" ]]'
echo init-v2 >"$R/usr/share/mkinitfs/initramfs-init"
gan post-commit; espera "gancho: init cambió → instalador para el kernel con imagen" '(( GRC == 0 )) && [[ "$(cat "$T/llamadas")" == "--kernel 6.18.1-0-lts --early $R/usr/lib/guardian/guardian-early --guardian $R/usr/lib/guardian/guardian" ]]'
espera "gancho: el kernel sin imagen (virt) no se toca" '! grep -q virt "$T/llamadas"'
FALLA=1 gan post-commit; espera "gancho: si el instalador falla, avisa y sale 0" '(( GRC == 0 )) && grep -q AVISO "$T/gout"'
rm -f "$R/etc/guardian/mkinitfs/initramfs-init"
gan post-commit; espera "gancho: sin Guardian instalado → nada" '(( GRC == 0 )) && [[ ! -e "$T/llamadas" ]]'
I2=$(sed -n '/^main() {/,/^}/p' "$I")
espera "instalador: guarda la suma del init original" 'grep -q "sha256sum \"\$ORIG\" | cut -d. . -f1 > \"\$R\$ORIGSUM\"" <<<"$I2"'
espera "instalador: deja el gancho y se copia a /usr/lib/guardian" 'grep -q "mkf_gancho > \"\$R\$HOOK\"" <<<"$I2" && grep -q "/usr/lib/guardian/instalar-mkinitfs" <<<"$I2"'
echo x >"$T/ge1"; mkf_copia_early "$T/ge1" "$T/ge1"; rc=$?
espera "copia de guardian-early: mismo archivo → no falla" '(( rc == 0 ))'
ln -sf ge1 "$T/ge2"; mkf_copia_early "$T/ge2" "$T/ge1"; rc=$?
espera "copia de guardian-early: enlace al mismo → no falla" '(( rc == 0 ))'
mkf_copia_early "$T/ge1" "$T/ge3"; rc=$?
espera "copia de guardian-early: distinto → copia" '(( rc == 0 )) && cmp -s "$T/ge1" "$T/ge3"'
espera "instalador: usa mkf_copia_early" 'grep -q "mkf_copia_early \"\$EARLY\" \"\$R\$GE\"" <<<"$I2"'
# fase tardía OpenRC
mkf_servicio >"$T/serv"
espera "servicio guardian-late: sh -n y lo esencial" 'sh -n "$T/serv" && grep -q "need localmount" "$T/serv" && grep -q "/run/guardian.skip" "$T/serv" && grep -q "timeout 300 /usr/lib/guardian/guardian --no-music --no-packages" "$T/serv" && grep -q "eend 0" "$T/serv"'
R=$T/o; mkdir -p "$R/etc/init.d" "$R/sbin"; : >"$R/sbin/openrc-run"; echo g >"$T/guard"
mkf_tardia "$T/guard" >"$T/tout"; rc=$?
espera "tardía: instala guardian, el servicio y el enlace default" '(( rc == 0 )) && cmp -s "$T/guard" "$R/usr/lib/guardian/guardian" && [[ -x "$R/etc/init.d/guardian-late" ]] && [[ "$(readlink "$R/etc/runlevels/default/guardian-late")" == /etc/init.d/guardian-late ]]'
mkf_tardia "$R/usr/lib/guardian/guardian" >/dev/null; rc=$?
espera "tardía: repetir (mismo archivo) no falla" '(( rc == 0 ))'
R=$T/sin; mkdir -p "$R/etc"; mkf_tardia "$T/guard" >"$T/tout"; rc=$?
espera "tardía: sin OpenRC → avisa y no instala" '(( rc == 0 )) && grep -q "sin OpenRC" "$T/tout" && [[ ! -e "$R/usr/lib/guardian/guardian" ]]'
R=""
espera "instalador: llama a mkf_tardia" 'grep -q "mkf_tardia \"\$GUARD\"" <<<"$I2"'
espera "instalador: gancho en /etc/apk/commit_hooks.d" 'grep -qx "HOOK=/etc/apk/commit_hooks.d/guardian-mkinitfs" "$I"'
R=""
if command -v cpio >/dev/null && command -v gzip >/dev/null; then
    mkdir -p "$T/img/usr/lib/guardian"; echo i >"$T/img/init"; echo g >"$T/img$GE"
    ( cd "$T/img" && find . | cpio -o -H newc 2>/dev/null | gzip >"$T/i.gz" )
    mkf_desempaquetar "$T/i.gz" "$T/u"; rc=$?
    espera "desempaquetar gzip+cpio" '(( rc == 0 )) && cmp -s "$T/u$GE" "$T/img$GE"'
    printf 'basura' >"$T/b.img"; mkf_desempaquetar "$T/b.img" "$T/u2"; rc=$?
    espera "desempaquetar: formato desconocido falla" '(( rc != 0 ))'
fi
# guardian: apk (gestor_paquetes + diagnosticar_apk), con un apk falso que imita apk 3 (alpine-lab3)
GU=$B/guardian
FA=$(sed -n '/^diagnosticar_apk() {/,/^}/p' "$GU"); FG=$(sed -n '/^gestor_paquetes() {/,/^}/p' "$GU")
espera "guardian: diagnosticar_apk y apk en gestor_paquetes" '[[ -n "$FA" ]] && grep -q "echo apk" <<<"$FG"'
espera "guardian: caso apk en diagnosticar_paquetes" 'sed -n "/^diagnosticar_paquetes() {/,/^}/p" "$GU" | grep -q "apk) diagnosticar_apk; return 0 ;;"'
mkdir -p "$T/abin"
cat >"$T/abin/apk" <<'AP'
#!/bin/bash
case "$1" in
  info)  [[ "${MODO:-}" == nodb ]] && { echo "ERROR: Unable to read database"; exit 1; }; printf 'alpine-baselayout\nbusybox\ne2fsprogs\n' ;;
  audit) [[ "${MODO:-}" == audit ]] && echo "X usr/sbin/e2image"; exit 0 ;;
  add)   [[ "${MODO:-}" == world ]] && { echo "ERROR: unable to select packages:"; echo "  paquete-que-no-existe (no such package):"; exit 1; }; echo "OK: 23 packages"; exit 0 ;;
esac
AP
printf '#!/bin/sh\n[ "${APK_OCUPADO:-0}" = 1 ]\n' >"$T/abin/pgrep"; chmod +x "$T/abin/apk" "$T/abin/pgrep"
: >"$T/apkdb"
cat >"$T/ga.sh" <<GA
ok() { echo "OK \$*"; }; warn() { echo "WARN \$*"; }; info() { echo "INFO \$*"; }; log() { :; }
rpm_db_presente() { false; }
LISTA_AVISOS=()
$FG
$FA
GA
da() { env -i PATH="$T/abin:/usr/bin:/bin" MODO="${MODO:-}" APK_OCUPADO="${APK_OCUPADO:-0}" GUARDIAN_APKDB="$T/apkdb" bash -c ". $T/ga.sh; $1"; }
BA=$(command -v bash)
espera "gestor: apk con su base → apk" '[[ "$(env -i PATH="$T/abin" GUARDIAN_APKDB="$T/apkdb" "$BA" -c ". $T/ga.sh; gestor_paquetes")" == apk ]]'
espera "gestor: apk sin base → no es apk" '[[ "$(env -i PATH="$T/abin" GUARDIAN_APKDB="$T/no" "$BA" -c ". $T/ga.sh; gestor_paquetes")" != apk ]]'
o=$(MODO= da diagnosticar_apk)
espera "apk sano: 3 OK y ningún WARN" '[[ "$(grep -c ^OK <<<"$o")" == 3 ]] && ! grep -q ^WARN <<<"$o" && grep -q "legible (3 paquetes)" <<<"$o"'
o=$(MODO=audit da diagnosticar_apk)
espera "apk: archivo ausente → WARN con 1 archivo" 'grep -q "^WARN apk audit --system: 1 archivo" <<<"$o"'
o=$(MODO=world da diagnosticar_apk)
espera "apk: world roto → WARN con el ERROR" 'grep -q "^WARN apk no puede cumplir lo instalado: ERROR: unable to select" <<<"$o"'
o=$(MODO=nodb da diagnosticar_apk)
espera "apk: base ilegible → WARN y no sigue" 'grep -q "^WARN No se puede leer la base de datos de apk" <<<"$o" && ! grep -q audit <<<"$o"'
o=$(APK_OCUPADO=1 da diagnosticar_apk)
espera "apk trabajando → INFO, no revisa" 'grep -q "^INFO Hay un apk trabajando" <<<"$o" && ! grep -q ^OK <<<"$o"'
# instalar-en-disco: rama mkinitfs (Alpine) → instalar-mkinitfs en modo disco
D=$B/instalar-en-disco
a=$(grep -n '^elif \[\[ -x "$MNT/usr/bin/dracut" \]\]; then$' "$D" | head -n1 | cut -d: -f1)
b=$(grep -n 'elif \[\[ -x "$MNT/sbin/mkinitfs" || -x "$MNT/usr/sbin/mkinitfs" \]\]; then' "$D" | head -n1 | cut -d: -f1)
c=$(grep -n '^else die "Ese sistema no usa initramfs-tools.*no soportado"; fi$' "$D" | head -n1 | cut -d: -f1)
espera "ied: rama mkinitfs ANTES del elif de dracut (la rama dracut queda igual)" '[[ -n "$a" && -n "$b" && -n "$c" ]] && (( b < a && a < c ))'
cat >"$T/rd.awk" <<'AWK'
/^elif \[\[ -x "\$MNT\/usr\/bin\/dracut" \]\]; then/{p=1; next} p && /^else die/{exit} p && /^elif /{print}
AWK
espera "ied: la rama dracut (elif…else die) no contiene otro elif" 'o=$(awk -f "$T/rd.awk" "$D") && [[ -z "$o" ]]'
espera "ied: llama a instalar-mkinitfs en modo disco" 'grep -q "exec /bin/bash \"\$SRC/instalar-mkinitfs\" \"\$DEV\" --sistema-confiable --early \"\$SRC/guardian-early\" --guardian \"\$SRC/guardian\"" "$D"'
espera "ied: pasa bash -n" 'bash -n "$D"'
espera "instalar-mkinitfs: modo disco (/dev/…)" 'grep -q "if \[\[ \"\${1:-}\" == /dev/\* \]\]; then mkf_en_disco" "$I"'
espera "modo disco: exige --sistema-confiable e instala bash con apk si falta" 'grep -q "requiere --sistema-confiable" "$I" && grep -q "apk add --no-progress bash" "$I" && grep -q "no pude instalarlo" "$I"'
GUARDIAN_MKF_FUNCIONES=1 bash -c ". $I; mkf_en_disco /dev/no-existe --sistema-confiable" >/dev/null 2>"$T/derr"; rc=$?
espera "modo disco: dispositivo inexistente → se niega" '(( rc != 0 )) && grep -q "no es un dispositivo de bloques" "$T/derr"'
echo "$P passed, $F failed"
(( F == 0 ))
