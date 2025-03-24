{ config, lib, pkgs, ... }:

with lib;

let

  monitors-json = pkgs.writeText "monitors.json" (builtins.toJSON config.services.phare.monitors);

  list-monitors = pkgs.writeScript "list-monitors" ''
    ${pkgs.curl}/bin/curl --request GET \
      --url https://api.phare.io/uptime/monitors \
      --header 'Authorization: Bearer ${config.services.phare.token}'
  '';

  update-monitor = pkgs.writeScript "update-monitor" ''
    MONITOR_ID=$1
    ${pkgs.curl}/bin/curl -vvvv --request POST \
      --url https://api.phare.io/uptime/monitors/"$MONITOR_ID" \
      --header 'Authorization: Bearer ${config.services.phare.token}' \
      --header 'Content-Type: application/json' \
      --data @-
 '';

  create-monitor = pkgs.writeScript "create-monitor" ''
    ${pkgs.curl}/bin/curl -vvvv --request POST \
      --url https://api.phare.io/uptime/monitors \
      --header 'Authorization: Bearer ${config.services.phare.token}' \
      --header 'Content-Type: application/json' \
      --data @-
 '';

  update-monitors = pkgs.writeScript "update-monitors" ''
    declare -A ids=()

    while IFS="=" read -r name id; do
      ids["$name"]="$id"
    done < <(${list-monitors} | ${pkgs.jq}/bin/jq -r '.data[] | "\(.name)=\(.id)"')

    cat ${monitors-json} | ${pkgs.jq}/bin/jq -c '.[]' | while read monitor; do
      name=$(echo "$monitor" | jq -r '.name')
      if [[ -v ids["$name"] ]]; then
         echo "$monitor" | jq --arg m "''${ids["$name"]}" '. += {"id":$m}' \
          | jq -f ${camelCaseToSnakeCase} \
          | ${update-monitor} ''${ids["$name"]}
       else
         echo "$monitor" | jq -f ${camelCaseToSnakeCase} | ${create-monitor}
       fi
    done
  '';

  # https://gist.github.com/reegnz/5bceb53427008a4ff9367eb8eae97b85
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
    services.phare.token = mkOption {
      type = types.str;
      default = null;
      description = "";
    };

    services.phare.monitors = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.alertPolicyId = mkOption {
            type = types.ints.positive;
            description = "";
          };
          options.name = mkOption {
            type = types.str;
          };
          options.protocol = mkOption {
            type = types.enum [
                 "http"
                 "tcp"
            ];
            default = "http";
          };

          options.request = mkOption {
            type = types.attrs;
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
          };
          options.incidentConfirmations = mkOption {
            type = types.enum [ 1 2 3 4 5 ];
            default = 1;

          };
          options.recoveryConfirmations = mkOption {
            type = types.enum [ 1 2 3 4 5 ];
            default = 1;
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
          };

        });
      };
  };

  config = {
    systemd.services."create-phare-monitors" = {
      description = "";
      serviceConfig = {
        ExecStart = "${list-monitors} | ${update-monitors}";
        Type = "oneshot";
      };
    };
  };

}
