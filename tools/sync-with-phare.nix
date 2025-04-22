{ python3, lib }:

python3.pkgs.buildPythonApplication {
  name = "sync-with-phare";

  format = "other";

  src = ./sync_with_phare.py;

  propagatedBuildInputs = with python3.pkgs; [
    deepdiff
    requests
  ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/sync-with-phare
    chmod +x $out/bin/sync-with-phare
  '';
}