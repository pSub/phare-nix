{ lib, pkgs, ... }:
let
  inherit (pkgs) stdenv mkdocs python312Packages;
  options-doc = pkgs.callPackage ./options-doc.nix { };
in
stdenv.mkDerivation {
  src = ./.;
  name = "docs";

  # depend on our options doc derivation
  buildInput = [ options-doc ];

  # mkdocs dependencies
  nativeBuildInputs = [
    mkdocs
    python312Packages.mkdocs-material
    python312Packages.pygments
  ];

  # symlink our generated docs into the correct folder before generating
  buildPhase = ''
    mkdir build
    ln -s ${options-doc} "build/nixos-options.md"
    # generate the site
    mkdocs build -f mkdocs.yml
  '';

  # copy the resulting output to the derivation's $out directory
  installPhase = ''
    mv site $out
  '';
}
