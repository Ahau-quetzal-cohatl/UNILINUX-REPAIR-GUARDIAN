#!/bin/bash
# ==============================================
# UniLinux Reparador - Instalador v2.0
# Creado por: Ahau Quetzalcóatl
# ==============================================

set -euo pipefail

readonly VERSION="2.0"
readonly SCRIPT_NAME="unilinux.sh"
readonly INSTALL_DIR="/usr/local/sbin"
readonly INITRAMFS_HOOK="/etc/initramfs-tools/hooks/unilinux"
readonly INITRAMFS_SCRIPT="/etc/initramfs-tools/scripts/local-premount/unilinux"
readonly SYSTEMD_SERVICE="/etc/systemd/system/unilinux-reparador.service"

# Colores
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

msg_ok()   { echo -e "${VERDE}[OK]${NC}   $1"; }
msg_err()  { echo -e "${ROJO}[ERR]${NC}  $1"; }
msg_warn() { echo -e "${AMARILLO}[WARN]${NC} $1"; }
msg_info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# Verificar root
if [[ $EUID -ne 0 ]]; then
    msg_err "Este instalador debe ejecutarse como root."
    echo "   Usa: sudo $0"
    exit 1
fi

# Verificar que existe el script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/${SCRIPT_NAME}" ]]; then
    msg_err "No se encontró ${SCRIPT_NAME} en ${SCRIPT_DIR}"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║    UniLinux Reparador v${VERSION} - Instalador        ║"
echo "║    Creado por: Ahau Quetzalcóatl                ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# --- 1. Instalar script principal ---
msg_info "Instalando script principal..."
cp "${SCRIPT_DIR}/${SCRIPT_NAME}" "${INSTALL_DIR}/unilinux"
chmod 755 "${INSTALL_DIR}/unilinux"
msg_ok "Script instalado en ${INSTALL_DIR}/unilinux"

# --- 2. Crear enlace simbólico ---
if [[ ! -L "/usr/local/bin/unilinux" ]]; then
    ln -sf "${INSTALL_DIR}/unilinux" "/usr/local/bin/unilinux"
    msg_ok "Enlace creado: /usr/local/bin/unilinux"
fi

# --- 3. Preguntar modo de instalación ---
echo ""
msg_info "Modos de instalación disponibles:"
echo "  1) Solo manual     - Ejecutar con: sudo unilinux"
echo "  2) Servicio systemd - Se ejecuta al arrancar"
echo "  3) Initramfs hook   - Se ejecuta ANTES del arranque (Debian/Ubuntu)"
echo "  4) Ambos (2 + 3)    - Máxima protección"
echo ""
read -r -p "Selecciona modo [1-4] (default: 1): " MODO
MODO=${MODO:-1}

case "$MODO" in
    2|4)
        # --- Crear servicio systemd ---
        msg_info "Creando servicio systemd..."
        cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=UniLinux Reparador - Sistema de autoreparación universal
After=local-fs.target
Before=network.target
DefaultDependencies=no
ConditionPathExists=!/var/tmp/unilinux_skip_boot

[Service]
Type=oneshot
ExecStart=${INSTALL_DIR}/unilinux --no-reboot
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=300

[Install]
WantedBy=sysinit.target
EOF
        systemctl daemon-reload
        systemctl enable unilinux-reparador.service
        msg_ok "Servicio systemd creado y habilitado"
        msg_info "Para deshabilitar: sudo systemctl disable unilinux-reparador.service"
        msg_info "Para saltar un arranque: touch /var/tmp/unilinux_skip_boot"
        ;;&  # fallthrough para opción 4

    3|4)
        # --- Crear hook de initramfs (solo Debian/Ubuntu) ---
        if [[ -d /etc/initramfs-tools ]]; then
            msg_info "Creando hook de initramfs..."

            # Hook para incluir archivos necesarios
            cat > "$INITRAMFS_HOOK" <<'EOF'
#!/bin/sh
set -e
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in
    prereqs) prereqs; exit 0 ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Copiar herramientas necesarias
for tool in fsck e2fsck fsck.ext4 fsck.vfat lsblk blkid; do
    if [ -x "$(command -v $tool)" ]; then
        copy_exec "$(command -v $tool)"
    fi
done
EOF
            chmod 755 "$INITRAMFS_HOOK"

            # Script de premount
            cat > "$INITRAMFS_SCRIPT" <<'SCRIPT'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in
    prereqs) prereqs; exit 0 ;;
esac

# Verificación rápida de filesystem raíz
if [ -n "$ROOT" ]; then
    log_begin_msg "UniLinux: Verificando filesystem raíz"
    fsck -y "$ROOT" 2>/dev/null || true
    log_end_msg $?
fi
SCRIPT
            chmod 755 "$INITRAMFS_SCRIPT"

            # Regenerar initramfs
            msg_info "Regenerando initramfs (puede tardar)..."
            update-initramfs -u
            msg_ok "Hook de initramfs instalado"
        else
            msg_warn "initramfs-tools no encontrado. Hook no instalado."
        fi
        ;;

    1)
        msg_ok "Modo manual instalado. Usa: sudo unilinux"
        ;;
    *)
        msg_warn "Opción no válida. Instalando modo manual."
        ;;
esac

# --- 4. Instalar dependencias opcionales ---
echo ""
msg_info "Verificando dependencias..."

DEPS_FALTANTES=""
for dep in espeak lspci lsblk fsck blkid; do
    if ! command -v "$dep" &>/dev/null; then
        DEPS_FALTANTES="$DEPS_FALTANTES $dep"
    fi
done

if [[ -n "$DEPS_FALTANTES" ]]; then
    msg_warn "Dependencias opcionales faltantes:$DEPS_FALTANTES"
    read -r -p "¿Instalar ahora? [s/N]: " INSTALAR_DEPS
    if [[ "$INSTALAR_DEPS" =~ ^[sS]$ ]]; then
        if command -v apt-get &>/dev/null; then
            apt-get update -qq
            # Mapear comandos a paquetes
            for dep in $DEPS_FALTANTES; do
                case "$dep" in
                    espeak) apt-get install -y espeak 2>/dev/null || true ;;
                    lspci)  apt-get install -y pciutils 2>/dev/null || true ;;
                    lsblk)  apt-get install -y util-linux 2>/dev/null || true ;;
                    fsck)   apt-get install -y e2fsprogs 2>/dev/null || true ;;
                    blkid)  apt-get install -y util-linux 2>/dev/null || true ;;
                esac
            done
        elif command -v dnf &>/dev/null; then
            dnf install -y espeak pciutils util-linux e2fsprogs 2>/dev/null || true
        elif command -v pacman &>/dev/null; then
            pacman -S --noconfirm espeak-ng pciutils util-linux e2fsprogs 2>/dev/null || true
        fi
        msg_ok "Dependencias instaladas"
    fi
fi

# --- 5. Resumen ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
msg_ok "UniLinux Reparador v${VERSION} instalado correctamente"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
msg_info "Comandos disponibles:"
echo "  sudo unilinux              # Reparación completa"
echo "  sudo unilinux --dry-run    # Simulación"
echo "  sudo unilinux --no-reboot  # Sin reiniciar"
echo "  sudo unilinux --help       # Ayuda"
echo ""
msg_info "Para desinstalar:"
echo "  sudo rm -f ${INSTALL_DIR}/unilinux /usr/local/bin/unilinux"
echo "  sudo rm -f ${SYSTEMD_SERVICE}"
echo "  sudo rm -f ${INITRAMFS_HOOK} ${INITRAMFS_SCRIPT}"
echo "  sudo systemctl daemon-reload"
echo ""
