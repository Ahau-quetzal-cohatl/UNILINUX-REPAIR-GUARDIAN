#!/bin/bash
# test-nixos.sh (4.18.5): revisión de paquetes con Nix (formato medido en nixos-lab1) y el módulo nixos/guardian.nix.
# Uso: bash tests/test-nixos.sh [directorio bin]   (contra 4.18.2 FALLA)
B=${1:-$(cd "$(dirname "$0")/../bin" && pwd)}
P=0; F=0
espera() { if eval "$2"; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FALLA $1"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
GU=$B/guardian; MO=$B/../nixos/guardian.nix
FN=$(sed -n '/^diagnosticar_nix() {/,/^}/p' "$GU" 2>/dev/null); FG=$(sed -n '/^gestor_paquetes() {/,/^}/p' "$GU" 2>/dev/null)
espera "guardian: diagnosticar_nix y nix en gestor_paquetes" '[[ -n "$FN" ]] && grep -q "echo nix$" <<<"$FG"'
espera "guardian: caso nix en diagnosticar_paquetes" 'sed -n "/^diagnosticar_paquetes() {/,/^}/p" "$GU" | grep -q "nix) diagnosticar_nix; return 0 ;;"'
espera "guardian: portage, xbps y apk siguen en gestor_paquetes" 'grep -q "echo portage" <<<"$FG" && grep -q "echo xbps" <<<"$FG" && grep -q "echo apk" <<<"$FG"'
espera "guardian: nix va después de portage" '[[ "$(grep -n "echo portage" <<<"$FG" | cut -d: -f1)" -lt "$(grep -n "echo nix$" <<<"$FG" | cut -d: -f1)" ]]'
espera "guardian pasa bash -n" 'bash -n "$GU"'
espera "guardian: PATH fijo con las de siempre y luego las de NixOS" 'grep -qx "export PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin\".*" "$GU" && [[ "$(grep -c "^export PATH=" "$GU")" == 1 ]]'
espera "guardian: el espacio no cuenta erofs/iso9660/cramfs (NixOS /etc)" 'grep -q "df -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x erofs -x iso9660 -x cramfs" "$GU"'
mkdir -p "$T/pbin" "$T/nixdb"
# nix-store como el real (Nix 2.31.5, nixos-lab1): «checking path existence...», «checking hashes...»,
# «path '/nix/store/<32>-nano-9.3' was modified! expected hash 'sha256:…', got 'sha256:…'», rc=1.
cat >"$T/pbin/nix-store" <<'NS'
#!/bin/bash
[[ "$*" == "--verify --check-contents" ]] || { echo "args malos: $*" >&2; exit 9; }
echo "checking path existence..." >&2; echo "checking hashes..." >&2
case "${MODO:-}" in
  una) echo "path '/nix/store/0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p-nano-9.3' was modified! expected hash 'sha256:1aaa', got 'sha256:1bbb'" >&2; exit 1 ;;
  dos) echo "path '/nix/store/0a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p-nano-9.3' was modified! expected hash 'sha256:1aaa', got 'sha256:1bbb'" >&2
       echo "path '/nix/store/9z8y7x6w5v4u3t2s1r0q9p8o7n6m5l4k-bash-5.3p3' was modified! expected hash 'sha256:2aaa', got 'sha256:2bbb'" >&2; exit 1 ;;
  falla) echo "error: opening lock file '/nix/var/nix/db/big-lock': Permission denied" >&2; exit 1 ;;
  lento) exit 124 ;;
  *) exit 0 ;;
esac
NS
printf '#!/bin/sh\n[ "${NIX_OCUPADO:-0}" = 1 ]\n' >"$T/pbin/pgrep"; chmod +x "$T/pbin/"*
cat >"$T/gp.sh" <<GP
ok() { echo "OK \$*"; }; warn() { echo "WARN \$*"; }; info() { echo "INFO \$*"; }; log() { :; }
rpm_db_presente() { false; }
LISTA_AVISOS=()
$FG
$FN
GP
BA=$(command -v bash)
# PATH solo de pbin (+ sed/grep/sort del anfitrión en $T/hbin): el dpkg del anfitrión (Debian) no estorba al gestor.
mkdir -p "$T/hbin"; for c in sed grep sort head tr cut timeout env; do ln -s "$(command -v $c)" "$T/hbin/$c"; done
dp() { env -i PATH="$T/pbin:$T/hbin" MODO="${MODO:-}" NIX_OCUPADO="${NIX_OCUPADO:-0}" GUARDIAN_NIXDB="${DB:-$T/nixdb}" GUARDIAN_PORTAGEDB="$T/no" GUARDIAN_APKDB="$T/no" GUARDIAN_XBPSDB="$T/no" "$BA" -c ". $T/gp.sh; $1"; }
espera "gestor: nix-store con la base → nix" '[[ "$(dp gestor_paquetes)" == nix ]]'
espera "gestor: sin la base → no es nix" '[[ "$(DB=$T/no dp gestor_paquetes)" != nix ]]'
o=$(MODO= dp diagnosticar_nix)
espera "sana → OK, ningún WARN" 'grep -q "^OK Tienda de Nix intacta" <<<"$o" && ! grep -q ^WARN <<<"$o"'
o=$(MODO=una dp diagnosticar_nix)
espera "una ruta alterada → WARN 1 nano-9.3 (sin hash)" 'grep -q "^WARN Tienda de Nix: 1 ruta(s) modificada(s): nano-9.3$" <<<"$o"'
o=$(MODO=dos dp diagnosticar_nix)
espera "dos rutas → WARN 2 bash-5.3p3 nano-9.3" 'grep -q "^WARN Tienda de Nix: 2 ruta(s) modificada(s): bash-5.3p3 nano-9.3$" <<<"$o"'
o=$(MODO=dos dp 'diagnosticar_nix >/dev/null; printf "%s\n" "${LISTA_AVISOS[@]}"')
espera "aviso en la lista con el arreglo (--repair-path)" 'grep -q "nix-store --repair-path RUTA" <<<"$o"'
o=$(MODO=falla dp diagnosticar_nix)
espera "verify falla sin rutas → WARN con el motivo" 'grep -q "^WARN nix-store --verify falló (rc=1): error: opening lock file" <<<"$o"'
o=$(MODO=lento dp diagnosticar_nix)
espera "rc=124 (tiempo) → INFO, sin WARN" 'grep -q "^INFO nix-store --verify tardó" <<<"$o" && ! grep -q ^WARN <<<"$o"'
o=$(NIX_OCUPADO=1 dp diagnosticar_nix)
espera "Nix trabajando → INFO, no revisa" 'grep -q "^INFO Nix está trabajando" <<<"$o" && ! grep -q ^OK <<<"$o"'
# módulo
espera "nixos/guardian.nix existe" '[[ -f "$MO" ]]'
espera "módulo: version 4.19.1 y src = ./.." 'grep -q "default = \"4.19.1\";" "$MO" && grep -q "default = ./..;" "$MO"'
espera "módulo: bloque de scripts y unidad con systemd" 'grep -q "# >>> guardian (nixos)" "$MO" && grep -q "services.guardian-early" "$MO" && grep -q "before = \[ \"systemd-fsck-root.service\" \"sysroot.mount\"" "$MO"'
espera "módulo: smartmontools en environment.systemPackages" 'grep -q "environment.systemPackages = \[ pkg pkgs.smartmontools \];" "$MO"'
espera "módulo: blkid en el initrd con systemd y guardian-late" 'grep -q "blkid = \"\${pkgs.util-linux}/bin/blkid\";" "$MO" && grep -q "systemd.services.guardian-late" "$MO"'
if command -v nix-instantiate >/dev/null 2>&1; then
  espera "módulo: nix-instantiate --parse" 'nix-instantiate --parse "$MO" >/dev/null 2>&1'
else echo "(sin nix-instantiate: no se analiza la sintaxis Nix)"; fi
echo "$P passed, $F failed"
(( F == 0 ))
