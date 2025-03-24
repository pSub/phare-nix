{ self, pkgs }:

pkgs.nixosTest {
  name = "hello-boots";
  nodes.machine = { config, pkgs, ... }: {
    imports = [
      self.nixosModules.phare
    ];
    services.phare.token = "test";

    services.phare.monitors.test =  {
      name = "test";
      alertPolicyId = 1;
    };

    system.stateVersion = "23.11";

      services.openssh = {
     enable = true;
     settings = {
       PermitRootLogin = "yes";
       PermitEmptyPasswords = "yes";
     };
   };

   security.pam.services.sshd.allowNullPassword = true;

   virtualisation.forwardPorts = [
     { from = "host"; host.port = 2000; guest.port = 22; }
   ];
  };

  testScript = ''
   machine.shell_interact()
  '';
}
