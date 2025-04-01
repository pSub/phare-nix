# phare-nix
A NixOS module for [phare.io](https://phare.io) monitor declarations.

## Motivation
NixOS provides you with tools to setup a webservice in a simple manner
and even takes care of SSL certificates for you. This module extends
the capabilities to monitoring webservices. You no longer have to
click through a webinterface each time you create / modify a webservice,
but instead turn on monitoring for a webservice by flicking a switch. As
there is (to my knowlege) no standardized API for monitoring, this module
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

The following code snippet demonstrates how you can use the `phare-nix` module.

``` nix
services.phare = {
    enable = true; # enables the script that interacts with phare.io
    tokenFile = "/run/secrets/phare-token"; # path to a file containing the API token
    alertPolicyId = 1234; # default alert-policy-id for monitors
    regions = [ "eu-deu-muc" ]; # default regions for monitors

    # the attribute sets for this option are converted to JSON and send to the phare.io
    # API, therefor you can use all fields provided by the phare.io API.
    monitors = {
        tcp-monitor = {
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
    # This option will generate a http-monitor for the virtual host. Depending on wheter
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

You can find the phare.io API documentation at https://docs.phare.io/api-reference/introduction.

