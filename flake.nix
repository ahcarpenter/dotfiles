{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    automic-vault.url = "github:ahcarpenter/automic-vault-nix";
    automic-vault.inputs.nixpkgs.follows = "nixpkgs";
    automic-vault.inputs.nix-darwin.follows = "nix-darwin";
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, automic-vault }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your macOS username differs.
      user = "ahcarpenter";
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit user; };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          automic-vault.darwinModules.default
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Move any other file in the way aside instead of stopping the rebuild.
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = { inherit user; };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };

      checks =
        let
          pkgs = self.darwinConfigurations."mac".pkgs;
          merge = pkgs.callPackage ./scripts/merge-claude-settings.nix { };
          brewSync = pkgs.callPackage ./scripts/brew-sync.nix { };
          checkHardened = pkgs.callPackage ./scripts/check-hardened.nix { };
        in
        {
          ${pkgs.stdenv.hostPlatform.system} = {
            merge-claude-settings =
              pkgs.runCommand "test-merge-claude-settings"
                { nativeBuildInputs = [ pkgs.bash pkgs.jq pkgs.coreutils pkgs.findutils pkgs.gnugrep ]; }
                ''
                  bash ${./scripts/test-merge-claude-settings.sh} ${pkgs.lib.getExe merge}
                  touch $out
                '';
            brew-sync =
              pkgs.runCommand "test-brew-sync"
                { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep ]; }
                ''
                  bash ${./scripts/test-brew-sync.sh} ${pkgs.lib.getExe brewSync}
                  touch $out
                '';
            # Runs Apple's dscl, which a sandboxed build cannot reach.
            check-hardened =
              pkgs.runCommand "test-check-hardened"
                { nativeBuildInputs = [ pkgs.bash ]; __noChroot = true; }
                ''
                  bash ${./scripts/test-check-hardened.sh} ${pkgs.lib.getExe checkHardened}
                  touch $out
                '';
          };
        };
    };
}
