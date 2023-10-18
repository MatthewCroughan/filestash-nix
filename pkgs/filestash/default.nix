{ buildGoModule
, dream2nix
, filestash-src
, glib
, gotools
, libraw
, pkg-config
, pkgs
, python
, self
, stdenv
, vips
, util-linux
, writeShellScriptBin
}:
let
  updateScript = (dream2nix.lib.makeFlakeOutputs {
    inherit pkgs;
    config.projectRoot = filestash-src;
    source = filestash-src;
    settings = [ { subsystemInfo.nodejs = "18"; subsystemInfo.npmArgs = "--legacy-peer-deps"; } ];
    autoProjects = true;
  }).packages.${pkgs.hostPlatform.system}.filestash.resolve;
  frontend = ((dream2nix.lib.init { inherit pkgs; }).dream2nix-interface.makeOutputsForDreamLock {
    dreamLock = ../../dream2nix-packages/filestash/dream-lock.json;
    sourceOverrides = oldSources: {
      "filestash"."0.0.0" = filestash-src;
    };
    packageOverrides = {
      node-sass = {
        add-pre-build-steps = {
          buildInputs = old: old ++ [
            pkgs.python
          ];
        };
      };
    };
  }).packages.filestash;
  libtranscode = stdenv.mkDerivation {
    name = "libtranscode";
    src = filestash-src + "/server/plugin/plg_image_light/deps/src";
    buildInputs = [
      libraw
    ];
    buildPhase = ''
      $CC -Wall -c libtranscode.c
      ar rcs libtranscode.a libtranscode.o
    '';
    installPhase = ''
      mkdir -p $out/lib
      mv libtranscode.a $out/lib/
    '';
  };
  libresize = stdenv.mkDerivation {
    name = "libresize";
    src = filestash-src + "/server/plugin/plg_image_light/deps/src";
    buildInputs = [
      vips
      glib
    ];
    nativeBuildInputs = [
      pkg-config
    ];
    buildPhase = ''
      $CC -Wall -c libresize.c `pkg-config --cflags glib-2.0`
      ar rcs libresize.a libresize.o
    '';
    installPhase = ''
      mkdir -p $out/lib
      mv libresize.a $out/lib/
    '';
  };
in
buildGoModule {
  passthru.update = updateScript;
  pname = "filestash";
  version = "unstable-" + filestash-src.shortRev;

  src = frontend + "/lib/node_modules/filestash";

  vendorHash = null;

  excludedPackages = [
    "server/generator"
    "server/plugin/plg_starter_http2"
    "server/plugin/plg_starter_https"
    "server/plugin/plg_search_sqlitefts"
  ];

  buildInputs = [
    glib
    libraw
    libresize
    libtranscode
    vips
  ];

  nativeBuildInputs = [
    (writeShellScriptBin "git" "echo '${filestash-src.rev}'")
    gotools
    util-linux
    pkg-config
  ];

  patches = [
    ## Use flake input's lastModified as build date (see `postPatch` phase), as
    ## `time.Now()` is impure. The build date is used in Filestash's own version
    ## reporting and the http User-Agent when connecting to a backend.
    ./fix-impure-build-date.patch
  ];

  postPatch =
    let
      platform = {
        aarch64-linux = "linux_arm";
        x86_64-linux = "linux_amd64";
      }.${pkgs.hostPlatform.system} or (throw "Unsupported system: ${pkgs.hostPlatform.system}");
    in
    ''
      substituteInPlace server/generator/constants.go --subst-var-by build_date '${toString filestash-src.lastModified}'

      ## fix "imported and not used" errors
      goimports -w server/

      sed -i 's#-L./deps -l:libresize_${platform}.a#-L${libresize.outPath}/lib -l:libresize.a -lvips#' server/plugin/plg_image_light/lib_resize_${platform}.go
      sed -i 's#-L./deps -l:libtranscode_${platform}.a#-L${libtranscode.outPath}/lib -l:libtranscode.a -lraw#' server/plugin/plg_image_light/lib_transcode_${platform}.go

      ## server/** requires globstar
      shopt -s globstar
      rename --no-overwrite --verbose linux_arm.go linux_arm64.go server/**
    '';

  preBuild = ''
    make build_init
  '';

  postInstall = ''
    mv $out/bin/server $out/bin/filestash
  '';
}
