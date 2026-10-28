{ config, lib, pkgs, user, ... }:

let
  # Whether Automic Vault's `av harden brew` has hardened this Mac's Homebrew.
  # Keep it false on a Mac where it hasn't, including a fresh one.
  hardenedHomebrew = true;

  brewPrefix = config.homebrew.prefix;
  # Installed by `av harden brew`; once it's there, it is the only brew that may change Homebrew.
  vaultBrew = "/usr/local/bin/brew";
  opensuperwhisper = pkgs.callPackage ./pkgs/opensuperwhisper.nix { };
  # Installs what's missing from the Homebrew lists below through Automic
  # Vault's brew. rebuild.sh runs it as you after the switch.
  brewSync = pkgs.writeShellScriptBin "brew-sync" ''
    exec ${lib.getExe (pkgs.callPackage ./scripts/brew-sync.nix { })} ${lib.escapeShellArgs (
      [ brewPrefix config.nix-homebrew.prefixes.${brewPrefix}.library vaultBrew ]
      ++ map (tap: "${if tap.trusted then "trusted-tap" else "tap"}:${tap.name}") config.homebrew.taps
      ++ map (brew: "formula:${brew.name}") config.homebrew.brews
      ++ map (cask: "cask:${cask.name}") config.homebrew.casks
    )}
  '';
in
{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };

  # Touch ID for sudo, which is what Automic Vault's `av harden sudo` sets up.
  # nix-darwin owns /etc/pam.d/sudo_local, so the line has to come from here.
  # pam_tid is "sufficient", so sudo still asks for the password when Touch ID
  # can't be used (lid closed, SSH).
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    # herdr, like tmux, runs its panes from a detached server, outside the
    # login session Touch ID needs. This brings sudo back into it.
    reattach = true;
  };

  # Apps come from Nix and land in /Applications/Nix Apps, because hardened
  # Homebrew only accepts command-line casks.
  environment.systemPackages = [ pkgs.ghostty-bin ]
    ++ lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform opensuperwhisper) opensuperwhisper
    ++ lib.optional hardenedHomebrew brewSync;

  # Automic Vault has to live at /Applications/Automic Vault.app, with its av
  # CLI at /usr/local/bin/av, so its module installs it there instead of
  # systemPackages. It only ships for Apple Silicon.
  programs.automic-vault.enable =
    lib.meta.availableOn pkgs.stdenv.hostPlatform config.programs.automic-vault.package;

  nix-homebrew = {
    enable = true;
    # Hardened Homebrew belongs to Automic Vault's account, so nix-homebrew
    # sets it up as that account.
    user = if hardenedHomebrew then "automic" else user;
    group = lib.mkIf hardenedHomebrew "vault";
    # Its shell hook runs `brew shellenv`, which puts Homebrew's bin ahead of
    # Automic Vault's brew and adds Homebrew's zsh completions, which zsh
    # refuses once Automic Vault owns them. The PATH below replaces it.
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableZshIntegration = false;
  };

  # Automic Vault's brew in /usr/local/bin has to come before Homebrew's own
  # and before nix-homebrew's launcher in the Nix profiles.
  environment.systemPath = lib.mkBefore [ "/usr/local/bin" "${brewPrefix}/bin" "${brewPrefix}/sbin" ];
  environment.variables = {
    HOMEBREW_PREFIX = brewPrefix;
    HOMEBREW_CELLAR = "${brewPrefix}/Cellar";
    HOMEBREW_REPOSITORY = "${config.nix-homebrew.prefixes.${brewPrefix}.library}/.homebrew-is-managed-by-nix";
    INFOPATH = "${brewPrefix}/share/info:";
  };

  homebrew = {
    # Hardened Homebrew refuses `brew bundle`, so there brew-sync installs
    # these lists instead of nix-darwin's Homebrew step.
    enable = !hardenedHomebrew;
    onActivation.cleanup = "none";  # install what's listed, leave everything else alone
    onActivation.autoUpdate = true;
    taps = [
      { name = "rjyo/moshi"; trusted = true; }
      { name = "automic-vault/isotopes"; trusted = true; }
    ];
    brews = [
      "herdr"
      "tailscale"
      "mosh"
      "moshi-hook"
    ];
    # Only command-line casks: hardened Homebrew refuses app casks.
    casks = [
      "claude-code@latest"
    ];
  };
}
