#!/bin/bash
# ==============================================
# UniLinux Reparador - Módulo de Música Relajante
# Creado por: Ahau Quetzalcóatl
# ==============================================
#
# Genera y reproduce música ambiental relajante
# mientras se ejecuta la reparación del sistema.
#
# Métodos de reproducción (en orden de prioridad):
#   1. paplay  (PulseAudio) - mejor calidad
#   2. aplay   (ALSA)       - disponible en casi todo Linux
#   3. sox/play              - muy versátil
#   4. speaker-test          - fallback con tonos
#   5. beep                  - último recurso (PC speaker)
#
# Uso:
#   source music/unilinux_music.sh
#   musica_iniciar           # Inicia la música
#   musica_detener           # Detiene la música
#   musica_estado            # Muestra si está sonando
# ==============================================

MUSICA_PID=""
MUSICA_ACTIVA=false
MUSICA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSICA_WAV="${MUSICA_DIR}/ambient_relax.wav"
MUSICA_GENERADA=false

# --- Detectar método de audio disponible ---
detectar_audio() {
    if command -v paplay &>/dev/null; then
        echo "paplay"
    elif command -v aplay &>/dev/null; then
        echo "aplay"
    elif command -v play &>/dev/null; then
        echo "sox"
    elif command -v speaker-test &>/dev/null; then
        echo "speaker-test"
    elif command -v beep &>/dev/null; then
        echo "beep"
    else
        echo "none"
    fi
}

# --- Generar archivo WAV ambiental con sox ---
# Crea una melodía relajante tipo "ambient/chillout" usando síntesis
generar_melodia_sox() {
    local output="$1"
    local duracion="${2:-120}"  # 2 minutos por defecto

    if ! command -v sox &>/dev/null; then
        return 1
    fi

    echo "[MUSIC] Generando melodía ambiental relajante..."

    # Crear tonos individuales suaves (escala pentatónica = siempre suena bien)
    # Notas: C4, D4, E4, G4, A4 (Do, Re, Mi, Sol, La)
    local tmpdir="/tmp/unilinux_music_$$"
    mkdir -p "$tmpdir"

    # Capa 1: Pad ambiental grave (colchón de sonido)
    sox -n -r 44100 -b 16 "${tmpdir}/pad.wav" \
        synth "$duracion" sine 130.81 sine 196.00 sine 261.63 \
        tremolo 0.5 40 \
        reverb 80 \
        vol 0.15 2>/dev/null

    # Capa 2: Melodía pentatónica suave con notas largas
    local notas_hz=(261.63 293.66 329.63 392.00 440.00 523.25 392.00 329.63)
    local melodia_files=()
    local nota_dur=4  # 4 segundos por nota

    for i in "${!notas_hz[@]}"; do
        local freq="${notas_hz[$i]}"
        local nota_file="${tmpdir}/nota_${i}.wav"
        sox -n -r 44100 -b 16 "$nota_file" \
            synth "$nota_dur" sine "$freq" \
            fade t 1.0 "$nota_dur" 1.5 \
            reverb 70 \
            vol 0.10 2>/dev/null
        melodia_files+=("$nota_file")
    done

    # Concatenar notas en una melodía
    sox "${melodia_files[@]}" "${tmpdir}/melodia_una.wav" 2>/dev/null

    # Repetir la melodía para cubrir la duración
    local repeats=$(( duracion / (nota_dur * ${#notas_hz[@]}) + 1 ))
    local repeat_files=()
    for ((r=0; r<repeats; r++)); do
        repeat_files+=("${tmpdir}/melodia_una.wav")
    done
    sox "${repeat_files[@]}" "${tmpdir}/melodia.wav" trim 0 "$duracion" 2>/dev/null

    # Capa 3: Efecto de agua/naturaleza (ruido rosa filtrado)
    sox -n -r 44100 -b 16 "${tmpdir}/agua.wav" \
        synth "$duracion" pinknoise \
        band 400 200 \
        tremolo 0.3 30 \
        reverb 90 \
        vol 0.05 2>/dev/null

    # Mezclar todas las capas
    sox -m "${tmpdir}/pad.wav" "${tmpdir}/melodia.wav" "${tmpdir}/agua.wav" \
        "$output" \
        fade t 3.0 "$duracion" 5.0 \
        norm -3 2>/dev/null

    # Limpiar temporales
    rm -rf "$tmpdir"

    if [[ -f "$output" ]]; then
        echo "[MUSIC] Melodía generada: $output"
        return 0
    else
        return 1
    fi
}

# --- Generar melodía con tonos simples (sin sox) ---
generar_melodia_beep() {
    # Usa 'beep' para crear una secuencia de tonos suaves
    # Escala pentatónica: C4=262, D4=294, E4=330, G4=392, A4=440
    while true; do
        beep -f 262 -l 2000 -D 500 2>/dev/null
        beep -f 330 -l 2000 -D 500 2>/dev/null
        beep -f 392 -l 2000 -D 500 2>/dev/null
        beep -f 440 -l 2000 -D 500 2>/dev/null
        beep -f 392 -l 2000 -D 500 2>/dev/null
        beep -f 330 -l 2000 -D 500 2>/dev/null
        beep -f 294 -l 3000 -D 1000 2>/dev/null
        beep -f 262 -l 3000 -D 1000 2>/dev/null
    done
}

# --- Reproducir con speaker-test (tonos sinusoidales) ---
reproducir_speaker_test() {
    # Tono suave de fondo a 440Hz (La4)
    speaker-test -t sine -f 220 -l 0 &>/dev/null
}

# --- FUNCIÓN PRINCIPAL: Iniciar música ---
musica_iniciar() {
    local metodo
    metodo=$(detectar_audio)

    if [[ "$metodo" == "none" ]]; then
        echo "[MUSIC] No se encontró sistema de audio. Música deshabilitada."
        return 1
    fi

    echo "[MUSIC] Sistema de audio detectado: $metodo"

    case "$metodo" in
        paplay|aplay|sox)
            # Intentar generar melodía con sox si está disponible
            if command -v sox &>/dev/null && [[ ! -f "$MUSICA_WAV" ]]; then
                generar_melodia_sox "$MUSICA_WAV" 180
                MUSICA_GENERADA=true
            fi

            if [[ -f "$MUSICA_WAV" ]]; then
                (
                    # Loop infinito de la melodía
                    while true; do
                        case "$metodo" in
                            paplay)  paplay "$MUSICA_WAV" 2>/dev/null ;;
                            aplay)   aplay -q "$MUSICA_WAV" 2>/dev/null ;;
                            sox)     play -q "$MUSICA_WAV" repeat 99 2>/dev/null; break ;;
                        esac
                    done
                ) &
                MUSICA_PID=$!
                MUSICA_ACTIVA=true
                echo "[MUSIC] ♪ Música ambiental iniciada (PID: $MUSICA_PID)"
            else
                # Fallback: sox en tiempo real sin archivo
                if [[ "$metodo" == "sox" ]]; then
                    (
                        play -n synth 300 sine 220 sine 330 sine 440 \
                            tremolo 0.4 30 reverb 80 vol 0.12 2>/dev/null
                    ) &
                    MUSICA_PID=$!
                    MUSICA_ACTIVA=true
                    echo "[MUSIC] ♪ Tonos ambientales iniciados"
                fi
            fi
            ;;

        speaker-test)
            (reproducir_speaker_test) &
            MUSICA_PID=$!
            MUSICA_ACTIVA=true
            echo "[MUSIC] ♪ Tono ambiental iniciado (speaker-test)"
            ;;

        beep)
            (generar_melodia_beep) &
            MUSICA_PID=$!
            MUSICA_ACTIVA=true
            echo "[MUSIC] ♪ Melodía con beep iniciada"
            ;;
    esac

    return 0
}

# --- FUNCIÓN: Detener música ---
musica_detener() {
    if [[ -n "$MUSICA_PID" ]]; then
        # Matar el proceso y todos sus hijos
        kill "$MUSICA_PID" 2>/dev/null || true
        wait "$MUSICA_PID" 2>/dev/null || true

        # Matar cualquier proceso de audio huérfano
        pkill -f "unilinux_music" 2>/dev/null || true
        pkill -f "ambient_relax.wav" 2>/dev/null || true

        MUSICA_PID=""
        MUSICA_ACTIVA=false
        echo "[MUSIC] ♪ Música detenida"
    fi

    # Limpiar wav generado si lo creamos
    if [[ "$MUSICA_GENERADA" == true ]] && [[ -f "$MUSICA_WAV" ]]; then
        rm -f "$MUSICA_WAV" 2>/dev/null || true
    fi
}

# --- FUNCIÓN: Estado de la música ---
musica_estado() {
    if [[ "$MUSICA_ACTIVA" == true ]] && [[ -n "$MUSICA_PID" ]]; then
        if kill -0 "$MUSICA_PID" 2>/dev/null; then
            echo "[MUSIC] ♪ Reproduciendo (PID: $MUSICA_PID)"
            return 0
        else
            MUSICA_ACTIVA=false
            echo "[MUSIC] Música terminó"
            return 1
        fi
    else
        echo "[MUSIC] Sin música"
        return 1
    fi
}

# --- Si se ejecuta directamente (no sourceado) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  UniLinux Reparador - Módulo de Música v2.0      ║"
    echo "║  Creado por: Ahau Quetzalcóatl                   ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "Este módulo se usa desde el script principal:"
    echo "  source music/unilinux_music.sh"
    echo "  musica_iniciar"
    echo "  musica_detener"
    echo ""
    echo "Probando sistema de audio..."
    echo "  Método detectado: $(detectar_audio)"
    echo ""
    echo "Para probar la música (30 segundos):"
    echo "  bash $0 --test"

    if [[ "${1:-}" == "--test" ]]; then
        echo ""
        echo "♪ Reproduciendo prueba de 30 segundos..."
        echo "  Presiona Ctrl+C para detener."
        musica_iniciar
        sleep 30
        musica_detener
        echo "♪ Prueba finalizada."
    fi
fi
