```
  █ █ █▄ █ █ █   █ █▄ █ █ █ ▀▄▀
  █▄█ █ ▀█ █ █▄▄ █ █ ▀█ █▄█ █ █
   ◆  G U A R D I A N  ◆
   Reparador de sistemas Linux
   Autores: Ahau Quetzalcóatl y Claude
```

# Unilinux Guardian — reparador de sistemas Linux

**Versión 4.19.1** · Licencia GPL-3.0 · Autores: **Ahau Quetzalcóatl** y **Claude**

Unilinux Guardian revisa y repara el sistema **en cada arranque, sin que nadie
intervenga**. Se pensó para una persona que no puede tocar el equipo físicamente.
Por eso su primera regla es **no empeorar nunca las cosas**: si duda, avisa y no toca.

## Cómo funciona

Trabaja en dos fases:

| Fase | Dónde corre | Qué hace |
|------|-------------|----------|
| **guardian-early** | initramfs (POSIX sh, también con klibc) | Revisa el filesystem **raíz antes de montarlo**. Si se necesita reparar, primero respalda los metadatos (e2image / btrfs) en un disco aparte. **Nunca bloquea el arranque** (siempre sale con 0). |
| **guardian** (tardía) | sistema en marcha (bash, `multi-user.target`) | Discos (SMART/NVMe), filesystems de fstab **desmontados**, bootloader (GRUB/systemd-boot/UKI), paquetes (dpkg/pacman/rpm/apk/xbps/portage/nix), snapshots, espacio, red y firmware. Escribe un resumen en `/var/lib/guardian/estado.txt`. |

Reglas del código:
- Nunca toca un filesystem montado. La raíz solo la trata la fase early.
- «Éxito» quiere decir que el problema ya no está, no que se ejecutó un comando.
- Los avisos de hardware (SMART, espacio, firmware) se informan y no se intenta «repararlos».
- No borra ni instala paquetes por su cuenta.

## Distribuciones

| Familia | Initramfs | Instalador |
|---------|-----------|------------|
| Debian, Ubuntu, Mint, Kali, Pop!_OS, Zorin, MX | initramfs-tools | `install-guardian` |
| Arch, Manjaro | mkinitcpio (systemd y busybox) | `install-guardian` |
| Fedora, openSUSE | dracut con systemd | `instalar-dracut` |
| Void (runit), Gentoo (OpenRC) | dracut sin systemd | `instalar-dracut-sinsd` |
| Alpine | mkinitfs | `instalar-mkinitfs` |
| NixOS | módulo `nixos/guardian.nix` | `imports` en `configuration.nix` |
| MiniOS (live modular) | segundo initrd junto al oficial | `instalar-minios` |

Con **arranque real** (no solo en laboratorio) se probaron: Debian 13 (uso diario),
Alpine, Void, Gentoo, NixOS, Ubuntu 26.04, Linux Mint 22, Kali, Pop!_OS, Zorin OS,
MX Linux, Manjaro y MiniOS.

## Instalación

```bash
git clone https://github.com/Ahau-quetzal-cohatl/UNILINUX-REPAIR-GUARDIAN.git
cd UNILINUX-REPAIR-GUARDIAN
for t in tests/*.sh; do bash "$t" || echo "FALLA $t"; done   # opcional, sin root
sudo bash bin/install-guardian           # Debian/Ubuntu/Arch y derivadas
# sudo bash bin/instalar-dracut          # Fedora / openSUSE
# sudo bash bin/instalar-dracut-sinsd    # Void / Gentoo
# sudo bash bin/instalar-mkinitfs        # Alpine
```

Para instalarlo en **otro disco** (no el que está en uso) hay que poner
`--sistema-confiable`. Esa opción existe porque el chroot ejecuta programas de ese
sistema como root:

```bash
sudo bash bin/instalar-en-disco /dev/sdXN --sistema-confiable
```

La configuración va en `/etc/guardian/early.conf`. Las opciones principales son
`ON_FAIL`, `BACKUP_UUID` (disco de respaldos), `BACKUP_EXCLUDE` (discos que no se
tocan nunca), `BACKUP_MIN_MB` y `META_MIN_MB`.

## Uso

```bash
sudo guardian --safe       # solo diagnóstico, sin cambios
sudo guardian --dry-run    # simula
sudo guardian --estado     # resumen del último chequeo
guardian --help
```

## Actualizaciones firmadas

`guardian-actualizar` instala solo un bundle **firmado** (ed25519, `ssh-keygen -Y`,
espacio de nombres `guardian-bundle`). La llave pública va fijada dentro del script;
la que trae el bundle no se usa. Los pasos, en orden:

1. Verifica la firma.
2. Extrae el bundle sin ejecutarlo.
3. Comprueba el manifiesto.
4. Comprueba que la versión sea más nueva (nunca instala una más vieja).
5. Pasa todas las pruebas como usuario sin privilegios.
6. Recién entonces instala.

```bash
sudo guardian-actualizar guardian-vX.Y.Z-bundle.sh   # con el .sig al lado
```

La llave pública está en `guardian-firma.pub`.

## Pruebas

En `tests/` hay 23 suites que corren sin root sobre imágenes en archivos (loop).
Simulan cada familia: initramfs-tools, mkinitcpio, dracut con y sin systemd,
mkinitfs, NixOS, MiniOS, subvolúmenes btrfs, `/boot` aparte, UKI, systemd-boot,
rpm y el actualizador firmado.

## Archivos

```
bin/guardian               fase tardía
bin/guardian-early         fase early (initramfs)
bin/guardian-actualizar    actualizador firmado
bin/install-guardian       instalador Debian/Ubuntu/Arch
bin/instalar-*             instaladores por familia
nixos/guardian.nix         módulo de NixOS
tests/                     pruebas
MANIFIESTO.sha256          sumas de bin/, tests/ y nixos/
```

## Licencia

GPL-3.0. Ver `LICENSE`.
