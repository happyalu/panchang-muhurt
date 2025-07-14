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

        swissephSrc = pkgs.fetchFromGitHub {
          owner = "aloistr";
          repo = "swisseph";
          rev = "3729404271ed525b82f517c7dabcd1a25cd6e644";
          hash = "sha256-Yj/ahXz/3FZNEsTvhCmoTB/TxQdHsp4EOqNSSMLnduw=";
        };

        shellForPkgs =
          pkgs:
          pkgs.mkShell {
            name = "panchang-muhurt";
            buildInputs = with pkgs; [
              zig
              awscli
            ];

            shellHook = ''
              export SE_EPHE_PATH=${swissephSrc}/ephe
            '';

          };
      in
      {
        devShells.default = shellForPkgs pkgs;
      }
    );
}
