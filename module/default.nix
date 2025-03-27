{ config, lib, pkgs, ... }:

with lib;

let

  monitors = mapAttrs (monitorName: monitorConfig:
    let name = if monitorConfig.name != null
      then monitorConfig.name
      else monitorName;
    in monitorConfig // { inherit name; }
  ) config.services.phare.monitors;

  monitors-json = pkgs.writeText "monitors.json" (builtins.toJSON monitors);

  list-monitors = pkgs.writeShellScript "list-monitors" ''
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${pkgs.curl}/bin/curl --request GET \
      --url https://api.phare.io/uptime/monitors \
      --header "Authorization: Bearer $TOKEN"
  '';

  update-monitor = pkgs.writeShellScript "update-monitor" ''
    MONITOR_ID=$1
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${pkgs.curl}/bin/curl --request POST \
      --url https://api.phare.io/uptime/monitors/"$MONITOR_ID" \
      --header "Authorization: Bearer $TOKEN" \
      --header 'Content-Type: application/json' \
      --data @-
 '';

  create-monitor = pkgs.writeShellScript "create-monitor" ''
    TOKEN=$(cat ${config.services.phare.tokenFile})
    ${pkgs.curl}/bin/curl --request POST \
      --url https://api.phare.io/uptime/monitors \
      --header "Authorization: Bearer $TOKEN" \
      --header 'Content-Type: application/json' \
      --data @-
 '';

  update-monitors = pkgs.writeShellScript "update-monitors" ''
    declare -A ids=()

    while IFS="=" read -r name id; do
      ids["$name"]="$id"
    done < <(${list-monitors} | ${pkgs.jq}/bin/jq -r '.data[] | "\(.name)=\(.id)"')

    cat ${monitors-json} | ${pkgs.jq}/bin/jq -c '.[]' | while read monitor; do
      name=$(echo "$monitor" | ${pkgs.jq}/bin/jq -r '.name')
      if [[ -v ids["$name"] ]]; then
         echo "$monitor" | ${pkgs.jq}/bin/jq --arg m "''${ids["$name"]}" '. += {"id":$m}' \
          | ${pkgs.jq}/bin/jq -f ${camelCaseToSnakeCase} \
          | ${update-monitor} ''${ids["$name"]}
       else
         echo "$monitor" | ${pkgs.jq}/bin/jq -f ${camelCaseToSnakeCase} | ${create-monitor}
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

in {
  options = {
    services.phare.enable = mkEnableOption "Whether to enable phare.io management";

    services.phare.tokenFile = mkOption {
      type = types.str;
      default = null;
      description = "Path to a file with the API key to access phare.io. It needs read and write access to 'Uptime'.";
    };

    services.phare.monitors = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.alertPolicyId = mkOption {
            type = types.ints.positive;
            description = "The ID of the associated alert policy.";
          };
          options.name = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "The name of the monitor. Defaults to attribute name in monitors.";
          };
          options.protocol = mkOption {
            type = types.enum [
                 "http"
                 "tcp"
            ];
            default = "http";
            description = "Whether the monitor should use http of tcp to access the resource.";
          };

          options.request = mkOption {
            type = types.attrs;
            description = "Monitoring request, depends of the chosen protocol.";
          };
          options.interval = mkOption {
            type = types.enum [
                 "30"
                 "60"
                 "120"
                 "180"
                 "300"
                 "600"
                 "900"
                 "1800"
                 "3600"
            ];
            default = "60";
            description = "Monitoring interval in seconds.";
          };
          options.timeout = mkOption {
            type = types.enum [
                 "1000"
                 "2000"
                 "3000"
                 "4000"
                 "5000"
                 "6000"
                 "7000"
                 "8000"
                 "9000"
                 "10000"
                 "15000"
                 "20000"
                 "25000"
                 "30000"
            ];
            default = "7000";
            description = "Monitoring timeout in milliseconds.";
          };
          options.incidentConfirmations = mkOption {
            type = types.enum [ 1 2 3 4 5 ];
            default = 1;
            description = "Number of uninterrupted failed checks required to create an incident";
          };
          options.recoveryConfirmations = mkOption {
            type = types.enum [ 1 2 3 4 5 ];
            default = 1;
            description = "Number of uninterrupted successful checks required to resolve an incident";
          };
          options.regions = mkOption {
            type = types.listOf (types.enum [
                 "as-ind-bom"
                 "as-jpn-nrt"
                 "as-sgp-sin"
                 "eu-deu-muc"
                 "eu-gbr-lhr"
                 "eu-swe-arn"
                 "na-mex-mex"
                 "na-usa-pdx"
                 "na-usa-ric"
            ]);
            default = [ "eu-deu-muc" ];
            description = "List of regions where monitoring checks are performed";
          };

        });
      };
  };

  config = mkIf config.services.phare.enable {
    system.userActivationScripts = {
      update-phare-monitors = "${update-monitors}";
    };
  };

}
