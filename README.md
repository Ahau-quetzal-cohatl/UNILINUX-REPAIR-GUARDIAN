# ◈◈◈ UniLinux Reparador v2.0 ◈◈◈

> *"Porque la tecnología debe adaptarse a nosotros, no al revés."*

**UniLinux Reparador** es un sistema de autoreparación universal para Linux que actúa automáticamente **antes del arranque del sistema operativo**. Funciona como un "ángel guardián" digital que protege tu equipo sin necesidad de intervención humana.

Diseñado especialmente para **personas con discapacidad**, eliminando las barreras técnicas que representan reparar un equipo después de un fallo.

**Creado por:** Ahau Quetzalcóatl  
**Licencia:** GPL v3  
**Contacto:** ciboangeles@gmail.com

---

## 🚀 Instalación Rápida

```bash
git clone https://github.com/Ahau-quetzal-cohatl/unilinux.sh.git
cd unilinux.sh
sudo bash install.sh
```

## 📖 Uso

```bash
# Reparación completa con reinicio automático
sudo unilinux

# Simulación (no hace cambios reales)
sudo unilinux --dry-run

# Reparación sin reiniciar al final
sudo unilinux --no-reboot

# Simulación con información detallada
sudo unilinux --dry-run --verbose

# Saltar verificación de filesystem (si ya lo hiciste)
sudo unilinux --skip-fsck --no-reboot

# Sin música ambiental
sudo unilinux --no-music

# Ver ayuda
sudo unilinux --help

# Ejecutar tests
bash tests/test_unilinux.sh --verbose
```

---

## ⚙️ Funciones

| Función | Descripción |
|---------|-------------|
| 🔍 Diagnóstico automático | Analiza hardware, discos, CPU, RAM, firmware |
| 💾 Reparación de discos | Corrige ext4, XFS, BTRFS, NTFS, FAT (solo desmontados) |
| 🔄 Reinstalación de GRUB | UEFI 64/32-bit, Legacy, modo dual |
| 🌐 Configuración de red | dhclient, dhcpcd, udhcpc con timeout |
| 📦 Firmware non-free | Broadcom, Intel WiFi, Realtek, Atheros, AMD, NVIDIA |
| 🎵 Multimedia | Cámara web, audio, USB |
| 📦 Paquetes rotos | apt, dnf, yum, pacman, zypper |
| ⚙️ Módulos del kernel | Carga controladores necesarios |
| 🎵 Música ambiental | Melodía relajante durante la reparación |
| 🔊 Accesibilidad por voz | espeak / espeak-ng |
| 🌍 Multi-idioma | es, en, fr, de, pt, it |

---

## 🛡️ Modos de Instalación

| Modo | Descripción | Cuándo se ejecuta |
|------|-------------|-------------------|
| **Manual** | `sudo unilinux` | Cuando tú decides |
| **Systemd** | Servicio al arrancar | Cada vez que enciendes |
| **Initramfs** | Hook pre-arranque | Antes de montar la raíz |
| **Ambos** | Systemd + Initramfs | Máxima protección |

---

## 🖥️ Compatibilidad

| Distro | Gestor | Estado |
|--------|--------|--------|
| Debian (todas) | apt | ✅ Completo |
| Ubuntu (todas) | apt | ✅ Completo |
| Linux Mint | apt | ✅ Completo |
| Fedora | dnf | ✅ Completo |
| RHEL / CentOS | dnf/yum | ✅ Completo |
| Arch Linux | pacman | ✅ Completo |
| openSUSE | zypper | ✅ Básico |
| Raspberry Pi OS | apt | ✅ Completo |

### Soporte de discos
| Tipo | Ejemplo | Estado |
|------|---------|--------|
| SATA/SCSI | /dev/sda | ✅ |
| NVMe | /dev/nvme0n1 | ✅ |
| eMMC/SD | /dev/mmcblk0 | ✅ |
| VirtIO | /dev/vda | ✅ |

---

## 🆕 Cambios en v2.0

### Correcciones Críticas
- ✅ **Protección fsck**: Nunca ejecuta fsck en particiones montadas
- ✅ **Soporte NVMe/eMMC**: Detección correcta del disco base
- ✅ **Multi-distro real**: apt, dnf, yum, pacman, zypper
- ✅ **Trap/cleanup**: Desmonta todo si se interrumpe
- ✅ **Anti-loop**: Cooldown de 5 min entre ejecuciones
- ✅ **Verificación root**: Error claro si no es root

### Mejoras
- ✅ **--dry-run**: Simular sin cambios
- ✅ **--no-reboot**: No reiniciar al final
- ✅ **--verbose**: Información detallada
- ✅ **--skip-fsck**: Saltar fsck
- ✅ **Lockfile**: Previene doble ejecución
- ✅ **Timestamps dinámicos**: Cada log con su hora real
- ✅ **espeak serializado**: Mensajes de voz sin superposición
- ✅ **Countdown cancelable**: Ctrl+C antes del reinicio
- ✅ **DNS en chroot**: Copia resolv.conf
- ✅ **Punto de montaje dedicado**: `/mnt/unilinux_repair`
- ✅ **Servicio systemd**: Con ConditionPath para saltar
- ✅ **Resumen final**: Muestra todo lo detectado/reparado
- ✅ **Música ambiental**: Melodía relajante generada con sox/aplay/beep
- ✅ **Suite de tests**: 53 pruebas automatizadas
- ✅ **.gitignore**: Configurado para el proyecto

---

## 📁 Estructura del Proyecto

```
UniLinux Reparador v2.0
├── unilinux.sh              # Script principal de reparación
├── install.sh               # Instalador interactivo
├── README.md                # Documentación
├── ANALISIS_FALLAS.md       # Análisis de fallas de v1.0
├── LICENSE                  # GPL v3
├── .gitignore               # Exclusiones de Git
├── music/
│   └── unilinux_music.sh   # 🎵 Módulo de música ambiental
└── tests/
    └── test_unilinux.sh    # ✅ Suite de 53 tests automatizados
```

---

## 🎵 Música Ambiental

UniLinux incluye un módulo de música que genera y reproduce melodías relajantes mientras se repara el sistema. La música se genera usando síntesis de audio — **no requiere archivos MP3 externos**.

### Backends de audio soportados (en orden de prioridad)
| Backend | Paquete | Calidad |
|---------|---------|---------|
| `paplay` | PulseAudio | ⭐⭐⭐ Mejor |
| `aplay` | ALSA (alsa-utils) | ⭐⭐ Buena |
| `play` | sox | ⭐⭐⭐ Mejor (genera melodías pentatónicas) |
| `speaker-test` | alsa-utils | ⭐ Básica |
| `beep` | beep | ⭐ Mínima (PC speaker) |

### Cómo funciona
- Al iniciar, genera una melodía ambiental relajante con notas pentatónicas + pad + efecto de agua
- Se reproduce en loop mientras dura la reparación
- Se detiene automáticamente al terminar (o con Ctrl+C)
- Usa `--no-music` para desactivar

### Probar la música
```bash
bash music/unilinux_music.sh --test   # Prueba de 30 segundos
```

---

## ♿ Accesibilidad

### Para personas con movilidad reducida
- No necesitas usar el teclado para reparar
- El sistema actúa solo al arrancar
- Si hay un apagón, al encender ya está reparado

### Para personas con discapacidad visual
- Mensajes por voz con espeak/espeak-ng
- Soporte multi-idioma automático

### Para personas con discapacidad cognitiva
- Proceso 100% automático
- Sin comandos que recordar
- Interfaz simple y clara

---

## ⚖️ Licencia

**GPL v3** - Software libre y de código abierto.  
Puedes usarlo, modificarlo y compartirlo libremente.  
Atribución requerida al creador original: **Ahau Quetzalcóatl**

---

> *"UniLinux Reparador nace de la necesidad y el corazón. No es solo código, es una herramienta de liberación tecnológica para quienes más lo necesitan."*  
> — **Ahau Quetzalcóatl**
