# Freescout Nix Flake

A [Nix](https://nixos.org/) flake that packages
[Freescout](https://freescout.net/) as both a package and a NixOS module.

## Getting started

This assumes you have a NixOS machine managed with flakes.

Add Freescout Nix Flake to your `flake.nix`:

```nix
  inputs.freescout = {
    url = "git+https://cyberchaos.dev/e1mo/freescout-nix-flake.git";
    inputs.nixpkgs.follows = "nixpkgs";
  };
```

Import the Freescout module and enable it in your `configuration.nix`:

```nix
{
  inputs, # Your flake inputs. Often made available via `specialArgs`.
  ...
}:

{
  imports = [
    inputs.freescout.nixosModules.freescout
  ];

  services.freescout = {
    enable = true;
    domain = "freescout.example.org"; # Replace with a domain you control.

    nginx = {
      forceSSL = true;
      enableACME = true;
    };

    # Generate this `APP_KEY` on the server.
    #
    #   $ echo "base64:$(nix run nixpkgs#openssl -- rand -base64 32)" > /run/secrets/freescout-app-key
    #
    # Be sure to back up this secret. See
    # <https://wiki.nixos.org/wiki/Comparison_of_secret_managing_schemes> for
    # alternate ways of managing secrets.
    settings.APP_KEY._secret = "/run/secrets/freescout-app-key";
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

After deploying the above, create your first admin user:

```console
/var/lib/freescout/artisan freescout:create-user --role=admin --firstName=Free --lastName=Scout --email admin@example.com
```

You should now be able to log into Freescout at <https://freescout.example.org>.

Check the system status at <https://freescout.example.org/system/status>. We
have a few known issues (see list below), but let us know if you see anything
else!

- https://cyberchaos.dev/e1mo/freescout-nix-flake/-/issues/2
- https://cyberchaos.dev/e1mo/freescout-nix-flake/-/issues/3
- https://cyberchaos.dev/e1mo/freescout-nix-flake/-/issues/4
