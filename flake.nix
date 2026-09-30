{
  description = "apache maka";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    # credit to: https://ayats.org/blog/no-flake-utils
    forAllSystems = function:
      nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ] (
        system:
          function rec {
            inherit system;
            pkgs = import nixpkgs {
              inherit system;
            };
            electron = pkgs.electron_43;
            compilationPkgs =
              [
                electron
                pkgs.nodejs_24
                pkgs.ripgrep
                pkgs.rustc
                pkgs.cargo
              ]
              ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.apple-sdk;

            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.bubblewrap
              pkgs.coreutils
            ];
          }
      );

    apache-maka = {
      pkgs,
      electron,
      compilationPkgs,
      buildInputs,
      ...
    }:
      pkgs.buildNpmPackage (finalAttrs: rec {
        name = "apache-maka";
        src = pkgs.fetchFromGitHub {
          owner = "apache";
          repo = "maka";
          rev = "542f04a4f328de7a49b96e5146f391fb923fa369";
          hash = "sha256-RiQ+AeKAXWHYyP0jPARNDnOgJPKf1gC4/4vZ++XbXF8=";
        };

        nativeBuildInputs =
          compilationPkgs
          ++ [
            pkgs.rustPlatform.cargoSetupHook
            pkgs.makeWrapper
            pkgs.copyDesktopItems
          ];

        npmDepsHash = "sha256-uk7emVa4eI5O5WvfRKjPQD3FuWV1JwLG5Az6gF+kWDM=";

        inherit buildInputs;

        env = {
          ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
        };

        npmFlags = ["--ignore-scripts"];
        dontNpmBuild = true;

        cargoRoot = "native/runtime-host-peer";
        cargoDeps = pkgs.rustPlatform.importCargoLock {
          lockFile = "${src}/native/runtime-host-peer/Cargo.lock";
          outputHashes = {
            "rtc-0.21.0-rc.1" = "sha256-3zDb+x2IhHBMh8tfumteDE5JG/zZacaevbSCkcqDZk0=";
          };
        };

        postPatch = ''
          substituteInPlace packages/runtime/src/sandbox/linux-capability.ts \
            --replace-fail "/usr/bin/bwrap" "${pkgs.bubblewrap}/bin/bwrap" \
            --replace-fail "/bin/true" "${pkgs.coreutils}/bin/true"
        '';

        buildPhase = ''
          node scripts/apply-dependency-patches.mjs

          npm run build
          npm run build:runtime-host-peer

          ${
            if pkgs.stdenv.hostPlatform.isDarwin
            then ''
              echo "Not implemented"
            ''
            else if pkgs.stdenv.hostPlatform.isAarch64
            then ''
              npm --workspace @maka/desktop exec electron-builder -- \
                --config electron-builder.config.mjs \
                --linux dir \
                --arm64 \
                --publish never \
                -c.electronDist=${electron.dist} \
                -c.electronVersion=${electron.version}
            ''
            else ''
              npm --workspace @maka/desktop exec electron-builder -- \
                --config electron-builder.config.mjs \
                --linux dir \
                --x64 \
                --publish never \
                -c.electronDist=${electron.dist} \
                -c.electronVersion=${electron.version}
            ''
          }
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/share
          cp -r apps/desktop/release/*-unpacked/{locales,resources{,.pak}} $out/share

          makeWrapper ${pkgs.lib.getExe electron} $out/bin/maka \
            --add-flags $out/share/resources/app.asar \
            --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

          install -m 444 -D $out/share/resources/assets/icon.png \
            $out/share/icons/hicolor/512x512/apps/apache-maka.png

          runHook postInstall
        '';

        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "apache-maka";
            desktopName = "Apache Maka";
            exec = "maka";
            icon = "apache-maka";
            categories = ["Development" "IDE"];
          })
        ];
      });
  in {
    packages = forAllSystems (args: {
      default = apache-maka args;
      apache-maka = apache-maka args;
    });

    overlays.default = final: prev: {
      apache-maka = self.packages.${final.stdenv.hostPlatform.system}.default;
    };

    apps = forAllSystems ({system, ...}: rec {
      default = apache-maka;
      apache-maka = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/maka";
      };
    });

    devShells = forAllSystems ({
      pkgs,
      electron,
      compilationPkgs,
      buildInputs,
      ...
    }: {
      default = pkgs.mkShell {
        ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
        ELECTRON_OVERRIDE_DIST_PATH = "${electron}/bin";

        shellHook = ''
          npm ci
        '';
        packages = compilationPkgs ++ buildInputs;
      };
    });

    formatter = forAllSystems ({pkgs, ...}: pkgs.alejandra);
  };
}
