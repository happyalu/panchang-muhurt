{
  description = "Flake for zig code to run panchang/muhurt";

  # repositories we are tracking
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
    }:
    let
      supportedSystems = [ "x86_64-linux" ];
    in
    utils.lib.eachSystem supportedSystems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        swisseph = pkgs.stdenv.mkDerivation rec {
          pname = "swisseph";
          version = "2.10.03";
          src = pkgs.fetchFromGitHub {
            owner = "aloistr";
            repo = "swisseph";
            rev = "v${version}";
            hash = "sha256-2vjLXxkBRXKQFW7IMSjzKv7ruupsYmmtdRTeWpZltMU=";
          };

          enableParallelBuilding = true;

          buildPhase = ''
            make libswe.so
          '';

          installPhase = ''
            ls -l
            mkdir -p $out/lib/pkgconfig
            mkdir -p $out/include
            mv libswe.so $out/lib/
            cp -pr *.h $out/include/

            cat > "$out/lib/pkgconfig/swisseph.pc" <<EOF
            prefix=$out
            libdir=$out/lib
            includedir=$out/include

            Name: SwissEph
            Description: Swiss Eph
            Version: ${version}
            Libs: -L$out/lib
            Cflags: -I$out/include
            EOF
          '';

        };

        shellForPkgs =
          pkgs:
          pkgs.mkShell {
            name = "panchang-muhurt";
            buildInputs = with pkgs; [
              pkg-config
              swisseph
              zig
            ];

            shellHook = ''

            '';

          };
      in
      {
        devShells.default = shellForPkgs pkgs;
      }
    );
}
