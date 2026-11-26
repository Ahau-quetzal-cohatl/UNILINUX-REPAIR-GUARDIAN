#!/bin/bash
# test-gentoo.sh (4.18.2): revisión de paquetes con portage/qcheck (formato medido en gentoo-lab2).
# Uso: bash tests/test-gentoo.sh [directorio bin]   (contra 4.18.1 FALLA)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
GU=$B/guardian
FP=$(sed -n '/^diagnosticar_portage() {/,/^}/p' "$GU" 2>/dev/null); FG=$(sed -n '/^gestor_paquetes() {/,/^}/p' "$GU" 2>/dev/null)
espera "guardian: diagnosticar_portage y portage en gestor_paquetes" '[[ -n "$FP" ]] && grep -q "echo portage" <<<"$FG"'
espera "guardian: caso portage en diagnosticar_paquetes" 'sed -n "/^diagnosticar_paquetes() {/,/^}/p" "$GU" | grep -q "portage) diagnosticar_portage; return 0 ;;"'
espera "guardian: xbps y apk siguen en gestor_paquetes" 'grep -q "echo xbps" <<<"$FG" && grep -q "echo apk" <<<"$FG"'
espera "guardian pasa bash -n" 'bash -n "$GU"'
mkdir -p "$T/pbin" "$T/db/sys-fs/e2fsprogs-1.47.1" "$T/db/sys-apps/portage-3.0.68" "$T/db/app-text/sgml-common-0.6.3-r7" "$T/vacia"
# qcheck como el real (portage-utils 0.97.1): «Checking ATOM ...», « AFK: /ruta», « MD5-DIGEST: /ruta», « MTIME: /ruta»,
# «  * N out of M files are good»; rc=1 ya en un Gentoo sano (/etc/sgml/catalog, .keep, /usr/src).
cat >"$T/pbin/qcheck" <<'Q'
#!/bin/bash
printf '\033[32mChecking\033[0m app-text/sgml-common-0.6.3-r7 ...\n MD5-DIGEST: /etc/sgml/catalog\n  * 9 out of 10 files are good\n'
printf 'Checking sys-apps/portage-3.0.68 ...\n MTIME: /var/log/portage/elog/.keep_sys-apps_portage-0\n  * 300 out of 301 files are good\n'
printf 'Checking sys-kernel/gentoo-kernel-bin-6.18.64_p1 ...\n AFK: /usr/src/linux-6.18.64-p1-gentoo-dist-bin/arch/x86/boot/initrd\n  * 50 out of 51 files are good\n'
printf 'Checking sys-fs/e2fsprogs-1.47.1 ...\n'
case "${MODO:-}" in
  borrado)  printf ' AFK: /usr/bin/lsattr\n  * 218 out of 219 files are good\n' ;;
  alterado) printf ' MD5-DIGEST: /usr/bin/lsattr\n  * 218 out of 219 files are good\n' ;;
  dos)      printf ' AFK: /usr/bin/lsattr\n  * 218 out of 219 files are good\n'
            printf 'Checking app-shells/bash-5.2_p37 ...\n SHA1-DIGEST: /bin/bash\n MD5-DIGEST: /usr/bin/bashbug\n  * 98 out of 100 files are good\n' ;;
  *)        printf '  * 219 out of 219 files are good\n' ;;
esac
exit 1
Q
printf '#!/bin/sh\n[ "${EMERGE_OCUPADO:-0}" = 1 ]\n' >"$T/pbin/pgrep"
printf '#!/bin/sh\nexit 0\n' >"$T/pbin/emerge"; chmod +x "$T/pbin/"*
cat >"$T/gp.sh" <<GP
ok() { echo "OK \$*"; }; warn() { echo "WARN \$*"; }; info() { echo "INFO \$*"; }; log() { :; }
rpm_db_presente() { false; }
LISTA_AVISOS=()
$FG
$FP
GP
BA=$(command -v bash)
dp() { env -i PATH="${DPPATH:-$T/pbin:/usr/bin:/bin}" MODO="${MODO:-}" EMERGE_OCUPADO="${EMERGE_OCUPADO:-0}" GUARDIAN_PORTAGEDB="${DB:-$T/db}" GUARDIAN_APKDB="$T/no" GUARDIAN_XBPSDB="$T/no" "$BA" -c ". $T/gp.sh; $1"; }
# gestor_paquetes mira dpkg/pacman/rpm antes que portage: con PATH solo de pbin el anfitrión (Debian) no estorba.
espera "gestor: emerge con /var/db/pkg → portage" '[[ "$(DPPATH=$T/pbin dp gestor_paquetes)" == portage ]]'
espera "gestor: sin la base → no es portage" '[[ "$(DPPATH=$T/pbin DB=$T/no dp gestor_paquetes)" != portage ]]'
o=$(MODO= dp diagnosticar_portage)
espera "sano (qcheck rc=1 por /etc, MTIME y /usr/src): 2 OK, ningún WARN" '[[ "$(grep -c ^OK <<<"$o")" == 2 ]] && ! grep -q ^WARN <<<"$o" && grep -q "legible (3 paquetes)" <<<"$o"'
o=$(MODO=borrado dp diagnosticar_portage)
espera "archivo borrado → WARN 1 en sys-fs/e2fsprogs (sin versión)" 'grep -q "^WARN qcheck: 1 archivo(s) cambiado(s) o ausente(s) en: sys-fs/e2fsprogs$" <<<"$o"'
o=$(MODO=alterado dp diagnosticar_portage)
espera "archivo alterado (MD5-DIGEST) → WARN 1" 'grep -q "^WARN qcheck: 1 archivo(s) cambiado(s) o ausente(s) en: sys-fs/e2fsprogs$" <<<"$o"'
o=$(MODO=dos dp diagnosticar_portage)
espera "dos paquetes (SHA1/MD5) → WARN 3 en app-shells/bash sys-fs/e2fsprogs" 'grep -q "^WARN qcheck: 3 archivo(s) cambiado(s) o ausente(s) en: app-shells/bash sys-fs/e2fsprogs$" <<<"$o"'
o=$(MODO=dos dp 'diagnosticar_portage >/dev/null; printf "%s\n" "${LISTA_AVISOS[@]}"')
espera "aviso en la lista con el arreglo (emerge -1)" 'grep -q "emerge -1 PAQUETE" <<<"$o"'
o=$(DB=$T/vacia dp diagnosticar_portage)
espera "base vacía → WARN y no corre qcheck" 'grep -q "^WARN No se puede leer la base de datos de portage" <<<"$o" && ! grep -q qcheck: <<<"$o"'
o=$(EMERGE_OCUPADO=1 dp diagnosticar_portage)
espera "emerge trabajando → INFO, no revisa" 'grep -q "^INFO Hay un emerge trabajando" <<<"$o" && ! grep -q ^OK <<<"$o"'
rm -f "$T/pbin/qcheck"
# 4.19.1: dentro de Gentoo existe /usr/bin/qcheck real: PATH de enlaces sin qcheck
mkdir -p "$T/sinq"; for x in /usr/bin/* /bin/*; do [[ ${x##*/} == qcheck ]] || ln -sf "$x" "$T/sinq/${x##*/}"; done
o=$(DPPATH=$T/pbin:$T/sinq dp diagnosticar_portage)
espera "sin qcheck → OK de la base + INFO, sin WARN" 'grep -q "^INFO qcheck (app-portage/portage-utils) no está" <<<"$o" && ! grep -q ^WARN <<<"$o"'
echo "$P passed, $F failed"
(( F == 0 ))
