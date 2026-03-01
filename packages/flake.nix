{
  description = "tarzst - A professional utility for creating secure, verifiable, and automated tar archives";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          tarzst = pkgs.callPackage ./package.nix { };
          default = self.packages.${system}.tarzst;
        }
      );

      overlays.default = final: prev: {
        tarzst = final.callPackage ./package.nix { };
      };
    };
}
