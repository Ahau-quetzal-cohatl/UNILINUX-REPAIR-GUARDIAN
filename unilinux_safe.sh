#!/bin/bash
# ==============================================
# ╔═══════════════════════════════════════════════╗
# ║  UniLinux Reparador v2.0 - MODO SEGURO        ║
# ║  Creado por: Ahau Quetzalcóatl                ║
# ║  Modo: SOLO LECTURA / DIAGNÓSTICO             ║
# ║  Licencia: GPL v3                              ║
# ╚═══════════════════════════════════════════════╝
# ==============================================
#
# ESTE SCRIPT NO MODIFICA ABSOLUTAMENTE NADA.
# Solo analiza, diagnostica e informa.
#
# Garantías:
#   ✅ NO ejecuta fsck
#   ✅ NO monta particiones
#   ✅ NO modifica GRUB
#   ✅ NO instala paquetes
#   ✅ NO hace chroot
#   ✅ NO reinicia
#   ✅ NO escribe en discos
#   ✅ Solo LECTURA de información del sistema
#
# ==============================================

set -euo pipefail

readonly VERSION="2.0-safe"
readonly SCRIPT_NAME="UniLinux Reparador (Modo Seguro)"

# --- OPCIONES ---
VERBOSE=false
GUARDAR_REPORTE=false
REPORTE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)  VERBOSE=true; shift ;;
        --reporte|-r)  GUARDAR_REPORTE=true; shift ;;
        --version)     echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
        --help|-h)
            cat <<HELP
$SCRIPT_NAME v$VERSION
Creado por: Ahau Quetzalcóatl

MODO 100% SEGURO - Solo diagnostica, NO modifica nada.

Uso: sudo $0 [opciones]

Opciones:
  --verbose, -v   Mostrar información detallada
  --reporte, -r   Guardar reporte en archivo
  --version       Mostrar versión
  --help, -h      Mostrar esta ayuda

Ejemplo:
  sudo $0              # Diagnóstico en pantalla
  sudo $0 -v -r        # Diagnóstico detallado + guardar reporte
HELP
            exit 0
            ;;
        *)
            echo "Opción desconocida: $1 (usa --help)"
            exit 1
            ;;
    esac
done

# --- VERIFICAR ROOT (necesario para leer info de discos) ---
if [[ $EUID -ne 0 ]]; then
    echo "⚠️  Algunas funciones requieren root para leer información."
    echo "   Ejecuta: sudo $0"
    echo "   Continuando con información limitada..."
    echo ""
    ES_ROOT=false
else
    ES_ROOT=true
fi

# --- COLORES ---
if [[ -t 1 ]]; then
    VERDE='\033[0;32m'
    AMARILLO='\033[1;33m'
    ROJO='\033[0;31m'
    AZUL='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BLANCO='\033[1;37m'
    NEGRO='\033[0;30m'
    FONDO_AMARILLO='\033[43m'
    FONDO_VERDE='\033[42m'
    FONDO_ROJO='\033[41m'
    NC='\033[0m'
else
    VERDE='' AMARILLO='' ROJO='' AZUL='' MAGENTA='' CYAN=''
    BLANCO='' NEGRO='' FONDO_AMARILLO='' FONDO_VERDE='' FONDO_ROJO='' NC=''
fi

# --- REPORTE ---
REPORTE=""

info()  { echo -e "${AZUL}[INFO]${NC} $1";    REPORTE+="[INFO] $1\n"; }
ok()    { echo -e "${VERDE}[OK]${NC}   $1";    REPORTE+="[OK]   $1\n"; }
warn()  { echo -e "${AMARILLO}[WARN]${NC} $1"; REPORTE+="[WARN] $1\n"; }
error() { echo -e "${ROJO}[ERR]${NC}  $1";     REPORTE+="[ERR]  $1\n"; }
paso()  { echo -e "${MAGENTA}[>>>]${NC} $1";   REPORTE+="[>>>]  $1\n"; }
linea() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; REPORTE+="──────────────────────────────────────────────────\n"; }
salto() { echo ""; REPORTE+="\n"; }

# --- FUNCIONES DE DIAGNÓSTICO (SOLO LECTURA) ---

diagnostico_sistema() {
    paso "INFORMACIÓN DEL SISTEMA"
    linea

    # Hostname
    local hostname
    hostname=$(hostname 2>/dev/null || echo "N/A")
    info "Hostname: $hostname"

    # Distribución
    if [[ -f /etc/os-release ]]; then
        local distro version
        distro=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2)
        info "Distribución: $distro"
    elif [[ -f /etc/debian_version ]]; then
        info "Distribución: Debian $(cat /etc/debian_version)"
    fi

    # Kernel
    info "Kernel: $(uname -r 2>/dev/null || echo 'N/A')"
    info "Arquitectura: $(uname -m 2>/dev/null || echo 'N/A')"

    # Uptime
    local uptime_str
    uptime_str=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A")
    info "Uptime: $uptime_str"

    # Fecha
    info "Fecha: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"

    salto
}

diagnostico_hardware() {
    paso "HARDWARE"
    linea

    # CPU
    local cpu
    cpu=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs || echo "N/A")
    local cores
    cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "N/A")
    info "CPU: $cpu"
    info "Núcleos: $cores"

    # RAM
    local ram_total ram_used ram_free
    ram_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "N/A")
    ram_used=$(free -h 2>/dev/null | awk '/^Mem:/{print $3}' || echo "N/A")
    ram_free=$(free -h 2>/dev/null | awk '/^Mem:/{print $4}' || echo "N/A")
    info "RAM Total: $ram_total"
    info "RAM Usada: $ram_used"
    info "RAM Libre: $ram_free"

    # RAM porcentaje
    local ram_pct
    ram_pct=$(free 2>/dev/null | awk '/^Mem:/{printf "%.0f", ($3/$2)*100}' || echo "0")
    if [[ "$ram_pct" -gt 90 ]]; then
        warn "⚠️  RAM al ${ram_pct}% — Uso muy alto"
    elif [[ "$ram_pct" -gt 70 ]]; then
        warn "RAM al ${ram_pct}% — Uso moderado-alto"
    else
        ok "RAM al ${ram_pct}% — Normal"
    fi

    # Swap
    local swap_total
    swap_total=$(free -h 2>/dev/null | awk '/^Swap:/{print $2}' || echo "N/A")
    info "Swap: $swap_total"

    # Firmware
    if [[ -d "/sys/firmware/efi" ]]; then
        if [[ -f "/sys/firmware/efi/fw_platform_size" ]]; then
            local fw_bits
            fw_bits=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "?")
            ok "Firmware: UEFI ${fw_bits}-bit"
        else
            ok "Firmware: UEFI"
        fi
    else
        info "Firmware: Legacy BIOS"
    fi

    # Temperatura CPU (si está disponible)
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp
        temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [[ -n "$temp" ]]; then
            local temp_c=$((temp / 1000))
            if [[ $temp_c -gt 80 ]]; then
                error "🌡️  Temperatura CPU: ${temp_c}°C — ¡MUY CALIENTE!"
            elif [[ $temp_c -gt 60 ]]; then
                warn "🌡️  Temperatura CPU: ${temp_c}°C — Elevada"
            else
                ok "🌡️  Temperatura CPU: ${temp_c}°C — Normal"
            fi
        fi
    fi

    salto
}

diagnostico_firmware() {
    paso "FIRMWARE / TIPO DE ARRANQUE"
    linea

    # Secure Boot
    if [[ -d "/sys/firmware/efi" ]]; then
        if command -v mokutil &>/dev/null; then
            local sb_state
            sb_state=$(mokutil --sb-state 2>/dev/null || echo "desconocido")
            info "Secure Boot: $sb_state"
        else
            info "Secure Boot: No se puede verificar (falta mokutil)"
        fi
    fi

    # GRUB
    if [[ -f /boot/grub/grub.cfg ]] || [[ -f /boot/grub2/grub.cfg ]]; then
        ok "GRUB: Configuración encontrada"

        # Verificar que el binario existe
        if command -v grub-install &>/dev/null || command -v grub2-install &>/dev/null; then
            ok "GRUB: Binario de instalación disponible"
        else
            warn "GRUB: grub-install no encontrado en PATH"
        fi
    else
        warn "GRUB: No se encontró grub.cfg"
    fi

    # EFI entries
    if command -v efibootmgr &>/dev/null && [[ -d "/sys/firmware/efi" ]]; then
        info "Entradas EFI:"
        efibootmgr 2>/dev/null | while IFS= read -r line; do
            info "  $line"
        done
    fi

    salto
}

diagnostico_discos() {
    paso "DISCOS Y PARTICIONES"
    linea

    # Listar discos
    info "Discos detectados:"
    salto
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,STATE 2>/dev/null | while IFS= read -r line; do
        echo -e "  ${CYAN}$line${NC}"
        REPORTE+="  $line\n"
    done
    salto

    # Espacio en particiones montadas
    paso "ESPACIO EN DISCO"
    df -h --output=source,size,used,avail,pcent,target 2>/dev/null | grep "^/dev" | while IFS= read -r line; do
        local pcent
        pcent=$(echo "$line" | awk '{print $5}' | tr -d '%')
        if [[ "$pcent" -gt 95 ]]; then
            error "💾 $line ← ¡DISCO CASI LLENO!"
        elif [[ "$pcent" -gt 85 ]]; then
            warn "💾 $line ← Espacio bajo"
        else
            ok "💾 $line"
        fi
    done
    salto

    # SMART (salud del disco) — SOLO LECTURA
    if command -v smartctl &>/dev/null && [[ "$ES_ROOT" == true ]]; then
        paso "SALUD DE DISCOS (S.M.A.R.T.)"
        for DISCO in $(lsblk -dno NAME 2>/dev/null); do
            local dev="/dev/$DISCO"
            local smart_health
            smart_health=$(smartctl -H "$dev" 2>/dev/null | grep -i "result\|status" | head -1 || echo "")
            if [[ -n "$smart_health" ]]; then
                if echo "$smart_health" | grep -qi "PASSED\|OK"; then
                    ok "Disco $dev: $smart_health"
                else
                    error "Disco $dev: $smart_health ← ¡REVISAR!"
                fi
            else
                info "Disco $dev: S.M.A.R.T. no disponible"
            fi
        done
        salto
    else
        if ! command -v smartctl &>/dev/null; then
            info "smartctl no instalado (instala: sudo apt install smartmontools)"
        fi
    fi

    # Verificar filesystem SIN reparar (solo estado)
    if [[ "$ES_ROOT" == true ]]; then
        paso "ESTADO DE FILESYSTEMS"
        info "(Solo verificación — NO se repara nada)"
        salto
        for PART in $(lsblk -ln -o NAME,TYPE 2>/dev/null | awk '$2=="part"{print "/dev/"$1}'); do
            local fstype
            fstype=$(lsblk -no FSTYPE "$PART" 2>/dev/null | head -1)
            local mounted
            mounted=$(lsblk -no MOUNTPOINT "$PART" 2>/dev/null | head -1)

            if [[ -z "$fstype" ]]; then
                continue
            fi

            local estado="desconocido"
            if [[ -n "$mounted" ]]; then
                estado="montada en $mounted"
            else
                estado="no montada"
            fi

            # Verificar si tiene errores conocidos (sin tocar el disco)
            if [[ "$fstype" =~ ^ext ]]; then
                local last_check
                last_check=$(tune2fs -l "$PART" 2>/dev/null | grep "Last checked" | cut -d':' -f2- | xargs || echo "")
                local mount_count
                mount_count=$(tune2fs -l "$PART" 2>/dev/null | grep "Mount count" | awk '{print $NF}' || echo "")
                local max_mount
                max_mount=$(tune2fs -l "$PART" 2>/dev/null | grep "Maximum mount count" | awk '{print $NF}' || echo "")
                local fs_state
                fs_state=$(tune2fs -l "$PART" 2>/dev/null | grep "Filesystem state" | cut -d':' -f2 | xargs || echo "")

                if [[ "$fs_state" == "clean" ]]; then
                    ok "$PART ($fstype) — Estado: LIMPIO ✨ [$estado]"
                elif [[ "$fs_state" =~ "error" ]]; then
                    error "$PART ($fstype) — Estado: ERRORES DETECTADOS ⚠️  [$estado]"
                    warn "  → Recomendación: ejecutar 'sudo fsck -n $PART' (verificar sin reparar)"
                else
                    info "$PART ($fstype) — Estado: $fs_state [$estado]"
                fi

                if [[ -n "$last_check" ]]; then
                    [[ "$VERBOSE" == true ]] && info "  Última verificación: $last_check"
                fi
                if [[ -n "$mount_count" ]] && [[ -n "$max_mount" ]] && [[ "$max_mount" != "-1" ]]; then
                    [[ "$VERBOSE" == true ]] && info "  Montajes: $mount_count / $max_mount"
                fi
            else
                info "$PART ($fstype) — [$estado]"
            fi
        done
    fi
    salto
}

diagnostico_red() {
    paso "RED / CONECTIVIDAD"
    linea

    # Interfaces
    for iface in $(ls /sys/class/net/ 2>/dev/null); do
        local state
        state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "desconocido")
        local mac
        mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "N/A")

        if [[ "$iface" == "lo" ]]; then
            continue
        fi

        if [[ "$state" == "up" ]]; then
            ok "Interfaz $iface: ACTIVA (MAC: $mac)"
            # IP
            local ip
            ip=$(ip -4 addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' || echo "sin IP")
            info "  IP: $ip"
        else
            warn "Interfaz $iface: $state (MAC: $mac)"
        fi
    done

    # Conectividad
    salto
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        ok "Internet: Conectado (ping a 8.8.8.8)"
    elif ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        ok "Internet: Conectado (ping a 1.1.1.1)"
    else
        warn "Internet: Sin conexión"
    fi

    # DNS
    if ping -c 1 -W 3 google.com &>/dev/null; then
        ok "DNS: Funcionando"
    else
        warn "DNS: No resuelve nombres"
    fi

    # Gateway
    local gw
    gw=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1 || echo "N/A")
    info "Gateway: $gw"

    salto
}

diagnostico_multimedia() {
    paso "DISPOSITIVOS MULTIMEDIA"
    linea

    # Cámara
    if [[ -e /dev/video0 ]]; then
        ok "Cámara web: Detectada (/dev/video0)"
    else
        info "Cámara web: No detectada"
    fi

    # Audio
    if [[ -d /dev/snd ]]; then
        ok "Audio (ALSA): Detectado"
        if command -v aplay &>/dev/null; then
            local cards
            cards=$(aplay -l 2>/dev/null | grep "^card" | head -3 || echo "N/A")
            [[ "$VERBOSE" == true ]] && info "  Tarjetas: $cards"
        fi
    else
        warn "Audio (ALSA): No detectado"
    fi

    # PulseAudio / PipeWire
    if command -v pactl &>/dev/null; then
        if pactl info &>/dev/null 2>&1; then
            local audio_server
            audio_server=$(pactl info 2>/dev/null | grep "Server Name" | cut -d':' -f2 | xargs || echo "N/A")
            ok "Servidor de audio: $audio_server"
        fi
    fi

    # Bluetooth
    if [[ -d /sys/class/bluetooth ]]; then
        local bt_count
        bt_count=$(ls /sys/class/bluetooth/ 2>/dev/null | wc -l)
        if [[ $bt_count -gt 0 ]]; then
            ok "Bluetooth: $bt_count adaptador(es) detectado(s)"
        fi
    else
        info "Bluetooth: No detectado"
    fi

    # USB
    if command -v lsusb &>/dev/null; then
        local usb_count
        usb_count=$(lsusb 2>/dev/null | wc -l || echo 0)
        info "Dispositivos USB: $usb_count conectados"
        if [[ "$VERBOSE" == true ]]; then
            lsusb 2>/dev/null | while IFS= read -r line; do
                info "  $line"
            done
        fi
    fi

    salto
}

diagnostico_servicios() {
    paso "SERVICIOS Y PAQUETES"
    linea

    # Gestor de paquetes
    if command -v apt &>/dev/null; then
        ok "Gestor de paquetes: apt (Debian/Ubuntu)"

        # Paquetes rotos
        local broken
        broken=$(dpkg --audit 2>/dev/null | wc -l || echo 0)
        if [[ "$broken" -gt 0 ]]; then
            warn "Paquetes con problemas: $broken"
            warn "  → Recomendación: sudo dpkg --configure -a"
        else
            ok "Paquetes: Sin problemas detectados"
        fi

        # Actualizaciones pendientes (sin instalar nada)
        if [[ "$ES_ROOT" == true ]]; then
            local updates
            updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo 0)
            info "Actualizaciones pendientes: ~$updates"
        fi

    elif command -v dnf &>/dev/null; then
        ok "Gestor de paquetes: dnf (Fedora/RHEL)"
    elif command -v pacman &>/dev/null; then
        ok "Gestor de paquetes: pacman (Arch)"
    elif command -v zypper &>/dev/null; then
        ok "Gestor de paquetes: zypper (openSUSE)"
    fi

    # Systemd
    if command -v systemctl &>/dev/null; then
        local failed
        failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l || echo 0)
        if [[ "$failed" -gt 0 ]]; then
            warn "Servicios fallidos: $failed"
            systemctl --failed --no-legend 2>/dev/null | while IFS= read -r line; do
                warn "  ✗ $line"
            done
        else
            ok "Servicios systemd: Todos funcionando"
        fi
    fi

    # Espacio en /boot (importante para kernels)
    local boot_pct
    boot_pct=$(df /boot 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo 0)
    if [[ "$boot_pct" -gt 85 ]]; then
        warn "/boot al ${boot_pct}% — Limpiar kernels antiguos"
        warn "  → Recomendación: sudo apt autoremove"
    else
        ok "/boot al ${boot_pct}% — OK"
    fi

    salto
}

diagnostico_firmware_hw() {
    paso "FIRMWARE DE HARDWARE"
    linea

    if command -v lspci &>/dev/null; then
        # WiFi
        local wifi
        wifi=$(lspci 2>/dev/null | grep -i "network\|wireless\|wifi" || echo "")
        if [[ -n "$wifi" ]]; then
            ok "WiFi detectado:"
            echo "$wifi" | while IFS= read -r line; do
                info "  $line"
            done

            # Verificar si tiene firmware
            if [[ -d /lib/firmware ]]; then
                local fw_count
                fw_count=$(find /lib/firmware -name "*.bin" -o -name "*.fw" -o -name "*.ucode" 2>/dev/null | wc -l || echo 0)
                info "Archivos de firmware instalados: $fw_count"
            fi
        fi

        # GPU
        local gpu
        gpu=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" || echo "")
        if [[ -n "$gpu" ]]; then
            ok "GPU detectada:"
            echo "$gpu" | while IFS= read -r line; do
                info "  $line"
            done
        fi
    else
        info "lspci no disponible (instala: sudo apt install pciutils)"
    fi

    # Firmware faltante en dmesg
    if [[ "$ES_ROOT" == true ]]; then
        local fw_errors
        fw_errors=$(dmesg 2>/dev/null | grep -ci "firmware.*fail\|firmware.*missing\|firmware.*not found" || true)
        fw_errors=${fw_errors:-0}
        fw_errors=$(echo "$fw_errors" | tr -d '[:space:]')
        if [[ "$fw_errors" -gt 0 ]]; then
            warn "Errores de firmware en dmesg: $fw_errors"
            warn "  → Puede que necesites: sudo apt install firmware-linux-nonfree"
        else
            ok "Sin errores de firmware en dmesg"
        fi
    fi

    salto
}

# ==============================================
# PROGRAMA PRINCIPAL
# ==============================================

clear 2>/dev/null || true
echo ""
echo -e "${FONDO_VERDE}${NEGRO}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║                                                      ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║   🛡️  UniLinux Reparador v${VERSION} — MODO SEGURO   ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║                                                      ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║   ✅ NO modifica nada                                ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║   ✅ NO repara nada                                  ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║   ✅ NO reinicia                                     ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║   ✅ Solo DIAGNOSTICA e INFORMA                      ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║                                                      ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║   Creado por: Ahau Quetzalcóatl                      ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}║                                                      ║${NC}"
echo -e "${FONDO_VERDE}${NEGRO}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Ejecutar todos los diagnósticos
diagnostico_sistema
diagnostico_hardware
diagnostico_firmware
diagnostico_discos
diagnostico_red
diagnostico_multimedia
diagnostico_servicios
diagnostico_firmware_hw

# Resumen final
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
paso "DIAGNÓSTICO COMPLETADO"
echo ""
ok "Tu sistema ha sido analizado sin modificar nada."
echo ""

# Contar problemas
WARNS=$(echo -e "$REPORTE" | grep -c "\[WARN\]" || true)
ERRORS=$(echo -e "$REPORTE" | grep -c "\[ERR\]" || true)
WARNS=$(echo "${WARNS:-0}" | tr -d '[:space:]')
ERRORS=$(echo "${ERRORS:-0}" | tr -d '[:space:]')
[[ -z "$WARNS" ]] && WARNS=0
[[ -z "$ERRORS" ]] && ERRORS=0

if [[ $ERRORS -gt 0 ]]; then
    echo -e "  ${ROJO}🔴 Errores encontrados: $ERRORS${NC}"
fi
if [[ $WARNS -gt 0 ]]; then
    echo -e "  ${AMARILLO}🟡 Advertencias: $WARNS${NC}"
fi
if [[ $ERRORS -eq 0 ]] && [[ $WARNS -eq 0 ]]; then
    echo -e "  ${VERDE}🟢 Todo se ve bien — No se detectaron problemas${NC}"
fi

echo ""
echo -e "  ${CYAN}¿Qué hacer ahora?${NC}"
echo -e "  Si se encontraron problemas, consulta las recomendaciones arriba."
echo -e "  Cada advertencia incluye un '→ Recomendación:' con el comando sugerido."
echo ""

# Guardar reporte
if [[ "$GUARDAR_REPORTE" == true ]]; then
    REPORTE_FILE="$HOME/unilinux_diagnostico_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "=============================================="
        echo " UniLinux Reparador v${VERSION} — DIAGNÓSTICO"
        echo " Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
        echo " Sistema: $(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'N/A')"
        echo "=============================================="
        echo ""
        echo -e "$REPORTE"
        echo ""
        echo "Errores: $ERRORS | Advertencias: $WARNS"
    } > "$REPORTE_FILE"

    ok "Reporte guardado en: $REPORTE_FILE"
    echo ""
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
