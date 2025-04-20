{ config, lib, pkgs, ... }:

with lib;

let

  syncWithPhare = pkgs.callPackage ../tools/sync-with-phare.nix { };

  standaloneMonitors = mapAttrs (monitorName: monitorConfig:
    let name = if monitorConfig.name != null
      then monitorConfig.name
      else monitorName;
    in monitorConfig // { inherit name; }
  ) config.services.phare.monitors;


  nginxMonitors = mapAttrs (virtualHost: vhc: let
      name = if vhc.phare.name != null
             then vhc.phare.name
             else virtualHost;
      request = if vhc.phare.request != null
        then vhc.phare.request
        else {
          method = "GET";
          url = (if vhc.forceSSL then "https" else "http") + "://" +  virtualHost;
        };
    in vhc.phare // { inherit name request; }
  ) (filterAttrs ( _: vhc: vhc.enablePhare) config.services.nginx.virtualHosts);

  monitors-json = pkgs.writeText "monitors.json" (builtins.toJSON monitors);
  nginx-monitors-json = pkgs.writeText "nginx-monitors.json" (builtins.toJSON nginxMonitors);
  monitors = standaloneMonitors // nginxMonitors;

  regionType = types.listOf (types.enum [
           "as-jpn-hnd"
           "as-sgp-sin"
           "eu-deu-fra"
           "eu-gbr-lhr"
           "eu-swe-arn"
           "na-mex-mex"
           "na-usa-sea"
           "na-usa-iad"

           "as-jpn-hnd"
           "eu-deu-fra"
           "na-usa-iad"
           "na-usa-sea"
           "oc-aus-syd"
           "sa-bra-gru"
      ]);

  options = {
    alertPolicyId = mkOption {
      type = types.ints.positive;
      default = config.services.phare.alertPolicyId;
      description = "The ID of the associated alert policy.";
    };
    projectId = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "The associated project.";
    };
    name = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "The name of the monitor. Defaults to attribute name in monitors.";
    };
    protocol = mkOption {
      type = types.enum [
           "http"
           "tcp"
      ];
      default = "http";
      description = "Whether the monitor should use http of tcp to access the resource.";
    };

    request = mkOption {
      type = types.nullOr types.attrs;
      default = null;
      description = "Monitoring request, depends of the chosen protocol.";
    };
    interval = mkOption {
      type = types.enum [
           30
           60
           120
           180
           300
           600
           900
           1800
           3600
      ];
      default = 60;
      description = "Monitoring interval in seconds.";
    };
    timeout = mkOption {
      type = types.enum [
           1000
           2000
           3000
           4000
           5000
           6000
           7000
           8000
           9000
           10000
           15000
           20000
           25000
           30000
      ];
      default = 7000;
      description = "Monitoring timeout in milliseconds.";
    };
    incidentConfirmations = mkOption {
      type = types.enum [ 1 2 3 4 5 ];
      default = 1;
      description = "Number of uninterrupted failed checks required to create an incident";
    };
    recoveryConfirmations = mkOption {
      type = types.enum [ 1 2 3 4 5 ];
      default = 1;
      description = "Number of uninterrupted successful checks required to resolve an incident";
    };
    regions = mkOption {
      type = regionType;
      default = config.services.phare.regions;
      description = "List of regions where monitoring checks are performed";
    };
  };

in {
  options = {
    services.phare.enable = mkEnableOption "Whether to enable phare.io management";

    services.phare.tokenFile = mkOption {
      type = types.str;
      default = null;
      description = "Path to a file with the API key to access phare.io. It needs read and write access to 'Uptime'.";
    };

    services.phare.alertPolicyId = mkOption {
      type = types.ints.positive;
      description = "The ID of the associated alert policy.";
    };

    services.phare.regions = mkOption {
      type = regionType;
      default = [ "eu-deu-muc" "eu-swe-arn" ];
      description = "List of regions where monitoring checks are performed";
    };

    services.phare.monitors = mkOption {
      type = types.attrsOf (types.submodule { inherit options; } );
      default = { };
    };

    services.nginx.virtualHosts =  mkOption {
      type = types.attrsOf (types.submodule {
        options.enablePhare = mkEnableOption "Whether to enable phare.io management for the virtualhost";
        options.phare = options;
      } );
    };
  };

  config = mkIf config.services.phare.enable {
    systemd.services.phare-monitors = {
      description = "Apply the phare monitor config";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        PHARE_TOKEN_FILE = config.services.phare.tokenFile;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${syncWithPhare}/bin/sync-with-phare --monitorfile ${monitors-json}";
        RemainAfterExit = "yes";
        TimeoutSec = "infinity";
        StandardOutput = "journal+console";
        
      };
    };
    
  };

}
