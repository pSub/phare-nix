{
  nixpkgs ? import <nixpkgs> { },
}:

nixpkgs.pkgs.callPackage ./doc.nix { }
