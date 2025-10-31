{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    zls = {
      url = "github:zigtools/zls?ref=0.15.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { flake-utils, zig2nix, zls, ... }: (flake-utils.lib.eachDefaultSystem (system: let
      # Zig flake helper
      # Check the flake.nix in zig2nix project for more options:
      # <https://github.com/Cloudef/zig2nix/blob/master/flake.nix>
      env = zig2nix.outputs.zig-env.${system} {
        zig = zig2nix.outputs.packages.${system}.zig-0_15_2;
      };
    in with builtins; with env.pkgs.lib; rec {
      # Produces clean binaries meant to be shipped outside of nix
      # nix build .#foreign
      packages.foreign = env.package {
        src = cleanSource ./.;

        # Smaller binaries and avoids shipping glibc.
        zigPreferMusl = true;
      };

      # nix build .
      packages.default = packages.foreign.override (attrs: {
        # Prefer nix friendly settings.
        zigPreferMusl = false;

        zigWrapperBins = [];
        zigWrapperLibs = attrs.buildInputs or [];
      });

      # For bundling with nix bundle for running outside of nix
      # example: https://github.com/ralismark/nix-appimage
      apps.bundle = {
        type = "app";
        program = "${packages.foreign}/bin/galock";
      };

      apps.default = {
        type = "app";
        program = "${packages.default}/bin/galock";
      };

      devShells.default = env.mkShell {
        nativeBuildInputs = [zls.packages.${system}.default]
          ++ packages.default.nativeBuildInputs
          ++ packages.default.buildInputs
          ++ packages.default.zigWrapperBins
          ++ packages.default.zigWrapperLibs;
      };
    }));
}
