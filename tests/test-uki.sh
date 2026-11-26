#!/bin/bash
# test-uki.sh (4.17.9): UKI en instalar-dracut (esp_imagen, uki_extraer, uki_preparar, integración).
# Uso: bash tests/test-uki.sh [directorio bin]   (contra 4.17.8 debe FALLAR)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FU=$(sed -n '/^# >>> uki/,/^# <<< uki/p' "$B/instalar-dracut")
FE=$(sed -n '/^# >>> esp_imagen/,/^# <<< esp_imagen/p' "$B/instalar-dracut")
espera "bloque uki existe en instalar-dracut" '[[ -n "$FU" ]]'
eval "$FE"; eval "$FU"
PY=$(command -v python3) || { echo "sin python3"; echo "$P passed, $((F+1)) failed"; exit 1; }
mkpe() {   # $1 salida  $2 contenido de .initrd  [$3 = sin → sin sección .initrd]
"$PY" - "$1" "$2" "${3:-}" <<'PYPE'
import struct, sys
out, pay, modo = sys.argv[1], open(sys.argv[2], "rb").read(), sys.argv[3]
secs = [(b".osrel", b"ID=fedora\n"), (b".linux", b"K" * 700)]
if modo != "sin": secs.append((b".initrd", pay))
pe = 0x80; so = 0; h = bytearray(0x200)
h[0:2] = b"MZ"; struct.pack_into("<I", h, 0x3c, pe); h[pe:pe+4] = b"PE\0\0"
struct.pack_into("<HH", h, pe+4, 0x8664, len(secs)); struct.pack_into("<H", h, pe+20, so)
body = bytearray(); base = 0x200
for i, (n, dat) in enumerate(secs):
    raw = (len(dat) + 0x1ff) // 0x200 * 0x200; o = pe + 24 + so + 40*i
    h[o:o+8] = n.ljust(8, b"\0")
    struct.pack_into("<IIII", h, o+8, len(dat), 0x1000*(i+1), raw, base + len(body))
    body += dat + b"\0" * (raw - len(dat))
open(out, "wb").write(bytes(h) + bytes(body))
PYPE
}
head -c 3001 /dev/urandom >"$T/ini"
mkpe "$T/u.efi" "$T/ini"
uki_extraer "$T/u.efi" "$T/sal"; espera "uki_extraer: .initrd exacto (sin relleno)" '[[ $? == 0 ]] && cmp -s "$T/ini" "$T/sal"'
printf 'MZ basura' >"$T/malo.efi"; uki_extraer "$T/malo.efi" "$T/s2"; rc=$?
espera "uki_extraer: PE inválido falla" '(( rc != 0 ))'
mkpe "$T/sin.efi" "$T/ini" sin; uki_extraer "$T/sin.efi" "$T/s3"; rc=$?
espera "uki_extraer: sin sección .initrd falla" '(( rc != 0 ))'
K=7.3.3-300.fc45.x86_64
nuevo() { rm -rf "$T/r"; mkdir -p "$T/r/boot" "$T/r/etc/kernel"; R=$T/r; KVER=$K; IMG=""; }
uk() { mkdir -p "$R$1"; mkpe "$R$1/Fedora-$K.efi" "$T/ini"; }
corre() { OUTP=$(esp_imagen 2>"$T/err"); RC=$?; }
nuevo; uk /efi/EFI/Linux; corre
espera "esp_imagen: un UKI → UKI:ruta" '[[ $RC == 0 && "$OUTP" == "UKI:$R/efi/EFI/Linux/Fedora-$K.efi" ]]'
nuevo; echo vieja >"$R/boot/initramfs-$K.img"; IMG=$R/boot/initramfs-$K.img; uk /boot/efi/EFI/Linux; corre
espera "esp_imagen: UKI en /boot/efi con /boot viejo" '[[ $RC == 0 && "$OUTP" == "UKI:$R/boot/efi/EFI/Linux/Fedora-$K.efi" ]]'
nuevo; uk /efi/EFI/Linux; cp "$R/efi/EFI/Linux/Fedora-$K.efi" "$R/efi/EFI/Linux/Otro-$K.efi"; corre
espera "esp_imagen: dos UKI se niega" '[[ $RC == 1 && -z "$OUTP" ]]'
nuevo; uk /efi/EFI/Linux; mkdir -p "$R/efi/loader/entries" "$R/efi/Fedora/$K"; echo x >"$R/efi/Fedora/$K/initrd"
printf 'initrd /Fedora/%s/initrd\n' "$K" >"$R/efi/loader/entries/Fedora-$K.conf"; corre
espera "esp_imagen: UKI + initrd BLS se niega" '[[ $RC == 1 && -z "$OUTP" ]]'
# uki_preparar con PATH controlado
mkdir -p "$T/bin"
for x in sed cat mktemp sha256sum cut tail rm ls; do ln -sf "$(command -v "$x")" "$T/bin/$x"; done
ln -sf "$PY" "$T/bin/python3"
falso() { printf '#!/bin/sh\nexit 0\n' >"$T/bin/$1"; chmod +x "$T/bin/$1"; }
quita() { rm -f "$T/bin/$1"; }
base() { nuevo; uk /efi/EFI/Linux; UKI=$R/efi/EFI/Linux/Fedora-$K.efi
         mkdir -p "$R/usr/lib/systemd/boot/efi" "$R/usr/lib/modules/$K"; echo s >"$R/usr/lib/systemd/boot/efi/linuxx64.efi.stub"
         echo v >"$R/usr/lib/modules/$K/vmlinuz"; printf 'layout=uki\nuki_generator=ukify\n' >"$R/etc/kernel/install.conf"
         falso kernel-install; falso ukify; falso objcopy; }
prep() { VIMG=""; VMLZ=""; UKI_SHA0=""; local p=$PATH; PATH=$T/bin; uki_preparar 2>"$T/err"; RC=$?; PATH=$p; }
ok='[[ $RC == 0 ]]'; niega='[[ $RC == 1 && -z "$VIMG" ]]'
base; prep
espera "preparar: todo bien → rc 0" "$ok"
espera "  VIMG = .initrd exacto" '[[ -n "$VIMG" ]] && cmp -s "$VIMG" "$T/ini"'
espera "  VMLZ /usr/lib/modules" '[[ "$VMLZ" == "/usr/lib/modules/$K/vmlinuz" ]]'
espera "  UKI_SHA0" '[[ "$UKI_SHA0" == "$(sha256sum "$UKI" | cut -d" " -f1)" ]]'
rm -f "$VIMG"
base; echo layout=bls >"$R/etc/kernel/install.conf"; prep; espera "preparar: layout=bls se niega" "$niega"
base; rm -f "$R/etc/kernel/install.conf"; prep; espera "preparar: sin install.conf se niega" "$niega"
espera "  aviso: otra herramienta" 'grep -q "otra herramienta" "$T/err"'
base; quita kernel-install; prep; espera "preparar: sin kernel-install se niega" "$niega"
base; quita python3; prep; espera "preparar: sin python3 se niega" "$niega"; ln -sf "$PY" "$T/bin/python3"
base; quita ukify; prep; espera "preparar: ukify sin ukify se niega" "$niega"
base; quita ukify; mkdir -p "$R/usr/lib/systemd"; printf '#!/bin/sh\n' >"$R/usr/lib/systemd/ukify"; chmod +x "$R/usr/lib/systemd/ukify"; prep
espera "preparar: ukify en /usr/lib/systemd vale" "$ok"; rm -f "$VIMG"
base; printf 'layout=uki\nuki_generator=dracut\n' >"$R/etc/kernel/install.conf"; quita objcopy; prep
espera "preparar: dracut --uefi sin objcopy se niega" "$niega"
base; printf 'layout=uki\n' >"$R/etc/kernel/install.conf"; quita objcopy; prep
espera "preparar: generador sin decir (=dracut) sin objcopy se niega" "$niega"
base; printf 'layout=uki\n' >"$R/etc/kernel/install.conf"; prep
espera "preparar: generador sin decir con objcopy vale" "$ok"; rm -f "$VIMG"
base; rm -f "$R/usr/lib/systemd/boot/efi/linuxx64.efi.stub"; prep; espera "preparar: sin stub se niega" "$niega"
base; rm -f "$R/usr/lib/modules/$K/vmlinuz"; prep; espera "preparar: sin vmlinuz se niega" "$niega"
base; rm -f "$R/etc/kernel/install.conf"; mkdir -p "$R/usr/lib/kernel" "$R/etc/kernel/install.conf.d"
echo layout=bls >"$R/usr/lib/kernel/install.conf"; printf 'layout=uki\nuki_generator=ukify\n' >"$R/etc/kernel/install.conf.d/50-uki.conf"; prep
espera "preparar: drop-in layout=uki manda" "$ok"; rm -f "$VIMG"
base; printf 'MZ basura' >"$UKI"; prep; espera "preparar: .efi ilegible se niega" "$niega"
# Integración en interno()
I=$(sed -n '/^interno() {/,/^}/p' "$B/instalar-dracut")
espera "interno: rama UKI tras esp_imagen" 'grep -q "if \[\[ \"\$EI\" == UKI:\* \]\]; then" <<<"$I"'
espera "interno: kernel-install add en vez de dracut" 'grep -q "kernel-install add \"\$KVER\" \"\$VMLZ\" </dev/null || drc=\$?" <<<"$I"'
espera "interno: lsinitrd del .initrd del UKI" 'grep -q "lsinitrd \"\${VIMG:-\$IMG}\"" <<<"$I"'
espera "interno: verificar_imagen del .initrd del UKI" 'grep -q "verificar_imagen \"\${VIMG:-\$IMG}\"" <<<"$I"'
a=$(grep -n 'uki_extraer "$IMG" "$VIMG"' <<<"$I" | head -n1 | cut -d: -f1)
b=$(grep -n 'local sz; sz=' <<<"$I" | head -n1 | cut -d: -f1)
c=$(grep -n 'kernel-install add "$KVER" "$VMLZ"' <<<"$I" | head -n1 | cut -d: -f1)
espera "interno: relee el UKI tras kernel-install y antes del tamaño" '[[ -n "$a" && -n "$b" && -n "$c" ]] && (( c < a && a < b ))'
espera "interno: UKI sin cambios → restaura" 'grep -q "kernel-install no rehízo" <<<"$I"'
echo "$P passed, $F failed"
(( F == 0 ))
