{ pkgs
, system ? "x86_64-linux"
, outputs
, lib
, ...
}:

let
  mailDomain = "freemail.local";
  freescoutDomain = "freescout.local";

  oldFreescoutVersion = pkgs.freescout.overrideAttrs (oa: rec {
    version = "1.8.139";
    src = pkgs.fetchFromGitHub {
      owner = "freescout-helpdesk";
      repo = "freescout";
      rev = version;
      hash = "sha256-v/bQuE1khKtAt2dc5Y83PhKTUj32His1SwRt3rkfBX4=";
    };
  });
  newFreescoutVersion = pkgs.freescout;
in pkgs.testers.nixosTest {
  name = "freescout-upgrade";

  nodes.machine = { config, ... }: {
    imports = [
      outputs.nixosModules.freescout
    ];
    networking.extraHosts = ''
      127.0.0.1 ${freescoutDomain}
    '';
    virtualisation.memorySize = 1024;
    environment.systemPackages = with pkgs; [
      curl
      jq
    ];
    services.freescout = {
      package = oldFreescoutVersion;
      enable = true;
      domain = freescoutDomain;
      settings = {
        APP_KEY = "base64:J8ZgK5LZkhVKpmZvjjA700sNL7+Y6aQTus8ZnUNNAaE=";
        APP_FORCE_HTTPS = false;
        APP_URL = "http://${freescoutDomain}:8888";
      };
      databaseSetup = {
        enable = true;
        kind = "pgsql";
      };
    };
    specialisation.upgrade.configuration.services.freescout.package = lib.mkForce newFreescoutVersion;
  };

  testScript = { nodes, ... }: let
    oldVersion = nodes.machine.services.freescout.package.version;
    newVersion = nodes.machine.specialisation.upgrade.configuration.services.freescout.package.version;
  in ''
    machine.start()
    machine.wait_for_unit("nginx")
    machine.wait_for_unit("freescout-setup")

    with subtest("Create user and log in"):
      # Create uesr
      machine.succeed("/var/lib/freescout/artisan freescout:create-user --role=admin --firstName=Xenia --lastName=TheFox --email xenia@${freescoutDomain} --no-interaction --password=foo | grep 'User created with id'")
      # Obtain CSRF token
      token=machine.succeed("curl -fsSL --cookie-jar cjar 'http://${freescoutDomain}/login' | grep -Po '(?<= name=\"_token\" value=\")(\w+)(?=\")'").strip()
      # Actually log in
      data=f"email=xenia%40${freescoutDomain}&password=foo&_token={token}&remember=on"
      machine.succeed(f"curl -sSfX POST --cookie-jar cjar --cookie cjar --data-raw '{data}' 'http://${freescoutDomain}/login' | grep 'Redirecting to'")

    with subtest("Check old API version"):
      machine.succeed("curl -fsSL --cookie-jar cjar --cookie cjar 'http://${freescoutDomain}/system/status' | grep ${oldVersion}")

    machine.execute("${nodes.machine.system.build.toplevel}/specialisation/upgrade/bin/switch-to-configuration test >&2")

    machine.wait_for_unit("nginx")
    machine.wait_for_unit("freescout-setup")

    with subtest("Check new API version"):
      machine.succeed("curl -fsSL --cookie-jar cjar --cookie cjar 'http://${freescoutDomain}/system/status' | grep ${newVersion}")
  '';
}
