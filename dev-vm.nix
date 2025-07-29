{ pkgs
, lib
, config
, modulesPath
, ...
}:

let
  httpsPort = 8443;
  keyFile = pkgs.writeText "freescout-app-key" "base64:J8ZgK5LZkhVKpmZvjjA700sNL7+Y6aQTus8ZnUNNAaE=";
in {
  imports = [
    "${toString modulesPath}/virtualisation/qemu-vm.nix"
    # ./module.nix
    (builtins.fetchurl {
      url = "https://git.clerie.de/clerie/nixfiles/raw/commit/64122a7149169f225a6c9e5a0840b1228148de10/modules/akne/default.nix";
      sha256 = "17l7q0vjzb5586dqf9dlcg8zmvx7xaihbghyh6w2y3apbdycr3kh";
    })
  ];
  system.stateVersion = "23.05";
  environment.systemPackages = with pkgs; [
    bat
    fd
    tree
    vim
  ];

  virtualisation = {
    memorySize = 2048;
    diskSize = 2048;
    graphics = false;
    writableStore = false;
    forwardPorts = [
      {
        from = "host";
        host.port = 8080;
        guest.port = 80;
      }
      {
        from = "host";
        host.port = httpsPort;
        guest.port = 443;
      }
      {
        from = "host";
        host.port = 2222;
        guest.port =  22;
      }
    ];
  };

  # That way we can preview our part of the options manual
  documentation.nixos.includeAllModules = false;
  networking.firewall.enable = false;
  users.users.root.password = "root";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  time.timeZone = "Europe/Berlin";

  clerie.akne = {
    enable = true;
    selfSignedOnlyHostNames = [ "freescout.local" ];
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "dummy@dummymail.io";
  };
  services.nginx.enableReload = true;

  services.freescout = rec {
    enable = true;
    /* package = pkgs.freescout.overrideAttrs (oldAttrs: rec {
      version = "1.7.15";
      src = pkgs.fetchFromGitHub {
        owner = "freescout-helpdesk";
        repo = oldAttrs.pname;
        rev = version;
        # hash = "sha256-4izKWWjHxa9I3NtAQbXUcyWTbCWCvLi9pZejm6wRuzc=";
        hash = "sha256-agRfiEU9NpNvHOEbabr5IkrNJ5mC7jfoPPjXRUUSGqo=";
      };
    });
    phpPackage = pkgs.php80; */
    settings = {
      APP_ENV = "local";
      APP_DEBUG = true;
      APP_KEY._secret = keyFile;
      APP_URL = "https://${domain}:${toString httpsPort}";
      APP_DISABLE_UPDATING = false;
    };
    databaseSetup = {
      enable = true;
      # kind = "mysql";
    };
    domain = "freescout.local";
    nginx = {
      forceSSL = true;
      enableACME = true;
    };
  };
}
