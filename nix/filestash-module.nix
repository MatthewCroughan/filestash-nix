{ config, lib, pkgs, ... }:
let
  cfg = config.services.filestash;
in {
  options.services.filestash = {
    enable = lib.mkEnableOption "filestash";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.filestash;
      defaultText = "pkgs.filestash";
      description = ''
        Which filestash package to use.
      '';
    };
    dataDir = lib.mkOption {
      default = "/var/lib/filestash";
      type = lib.types.str;
    };
  };
  config = lib.mkIf cfg.enable {
    systemd = {
      tmpfiles.rules = [
        "d  ${cfg.dataDir}/data        0771 - - - -"
        "d  ${cfg.dataDir}/data/state  0771 - - - -"
      ];
      services.filestash = {
        description = "A modern web client for SFTP and more";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.bash}/bin/bash -c 'WORK_DIR=$STATE_DIRECTORY ${lib.getExe cfg.package}'";
          Restart = "always";
          DynamicUser = true;
          StateDirectory = baseNameOf cfg.dataDir;
        };
      };
    };
  };
}
