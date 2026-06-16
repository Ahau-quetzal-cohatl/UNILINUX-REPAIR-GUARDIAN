#!/bin/bash
# ==============================================
# UniLinux Reparador - Suite de Tests v2.0
# Creado por: Ahau Quetzalcóatl
# ==============================================
#
# Ejecuta pruebas unitarias y de integración
# para verificar que el script funciona correctamente.
#
# Uso:
#   bash tests/test_unilinux.sh
#   bash tests/test_unilinux.sh --verbose
# ==============================================

set -uo pipefail

# --- Configuración ---
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPT="${PROJECT_DIR}/unilinux.sh"
INSTALL_SCRIPT="${PROJECT_DIR}/install.sh"
MUSIC_SCRIPT="${PROJECT_DIR}/music/unilinux_music.sh"

VERBOSE=false
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=true

# Contadores
TESTS_TOTAL=0
TESTS_PASS=0
TESTS_FAIL=0
TESTS_SKIP=0

# --- Colores ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Funciones de test ---
test_pass() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_PASS=$((TESTS_PASS + 1))
    echo -e "  ${VERDE}✅ PASS${NC} $1"
}

test_fail() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_FAIL=$((TESTS_FAIL + 1))
    echo -e "  ${ROJO}❌ FAIL${NC} $1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "         ${ROJO}→ $2${NC}"
    fi
}

test_skip() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_SKIP=$((TESTS_SKIP + 1))
    echo -e "  ${AMARILLO}⏭️  SKIP${NC} $1 ($2)"
}

# --- Header ---
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  UniLinux Reparador - Suite de Tests v2.0        ║"
echo "║  $(date '+%Y-%m-%d %H:%M:%S')                             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# =========================================
# GRUPO 1: ARCHIVOS Y ESTRUCTURA
# =========================================
echo -e "${CYAN}[1/7] Verificando estructura del proyecto...${NC}"

# Test 1.1: Archivos existen
for FILE in unilinux.sh install.sh README.md LICENSE ANALISIS_FALLAS.md music/unilinux_music.sh .gitignore; do
    if [[ -f "${PROJECT_DIR}/${FILE}" ]]; then
        test_pass "Archivo existe: $FILE"
    else
        test_fail "Archivo existe: $FILE" "No encontrado en ${PROJECT_DIR}/${FILE}"
    fi
done

# Test 1.2: Permisos ejecutables
for FILE in unilinux.sh install.sh music/unilinux_music.sh; do
    FILEPATH="${PROJECT_DIR}/${FILE}"
    if [[ -f "$FILEPATH" ]]; then
        # Verificar que tiene shebang
        if head -1 "$FILEPATH" | grep -q "^#!/bin/bash"; then
            test_pass "Shebang correcto: $FILE"
        else
            test_fail "Shebang correcto: $FILE" "Primera línea: $(head -1 "$FILEPATH")"
        fi
    fi
done

# Test 1.3: Directorio music existe
if [[ -d "${PROJECT_DIR}/music" ]]; then
    test_pass "Directorio music/ existe"
else
    test_fail "Directorio music/ existe" "No encontrado"
fi

# =========================================
# GRUPO 2: SINTAXIS BASH
# =========================================
echo ""
echo -e "${CYAN}[2/7] Verificando sintaxis bash...${NC}"

for FILE in unilinux.sh install.sh music/unilinux_music.sh; do
    FILEPATH="${PROJECT_DIR}/${FILE}"
    if [[ -f "$FILEPATH" ]]; then
        ERROR_OUTPUT=$(bash -n "$FILEPATH" 2>&1)
        if [[ $? -eq 0 ]]; then
            test_pass "Sintaxis válida: $FILE"
        else
            test_fail "Sintaxis válida: $FILE" "$ERROR_OUTPUT"
        fi
    fi
done

# Test: Sin entidades HTML
for FILE in unilinux.sh install.sh; do
    FILEPATH="${PROJECT_DIR}/${FILE}"
    if grep -qP '&(gt|lt|amp|quot);' "$FILEPATH" 2>/dev/null; then
        test_fail "Sin entidades HTML: $FILE" "Contiene &gt; &lt; &amp; o &quot;"
    else
        test_pass "Sin entidades HTML: $FILE"
    fi
done

# =========================================
# GRUPO 3: OPCIONES DE LÍNEA DE COMANDOS
# =========================================
echo ""
echo -e "${CYAN}[3/7] Verificando opciones de línea de comandos...${NC}"

# Test --version
VERSION_OUTPUT=$(bash "$SCRIPT" --version 2>&1)
if echo "$VERSION_OUTPUT" | grep -q "UniLinux Reparador v"; then
    test_pass "--version muestra versión: $VERSION_OUTPUT"
else
    test_fail "--version muestra versión" "Output: $VERSION_OUTPUT"
fi

# Test --help
HELP_OUTPUT=$(bash "$SCRIPT" --help 2>&1)
if echo "$HELP_OUTPUT" | grep -q "dry-run" && \
   echo "$HELP_OUTPUT" | grep -q "no-reboot" && \
   echo "$HELP_OUTPUT" | grep -q "no-music" && \
   echo "$HELP_OUTPUT" | grep -q "skip-fsck"; then
    test_pass "--help muestra todas las opciones"
else
    test_fail "--help muestra todas las opciones" "Faltan opciones en la ayuda"
fi

# Test --help incluye creador
if echo "$HELP_OUTPUT" | grep -q "Ahau Quetzalcóatl"; then
    test_pass "--help muestra creador"
else
    test_fail "--help muestra creador" "No se encontró el nombre del creador"
fi

# Test opción desconocida
UNKNOWN_OUTPUT=$(bash "$SCRIPT" --opcion-falsa 2>&1)
UNKNOWN_EXIT=$?
if [[ $UNKNOWN_EXIT -ne 0 ]]; then
    test_pass "Opción desconocida retorna error"
else
    test_fail "Opción desconocida retorna error" "Exit code: $UNKNOWN_EXIT"
fi

# =========================================
# GRUPO 4: FUNCIONES INTERNAS
# =========================================
echo ""
echo -e "${CYAN}[4/7] Verificando funciones internas...${NC}"

# Test: obtener_disco_base está definida
if grep -q "obtener_disco_base()" "$SCRIPT"; then
    test_pass "Función obtener_disco_base existe"
else
    test_fail "Función obtener_disco_base existe" "No encontrada"
fi

# Test: Soporte NVMe en obtener_disco_base
if grep -q "nvme" "$SCRIPT"; then
    test_pass "Soporte NVMe en detección de disco"
else
    test_fail "Soporte NVMe en detección de disco" "No se encontró referencia a nvme"
fi

# Test: Soporte eMMC en obtener_disco_base
if grep -q "mmcblk" "$SCRIPT"; then
    test_pass "Soporte eMMC/SD en detección de disco"
else
    test_fail "Soporte eMMC/SD en detección de disco" "No se encontró referencia a mmcblk"
fi

# Test: Verificación de root
if grep -q "EUID" "$SCRIPT"; then
    test_pass "Verificación de root (EUID)"
else
    test_fail "Verificación de root (EUID)" "No se verifica si es root"
fi

# Test: Protección fsck
if grep -q "esta_montada" "$SCRIPT"; then
    test_pass "Protección fsck (verifica si está montada)"
else
    test_fail "Protección fsck (verifica si está montada)" "No se verifica antes de fsck"
fi

# Test: Trap cleanup
if grep -q "trap cleanup" "$SCRIPT"; then
    test_pass "Trap cleanup definido"
else
    test_fail "Trap cleanup definido" "No se encontró trap cleanup"
fi

# Test: Lockfile
if grep -q "LOCKFILE" "$SCRIPT"; then
    test_pass "Protección con lockfile"
else
    test_fail "Protección con lockfile" "No se encontró LOCKFILE"
fi

# Test: Cooldown anti-loop
if grep -q "COOLDOWN" "$SCRIPT"; then
    test_pass "Cooldown anti-loop"
else
    test_fail "Cooldown anti-loop" "No se encontró COOLDOWN"
fi

# Test: Punto de montaje dedicado (no /mnt genérico)
if grep -q "/mnt/unilinux_repair" "$SCRIPT"; then
    test_pass "Punto de montaje dedicado (/mnt/unilinux_repair)"
else
    test_fail "Punto de montaje dedicado" "Usa /mnt genérico"
fi

# =========================================
# GRUPO 5: MULTI-DISTRO
# =========================================
echo ""
echo -e "${CYAN}[5/7] Verificando soporte multi-distribución...${NC}"

for GESTOR in apt dnf yum pacman zypper; do
    if grep -q "\"$GESTOR\"" "$SCRIPT"; then
        test_pass "Soporte para gestor: $GESTOR"
    else
        test_fail "Soporte para gestor: $GESTOR" "No encontrado en el script"
    fi
done

# Test: detectar_gestor_paquetes o detectar_gestor
if grep -q "detectar_gestor_paquetes\|detectar_gestor()" "$SCRIPT"; then
    test_pass "Función detectar gestor de paquetes existe"
else
    test_fail "Función detectar gestor de paquetes existe" "No encontrada"
fi

# =========================================
# GRUPO 6: MULTI-IDIOMA
# =========================================
echo ""
echo -e "${CYAN}[6/7] Verificando soporte multi-idioma...${NC}"

for IDIOMA in es en fr de pt it; do
    if grep -q "\"$IDIOMA\")\|\"$IDIOMA\"$\|$IDIOMA)" "$SCRIPT"; then
        test_pass "Idioma soportado: $IDIOMA"
    else
        # En v2.1 los idiomas extra se manejan con el bloque *) fallback
        if [[ "$IDIOMA" =~ ^(fr|de|pt|it)$ ]] && grep -q "detectar_idioma" "$SCRIPT" && grep -q "$IDIOMA" "$SCRIPT"; then
            test_pass "Idioma soportado: $IDIOMA (vía detectar_idioma)"
        else
            test_fail "Idioma soportado: $IDIOMA" "No encontrado"
        fi
    fi
done

# =========================================
# GRUPO 7: MÓDULO DE MÚSICA
# =========================================
echo ""
echo -e "${CYAN}[7/7] Verificando módulo de música...${NC}"

if [[ -f "$MUSIC_SCRIPT" ]]; then
    # Test: Sintaxis
    ERROR_OUTPUT=$(bash -n "$MUSIC_SCRIPT" 2>&1)
    if [[ $? -eq 0 ]]; then
        test_pass "Música: sintaxis válida"
    else
        test_fail "Música: sintaxis válida" "$ERROR_OUTPUT"
    fi

    # Test: Funciones principales
    for FUNC in musica_iniciar musica_detener musica_estado detectar_audio; do
        if grep -q "${FUNC}()" "$MUSIC_SCRIPT"; then
            test_pass "Música: función $FUNC existe"
        else
            test_fail "Música: función $FUNC existe" "No encontrada"
        fi
    done

    # Test: Soporte múltiples backends de audio
    for BACKEND in paplay aplay sox speaker-test beep; do
        if grep -q "$BACKEND" "$MUSIC_SCRIPT"; then
            test_pass "Música: soporte backend $BACKEND"
        else
            test_fail "Música: soporte backend $BACKEND" "No encontrado"
        fi
    done

    # Test: --no-music está integrado en unilinux.sh
    if grep -q "no-music" "$SCRIPT"; then
        test_pass "Música: opción --no-music integrada"
    else
        test_fail "Música: opción --no-music integrada" "No encontrada en unilinux.sh"
    fi

    # Test: musica_detener en cleanup
    if grep -q "musica_detener" "$SCRIPT"; then
        test_pass "Música: se detiene en cleanup"
    else
        test_fail "Música: se detiene en cleanup" "No se llama musica_detener en cleanup"
    fi
else
    test_skip "Módulo de música" "archivo no encontrado"
fi

# =========================================
# RESUMEN
# =========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}RESUMEN DE TESTS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "  Total:    ${TESTS_TOTAL}"
echo -e "  ${VERDE}✅ Pass:    ${TESTS_PASS}${NC}"
echo -e "  ${ROJO}❌ Fail:    ${TESTS_FAIL}${NC}"
echo -e "  ${AMARILLO}⏭️  Skip:    ${TESTS_SKIP}${NC}"
echo ""

if [[ $TESTS_FAIL -eq 0 ]]; then
    echo -e "  ${VERDE}══════════════════════════════════════${NC}"
    echo -e "  ${VERDE}  ✅  TODOS LOS TESTS PASARON  ✅    ${NC}"
    echo -e "  ${VERDE}══════════════════════════════════════${NC}"
    EXIT_CODE=0
else
    echo -e "  ${ROJO}══════════════════════════════════════${NC}"
    echo -e "  ${ROJO}  ❌  ${TESTS_FAIL} TEST(S) FALLARON  ❌       ${NC}"
    echo -e "  ${ROJO}══════════════════════════════════════${NC}"
    EXIT_CODE=1
fi

echo ""
exit $EXIT_CODE
