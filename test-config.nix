{
  pkgs,
  lib,
  config,
  ...
}:
{
  config.services.phare = {
    token = "1234";
  };
}
