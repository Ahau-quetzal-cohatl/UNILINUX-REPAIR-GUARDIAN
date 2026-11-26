#!/bin/bash
# Tests de comportamiento Guardian v4.12 (no requieren root; usan imágenes ext4 en /tmp)
DIR="$(cd "$(dirname "$0")/../bin" 2>/dev/null && pwd || dirname "$0")"
[[ -f "$DIR/guardian-early" ]] || DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$PATH:/sbin:/usr/sbin"
PASS=0; FAIL=0; SKIP=0
check() { if eval "$1"; then echo "  ✔ $2"; PASS=$((PASS+1)); else echo "  ✖ $2"; FAIL=$((FAIL+1)); fi; }
echo "=== Tests Guardian v4.19.1 ==="

# ── Sintaxis ──
check "bash -n '$DIR/guardian'" "sintaxis bash (guardian)"
check "sh -n '$DIR/guardian-early'" "sintaxis sh (guardian-early)"
if command -v dash >/dev/null; then check "dash -n '$DIR/guardian-early'" "early válido en dash (POSIX)"; fi
check "! grep -nE '\[\[|declare -|local ' '$DIR/guardian-early'" "early sin bashismos"
check "! grep -nE '(^|[;&|({] *|then +|do +)(cp|grep|sed|awk|head|tail|tr|cut|wc|ls|find|touch|mv) ' '$DIR/guardian-early' | grep -v '^[0-9]*: *#'" "early: no usa comandos que el initramfs (klibc) no trae (cp, grep, sed, awk...)"
check "grep -q 'PREREQ=\"resume\"' '$DIR/install-guardian'" "premount depende de resume"
check "! grep -q '/home' '$DIR/guardian'" "late no usa /home"

check "grep -q 'no-packages' '$DIR/install-guardian'" "servicio de arranque sin apt (--no-packages)"
check "grep -q 'sound.target' '$DIR/install-guardian'" "servicio espera al audio"
check "grep -q 'set -f' '$DIR/guardian-early'" "early sin globbing en cmdline"

check "grep -q 'GUARDIAN_KVER' '$DIR/install-guardian'" "instalador acepta kernel explícito (chroot)"
check "bash -n '$DIR/install-guardian'" "install-guardian: sintaxis"
check "[[ ! -f '$DIR/instalar-en-disco' ]] || bash -n '$DIR/instalar-en-disco'" "instalar-en-disco: sintaxis"

check "grep -q sistema-confiable '$DIR/instalar-en-disco' 2>/dev/null || grep -q sistema-confiable '$DIR/../bin/instalar-en-disco'" "instalar-en-disco exige --sistema-confiable"

check "grep -q 'diagnosticar_smart_sata' '$DIR/guardian'" "SMART de discos SATA"
check "grep -q 'Reparador de sistemas Linux' '$DIR/guardian' && grep -q 'Autores: Ahau Quetzalcóatl y Claude' '$DIR/guardian'" "banner Unilinux Guardian con autores"

# ── Funciones de late ──
# shellcheck disable=SC1090
( source "$DIR/guardian"
  e2fsck_ok 0 && e2fsck_ok 1 && e2fsck_ok 2 && e2fsck_ok 3 && ! e2fsck_ok 4 && ! e2fsck_ok 8 && ! e2fsck_ok 12 ) 
check "[[ $? -eq 0 ]]" "e2fsck_ok: 0-3 éxito, >=4 fallo"

( source "$DIR/guardian"
  T2=$(mktemp -d); ln -s /tmp "$T2/lnk"
  ! dir_seguro "$T2/lnk" )
check "[[ $? -eq 0 ]]" "dir_seguro rechaza symlinks"
T=$(mktemp -d)
( source "$DIR/guardian"
  STATE_DIR="$T"; DRY_RUN=false; SAFE=false
  EARLY_STATUS=failed; FS_FALLIDOS=(); actualizar_flag; [[ -f "$T/needs_attention" ]] || exit 1
  EARLY_STATUS=none;   actualizar_flag; grep -qx root "$T/needs_attention" || exit 2   # se conserva
  EARLY_STATUS=ok;     actualizar_flag; [[ ! -f "$T/needs_attention" ]] || exit 3        # se limpia
  EARLY_STATUS=ok; FS_FALLIDOS=("fs:/dev/x"); actualizar_flag; grep -qx 'fs:/dev/x' "$T/needs_attention" || exit 4
  FS_FALLIDOS=(); actualizar_flag; [[ ! -f "$T/needs_attention" ]] || exit 5 )
check "[[ $? -eq 0 ]]" "flag persistente: crea / conserva / limpia correctamente"
rm -rf "$T"

# ── Veredicto final y código de salida (0 sano, 3 avisos de hardware, 1 problema) ──
export VT=$(mktemp -d)
verdict() { # $1 = overrides de diagnóstico (hermético: funciona sin root)
    bash -c "source '$DIR/guardian'; STATE_DIR=\"\$VT\"; require_root(){ :; }; init_paths(){ LOG_FILE=''; }; adquirir_lock(){ :; }; leer_early(){ EARLY_STATUS=ok; }; detectar_audio_usuario(){ :; }; hablar(){ :; }; musica_iniciar(){ :; }; musica_detener(){ :; }; detectar_discos(){ :; }; diagnosticar_smart_sata(){ :; }; diagnosticar_fs(){ :; }; diagnosticar_grub(){ :; }; diagnosticar_paquetes(){ :; }; diagnosticar_espacio(){ :; }; diagnosticar_red(){ :; }; diagnosticar_firmware(){ :; }; $1 main --safe --no-voice --no-packages" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
    return "${PIPESTATUS[0]}"
}
OUT=$(verdict ''); RC=$?
check "[[ $RC -eq 0 && \"\$OUT\" == *'SISTEMA SANO'* ]]" "veredicto: sin avisos → SANO, salida 0"
OUT=$(verdict 'diagnosticar_smart_sata(){ LISTA_AVISOS+=("Disco falso con señales de fallo"); };'); RC=$?
check "[[ $RC -eq 3 && \"\$OUT\" == *'AVISO'* && \"\$OUT\" != *'SISTEMA SANO'* ]]" "veredicto: aviso de hardware → NO dice SANO, salida 3"
OUT=$(verdict 'leer_early(){ EARLY_STATUS=failed; };'); RC=$?
check "[[ $RC -eq 1 && \"\$OUT\" != *'SISTEMA SANO'* ]]" "veredicto: early falló → salida 1"
OUT=$(verdict 'leer_early(){ EARLY_STATUS=forced; };'); RC=$?
check "[[ $RC -eq 3 && \"\$OUT\" == *FORZADA* && \"\$OUT\" != *'SISTEMA SANO'* ]]" "veredicto: raíz reparada a la fuerza → avisa claramente, salida 3"
check "grep -q \"elif ! grep -q '^ON_FAIL='\" '$DIR/install-guardian'" "instalador: actualiza early.conf antiguo con la política nueva"
TI=$(mktemp -d); mkdir -p "$TI/run" "$TI/logs"; printf 'e2fsck: Inode 12 cleared\n' > "$TI/run/early.log"
( source "$DIR/guardian"; export GUARDIAN_EARLY_LOG="$TI/run/early.log"; LOG_FILE="$TI/logs/g.log"; DRY_RUN=false; SAFE=false; EARLY_STATUS=forced
  guardar_informe_early; [[ -n "$INFORME_EARLY" ]] && grep -q 'Inode 12 cleared' "$INFORME_EARLY" || exit 1
  rm -f "$TI"/logs/early_*; INFORME_EARLY=""; EARLY_STATUS=ok; guardar_informe_early; ! ls "$TI"/logs/early_* >/dev/null 2>&1 || exit 2
  EARLY_STATUS=forced; SAFE=true; guardar_informe_early; ! ls "$TI"/logs/early_* >/dev/null 2>&1 || exit 3 )
check "[[ $? -eq 0 ]]" "tardía: guarda el informe del early en /var/log (solo si hubo reparación y no en --safe)"
check "grep -q 'BACKUP_EXCLUDE' '$DIR/guardian-early' && grep -q 'BACKUP_EXCLUDE' '$DIR/install-guardian'" "early: BACKUP_EXCLUDE evita usar discos que fallan"
check "grep -q 'partición EFI' '$DIR/guardian-early' && grep -q 'for _pass in ext vfat' '$DIR/guardian-early'" "early: nunca usa la partición EFI y prefiere ext antes que vfat"
check "grep -q 'bin/e2image' '$DIR/install-guardian'" "instalador: e2image va al initramfs (respaldo de metadatos)"
check "grep -q 'SuccessExitStatus=3' '$DIR/install-guardian'" "servicio acepta salida 3 (avisos) como éxito"

# ── estado.txt legible ──
VT2=$(mktemp -d); export VT2
vstate() { # $1 = overrides, $2 = flags extra
    bash -c "source '$DIR/guardian'; STATE_DIR=\"\$VT2\"; require_root(){ :; }; init_paths(){ LOG_FILE=''; }; adquirir_lock(){ :; }; leer_early(){ EARLY_STATUS=ok; }; detectar_audio_usuario(){ :; }; hablar(){ :; }; musica_iniciar(){ :; }; musica_detener(){ :; }; detectar_discos(){ :; }; diagnosticar_smart_sata(){ :; }; diagnosticar_fs(){ :; }; diagnosticar_grub(){ :; }; diagnosticar_paquetes(){ :; }; diagnosticar_espacio(){ :; }; diagnosticar_red(){ :; }; diagnosticar_firmware(){ :; }; $1 main --no-voice --no-packages $2" >/dev/null 2>&1
}
vstate 'diagnosticar_smart_sata(){ LISTA_AVISOS+=("Disco falso con señales de fallo"); };'
check "grep -q 'AVISO' '$VT2/estado.txt' && grep -q 'Disco falso' '$VT2/estado.txt' && grep -q 'código 3' '$VT2/estado.txt'" "estado.txt: resume el resultado y los avisos"
rm -f "$VT2/estado.txt"; vstate '' '--safe'
check "[[ ! -f '$VT2/estado.txt' ]]" "estado.txt: --safe no escribe nada"
vstate ''
check "grep -q 'RESULTADO: SANO' '$VT2/estado.txt'" "estado.txt: sano cuando no hay nada"

# ── v4.12: Arch (mkinitcpio). Se prueban los archivos EXACTOS que escribe el instalador ──
A=$(mktemp -d)
GUARDIAN_EMIT_ARCH="$A" bash "$DIR/install-guardian" >/dev/null 2>&1
AH="$A/etc/initcpio/hooks/guardian"; AB="$A/etc/initcpio/install/guardian"
AU="$A/usr/lib/guardian/guardian-early-initrd.service"; AD="$A/etc/mkinitcpio.conf.d/guardian.conf"
check "[[ -s '$AH' && -s '$AB' && -s '$AU' && -s '$AD' ]]" "Arch: el instalador escribe gancho de ejecución, de construcción, unidad y drop-in"
check "bash -n '$AB' && bash -n '$AD' && sh -n '$AH'" "Arch: sintaxis de los ganchos y del drop-in"
if command -v dash >/dev/null; then check "dash -n '$AH'" "Arch: run_hook válido en dash (ash de busybox)"; fi
hk() { bash -c "HOOKS=($1); . '$AD'; . '$AD'; echo \"\${HOOKS[*]}\""; }   # se carga dos veces: debe dar lo mismo
check "[[ \"\$(hk 'base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck')\" == 'base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems guardian fsck' ]]" "Arch drop-in: HOOKS por defecto (systemd) → guardian justo antes de fsck"
check "[[ \"\$(hk 'base udev block filesystems')\" == 'base udev block filesystems guardian' ]]" "Arch drop-in: sin fsck → guardian al final"
check "[[ \"\$(hk 'base yoyo udev autodetect microcode modconf block filesystems guardian fsck')\" == 'base yoyo udev autodetect microcode modconf block filesystems guardian fsck' ]]" "Arch drop-in: si guardian ya está, no cambia nada"
mkdir -p "$A/etc"; echo 'HOOKS=(base systemd block filesystems fsck)' > "$A/etc/mkinitcpio.conf"
echo 'HOOKS=(base udev resume block filesystems fsck)' > "$A/etc/mkinitcpio.conf.d/busybox.conf"
check "[[ \"\$(GUARDIAN_EMIT_ARCH='$A' GUARDIAN_EMIT_HOOKS=1 bash '$DIR/install-guardian')\" == 'base udev resume block filesystems guardian fsck' ]]" "Arch: el instalador calcula los HOOKS efectivos (mkinitcpio.conf + conf.d en orden)"
sim_build() { # $1 = systemd | busybox ; simula las funciones de mkinitcpio y lista lo que el gancho añade
    bash -c "BUILDROOT=\$(mktemp -d); mkdir -p \"\$BUILDROOT/usr/bin\" \"\$BUILDROOT/usr/lib/systemd\"
      if [[ $1 == systemd ]]; then : > \"\$BUILDROOT/usr/lib/systemd/systemd\"; else for c in sh cat mkdir mount umount sleep sync readlink rmdir; do : > \"\$BUILDROOT/usr/bin/\$c\"; done; fi
      add_file(){ echo \"file \$*\"; }; add_binary(){ echo \"bin \$*\"; }; add_symlink(){ echo \"link \$*\"; }
      add_module(){ echo \"mod \$*\"; }; add_runscript(){ echo runscript; }; warning(){ echo \"warn \$*\"; }
      . '$AB'; build; rm -rf \"\$BUILDROOT\""
}
BS=$(sim_build systemd); BB=$(sim_build busybox)
check "grep -E -q '^file (/usr/lib/guardian|/usr/local/sbin)/guardian-early /usr/bin/guardian-early 755' <<<\"\$BS\" && grep -q 'e2fsck /usr/bin/e2fsck' <<<\"\$BS\" && grep -q 'blkid /usr/bin/blkid' <<<\"\$BS\" && grep -q '/usr/bin/guardian-df' <<<\"\$BS\" && grep -qx runscript <<<\"\$BS\"" "Arch build: mete guardian-early, e2fsck, blkid y guardian-df"
check "grep -q '^file .*guardian-early-initrd.service /usr/lib/systemd/system/guardian-early.service' <<<\"\$BS\" && grep -q '^link /usr/lib/systemd/system/initrd-root-fs.target.wants/guardian-early.service' <<<\"\$BS\" && grep -qx 'bin bash' <<<\"\$BS\" && grep -qx 'bin cat' <<<\"\$BS\"" "Arch build (systemd): añade la unidad, su enlace, un shell y los comandos básicos"
check "! grep -q 'guardian-early.service' <<<\"\$BB\" && ! grep -qx 'bin bash' <<<\"\$BB\" && ! grep -qx 'bin cat' <<<\"\$BB\" && grep -qx runscript <<<\"\$BB\"" "Arch build (busybox): sin unidad systemd y sin tapar los comandos de busybox"
check "grep -qx 'bin date' <<<\"\$BS\" && grep -qx 'bin date' <<<\"\$BB\"" "Arch build: añade date (respaldos con fecha) en las dos variantes"
check "grep -q '^Before=systemd-fsck-root.service sysroot.mount' '$AU' && grep -q '^After=initrd-root-device.target systemd-hibernate-resume.service' '$AU' && grep -q '^ExecStart=/usr/bin/guardian-early' '$AU'" "Arch unidad: después del disco raíz y de la reanudación, antes del fsck y del montaje"
printf '#!/bin/sh\necho corrio > "%s/early-corrio"\nexit 7\n' "$A" > "$A/fake-early"; chmod +x "$A/fake-early"
sed "s#/usr/bin/guardian-early#$A/fake-early#g" "$AH" > "$A/hook-prueba"
check "sh -c '. \"$A/hook-prueba\"; root=/dev/null; run_hook' && [[ -f '$A/early-corrio' ]]" "Arch run_hook: llama a guardian-early y nunca devuelve error (no bloquea el arranque)"
check "grep -q 'mkinitcpio -P' '$DIR/install-guardian' && grep -q 'lsinitcpio' '$DIR/install-guardian' && grep -q 'arch_restaurar' '$DIR/install-guardian'" "Arch: el instalador regenera, verifica con lsinitcpio y restaura si algo falla"
check "grep -q 'mkinitcpio' '$DIR/instalar-en-disco' && grep -q 'TIPO=arch' '$DIR/instalar-en-disco'" "instalar-en-disco acepta Arch"
rm -rf "$A"

# ── v4.12: fase tardía en Arch (grub-mkconfig y pacman) ──
S=$(mktemp -d); mkdir -p "$S/a" "$S/b" "$S/p"
printf '#!/bin/sh\n' > "$S/a/update-grub"; printf '#!/bin/sh\n' > "$S/b/grub-mkconfig"; chmod +x "$S/a/update-grub" "$S/b/grub-mkconfig"
( source "$DIR/guardian"
  PATH="$S/a:$S/b"; [[ "$(grub_regen)" == "update-grub" ]] || exit 1
  PATH="$S/b";      [[ "$(grub_regen)" == "grub-mkconfig -o /boot/grub/grub.cfg" ]] || exit 2
  PATH="$S/nada";   [[ -z "$(grub_regen)" ]] || exit 3 )
check "[[ $? -eq 0 ]]" "tardía: regenera GRUB con update-grub (Debian/Ubuntu) o grub-mkconfig -o (Arch)"
( source "$DIR/guardian"; LOG_FILE=""; NO_PACKAGES=false; DRY_RUN=false
  export GUARDIAN_PKG=pacman GUARDIAN_PACMAN_LOCK="$S/db.lck"; PATH="$S/p:$PATH"; pacman_en_uso() { return 1; }   # (4.18.5) no depender de packagekitd/pacman del anfitrión
  printf '#!/bin/sh\necho "No database errors have been found!"\nexit 0\n' > "$S/p/pacman"; chmod +x "$S/p/pacman"
  diagnosticar_paquetes >/dev/null; (( ${#LISTA_AVISOS[@]} == 0 && ${#PEND[@]} == 0 )) || exit 1
  printf '#!/bin/sh\necho "error: falta la dependencia x"\nexit 1\n' > "$S/p/pacman"
  diagnosticar_paquetes >/dev/null; (( ${#LISTA_AVISOS[@]} == 1 && ${#PEND[@]} == 0 )) || exit 2
  : > "$S/db.lck"; diagnosticar_paquetes >/dev/null; [[ -z "${PEND[pacman-lock]:-}" ]] || exit 3      # candado de este arranque: no se toca
  reparar_pacman >/dev/null; [[ -e "$S/db.lck" ]] || exit 4
  touch -d '2001-01-01' "$S/db.lck"; diagnosticar_paquetes >/dev/null; [[ -n "${PEND[pacman-lock]:-}" ]] || exit 5
  reparar_pacman >/dev/null; [[ ! -e "$S/db.lck" && -z "${PEND[pacman-lock]:-}" ]] || exit 6 )
check "[[ $? -eq 0 ]]" "tardía (Arch): pacman -Dk solo avisa; el candado huérfano se quita y el de este arranque no se toca"
rm -rf "$S"

# ── guardian-early con ext4 real ──
if command -v mke2fs >/dev/null && command -v debugfs >/dev/null && command -v e2fsck >/dev/null && command -v blkid >/dev/null; then
    W=$(mktemp -d)
    mkimg() { rm -f "$W/d.img"; mke2fs -q -F -t ext4 "$W/d.img" 8M >/dev/null 2>&1; }
    # run_early POLÍTICA [MIN_MB] [con_respaldo=1|0]
    run_early() {
        printf 'ON_FAIL=%s\nBACKUP_MIN_MB=%s\nMETA_MIN_MB=%s\n' "$1" "${2:-1}" "${4:-1}" > "$W/early.conf"
        rm -rf "$W/run" "$W/bk"
        if [[ "${3:-1}" == 1 ]]; then export GUARDIAN_BACKUP_DIR="$W/bk"; else unset GUARDIAN_BACKUP_DIR; fi
        ROOT="$W/d.img" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/early.conf" sh "$DIR/guardian-early" >/dev/null 2>&1
        echo $? > "$W/exit"; cat "$W/run/early_status" 2>/dev/null
    }
    heavy() { mkimg; debugfs -w -R "clri <2>" "$W/d.img" >/dev/null 2>&1; debugfs -w -R "ssv state 0" "$W/d.img" >/dev/null 2>&1; }
    mkimg;                                     check "[[ \$(run_early nada) == ok ]]"       "early: FS limpio → ok"
    check "[[ \$(cat $W/exit) == 0 ]]" "early: siempre sale con 0"

    mkimg; debugfs -w -R "ssv state 0" "$W/d.img" >/dev/null 2>&1
    debugfs -w -R "ssv free_blocks_count 5" "$W/d.img" >/dev/null 2>&1
    check "[[ \$(run_early nada) == repaired ]]"  "early: daño leve → -p repara → repaired (incluso con política nada)"
    check "e2fsck -fn '$W/d.img' >/dev/null 2>&1" "early: tras reparar, e2fsck -fn limpio"

    heavy
    check "[[ \$(run_early nada) == failed ]]"    "early: daño grave y política nada → failed (sin -y)"
    check "[[ \$(cat $W/exit) == 0 ]]" "early: falla pero no bloquea el arranque"
    check "! e2fsck -fn '$W/d.img' >/dev/null 2>&1" "early: con política nada el FS no se tocó"
    check "[[ \$(grep -c 'reintento' $W/run/early.log) -eq 1 && \$(grep -c '2.º intento' $W/run/early.log) -eq 1 ]]" "early: reintenta -p una vez antes de rendirse"
    check "! grep -q 'e2fsck -fy' $W/run/early.log" "early: política nada nunca invoca -y"

    # Política por defecto del usuario: respaldo si hay espacio; si no, forzar
    heavy; e2fsck -p "$W/d.img" >/dev/null 2>&1; e2fsck -p "$W/d.img" >/dev/null 2>&1; cp "$W/d.img" "$W/orig.img"   # estado tras los -p (solo cambian marcas del superbloque)
    check "[[ \$(run_early respaldo_y_forzar 1 1) == forced ]]" "early: daño grave + respaldo_y_forzar con espacio → forced"
    check "ls $W/bk/guardian-backups/root-undo-*.e2undo >/dev/null 2>&1" "early: se creó el archivo de deshacer (respaldo)"
    check "grep -q '^BACKUP_FILE=guardian-backups/root-undo-' $W/run/early_backup" "early: dejó anotado dónde está el respaldo"
    check "e2fsck -fn '$W/d.img' >/dev/null 2>&1" "early: tras la reparación forzada el FS queda limpio"
    if command -v e2undo >/dev/null; then
        U=$(ls "$W"/bk/guardian-backups/root-undo-*.e2undo 2>/dev/null | head -1)
        e2undo "$U" "$W/d.img" >/dev/null 2>&1
        check "! e2fsck -fn '$W/d.img' >/dev/null 2>&1 && cmp -s -i 8192 '$W/d.img' '$W/orig.img'" "early: e2undo devuelve el disco EXACTAMENTE a como estaba antes de la reparación forzada"
    fi

    # Dos reparaciones forzadas seguidas con el mismo destino: el 2.º respaldo NO debe pisar al 1.º
    heavy; run_early respaldo_y_forzar 1 1 >/dev/null; N1=$(ls "$W"/bk/guardian-backups/*.e2undo 2>/dev/null | wc -l)
    mkdir -p "$W/bk_keep"; cp -r "$W"/bk/guardian-backups "$W/bk_keep/"
    heavy; export GUARDIAN_BACKUP_DIR="$W/bk"; printf 'ON_FAIL=respaldo_y_forzar\nBACKUP_MIN_MB=1\n' > "$W/early.conf"; rm -rf "$W/run"
    ROOT="$W/d.img" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/early.conf" sh "$DIR/guardian-early" >/dev/null 2>&1
    check "[[ \$(ls $W/bk/guardian-backups/*.e2undo | wc -l) -eq 2 ]]" "early: un segundo respaldo no sobrescribe el primero (nombres únicos)"
    # Respaldo que sirve DESPUÉS del arranque: imagen de metadatos + informe del fsck
    if command -v e2image >/dev/null; then
        heavy; run_early respaldo_y_forzar 1 1 1 >/dev/null
        check "[[ -s \$(ls $W/bk/guardian-backups/root-meta-*.img 2>/dev/null | head -1) ]] && grep -q '^META_FILE=guardian-backups/root-meta-' $W/run/early_backup" "early: guarda la imagen de metadatos (e2image -r) antes de forzar"
        check "grep -q 'reparación forzada completada' $W/bk/guardian-backups/root-fsck-*.log && grep -q '^FSCK_LOG=' $W/run/early_backup" "early: guarda junto al respaldo el informe de lo que cambió el fsck"
        # Registro en vivo: el log del early queda en la partición de respaldo (sobrevive a un reinicio a medias)
        heavy; run_early respaldo_y_forzar 1 1 1 >/dev/null
        check "grep -q 'reparación forzada completada' $W/bk/guardian-backups/early-live-*.log && grep -Eq 'guardian-early \\+[0-9.]+s' $W/bk/guardian-backups/early-live-*.log" "early: guarda el registro en vivo en la partición de respaldo (con segundos desde el arranque)"
        sleep 3
        check "! pgrep -ax sleep 2>/dev/null | grep -v defunct | grep -q ." "early: no deja el registro en vivo corriendo tras terminar"
        # Entorno MÍNIMO como el initramfs real de Debian (klibc): solo estos comandos, sin cp/rm/grep/sed/awk/date
        mkdir -p "$W/tools"; rm -f "$W"/tools/*
        for _c in cat sleep sync mount umount mkdir readlink rmdir e2fsck e2image blkid; do ln -s "$(command -v $_c)" "$W/tools/$_c"; done
        ln -s "$(command -v dash || command -v sh)" "$W/tools/sh"; ln -s "$(command -v df)" "$W/tools/guardian-df"
        heavy; printf 'ON_FAIL=respaldo_y_forzar\nBACKUP_MIN_MB=1\nMETA_MIN_MB=1\n' > "$W/early.conf"; rm -rf "$W/run" "$W/bk"
        GUARDIAN_PATH="$W/tools" GUARDIAN_BACKUP_DIR="$W/bk" ROOT="$W/d.img" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/early.conf" "$W/tools/sh" "$DIR/guardian-early" >/dev/null 2>&1
        check "[[ \$(cat $W/run/early_status) == forced ]] && ls $W/bk/guardian-backups/root-undo-sin-fecha-*.e2undo $W/bk/guardian-backups/root-meta-*.img $W/bk/guardian-backups/root-fsck-*.log $W/bk/guardian-backups/early-live-*.log >/dev/null 2>&1" "early: con SOLO los comandos del initramfs real igual repara, guarda el respaldo, el informe del fsck y el registro en vivo"
        # v4.12 — mismo entorno mínimo + date (lo que el gancho de Arch añade): el respaldo lleva fecha real
        ln -s "$(command -v date)" "$W/tools/date"
        heavy; rm -rf "$W/run" "$W/bk"
        GUARDIAN_PATH="$W/tools" GUARDIAN_BACKUP_DIR="$W/bk" ROOT="$W/d.img" GUARDIAN_RUN="$W/run" GUARDIAN_EARLY_CONF="$W/early.conf" "$W/tools/sh" "$DIR/guardian-early" >/dev/null 2>&1
        check "[[ \$(cat $W/run/early_status) == forced ]] && ls $W/bk/guardian-backups/root-undo-20[0-9][0-9][01][0-9][0-3][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]-1.e2undo >/dev/null 2>&1" "early: con date en el initramfs (Arch v4.12) el respaldo lleva fecha y hora en el nombre"
        # Destino vfat (p. ej. una ESP): NUNCA e2image (FAT no tiene archivos dispersos y llenaría la partición)
        heavy; GUARDIAN_BACKUP_FS=vfat run_early respaldo_y_forzar 1 1 1 >/dev/null
        check "ls $W/bk/guardian-backups/root-undo-*.e2undo >/dev/null 2>&1 && ! ls $W/bk/guardian-backups/root-meta-*.img >/dev/null 2>&1 && grep -q 'destino es vfat' $W/run/early.log" "early: destino vfat → solo el deshacer, sin imagen de metadatos"
        heavy; run_early respaldo_y_forzar 1 1 99999999 >/dev/null
        check "ls $W/bk/guardian-backups/root-undo-*.e2undo >/dev/null 2>&1 && ! ls $W/bk/guardian-backups/root-meta-*.img >/dev/null 2>&1 && grep -q 'se omite la imagen de metadatos' $W/run/early.log" "early: sin espacio para metadatos → solo el deshacer, y lo registra"
    fi
    heavy
    check "[[ \$(run_early respaldo_y_forzar 99999999 1) == forced ]]" "early: sin espacio para respaldo + respaldo_y_forzar → se fuerza igualmente"
    check "grep -q 'BACKUP=ninguno' $W/run/early_backup && grep -q 'SIN RESPALDO' $W/run/early.log" "early: queda registrado que NO hubo respaldo"
    heavy
    check "[[ \$(run_early solo_con_respaldo 99999999 1) == failed ]] && ! e2fsck -fn '$W/d.img' >/dev/null 2>&1" "early: sin espacio + solo_con_respaldo → NO fuerza, el FS no se toca"
    heavy
    check "[[ \$(run_early forzar 1 0) == forced ]]" "early: política forzar (sin intentar respaldo) → forced"

    mkimg
    check "[[ \$(ROOT=/dev/no/existe GUARDIAN_RUN=$W/run2 sh $DIR/guardian-early 2>/dev/null; cat $W/run2/early_status) == skipped ]]" "early: dispositivo inexistente → skipped"
    rm -rf "$W"
else
    echo "  - (omitido) faltan mke2fs/debugfs/e2fsck/blkid para los tests con ext4"; SKIP=1
fi

echo ""
echo "Resultado: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "✅ Tests OK" || exit 1
echo "Las pruebas de Arch simulan mkinitcpio: la prueba real es el arranque en el disco de prueba (técnica del yoyo)."
