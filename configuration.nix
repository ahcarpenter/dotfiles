{ config, lib, pkgs, user, ... }:

let
  brewPrefix = config.homebrew.prefix;
  # Installed by `av harden brew`; once it's there, it is the only brew that may change Homebrew.
  vaultBrew = "/usr/local/bin/brew";
  opensuperwhisper = pkgs.callPackage ./pkgs/opensuperwhisper.nix { };
  hardenedBrewInstall = pkgs.callPackage ./scripts/hardened-brew-install.nix { };
  hardenedBrewItems =
    map (tap: "${if tap.trusted then "trusted-tap" else "tap"}:${tap.name}") config.homebrew.taps
    ++ map (brew: "formula:${brew.name}") config.homebrew.brews
    ++ map (cask: "cask:${cask.name}") config.homebrew.casks;
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

  # Apps come from Nix and land in /Applications/Nix Apps, because hardened
  # Homebrew only accepts command-line casks.
  environment.systemPackages = [ pkgs.wezterm ]
    ++ lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform opensuperwhisper) opensuperwhisper;

  nix-homebrew = {
    enable = true;
    inherit user;
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
    enable = true;
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

  # Hardened Homebrew refuses `brew bundle`, and the user can't write its
  # prefix. Once Automic Vault's brew is installed, a rebuild installs whatever
  # is missing from the lists above through it instead, one command each;
  # otherwise it runs nix-darwin's own Homebrew step unchanged.
  system.activationScripts.homebrew.text = lib.mkIf config.homebrew.enable (lib.mkForce ''
    ${config.system.activationScripts.setup-homebrew.text}

    if ${vaultBrew} --automic-vault-brew-stub-marker 2>/dev/null | grep -q '^AUTOMIC_VAULT_BREW_STUB_'; then
      echo >&2 "Homebrew is hardened by Automic Vault, installing what's missing through its brew..."
      ${lib.getExe hardenedBrewInstall} ${lib.escapeShellArgs ([ config.homebrew.user brewPrefix vaultBrew ] ++ hardenedBrewItems)}
    else
      # nix-darwin's Homebrew Bundle step, as in its modules/homebrew.nix.
      echo >&2 "Homebrew bundle..."
      if [ -f "${brewPrefix}/bin/brew" ]; then
        PATH="${brewPrefix}/bin:${lib.makeBinPath [ pkgs.mas ]}:$PATH" \
        sudo \
          --preserve-env=PATH \
          --user=${lib.escapeShellArg config.homebrew.user} \
          --set-home \
          env \
          ${config.homebrew.onActivation.brewBundleCmd}
      else
        echo -e "\e[1;31merror: Homebrew is not installed, skipping...\e[0m" >&2
      fi
    fi
  '');
}
