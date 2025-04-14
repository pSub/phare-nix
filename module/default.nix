{ config, lib, pkgs, ... }:

with lib;

let

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

  monitors = standaloneMonitors // nginxMonitors;

  monitors-json = pkgs.writeText "monitors.json" (builtins.toJSON monitors);

  nginx-monitors-json = pkgs.writeText "nginx-monitors.json" (builtins.toJSON nginxMonitors);

  curl = "${pkgs.curl}/bin/curl --fail --silent";

  list-monitors = pkgs.writeShellScript "list-monitors" ''
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${curl} --request GET \
      --url https://api.phare.io/uptime/monitors \
      --header "Authorization: Bearer $TOKEN"
  '';

  update-monitor = pkgs.writeShellScript "update-monitor" ''
    MONITOR_ID=$1
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${curl} --request POST \
      --url https://api.phare.io/uptime/monitors/"$MONITOR_ID" \
      --header "Authorization: Bearer $TOKEN" \
      --header 'Content-Type: application/json' \
      --data @- > /dev/null
  '';

  create-monitor = pkgs.writeShellScript "create-monitor" ''
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${curl} --request POST \
      --url https://api.phare.io/uptime/monitors \
      --header "Authorization: Bearer $TOKEN" \
      --header 'Content-Type: application/json' \
      --data @- > /dev/null
  '';

  pause-monitor = pkgs.writeShellScript "pause-monitor" ''
    MONITOR_ID=$1
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${curl} --request POST \
      --url https://api.phare.io/uptime/monitors/"$MONITOR_ID"/pause \
      --header "Authorization: Bearer $TOKEN"
  '';

  resume-monitor = pkgs.writeShellScript "resume-monitor" ''
    MONITOR_ID=$1
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${curl} --request POST \
      --url https://api.phare.io/uptime/monitors/"$MONITOR_ID"/resume \
      --header "Authorization: Bearer $TOKEN"
  '';


  update-monitors = pkgs.writeShellScript "update-monitors" ''
    declare -A ids=()
    declare -A status=()
    declare -A jsons=()

    ignore=".id, .response_time, .response_time, .updated_at, .created_at, .paused, .status"

    upstream=$(${list-monitors})

    while read json; do
      IFS=$'\t' read name id paused < <(${pkgs.jq}/bin/jq -r '[.name, .id, .paused] | @tsv' <<< "$json")

      ids["$name"]="$id"
      status["$name"]="$paused"
      jsons["$name"]="$json"
    done < <(${pkgs.jq}/bin/jq -r -c '.data[]' <<< "$upstream")

    while read monitor; do
      name=$(${pkgs.jq}/bin/jq -r '.name' <<< "$monitor")
      if [[ -v ids["$name"] ]]; then

        if [[ "''${status[$name]}" == "true" ]]; then
          echo "Resuming monitor $name"
          ${resume-monitor} ''${ids["$name"]}
        fi

        ${pkgs.jq}/bin/jq -e 'has(".project_id")' <<< "$monitor" &> /dev/null
        if [[ $? -ne 0 ]]; then
          ignore+=", .project_id"
        fi

        ${pkgs.jq}/bin/jq -e 'has(".request.keyword")' <<< "$monitor" &> /dev/null
        if [[ $? -ne 0 ]]; then
          ignore+=", .request.keyword"
        fi

        monitorSnakeCase=$(${pkgs.jq}/bin/jq --sort-keys -f ${camelCaseToSnakeCase} <<< "$monitor")

        ${pkgs.diffutils}/bin/diff &> /dev/null <(${pkgs.jq}/bin/jq --sort-keys "del($ignore)" <<< "''${jsons["$name"]}") \
             <(echo "$monitorSnakeCase") 

        if [[ $? -ne 0 ]]; then
          echo "Updating monitor $name"
          ${pkgs.jq}/bin/jq --arg m "''${ids["$name"]}" '. += {"id":$m}' <<< "$monitorSnakeCase" \
            | ${update-monitor} ''${ids["$name"]}
        else
          echo "Monitor $name is up-to-date with phare.io"
        fi

        unset ids["$name"]

       else
        echo "Creating monitor with name $name"
        ${pkgs.jq}/bin/jq -f ${camelCaseToSnakeCase} <<< "$monitor" | ${create-monitor}
       fi
    done < <(cat ${monitors-json} | ${pkgs.jq}/bin/jq -c '.[]')

    for name in "''${!ids[@]}"; do
      if [[ "''${status[$name]}" != "true" ]]; then
        echo "Pausing monitor $name"
        ${pause-monitor} "''${ids[$name]}"
      fi
    done
  '';

  # Copied from https://gist.github.com/reegnz/5bceb53427008a4ff9367eb8eae97b85
  camelCaseToSnakeCase = pkgs.writeText "camelCaseToSnakeCase" ''
    def map_keys(mapper):
      walk(
        if type == "object"
        then
          with_entries({
            key: (.key|mapper),
    	value
          })
        else .
        end
      );

    def camel_to_snake:
      [
        splits("(?=[A-Z])")
      ]
      |map(
        select(. != "")
        | ascii_downcase
      )
      | join("_");

    def snake_to_camel:
      split("_")
      | map(
        split("")
        | .[0] |= ascii_upcase
        | join("")
      )
      | join("");

    map_keys(camel_to_snake)
      '';

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

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${update-monitors}";
        RemainAfterExit = "yes";
        TimeoutSec = "infinity";
        StandardOutput = "journal+console";
      };
    };
    
  };

}
