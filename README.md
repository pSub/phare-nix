# phare-nix
A NixOS module for [phare.io](https://phare.io) monitor declarations.

## Motivation
NixOS provides you with tools to setup a web-service in a simple manner
and even takes care of SSL certificates for you. This module extends
the capabilities to monitoring web-services. You no longer have to
click through a web-interface each time you create / modify a web-service,
but instead turn on monitoring for a web-service by flicking a switch. As
there is (to my knowledge) no standardized API for monitoring, this module
uses the monitoring service [phare.io](https://phare.io).

## Installation
> [!NOTE]  
> This NixOS module requires [flakes](https://wiki.nixos.org/wiki/Flakes).

Installation is straightforward and does not differ from other flakes. As
basic flake with phare-nix cloud look like this:

``` nix
{
  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
  inputs.phare-nix.url = github:pSub/phare-nix;
  outputs = { self, nixpkgs }: {
    nixosConfigurations.some-server = nixpkgs.lib.nixosSystem {
      modules = [
          ./configuration.nix
          phare-nix.nixosModules.phare
      ];
    };
  };
}
```

## Usage

The following code snippet demonstrates how you can use the `phare-nix` module in
your configuration.

``` nix
services.phare = {
    enable = true; # enables the script that interacts with phare.io
    tokenFile = "/run/secrets/phare-token"; # path to a file containing the API token
    alertPolicyId = 1234; # default alert-policy-id for monitors
    regions = [ "eu-deu-muc" ]; # default regions for monitors

    # the attribute sets for this option are converted to JSON and send to the phare.io
    # API, therefor you can use all fields provided by the phare.io API.
    # Note: The Nix option names are in camel case and are converted to snake case before
    # they are sent to phare.io.
    monitors = {
        tcp-monitor = { # name of the monitor
            protocol = "tcp";
            request = {
                host = "example.org";
                port = "22";
            };
        }
        
        http-monitor = {
            protocol = "http";
            request = {
                url = "https://example.org";
                method = "GET";
                keyword = "pong";
            };
        };
    };
}

services.nginx.virtualHosts."example.org" = {
    # This option will generate a http-monitor for the virtual host. Depending on whether
    # forceSSL is enabled for the virtual host the url for the monitor uses https.
    enablePhare = true;
    
    # You can overwrite each attribute of the monitor configuration.
    phare = {
        request = {
            url = "example.org/redirect";
            method = "GET";
        }
    };
};
```

Once you rebuild your system (eg. with `nixos-rebuiold`) the configuration of the monitors is
applied by a systemd service to phare.io. Depending on the state of phare.io different actions are performed:

- If there is a monitor in your configuration but not on phare.io, then the monitor created on phare.io.
- If there is a monitor in your configuration and on phare.io, then the monitor is updated on phare.io.
- If there is a monitor in your configuration but paused on phare.io, then the monitor is resumed on phare.io.
- If there is a monitor on phare.io but not in your configuration, then the monitor is paused on phare.io.

The test on whether there is a monitor on phare.io or not is done using the name of the monitor.

You can find the phare.io API documentation at https://docs.phare.io/api-reference/introduction.

