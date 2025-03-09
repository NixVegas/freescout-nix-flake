{ lib
, config
, pkgs
, modulesPath
, ...
}:

with lib;

let
  # Simple alias variables
  user = "freescout";
  group = user;
  cfg = config.services.freescout;
  datadir = "/var/lib/freescout";
  cachedir = "/var/cache/freescout";
  fpmPool = "freescout";
  fpmService = "phpfpm-${user}";

  # Generated config and more complex templates / default variables
  autoDb = if !cfg.databaseSetup.enable then false else cfg.databaseSetup.kind;
  dbService = optional (autoDb != false) (if autoDb == "mysql" then "mysql.service" else "postgresql.service");
  db_config = optionalAttrs (autoDb != false) (
    if autoDb == "mysql" then {
      DB_CONNECTION = "mysql";
      # DB_HOST = "localhost"; # Should automatically use the socket --- No it does not and why did i only find that in the source code and the doctrine docs (which are not linked from the freescout wiki)
      DB_HOST = ""; # Should automatically use the socket
      DB_SOCKET = "/run/mysqld/mysqld.sock"; # Should automatically use the socket
      DB_USERNAME = user;
      DB_DATABASE = user;
    } else {
      DB_CONNECTION = "pgsql";
      DB_HOST = "/run/postgresql";
      DB_DATABASE = user;
      DB_USERNAME = user;
    }
  );

  raw_config = rec {
      APP_ENV = "production";
      APP_FORCE_HTTPS = true;
      APP_URL = "https://${cfg.domain}";
      APP_TIMEZONE = config.time.timeZone;
      APP_DISABLE_UPDATING = true;
    }
    // cfg.settings
    // db_config;
  app_config = dropNull raw_config;
  baseService = {
    path = [ pkgs.ps artisanWrapped ];
    requires =  [
      # Using the stringer requires (instead of wants) since a failing config
      # is indeed critical and should not allow this service to continue
      "freescout-setup.service"
    ] ++ dbService;
    # after = dbService;
    serviceConfig = {
      User = user;
      Group = group;
    };
  };

  # Custom built packages / files / scripts
  phpPackage = cfg.phpPackage.buildEnv {
    extensions = { all, enabled }: enabled ++ (with all; [ iconv opcache ]);
    extraConfig = ''
      error_reporting = E_ALL ^ E_DEPRECATED
    '';
  };
  package = cfg.package.overrideAttrs (prev: {
    pname = "${prev.pname}-${cfg.domain}";
    postInstall = prev.postInstall or "" + ''
      ln -s ${datadir} $out/share/freescout/data
    '';
  });
  artisanWrapped = pkgs.writeShellScriptBin "artisan" ''
    cd ${datadir}
    sudo=exec
    if [[ "$USER" != ${user} ]]; then
      sudo='exec ${pkgs.sudo}/bin/sudo /run/wrappers/bin/sudo -u ${user}'
    fi
    $sudo ${phpPackage}/bin/php ${package}/share/freescout/artisan $*
  '';
  configFile = mkEnvFile "freescout.env" app_config;
  allSecrets = catAttrs "_secret" (collect isSecret app_config);
  configSetupScript = pkgs.writeShellScript "freescout-config-setup" ''
    set -o errexit -o pipefail -o nounset -o errtrace
    shopt -s inherit_errexit
    set -x
    PATH=${lib.makeBinPath [ pkgs.replace-secret ]}:$PATH
    cp ${configFile} "/tmp/raw.env";
    ${mkSecretsReplacement "/tmp/raw.env" allSecrets}
    install -T --mode 400 -o ${user} -g ${group} "/tmp/raw.env" "${datadir}/.env"
    rm "/tmp/raw.env"
  '';

  freescoutSetupScript = let
    rwPaths = [
      "storage/app"
      "storage/framework"
      "storage/framework/sessions"
      "storage/framework/views"
      "storage/framework/cache/data"
      "storage/logs"
      "bootstrap/cache"
      "public/css/builds"
      "public/js/builds"
    ];
  in ''
    set -x
    umask 027
    # Working arround https://github.com/freescout-helpdesk/freescout/issues/2547
    rm -f ${datadir}/bootstrap/cache.php ${datadir}/bootstrap/cache/config.php
    ln -sf "${artisanWrapped}/bin/artisan" "${datadir}/artisan"
    ${concatMapStringsSep "\n" (p: "mkdir -p ${datadir}/${p}") rwPaths}

    # Migrate database and stuff
    # This does migrate, cache:clear, queue:restart
    artisan freescout:after-app-update
  '';

  # Helper functions
  isSecret = v: isAttrs v && v ? _secret && (isString v._secret || builtins.isPath v._secret);
  hashSecret = p: builtins.hashString "sha256" p;
  # hasSecrets = (isList allSecrets && allSecrets != [ ]) or (allSecrets == null);
  dropNull = filterAttrsRecursive (
    n: v: ! elem v [ null [] {} ]
  );
  mkEnvVars = lib.generators.toKeyValue {
    mkKeyValue = flip lib.generators.mkKeyValueDefault "=" {
      mkValueString = v: with builtins;
      if isInt         v then toString v
      else if isString v then v
      else if isBool   v then boolToString v
      else if isSecret v then hashSecret v._secret
      else throw "unsupported type ${typeOf v}: ${(lib.generators.toPretty {}) v}";
    };
  };
  mkEnvFile = fname: values: pkgs.writeText fname (mkEnvVars values);
  mkSecretsReplacement = filePath: concatMapStringsSep "\n" (sp: "replace-secret ${escapeShellArgs [ (hashSecret sp) sp ]} ${filePath}");
in {
  options.services.freescout = with lib; {
    enable = mkEnableOption (lib.mdDoc "FreeScout helpdesk application");

    package = mkPackageOption pkgs "freescout" { };

    phpPackage = mkOption {
      type = types.package;
      default = pkgs.php82;
      description = lib.mdDoc "The php package to use";
      defaultText = literalExpression "pkgs.php";
      # php8.4 is not yet compatible: https://github.com/freescout-help-desk/freescout/issues/4630 (as of 2025-03-09)
      relatedPackages = [ "php81" "php82" "php83" ];
    };

    domain = mkOption {
      type = types.str;
      description = lib.mdDoc "Domain the freescout installation will run under";
      example = "support.mydomain.net";
    };

    settings = mkOption {
      # type = with types; attrsOf [ string path int bool (attrsOf string) ];
      type = with types; attrsOf anything;
      apply = mapAttrs' (k: v: { name = toUpper k; value = v; });
      default = {};
      description = lib.mdDoc ''
        Settings to be set in the `.env` file. See
        <https://github.com/freescout-helpdesk/freescout/blob/master/.env.example>
        for reference on available environment variables.

        Will be merged with the shown defaults.
      '';
      defaultText = lib.literalExpression ''
        rec {
          APP_ENV = "production";
          APP_FORCE_HTTPS = true;
          APP_URL = "https://''${cfg.domain}";
          APP_TIMEZONE = config.time.timeZone;
          APP_DISABLE_UPDATING = true;
        }
      '';
      example = lib.literalExpression ''
        {
          # NOTE: MUST be 256 bits (32 bytes) in length, the form of base64:<base64 encoded key> is recommended.
          # You can generate a valid one using `echo "base64:$(openssl rand -base64 32)"`
          APP_KEY._secret = "/run/secret/freescout/app_key";
          DB_CONNECTION = "mysql";
          DB_HOST = "localhost";
          DB_PORT = 3306;
          DB_DATABASE = "freescout";
          DB_USERNAME = "freescout";
          DB_PASSWORD._secret = "/run/secret/freescout/db_pass";
        }
      '';
    };

    poolConfig = mkOption {
      type = with types; attrsOf (oneOf [ str int bool ]);
      default = {
        "pm" = "ondemand";
        "pm.max_children" = 32;
        "pm.process_idle_timeout" = "120s";
        "pm.max_requests" = 500;
        /* "pm" = "dynamic";
        "pm.max_children" = 32;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 2;
        "pm.max_spare_servers" = 4;
        "pm.max_requests" = 500; */
      };
      description = lib.mdDoc ''
        Options for the freescout PHP pool. See the documentation on `php-fpm.conf`
        for details on configuration directives.
      '';
    };

    # TODO: Implement (service dependencies, enable services, create database and user, add to config)
    databaseSetup = {
      enable = mkEnableOption (lib.mdDoc "Automatic database setup and configuration");
      kind = mkOption {
        type = types.enum [ "mysql" "pgsql" ];
        default = "pgsql";
        example = "mysql";
        description = lib.mdDoc "Type of database to automatically set up";
      };
    };

    nginx = mkOption {
      type = types.submodule ( recursiveUpdate
          (import (modulesPath + "/services/web-servers/nginx/vhost-options.nix") { inherit config lib; }) {}
        );
      default = {};
      example = literalExpression ''
        {
          forceSSL = true;
          enableACME = true;
        }
      '';
      description = lib.mdDoc ''
        Optional settings to pass to the nginx virtualHost.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = (app_config ? "APP_KEY");
      message = "`services.freescout.settings.APP_KEY` is required!";
    }];

    warnings = []
      ++ optional (app_config ? "APP_KEY" && isString app_config.APP_KEY)
        "`services.freescout.settings.APP_KEY` will be stored in the world readable nix store. Use `APP_KEY._secret` or `APP_KEY_FILE` instead!";

    users.users.${user} = {
      inherit group;
      isSystemUser = true;
      createHome = true;
      home = datadir;
      homeMode = "750";
    };
    users.users.${config.services.nginx.user}.extraGroups = [ group ];
    users.groups.${group} = {};

    services.postgresql = mkIf (autoDb == "pgsql") {
      enable = true;
      ensureUsers = [{
        name = user;
        ensureDBOwnership = true;
      }];
      ensureDatabases = [
        app_config.DB_DATABASE
      ];
    };

    services.mysql = mkIf (autoDb == "mysql") {
      enable = true;
      package = mkDefault pkgs.mariadb;
      ensureUsers = [{
        name = user;
        ensurePermissions = {
          "${app_config.DB_DATABASE}.*" = "ALL PRIVILEGES";
        };
      }];
      ensureDatabases = [
        app_config.DB_DATABASE
      ];
    };

    services.phpfpm.pools.${user} = {
      inherit phpPackage user group;

      phpOptions = ''
        display_errors = On
        display_startup_errors = On
      '';
      settings = {
        "listen.owner" = user;
        "listen.group" = config.services.nginx.group;
        "catch_workers_output" = true;
      } // cfg.poolConfig;
    };

    systemd.services.${fpmService} = {
      # Somehow the webinterface shows
      inherit (baseService) path;
    };

    systemd.services.freescout-setup = recursiveUpdate baseService {
      description = "Preparational tasks for freescout";
      requires = dbService;
      wantedBy = [ "multi-user.target" ];
      after = dbService;
      script = freescoutSetupScript;
      serviceConfig = {
        PrivateTmp = true;
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "+${configSetupScript}";
      };
    };

    systemd.services."freescout-schedule-run" = baseService // {
      startAt = "minutely";
      script = "artisan schedule:run --no-interaction";
    };

    systemd.services."freescout-queue" = recursiveUpdate baseService {
      script = "artisan queue:work --queue emails,default --sleep=5 -vv --tries=20 | tee -a ${datadir}/storage/logs/queue-jobs.log";
      serviceConfig = {
        RestartSec = "15s";
        RuntimeMaxSec = "1h";
        Restart = "always";
      };
      wantedBy = [ "multi-user.target" ];
      after = [ "freescout-setup.service" ] ++ dbService;
    };

    services.nginx = {
      enable = true;
      virtualHosts.${cfg.domain} = let
        optSsl = optionalString (cfg.nginx.forceSSL || cfg.nginx.onlySSL) "fastcgi_param HTTPS on;";
      in mkMerge [ cfg.nginx {
        root = mkForce "${package}/share/freescout/public";

        locations = {
          "/" = {
            index = "index.php";
            tryFiles = "$uri $uri/ /index.php$is_args$args";

            extraConfig = ''
              # Defeats E-Mail open tracking or possibly "real" exploits
              add_header X-XSS-Protection "1; mode=block" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header Referrer-Policy "no-referrer-when-downgrade" always;
              add_header Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'";
            '';
          };

          "~ \.php$" = {
            tryFiles = "$uri $uri/ =404";
            extraConfig = ''
              fastcgi_index index.php;
              include ${pkgs.nginx}/conf/fastcgi_params;
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              fastcgi_pass unix:${config.services.phpfpm.pools.${user}.socket};
              ${optSsl}

              # Defeats E-Mail open tracking or possibly "real" exploits
              add_header X-XSS-Protection "1; mode=block" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header Referrer-Policy "no-referrer-when-downgrade" always;
              add_header Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'";
            '';
          };

          "~* ^/storage/attachment/" = {
            tryFiles = "$uri $uri/ /index.php?$query_string";
            extraConfig = ''
              expires 1M;
              access_log off;
            '';
          };

          "~* ^/(?:css|js)/.*\.(?:css|js)$".extraConfig = ''
            expires 2d;
            access_log off;
            add_header Cache-Control "public, must-revalidate";
            # Defeats E-Mail open tracking or possibly "real" exploits
            add_header X-XSS-Protection "1; mode=block" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "no-referrer-when-downgrade" always;
            add_header Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'";
          '';

          "~* ^/(?:css|fonts|img|installer|js|modules)$".extraConfig = ''
            expires 1M;
            access_log off;
            add_header Cache-Control "public, must-revalidate";
          '';

          "~ /\\.".extraConfig = ''
            deny all;
          '';
          "^~ /(css|js)/builds/".root = "${cachedir}/public/";
          "^~ /storage/app/attachment/" = {
            alias = "${datadir}/storage/app/attachment/";
            extraConfig = ''
              internal;
            '';
          };
        };
      }];
    };
  };
}
