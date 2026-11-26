#!/bin/bash
# test-actualizar.sh (4.19.0): guardian-actualizar solo acepta bundles FIRMADOS con la llave fijada,
# íntegros, más nuevos que lo instalado y con pruebas en verde. Sin root (--sin-instalar).
# Uso: bash tests/test-actualizar.sh [directorio bin]   (contra 4.18.6 FALLA: no existe guardian-actualizar)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
GA=$B/guardian-actualizar
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
espera "existe bin/guardian-actualizar y pasa bash -n" '[[ -f "$GA" ]] && bash -n "$GA"'
espera "install-guardian lo instala en /usr/lib/guardian y /usr/local/sbin" \
  'grep -qF "guardian-actualizar\" /usr/lib/guardian/guardian-actualizar" "$B/install-guardian" && grep -qF "guardian-actualizar\" /usr/local/sbin/guardian-actualizar" "$B/install-guardian"'
command -v ssh-keygen >/dev/null || { echo "FALLA no hay ssh-keygen"; echo "$P passed, $((F+1)) failed"; exit 1; }
ssh-keygen -q -t ed25519 -N '' -C prueba -f "$T/llave" || exit 1
ssh-keygen -q -t ed25519 -N '' -C otra -f "$T/otra" || exit 1
PUB=$(cat "$T/llave.pub")
# copia con la llave de prueba fijada y un "instalado" falso de versión 4.19.0
mkdir -p "$T/inst"; printf 'readonly VERSION="4.19.0"\n' >"$T/inst/guardian"
sed -e "s|^readonly LLAVE_PUBLICA=.*|readonly LLAVE_PUBLICA=\"$PUB\"|" \
    -e "s|^readonly INSTALADOS=.*|readonly INSTALADOS=\"$T/inst/guardian\"|" "$GA" >"$T/ga"
espera "la copia de prueba cambió exactamente 2 líneas" '[[ $(diff "$GA" "$T/ga" | grep -c "^>") -eq 2 ]]'
# bundle de prueba con el formato real (cabecera, __CARGA__, base64 de tar.xz con MANIFIESTO)
bundle() { # $1 salida  $2 versión  $3 extra (falla|fuera|cabecera)
    local d=$T/a.$$ v=$2; rm -rf "$d"; mkdir -p "$d/bin" "$d/tests"
    printf '#!/bin/bash\nreadonly VERSION="%s"\n' "$v" >"$d/bin/guardian"
    printf '#!/bin/bash\n%s\n' "$([[ ${3:-} == falla ]] && echo 'exit 1' || echo 'exit 0')" >"$d/tests/test-uno.sh"
    ( cd "$d" && find bin tests -type f | sort | xargs sha256sum >MANIFIESTO.sha256 )
    [[ ${3:-} == fuera ]] && echo x >"$d/bin/intruso"
    local h=$v; [[ ${3:-} == cabecera ]] && h=9.9.9
    { printf '#!/bin/bash\n# Guardian v%s — bundle de prueba\nexit 0\n__CARGA__\n' "$h"
      tar -C "$d" -c bin tests MANIFIESTO.sha256 | xz -c | base64; } >"$1"
}
firma() { ssh-keygen -q -Y sign -f "$1" -n "${3:-guardian-bundle}" "$2" >/dev/null 2>&1; }
corre() { o=$(bash "$T/ga" "$@" --sin-instalar 2>&1); rc=$?; }

bundle "$T/b1.sh" 4.20.0; firma "$T/llave" "$T/b1.sh"
corre "$T/b1.sh"
espera "bueno: firma válida, VERIFICADO_OK, rc=0" '(( rc == 0 )) && grep -q "^SI firma válida" <<<"$o" && grep -q "VEREDICTO ACTUALIZAR_VERIFICADO_OK" <<<"$o"'
espera "bueno: muestra la huella de la llave fijada (4.19.1)" 'grep -qF "llave fijada $(ssh-keygen -lf "$T/llave.pub" | awk "NR==1{print \$2}" | cut -c1-20)…" <<<"$o"'
espera "bueno: dice versión 4.20.0 > instalada 4.19.0" 'grep -q "^SI versión 4.20.0 > instalada 4.19.0" <<<"$o"'

bundle "$T/b2.sh" 4.20.0
corre "$T/b2.sh"
espera "sin .sig: NO" '(( rc != 0 )) && grep -q "^NO falta la firma" <<<"$o"'

bundle "$T/b3.sh" 4.20.0; firma "$T/otra" "$T/b3.sh"
corre "$T/b3.sh"
espera "firmado con otra llave: FIRMA NO VÁLIDA" '(( rc != 0 )) && grep -q "^NO FIRMA NO VÁLIDA" <<<"$o"'

bundle "$T/b4.sh" 4.20.0; firma "$T/llave" "$T/b4.sh"; echo "echo malo" >>"$T/b4.sh"
corre "$T/b4.sh"
espera "alterado tras firmar: FIRMA NO VÁLIDA" '(( rc != 0 )) && grep -q "^NO FIRMA NO VÁLIDA" <<<"$o"'

bundle "$T/b5.sh" 4.20.0; firma "$T/llave" "$T/b5.sh" otro-espacio
corre "$T/b5.sh"
espera "otro espacio de nombres: FIRMA NO VÁLIDA" '(( rc != 0 )) && grep -q "^NO FIRMA NO VÁLIDA" <<<"$o"'

bundle "$T/b6.sh" 4.18.6; firma "$T/llave" "$T/b6.sh"
corre "$T/b6.sh"
espera "versión vieja firmada: no vuelve atrás" '(( rc != 0 )) && grep -q "no vuelvo atrás" <<<"$o"'

bundle "$T/b7.sh" 4.19.0; firma "$T/llave" "$T/b7.sh"
corre "$T/b7.sh"
espera "misma versión: no reinstala" '(( rc != 0 )) && grep -q "no es más nueva" <<<"$o"'

bundle "$T/b7b.sh" 4.19.10; firma "$T/llave" "$T/b7b.sh"
corre "$T/b7b.sh"
espera "4.19.10 > 4.19.0 (orden de versiones, no de texto)" '(( rc == 0 )) && grep -q "^SI versión 4.19.10 > instalada 4.19.0" <<<"$o"'

bundle "$T/b8.sh" 4.20.0 falla; firma "$T/llave" "$T/b8.sh"
corre "$T/b8.sh"
espera "prueba que falla: no instala" '(( rc != 0 )) && grep -q "^NO fallaron pruebas" <<<"$o"'

bundle "$T/b9.sh" 4.20.0 fuera; firma "$T/llave" "$T/b9.sh"
corre "$T/b9.sh"
espera "archivo fuera del MANIFIESTO: NO" '(( rc != 0 )) && grep -q "fuera del MANIFIESTO" <<<"$o"'

bundle "$T/b10.sh" 4.20.0 cabecera; firma "$T/llave" "$T/b10.sh"
corre "$T/b10.sh"
espera "cabecera ≠ versión: NO" '(( rc != 0 )) && grep -q "cabecera del bundle" <<<"$o"'

bundle "$T/b11.sh" 4.20.0; firma "$T/llave" "$T/b11.sh"
o=$(bash "$GA" "$T/b11.sh" --sin-instalar 2>&1); rc=$?
espera "copia sin llave fijada (marcador o real): solo acepta su propia llave" \
  '(( rc != 0 )) && grep -qE "no tiene llave pública fijada|FIRMA NO VÁLIDA" <<<"$o"'

o=$(bash "$T/ga" "$T/b1.sh" 2>&1); rc=$?
espera "instalar sin root: NO" '(( rc != 0 )) && grep -q "necesita root" <<<"$o"'

espera "el bundle no se ejecuta (no hay bash del bundle en el código)" '[[ -f "$GA" ]] && ! grep -qE "bash \"?\\\$TMP/bundle.sh" "$GA"'
espera "llave REAL fijada (ed25519, no el marcador)" 'grep -qE "^readonly LLAVE_PUBLICA=\"ssh-ed25519 [A-Za-z0-9+/]{60,}=*\"$" "$GA"'
echo "$P passed, $F failed"
(( F == 0 ))
