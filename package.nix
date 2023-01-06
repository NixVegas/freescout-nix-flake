{ lib
, stdenv
, fetchFromGitHub
, nixosTests
}:
stdenv.mkDerivation rec {
  pname = "freescout";
  version = "1.8.46";

  src = fetchFromGitHub {
    owner = "freescout-helpdesk";
    repo = pname;
    rev = version;
    hash = "sha256-bnAYjY5LMRSsNFQSiknGLOWlzgfW3C2RqomzDQtqPUk=";
  };

  patches = [
    ./0001-Fix-settings-page-error-due-to-unwritable-.env-file.patch
  ];

  prePatch = ''
    rm -rf storage
    rm bootstrap/cache/.gitignore
    rm public/{css,js}/builds/.htaccess
    rmdir bootstrap/cache public/{css,js}/builds
    ln -rs data/.env .env
    ln -rs data/storage storage
    ln -rs data/bootstrap/cache bootstrap/cache
    ln -rs data/storage/app/public public/storage
    ln -rs data/public/css/builds public/css/builds
    ln -rs data/public/js/builds public/js/builds
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/freescout
    cp -ar . $out/share/freescout
    chmod +x $out/share/freescout/artisan

    runHook postInstall
  '';

  meta = with lib; {
    description = "Free self-hosted help desk & shared mailbox";
    license = licenses.agpl3Only;
    homepage = "https://freescout.net/";
    platforms = platforms.all;
    # maintainers = with maintainers; [ e1mo ];
  };
}
