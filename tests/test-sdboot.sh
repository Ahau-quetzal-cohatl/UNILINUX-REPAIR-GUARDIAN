#!/bin/bash
# test-sdboot.sh (4.17.8 v2): esp_imagen de instalar-dracut (systemd-boot tipo 1 / UKI).
# Uso: bash tests/test-sdboot.sh [directorio bin]   (contra 4.17.7 debe FALLAR)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FN=$(sed -n '/^# >>> esp_imagen/,/^# <<< esp_imagen/p' "$B/instalar-dracut")
espera "esp_imagen existe en instalar-dracut" '[[ -n "$FN" ]]'
eval "$FN"
K=7.3.3-300.fc45.x86_64
nuevo() { rm -rf "$T/r"; mkdir -p "$T/r/boot" "$T/r/etc/kernel"; R=$T/r; KVER=$K; IMG=""; }
viejo() { echo vieja >"$R/boot/initramfs-$K.img"; IMG=$R/boot/initramfs-$K.img; }
ent() { mkdir -p "$1/loader/entries"; printf 'title Fedora\nlinux %s\ninitrd %s\n' "/x/$K/linux" "$2" >"$1/loader/entries/Fedora-$K.conf"; }
esp() { mkdir -p "$(dirname "$1")"; echo esp >"$1"; }
corre() { OUTP=$(esp_imagen 2>"$T/err"); RC=$?; }
vacio='[[ $RC == 0 && -z "$OUTP" ]]'
niega='[[ $RC == 1 && -z "$OUTP" ]]'

nuevo; viejo; corre;                                         espera "GRUB clásico: nada" "$vacio"
ulb() { mkdir -p "$R/usr/lib/kernel"; echo layout=bls >"$R/usr/lib/kernel/install.conf"; }
nuevo; viejo; ent "$R/boot" "/initramfs-$K.img"; ulb; corre
espera "GRUB BLS, /boot aparte + layout=bls de /usr/lib: nada" "$vacio"
nuevo; viejo; ent "$R/boot" "/boot/initramfs-$K.img"; ulb; corre
espera "GRUB BLS, /boot en la raíz + layout=bls de /usr/lib: nada" "$vacio"
nuevo; viejo; ent "$R/boot" "/boot/initramfs-$K.img"; echo layout=bls >"$R/etc/kernel/install.conf"; corre
espera "GRUB BLS + layout=bls en /etc, sin ESP: se niega" "$niega"
nuevo; viejo; ent "$R/boot" "/boot/initramfs-$K.img"; echo Fedora >"$R/etc/kernel/entry-token"; corre
espera "GRUB BLS + entry-token, sin ESP: se niega" "$niega"
nuevo; viejo; ent "$R/efi" "/efi/Fedora/$K/initrd"; esp "$R/efi/Fedora/$K/initrd"; echo layout=bls >"$R/etc/kernel/install.conf"; corre
espera "entrada con ruta absoluta /efi/... (lab): ESP" '[[ $RC == 0 && "$OUTP" == "$R/efi/Fedora/$K/initrd" ]]'
nuevo; viejo; mkdir -p "$R/srv"; echo x >"$R/srv/initrd"; ent "$R/efi" "/srv/initrd"; corre
espera "ruta absoluta FUERA de la ESP: no cuenta" "$vacio"
nuevo; viejo; ent "$R/efi" "/Fedora/$K/initrd"; esp "$R/efi/Fedora/$K/initrd"; corre
espera "systemd-boot en /efi con /boot viejo: ESP" '[[ $RC == 0 && "$OUTP" == "$R/efi/Fedora/$K/initrd" ]]'
nuevo; ent "$R/efi" "/Fedora/$K/initrd"; esp "$R/efi/Fedora/$K/initrd"; corre
espera "systemd-boot en /efi sin /boot: ESP" '[[ $RC == 0 && "$OUTP" == "$R/efi/Fedora/$K/initrd" ]]'
nuevo; viejo; ent "$R/boot/efi" "/Fedora/$K/initrd"; esp "$R/boot/efi/Fedora/$K/initrd"; corre
espera "systemd-boot en /boot/efi: ESP" '[[ $RC == 0 && "$OUTP" == "$R/boot/efi/Fedora/$K/initrd" ]]'
nuevo; ent "$R/boot" "/Fedora/$K/initrd"; esp "$R/boot/Fedora/$K/initrd"; corre
espera "ESP montada en /boot: ESP" '[[ $RC == 0 && "$OUTP" == "$R/boot/Fedora/$K/initrd" ]]'
nuevo; viejo; mkdir -p "$R/boot/efi"; ln -s boot/efi "$R/efi"; ent "$R/boot/efi" "/Fedora/$K/initrd"; esp "$R/boot/efi/Fedora/$K/initrd"; corre
espera "/efi enlace a /boot/efi: una sola ESP" '[[ $RC == 0 && "$OUTP" == "$R/boot/efi/Fedora/$K/initrd" ]]'
nuevo; viejo; esp "$R/efi/EFI/Linux/Fedora-$K.efi"; corre
espera "UKI: lo entrega como UKI:ruta (4.17.9)" '[[ $RC == 0 && "$OUTP" == "UKI:$R/efi/EFI/Linux/Fedora-$K.efi" ]]'
espera "UKI: sin aviso" '[[ ! -s "$T/err" ]]'
nuevo; viejo; echo layout=uki >"$R/etc/kernel/install.conf"; corre
espera "layout=uki sin ESP visible: se niega" "$niega"
nuevo; viejo; printf '# c\nlayout=bls\n' >"$R/etc/kernel/install.conf"; corre
espera "layout=bls sin entrada ni ESP: se niega" "$niega"
espera "  y avisa de la ESP sin montar" 'grep -q "ESP sin montar" "$T/err"'
nuevo; viejo; echo Fedora >"$R/etc/kernel/entry-token"; corre
espera "entry-token sin ESP: se niega" "$niega"
nuevo; viejo; mkdir -p "$R/usr/lib/kernel"; echo '#layout=bls|other|...' >"$R/usr/lib/kernel/install.conf"; corre
espera "install.conf solo comentado (Fedora): nada" "$vacio"
nuevo; viejo; ent "$R/efi" "/Fedora/$K/initrd"; esp "$R/efi/Fedora/$K/initrd"
mkdir -p "$R/boot/efi/loader/entries"; printf 'initrd /otra/initrd\n' >"$R/boot/efi/loader/entries/b-$K.conf"; esp "$R/boot/efi/otra/initrd"; corre
espera "dos initrd distintos: se niega" "$niega"
nuevo; viejo; mkdir -p "$R/efi/loader/entries"; printf 'initrd /Fedora/6.1.0/initrd\n' >"$R/efi/loader/entries/Fedora-6.1.0.conf"; esp "$R/efi/Fedora/6.1.0/initrd"; corre
espera "entrada de OTRO kernel: nada" "$vacio"
nuevo; viejo; ent "$R/efi" "/Fedora/$K/no-existe"; corre
espera "entrada con initrd inexistente y sin señal: nada" "$vacio"
# Integración: interno() llama a esp_imagen ANTES del «No encuentro el initramfs»
a=$(grep -n 'EI=$(esp_imagen)' "$B/instalar-dracut" | head -n1 | cut -d: -f1)
b=$(grep -n 'No encuentro el initramfs de $KVER en /boot' "$B/instalar-dracut" | head -n1 | cut -d: -f1)
espera "interno llama a esp_imagen antes de exigir /boot" '[[ -n "$a" && -n "$b" ]] && (( a < b ))'
espera "IMG pasa a la ESP" 'grep -q "IMG=\"\$EI\"" "$B/instalar-dracut"'
espera "aviso final de kernel-install" 'grep -q "kernel-install add \$KVER" "$B/instalar-dracut"'
echo "$P passed, $F failed"
(( F == 0 ))
