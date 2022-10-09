{ dream2nix, stdenv, python, runCommand, pkgs, filestash-src, glib, vips, libraw, pkg-config, buildGoModule }:
let
  filestash-src-with-lock = runCommand "filestash-src-with-lock" {} ''
    cp -r --no-preserve=mode ${filestash-src} $out
    cp ${./package-lock.json} $out/package-lock.json
  '';
  js = (dream2nix.lib.makeFlakeOutputs {
    inherit pkgs;
    config.projectRoot = filestash-src-with-lock;
    source = filestash-src-with-lock;
    settings = [ { subsystemInfo.nodejs = "14"; } ];
    packageOverrides = {
      filestash = {
        add-pre-build-steps = {
          preBuild = ''
            cd $out
            mv $sourceRoot $out/src
            ln -s $out/src $sourceRoot
            cd $out/src
          '';
          postBuild = ''
            rm $sourceRoot
            mv $out/src $sourceRoot
          '';
          dontPatchELF = true;
        };
      };
      node-sass = {
        add-pre-build-steps = {
          dontPatchELF = true;
          buildInputs = old: old ++ [
            pkgs.python
          ];
        };
      };
    };
  }).packages.${pkgs.hostPlatform.system}.filestash;
  go = buildGoModule rec {
    name = "filestash-golang";
    src = filestash-src;
    vendorSha256 = null;
    buildInputs = [
      glib libresize libtranscode vips libraw
    ];
    nativeBuildInputs = [
      pkg-config
    ];
    patchPhase = ''
      substituteInPlace server/plugin/plg_backend_ftp_only/index.go \
        --replace '"crypto/tls"' '//"crypto/tls"'
    '';
    preBuild = let
      libresizePath = (builtins.replaceStrings [ "/" ] [ "\\/" ] libresize.outPath);
      libtranscodePath = (builtins.replaceStrings [ "/" ] [ "\\/" ] libtranscode.outPath);
    in ''
      make build_init
      sed -ie 's/-L.\/deps -l:libresize_linux_amd64.a/-L${libresizePath}\/lib -l:libresize.a -lvips/' server/plugin/plg_image_light/lib_resize_linux_amd64.go
      sed -ie 's/-L.\/deps -l:libtranscode_linux_amd64.a/-L${libtranscodePath}\/lib -l:libtranscode.a -lraw/' server/plugin/plg_image_light/lib_transcode_linux_amd64.go
    '';
    postInstall = ''
      cp $out/bin/server $out/bin/filestash
    '';
    excludedPackages = "\\(server/generator\\|server/plugin/plg_starter_http2\\|server/plugin/plg_starter_https\\|server/plugin/plg_search_sqlitefts\\)";
  };
  libtranscode = stdenv.mkDerivation {
    name = "libtranscode";
    src = filestash-src + "/server/plugin/plg_image_light/deps/src";
    buildInputs = with pkgs; [
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
pkgs.stdenv.mkDerivation {
  name = "filestash";
  phases = [ "InstallPhase" ];
  InstallPhase = ''
    mkdir -p $out/bin
    cp ${go}/bin/filestash $out/bin
    mkdir -p $out/data
    cp -r ${js}/lib/node_modules/filestash/dist/data/public $out/data
  '';
}
