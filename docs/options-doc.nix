{ lib, runCommand, nixosOptionsDoc, pkgs, ...}: let

  dontCheckModules = {
    _module.check = false;
  };

    # evaluate our options
    eval = lib.evalModules {
        modules = [
            ../module/default.nix
            dontCheckModules

                    {  options = {
                        _module.args = pkgs.lib.mkOption {
                          internal = true;
                        };
                        };
                    }
        ];
    };

      stripAnyPrefixes = p: {
        url = "https://github.com/pSub/phare-nix/blob/main/module/default.nix";
        name = "module/default.nix";
      };
    # generate our docs
    optionsDoc = nixosOptionsDoc {
        inherit (eval) options;
            transformOptions =
              opt:
              opt // {
                # Clean up declaration sites to not refer to the source tree.
               declarations = map stripAnyPrefixes opt.declarations;
              };
    };
in
    # create a derivation for capturing the markdown output
    runCommand "options-doc.md" {} ''
        cat ${optionsDoc.optionsCommonMark} >> $out
    ''
