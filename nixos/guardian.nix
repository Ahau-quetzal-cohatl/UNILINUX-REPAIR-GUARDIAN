# guardian.nix — Guardian 4.19.1 para NixOS (4.18.6 probado en nixos-lab1 v1.1: NIXOS_LAB1_OK 30/30, nixpkgs 26.05).
# Uso: copia la carpeta de Guardian (con bin/ y nixos/) a /etc/nixos/guardian y en configuration.nix:
#   imports = [ ./guardian/nixos/guardian.nix ];  guardian.enable = true;
#   (opcional) guardian.earlyConf = '' ON_FAIL=… BACKUP_UUID=… '';   luego: sudo nixos-rebuild boot
# guardian-early corre ANTES de montar la raíz: stage-1 de scripts → postDeviceCommands (tras udev y
# LVM/LUKS, antes de mountFS); stage-1 con systemd → guardian-early.service antes de sysroot.mount.
# Fase tardía: guardian-late.service (una vez por arranque, nunca hace fallar el arranque).
{ config, lib, pkgs, ... }:
let
  cfg = config.guardian;
  sd = config.boot.initrd.systemd.enable;
  rootDev = config.fileSystems."/".device;
  pkg = pkgs.runCommand "guardian-${cfg.version}" { buildInputs = [ pkgs.bash ]; } ''
    mkdir -p $out/lib/guardian $out/bin
    install -m 0755 ${cfg.src}/bin/guardian $out/lib/guardian/guardian
    install -m 0755 ${cfg.src}/bin/guardian-early $out/lib/guardian/guardian-early
    patchShebangs --host $out/lib/guardian/guardian
    ln -s $out/lib/guardian/guardian $out/bin/guardian
    if [ -f ${cfg.src}/bin/guardian-actualizar ]; then   # 4.19.1: solo verifica en NixOS (instalar = nixos-rebuild)
      install -m 0755 ${cfg.src}/bin/guardian-actualizar $out/lib/guardian/guardian-actualizar
      patchShebangs --host $out/lib/guardian/guardian-actualizar
      ln -s $out/lib/guardian/guardian-actualizar $out/bin/guardian-actualizar
    fi
  '';
  earlyFile = pkgs.writeText "guardian-early.conf" cfg.earlyConf;
  guardianDf = pkgs.writeShellScript "guardian-df" ''exec ${pkgs.coreutils}/bin/df "$@"'';
in
{
  options.guardian = {
    enable = lib.mkEnableOption "Guardian (revisión y reparación de la raíz al arrancar)";
    version = lib.mkOption { type = lib.types.str; default = "4.19.1"; };
    src = lib.mkOption { type = lib.types.path; default = ./..; description = "Carpeta de Guardian (con bin/guardian y bin/guardian-early)."; };
    earlyConf = lib.mkOption {
      type = lib.types.lines;
      default = ''
        ON_FAIL=respaldo_y_forzar
        BACKUP_MIN_MB=512
        META_MIN_MB=2048
      '';
    };
    late = lib.mkOption { type = lib.types.bool; default = true; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      boot.initrd.availableKernelModules = [ "ext4" "vfat" "nls_cp437" "nls_iso8859_1" ];
      environment.systemPackages = [ pkg pkgs.smartmontools ];   # el PATH fijo de guardian ve /run/current-system/sw/bin
      environment.etc."guardian/early.conf".source = earlyFile;
    }
    (lib.mkIf (!sd) {
      boot.initrd.extraUtilsCommands = ''
        cp -pv ${pkg}/lib/guardian/guardian-early $out/bin/guardian-early
        chmod 0755 $out/bin/guardian-early
        for b in e2fsck e2image blkid; do
          for d in ${pkgs.e2fsprogs}/bin ${pkgs.e2fsprogs}/sbin ${pkgs.util-linux}/bin ${pkgs.util-linux}/sbin; do
            if [ -e $d/$b ]; then copy_bin_and_libs "$(readlink -f $d/$b)"; break; fi
          done
        done
        DF=$(readlink -f ${pkgs.coreutils}/bin/df)
        if [ "$(basename "$DF")" = df ]; then
          cp -pv "$DF" $out/bin/guardian-df
        else
          cp -pv "$DF" $out/bin/coreutils-guardian
          chmod 0755 $out/bin/coreutils-guardian
          printf '#!%s/bin/sh\nexec %s/bin/coreutils-guardian --coreutils-prog=df "$@"\n' "$out" "$out" > $out/bin/guardian-df
        fi
        chmod 0755 $out/bin/guardian-df
      '';
      boot.initrd.extraUtilsCommandsTest = ''
        $out/bin/guardian-df --version >/dev/null
      '';
      boot.initrd.postDeviceCommands = lib.mkAfter ''
        # >>> guardian (nixos)
        mkdir -p /etc /usr/bin
        printf '%s\n' ${lib.escapeShellArg cfg.earlyConf} > /etc/guardian-early.conf
        [ -e /usr/bin/guardian-df ] || ln -s "$(command -v guardian-df)" /usr/bin/guardian-df
        ROOT=${lib.escapeShellArg rootDev} GUARDIAN_EARLY_CONF=/etc/guardian-early.conf sh "$(command -v guardian-early)" || :
        # <<< guardian (nixos)
      '';
    })
    (lib.mkIf sd {
      boot.initrd.systemd = {
        initrdBin = [ pkgs.e2fsprogs ];
        extraBin = {
          guardian-early = "${pkg}/lib/guardian/guardian-early";
          guardian-df = "${guardianDf}";
          blkid = "${pkgs.util-linux}/bin/blkid";
        };
        contents."/etc/guardian-early.conf".source = earlyFile;
        storePaths = [ "${pkgs.bash}/bin/bash" ];
        services.guardian-early = {
          description = "Guardian early: revisa la raiz antes de montarla";
          wantedBy = [ "initrd-root-fs.target" ];
          after = [ "initrd-root-device.target" "systemd-hibernate-resume.service" ];
          before = [ "systemd-fsck-root.service" "sysroot.mount" "initrd-root-fs.target" "shutdown.target" ];
          conflicts = [ "shutdown.target" ];
          unitConfig = { DefaultDependencies = false; ConditionPathExists = "/etc/initrd-release"; };
          environment = { ROOT = rootDev; GUARDIAN_EARLY_CONF = "/etc/guardian-early.conf"; PATH = lib.mkForce "/bin:/sbin"; };
          serviceConfig = {
            Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = 0;
            ExecStart = "${pkgs.bash}/bin/bash /bin/guardian-early";
            StandardOutput = "journal+console"; StandardError = "journal+console";
          };
        };
      };
    })
    (lib.mkIf cfg.late {
      systemd.services.guardian-late = {
        description = "Guardian: revision tardia (una vez por arranque)";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        unitConfig.ConditionPathExists = "!/run/guardian.skip";
        path = [ pkgs.bash pkgs.coreutils pkgs.util-linux pkgs.e2fsprogs pkgs.gnugrep pkgs.gnused pkgs.gawk
                 pkgs.findutils pkgs.procps pkgs.kmod pkgs.smartmontools config.systemd.package config.nix.package ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = 420; };
        script = ''
          timeout 300 ${pkg}/lib/guardian/guardian --no-music --no-packages > /var/log/guardian-late.log 2>&1 || :
        '';
      };
    })
  ]);
}
