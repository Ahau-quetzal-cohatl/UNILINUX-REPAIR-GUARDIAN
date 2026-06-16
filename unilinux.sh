#!/bin/bash
# ==============================================
# ╔═══════════════════════════════════════════════╗
# ║  UniLinux Reparador v2.1 INTELIGENTE          ║
# ║  Creado por: Ahau Quetzalcóatl                ║
# ║  Sistema de autoreparación universal           ║
# ║  Licencia: GPL v3                              ║
# ╚═══════════════════════════════════════════════╝
# ==============================================
#
# FILOSOFÍA v2.1:
#   PRIMERO diagnostica, LUEGO decide.
#   Si todo está bien → NO TOCA NADA.
#   Si hay problema → REPARA solo lo necesario.
#
# DISEÑADO PARA: Personas con discapacidad motriz
#   - 100% automático, sin intervención
#   - Se ejecuta al arrancar
#   - Si tu PC colapsa, se repara sola
#
# SEGURIDAD:
#   - NUNCA ejecuta fsck en particiones montadas
#   - Solo repara si detecta un problema real
#   - Cooldown anti-loop (5 min entre ejecuciones)
#   - Soporte NVMe/eMMC/SATA
#   - Multi-distro (apt/dnf/pacman/zypper)
#   - Cleanup automático si se interrumpe
#
# ==============================================

set -uo pipefail

# --- VERSIÓN ---
readonly VERSION="2.1"
readonly SCRIPT_NAME="UniLinux Reparador"
readonly LOCKFILE="/tmp/unilinux_reparador.lock"
readonly COOLDOWN_FILE="/var/tmp/unilinux_last_run"
readonly COOLDOWN_SECONDS=300

# --- OBTENER DIRECTORIO DEL SCRIPT ---
SCRIPT_REAL_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")")" && pwd)"

# --- OPCIONES ---
DRY_RUN=false
NO_REBOOT=false
VERBOSE=false
SKIP_FSCK=false
FORCE=false
MUSICA_ENABLED=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)     DRY_RUN=true; shift ;;
        --no-reboot)   NO_REBOOT=true; shift ;;
        --verbose|-v)  VERBOSE=true; shift ;;
        --skip-fsck)   SKIP_FSCK=true; shift ;;
        --force|-f)    FORCE=true; shift ;;
        --no-music)    MUSICA_ENABLED=false; shift ;;
        --version)     echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
        --help|-h)
            cat <<HELP
$SCRIPT_NAME v$VERSION - Sistema de autoreparación INTELIGENTE para Linux
Creado por: Ahau Quetzalcóatl
Diseñado para personas con discapacidad motriz.

CÓMO FUNCIONA:
  1. Diagnostica el sistema
  2. Si todo está bien → no toca nada
  3. Si hay problema → repara solo lo necesario

Uso: sudo $0 [opciones]

Opciones:
  --dry-run       Simular sin hacer cambios
  --no-reboot     No reiniciar al finalizar
  --skip-fsck     Saltar verificación de disco
  --force, -f     Ignorar cooldown y lockfile
  --no-music      Sin música ambiental
  --verbose, -v   Información detallada
  --version       Mostrar versión
  --help, -h      Mostrar esta ayuda

Ejemplos:
  sudo $0                    # Automático: diagnostica y repara si es necesario
  sudo $0 --dry-run -v      # Simulación con detalles
  sudo $0 --no-reboot       # Sin reinicio al final
HELP
            exit 0
            ;;
        *)
            echo "Opción desconocida: $1 (usa --help)"
            exit 1
            ;;
    esac
done

# --- CONFIGURACIÓN ---
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/unilinux_reparador.log"
MOUNT_POINT="/mnt/unilinux_repair"
PARTICIONES_MONTADAS=()

# Contadores de problemas detectados
PROBLEMAS_DETECTADOS=0
REPARACIONES_HECHAS=0
declare -a PROBLEMAS_LISTA=()
declare -a REPARACIONES_LISTA=()

# --- VERIFICAR ROOT ---
if [[ $EUID -ne 0 ]]; then
    echo "❌ ERROR: Este script debe ejecutarse como root."
    echo "   Usa: sudo $0"
    exit 1
fi

# --- LOCKFILE ---
if [[ -f "$LOCKFILE" ]] && [[ "$FORCE" == false ]]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "⚠️  Ya hay una instancia ejecutándose (PID $LOCK_PID)."
        exit 0
    else
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"

# --- COOLDOWN ---
if [[ -f "$COOLDOWN_FILE" ]] && [[ "$FORCE" == false ]]; then
    LAST_RUN=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_RUN))
    if [[ $DIFF -lt $COOLDOWN_SECONDS ]]; then
        rm -f "$LOCKFILE"
        exit 0
    fi
fi

# --- DIRECTORIOS ---
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_FILE="/tmp/unilinux_reparador.log"
mkdir -p "$MOUNT_POINT" 2>/dev/null || true

# --- CARGAR MÚSICA ---
MUSICA_MODULE="${SCRIPT_REAL_DIR}/music/unilinux_music.sh"
if [[ ! -f "$MUSICA_MODULE" ]]; then
    MUSICA_MODULE="${SCRIPT_REAL_DIR}/unilinux_music.sh"
fi
if [[ -f "$MUSICA_MODULE" ]]; then
    source "$MUSICA_MODULE"
else
    musica_iniciar() { return 0; }
    musica_detener() { return 0; }
    MUSICA_ENABLED=false
fi

# --- IDIOMA ---
detectar_idioma() {
    local lang_var="${LANG:-${LANGUAGE:-es}}"
    local idioma
    idioma=$(echo "$lang_var" | cut -d'_' -f1 | cut -d'.' -f1 | cut -d':' -f1 | tr '[:upper:]' '[:lower:]')
    case "$idioma" in
        es) echo "es" ;; en) echo "en" ;; fr) echo "fr" ;;
        de) echo "de" ;; it) echo "it" ;; pt) echo "pt" ;;
        *) echo "es" ;;
    esac
}
IDIOMA=$(detectar_idioma)

# --- MENSAJES ---
declare -A MSG
case $IDIOMA in
    "es")
        MSG[inicio]="Iniciando UniLinux Reparador v${VERSION}"
        MSG[diagnosticando]="Diagnosticando sistema..."
        MSG[todo_bien]="SISTEMA SANO — No se necesita reparación"
        MSG[problemas]="Problemas detectados — Iniciando reparación"
        MSG[reparando]="Reparando"
        MSG[exito]="REPARACIÓN COMPLETADA CON ÉXITO"
        MSG[sin_cambios]="No se hicieron cambios — Todo está bien"
        MSG[reinicio]="El sistema se reiniciará en"
        MSG[seg]="segundos"
        MSG[creador]="creado por: Ahau Quetzalcóatl"
        ;;
    "en")
        MSG[inicio]="Starting UniLinux Reparador v${VERSION}"
        MSG[diagnosticando]="Diagnosing system..."
        MSG[todo_bien]="SYSTEM HEALTHY — No repair needed"
        MSG[problemas]="Problems detected — Starting repair"
        MSG[reparando]="Repairing"
        MSG[exito]="REPAIR COMPLETED SUCCESSFULLY"
        MSG[sin_cambios]="No changes made — Everything is fine"
        MSG[reinicio]="System will reboot in"
        MSG[seg]="seconds"
        MSG[creador]="created by: Ahau Quetzalcóatl"
        ;;
    *)
        MSG[inicio]="Iniciando UniLinux Reparador v${VERSION}"
        MSG[diagnosticando]="Diagnosticando sistema..."
        MSG[todo_bien]="SISTEMA SANO — No se necesita reparación"
        MSG[problemas]="Problemas detectados — Iniciando reparación"
        MSG[reparando]="Reparando"
        MSG[exito]="REPARACIÓN COMPLETADA CON ÉXITO"
        MSG[sin_cambios]="No se hicieron cambios — Todo está bien"
        MSG[reinicio]="El sistema se reiniciará en"
        MSG[seg]="segundos"
        MSG[creador]="creado por: Ahau Quetzalcóatl"
        ;;
esac

# --- COLORES ---
if [[ -t 1 ]]; then
    readonly VERDE='\033[0;32m' AMARILLO='\033[1;33m' ROJO='\033[0;31m'
    readonly AZUL='\033[0;34m' MAGENTA='\033[0;35m' CYAN='\033[0;36m'
    readonly BLANCO='\033[1;37m' NEGRO='\033[0;30m'
    readonly FONDO_AMARILLO='\033[43m' FONDO_VERDE='\033[42m' NC='\033[0m'
else
    readonly VERDE='' AMARILLO='' ROJO='' AZUL='' MAGENTA='' CYAN=''
    readonly BLANCO='' NEGRO='' FONDO_AMARILLO='' FONDO_VERDE='' NC=''
fi

# --- FUNCIONES BASE ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
    [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[LOG]${NC} $1"
}

ESPEAK_PID=""
hablar() {
    local mensaje="$1" nivel="${2:-info}"
    case $nivel in
        "info")    echo -e "${AZUL}[INFO]${NC} $mensaje" ;;
        "ok")      echo -e "${VERDE}[ OK ]${NC} $mensaje" ;;
        "error")   echo -e "${ROJO}[ERR!]${NC} $mensaje" ;;
        "warn")    echo -e "${AMARILLO}[WARN]${NC} $mensaje" ;;
        "paso")    echo -e "${MAGENTA}[>>>>]${NC} $mensaje" ;;
        "fix")     echo -e "${VERDE}[FIX ]${NC} $mensaje" ;;
        *)         echo -e "[----] $mensaje" ;;
    esac
    log "[$nivel] $mensaje"

    [[ -n "$ESPEAK_PID" ]] && wait "$ESPEAK_PID" 2>/dev/null || true
    if command -v espeak &>/dev/null; then
        espeak -v "${IDIOMA}+m1" -s 150 "$mensaje" 2>/dev/null &
        ESPEAK_PID=$!
    elif command -v espeak-ng &>/dev/null; then
        espeak-ng -v "${IDIOMA}" -s 150 "$mensaje" 2>/dev/null &
        ESPEAK_PID=$!
    fi
}

registrar_problema() {
    PROBLEMAS_DETECTADOS=$((PROBLEMAS_DETECTADOS + 1))
    PROBLEMAS_LISTA+=("$1")
    hablar "⚠️  Problema: $1" "warn"
}

registrar_reparacion() {
    REPARACIONES_HECHAS=$((REPARACIONES_HECHAS + 1))
    REPARACIONES_LISTA+=("$1")
    hablar "🔧 Reparado: $1" "fix"
}

ejecutar() {
    local desc="$1"; shift
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] $desc: $*"
        echo -e "  ${CYAN}[DRY-RUN]${NC} $*"
        return 0
    else
        log "[EXEC] $desc: $*"
        "$@" >> "$LOG_FILE" 2>&1
        return $?
    fi
}

centrar() {
    local texto="$1"
    local ancho=$(tput cols 2>/dev/null || echo 80)
    local limpio=$(echo -e "$texto" | sed 's/\x1b\[[0-9;]*m//g')
    local espacios=$(( (ancho - ${#limpio}) / 2 ))
    [[ $espacios -lt 0 ]] && espacios=0
    printf "%${espacios}s" ""; echo -e "$texto"
}

# --- CLEANUP ---
cleanup() {
    local exit_code=$?
    musica_detener 2>/dev/null || true
    [[ -n "${ESPEAK_PID:-}" ]] && wait "$ESPEAK_PID" 2>/dev/null || true

    for ((i=${#PARTICIONES_MONTADAS[@]}-1; i>=0; i--)); do
        umount "${PARTICIONES_MONTADAS[$i]}" 2>/dev/null || true
    done
    for DIR in dev/pts dev proc sys run; do
        umount "${MOUNT_POINT}/${DIR}" 2>/dev/null || true
    done
    umount -R "$MOUNT_POINT" 2>/dev/null || true

    rm -f "$LOCKFILE" /tmp/unilinux_disco_info.txt 2>/dev/null || true
    [[ $exit_code -ne 0 ]] && log "=== INTERRUMPIDO (código: $exit_code) ==="
    exit $exit_code
}
trap cleanup EXIT INT TERM HUP

# --- FUNCIONES DE DETECCIÓN ---
esta_montada() { mount | grep -q "^${1} "; }

detectar_firmware() {
    if [[ -d "/sys/firmware/efi" ]]; then
        local fw_size=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "")
        case "$fw_size" in
            64) echo "UEFI_64" ;; 32) echo "UEFI_32" ;; *) echo "UEFI" ;;
        esac
    else
        echo "LEGACY"
    fi
}

obtener_disco_base() {
    local p="$1"
    if [[ "$p" =~ ^/dev/nvme[0-9]+n[0-9]+p[0-9]+$ ]]; then echo "${p%p[0-9]*}"; return; fi
    if [[ "$p" =~ ^/dev/mmcblk[0-9]+p[0-9]+$ ]]; then echo "${p%p[0-9]*}"; return; fi
    if [[ "$p" =~ ^/dev/[shv]d[a-z]+[0-9]+$ ]]; then echo "${p%%[0-9]*}"; return; fi
    local parent=$(lsblk -no PKNAME "$p" 2>/dev/null | head -1)
    [[ -n "$parent" ]] && echo "/dev/$parent" || echo "${p%%[0-9]*}"
}

detectar_gestor() {
    local r="$1"
    [[ -f "${r}/usr/bin/apt-get" || -f "${r}/usr/bin/apt" ]] && echo "apt" && return
    [[ -f "${r}/usr/bin/dnf" ]] && echo "dnf" && return
    [[ -f "${r}/usr/bin/yum" ]] && echo "yum" && return
    [[ -f "${r}/usr/bin/pacman" ]] && echo "pacman" && return
    [[ -f "${r}/usr/bin/zypper" ]] && echo "zypper" && return
    echo "desconocido"
}

es_raiz_linux() {
    local m="$1"
    [[ -d "${m}/bin" || -d "${m}/usr/bin" ]] && [[ -d "${m}/etc" ]] && \
    [[ -d "${m}/var" ]] && [[ -d "${m}/usr" ]]
}

# ==============================================
#  FASE 1: DIAGNÓSTICO (solo lectura)
# ==============================================

diagnosticar_filesystems() {
    hablar "Verificando estado de filesystems..." "paso"

    for PART in $(lsblk -ln -o NAME,TYPE 2>/dev/null | awk '$2=="part"{print "/dev/"$1}'); do
        local fstype=$(lsblk -no FSTYPE "$PART" 2>/dev/null | head -1)
        [[ -z "$fstype" || "$fstype" == "swap" || "$fstype" == "vfat" || "$fstype" == "exfat" ]] && continue

        if [[ "$fstype" =~ ^ext ]]; then
            local fs_state=$(tune2fs -l "$PART" 2>/dev/null | grep "Filesystem state" | cut -d':' -f2 | xargs || echo "")
            if [[ -n "$fs_state" && "$fs_state" != "clean" ]]; then
                registrar_problema "Filesystem $PART ($fstype) estado: $fs_state"
                FSCK_NEEDED+=("$PART")
            else
                hablar "$PART ($fstype): LIMPIO ✨" "ok"
            fi
        fi
    done
}

diagnosticar_grub() {
    hablar "Verificando GRUB..." "paso"

    if [[ ! -f /boot/grub/grub.cfg ]] && [[ ! -f /boot/grub2/grub.cfg ]]; then
        registrar_problema "GRUB: No se encontró grub.cfg"
        GRUB_REPARAR=true
    else
        hablar "GRUB: Configuración OK" "ok"
        GRUB_REPARAR=false
    fi

    if ! command -v grub-install &>/dev/null && ! command -v grub2-install &>/dev/null; then
        registrar_problema "GRUB: grub-install no encontrado"
        GRUB_REPARAR=true
    fi
}

diagnosticar_paquetes() {
    hablar "Verificando paquetes..." "paso"

    if command -v dpkg &>/dev/null; then
        local broken=$(dpkg --audit 2>/dev/null | wc -l || echo 0)
        broken=$(echo "$broken" | tr -d '[:space:]')
        if [[ "$broken" -gt 0 ]]; then
            registrar_problema "Paquetes rotos detectados: $broken"
            PAQUETES_REPARAR=true
        else
            hablar "Paquetes: OK" "ok"
            PAQUETES_REPARAR=false
        fi
    else
        PAQUETES_REPARAR=false
    fi
}

diagnosticar_red() {
    hablar "Verificando red..." "paso"

    if ping -c 1 -W 3 8.8.8.8 &>/dev/null || ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        hablar "Internet: Conectado" "ok"
        INTERNET=true
    else
        # Intentar activar interfaces
        local activada=false
        for IFACE in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
            local state=$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null || echo "down")
            if [[ "$state" == "down" ]]; then
                ip link set "$IFACE" up 2>/dev/null || true
                activada=true
            fi
        done

        if [[ "$activada" == true ]]; then
            # Intentar DHCP
            if command -v dhclient &>/dev/null; then
                for IFACE in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
                    timeout 10 dhclient -v "$IFACE" >> "$LOG_FILE" 2>&1 || true
                done
            elif command -v dhcpcd &>/dev/null; then
                for IFACE in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
                    timeout 10 dhcpcd "$IFACE" >> "$LOG_FILE" 2>&1 || true
                done
            fi
            sleep 3

            if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
                hablar "Internet: Conectado (después de activar interfaz)" "ok"
                registrar_reparacion "Red activada automáticamente"
                INTERNET=true
            else
                hablar "Internet: Sin conexión" "warn"
                INTERNET=false
            fi
        else
            hablar "Internet: Sin conexión" "warn"
            INTERNET=false
        fi
    fi
}

diagnosticar_servicios() {
    hablar "Verificando servicios..." "paso"

    if command -v systemctl &>/dev/null; then
        local failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l || echo 0)
        failed=$(echo "$failed" | tr -d '[:space:]')
        if [[ "$failed" -gt 0 ]]; then
            hablar "Servicios fallidos: $failed (no crítico)" "warn"
        else
            hablar "Servicios: Todos OK" "ok"
        fi
    fi
}

diagnosticar_espacio() {
    hablar "Verificando espacio en disco..." "paso"

    df -h --output=source,pcent,target 2>/dev/null | grep "^/dev" | while IFS= read -r line; do
        local pct=$(echo "$line" | awk '{print $2}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $3}')
        if [[ "$pct" -gt 95 ]]; then
            registrar_problema "Disco $mount al ${pct}% — ¡CASI LLENO!"
        elif [[ "$pct" -gt 90 ]]; then
            hablar "Disco $mount al ${pct}% — Espacio bajo" "warn"
        else
            hablar "Disco $mount al ${pct}% — OK" "ok"
        fi
    done
}

# ==============================================
#  FASE 2: REPARACIÓN (solo si hay problemas)
# ==============================================

reparar_filesystems() {
    if [[ ${#FSCK_NEEDED[@]} -eq 0 ]]; then
        return
    fi

    hablar "${MSG[reparando]} filesystems..." "paso"

    for PART in "${FSCK_NEEDED[@]}"; do
        if esta_montada "$PART"; then
            hablar "Saltando $PART (montada — se reparará en el próximo arranque)" "warn"
            continue
        fi

        local fstype=$(lsblk -no FSTYPE "$PART" 2>/dev/null | head -1)
        hablar "Reparando $PART ($fstype)..." "info"

        case "$fstype" in
            ext2|ext3|ext4)
                ejecutar "fsck $PART" e2fsck -y -f "$PART" && registrar_reparacion "Filesystem $PART reparado" || true
                ;;
            xfs)
                ejecutar "xfs_repair $PART" xfs_repair "$PART" && registrar_reparacion "Filesystem $PART reparado" || true
                ;;
            btrfs)
                ejecutar "btrfs $PART" btrfs check --repair "$PART" && registrar_reparacion "Filesystem $PART reparado" || true
                ;;
            *)
                ejecutar "fsck $PART" fsck -y "$PART" && registrar_reparacion "Filesystem $PART reparado" || true
                ;;
        esac
    done
}

reparar_grub() {
    if [[ "$GRUB_REPARAR" != true ]]; then
        return
    fi

    hablar "${MSG[reparando]} GRUB..." "paso"

    local root_part=""
    for PART in $(lsblk -ln -o NAME,TYPE 2>/dev/null | awk '$2=="part"{print "/dev/"$1}'); do
        if esta_montada "$PART"; then continue; fi
        if mount -o ro "$PART" "$MOUNT_POINT" 2>/dev/null; then
            if es_raiz_linux "$MOUNT_POINT"; then
                root_part="$PART"
                umount "$MOUNT_POINT" 2>/dev/null
                break
            fi
            umount "$MOUNT_POINT" 2>/dev/null
        fi
    done

    # Si no encontramos una raíz desmontada, usar la actual
    if [[ -z "$root_part" ]]; then
        root_part=$(df / 2>/dev/null | tail -1 | awk '{print $1}')
    fi

    if [[ -z "$root_part" ]]; then
        hablar "No se pudo encontrar partición raíz para GRUB" "error"
        return
    fi

    local disco=$(obtener_disco_base "$root_part")
    local firmware=$(detectar_firmware)

    # Montar para chroot
    ejecutar "Montar raíz" mount "$root_part" "$MOUNT_POINT" || return
    PARTICIONES_MONTADAS+=("$MOUNT_POINT")

    # Buscar y montar EFI
    for EPART in $(lsblk -ln -o NAME,FSTYPE 2>/dev/null | awk '$2=="vfat"{print "/dev/"$1}'); do
        if ! esta_montada "$EPART"; then
            mkdir -p "${MOUNT_POINT}/boot/efi" 2>/dev/null
            mount "$EPART" "${MOUNT_POINT}/boot/efi" 2>/dev/null && break
        fi
    done

    # Bind mounts
    for DIR in dev proc sys run; do
        [[ -d "/${DIR}" ]] && mkdir -p "${MOUNT_POINT}/${DIR}" 2>/dev/null && \
            mount --bind "/${DIR}" "${MOUNT_POINT}/${DIR}" 2>/dev/null || true
    done
    [[ -d /dev/pts ]] && mkdir -p "${MOUNT_POINT}/dev/pts" 2>/dev/null && \
        mount --bind /dev/pts "${MOUNT_POINT}/dev/pts" 2>/dev/null || true

    # DNS
    [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf" 2>/dev/null || true

    local gestor=$(detectar_gestor "$MOUNT_POINT")
    local grub_cmd="grub-install"
    local update_cmd="update-grub"
    [[ -f "${MOUNT_POINT}/usr/sbin/grub2-install" ]] && grub_cmd="grub2-install" && update_cmd="grub2-mkconfig -o /boot/grub2/grub.cfg"

    case "$firmware" in
        UEFI_64|UEFI)
            ejecutar "GRUB UEFI" chroot "$MOUNT_POINT" /bin/bash -c \
                "$grub_cmd --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck 2>&1" || true
            ;;
        UEFI_32)
            ejecutar "GRUB UEFI 32" chroot "$MOUNT_POINT" /bin/bash -c \
                "$grub_cmd --target=i386-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck 2>&1" || true
            ;;
        LEGACY)
            ejecutar "GRUB Legacy" chroot "$MOUNT_POINT" /bin/bash -c \
                "$grub_cmd --target=i386-pc --recheck '$disco' 2>&1" || true
            ;;
    esac

    ejecutar "Update GRUB" chroot "$MOUNT_POINT" /bin/bash -c "$update_cmd 2>&1" || true
    registrar_reparacion "GRUB reinstalado"
}

reparar_paquetes() {
    if [[ "$PAQUETES_REPARAR" != true ]]; then
        return
    fi

    hablar "${MSG[reparando]} paquetes..." "paso"

    if command -v dpkg &>/dev/null; then
        ejecutar "dpkg configure" dpkg --configure -a && registrar_reparacion "dpkg --configure -a" || true
        ejecutar "apt fix" apt-get install -f -y && registrar_reparacion "apt-get install -f" || true
    elif command -v dnf &>/dev/null; then
        ejecutar "dnf check" dnf check && registrar_reparacion "dnf check" || true
    elif command -v pacman &>/dev/null; then
        ejecutar "pacman repair" pacman -Syyu --noconfirm && registrar_reparacion "pacman -Syyu" || true
    fi
}

# ==============================================
#  PROGRAMA PRINCIPAL
# ==============================================

clear 2>/dev/null || true
echo ""
centrar "${FONDO_AMARILLO}${NEGRO}╔══════════════════════════════════════════════════╗${NC}"
centrar "${FONDO_AMARILLO}${NEGRO}║     ◈◈◈  UniLinux Reparador v${VERSION}  ◈◈◈        ║${NC}"
centrar "${FONDO_AMARILLO}${NEGRO}║     ${MSG[creador]}                ║${NC}"
centrar "${FONDO_AMARILLO}${NEGRO}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    centrar "${AMARILLO}>>> MODO SIMULACIÓN — No se harán cambios <<<${NC}"
    echo ""
fi

# Iniciar música
[[ "$MUSICA_ENABLED" == true ]] && musica_iniciar 2>/dev/null || true

hablar "${MSG[inicio]}" "paso"
log "=== INICIO v${VERSION} ==="

# Variables para reparaciones
declare -a FSCK_NEEDED=()
GRUB_REPARAR=false
PAQUETES_REPARAR=false
INTERNET=false

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FASE 1: DIAGNÓSTICO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
hablar "━━━━━ FASE 1: DIAGNÓSTICO ━━━━━" "paso"
echo ""

FIRMWARE_TIPO=$(detectar_firmware)
hablar "Firmware: $FIRMWARE_TIPO" "ok"

# Hardware básico
PROCESADOR=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs || echo "N/A")
MEMORIA=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "N/A")
hablar "CPU: $PROCESADOR" "info"
hablar "RAM: $MEMORIA" "info"

# Diagnósticos
[[ "$SKIP_FSCK" == false ]] && diagnosticar_filesystems || hablar "fsck saltado por --skip-fsck" "warn"
diagnosticar_grub
diagnosticar_paquetes
diagnosticar_red
diagnosticar_servicios
diagnosticar_espacio

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DECISIÓN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""

if [[ $PROBLEMAS_DETECTADOS -eq 0 ]]; then
    # ¡TODO BIEN! No tocar nada.
    hablar "━━━━━ RESULTADO ━━━━━" "paso"
    echo ""
    echo -e "  ${FONDO_VERDE}${NEGRO}                                              ${NC}"
    echo -e "  ${FONDO_VERDE}${NEGRO}   🟢  ${MSG[todo_bien]}   ${NC}"
    echo -e "  ${FONDO_VERDE}${NEGRO}                                              ${NC}"
    echo ""
    hablar "${MSG[sin_cambios]}" "ok"

else
    # HAY PROBLEMAS → REPARAR
    hablar "━━━━━ FASE 2: REPARACIÓN ━━━━━" "paso"
    echo ""
    hablar "${MSG[problemas]}: $PROBLEMAS_DETECTADOS problema(s)" "warn"
    echo ""

    for p in "${PROBLEMAS_LISTA[@]}"; do
        hablar "  → $p" "warn"
    done
    echo ""

    # Ejecutar reparaciones
    reparar_filesystems
    reparar_grub
    reparar_paquetes

    echo ""
    hablar "━━━━━ RESULTADO ━━━━━" "paso"
    echo ""

    if [[ $REPARACIONES_HECHAS -gt 0 ]]; then
        echo -e "  ${FONDO_VERDE}${NEGRO}                                              ${NC}"
        echo -e "  ${FONDO_VERDE}${NEGRO}   ✅  ${MSG[exito]}                ${NC}"
        echo -e "  ${FONDO_VERDE}${NEGRO}                                              ${NC}"
        echo ""
        hablar "Reparaciones realizadas: $REPARACIONES_HECHAS" "ok"
        for r in "${REPARACIONES_LISTA[@]}"; do
            hablar "  ✓ $r" "fix"
        done
    else
        hablar "Se detectaron problemas pero no se pudieron reparar automáticamente" "warn"
        hablar "Revisa el log: $LOG_FILE" "info"
    fi
fi

# Detener música
musica_detener 2>/dev/null || true

# Guardar cooldown
date +%s > "$COOLDOWN_FILE" 2>/dev/null || true

# Guardar log
LOG_DEST="/var/log/unilinux_$(date +%Y%m%d_%H%M%S).log"
cp "$LOG_FILE" "$LOG_DEST" 2>/dev/null || true

echo ""
log "=== FIN: Problemas=$PROBLEMAS_DETECTADOS Reparaciones=$REPARACIONES_HECHAS ==="

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# REINICIO (solo si se reparó algo)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ $REPARACIONES_HECHAS -gt 0 ]]; then
    # Se reparó algo → reiniciar para aplicar cambios
    if [[ "$DRY_RUN" == true ]]; then
        hablar "Modo simulación: no se reiniciará" "warn"
    elif [[ "$NO_REBOOT" == true ]]; then
        hablar "Opción --no-reboot: no se reiniciará" "warn"
    else
        COUNTDOWN=15
        hablar "${MSG[reinicio]} $COUNTDOWN ${MSG[seg]}" "warn"
        echo ""
        for ((i=COUNTDOWN; i>0; i--)); do
            printf "\r  ⏱️  Reiniciando en %2d ${MSG[seg]}... (Ctrl+C para cancelar)" "$i"
            sleep 1
        done
        echo ""
        reboot
    fi
else
    # No se reparó nada → NO reiniciar
    hablar "Sistema sano — continuando arranque normal" "ok"
fi

echo ""
