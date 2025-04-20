{ nixpkgs ? import <nixpkgs> {} }:

nixpkgs.pkgs.callPackage ./sync-with-phare.nix {  }