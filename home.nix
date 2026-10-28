{ config, lib, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    neovim
    gh
    fnm
    # Nerd Font; Ghostty itself renders in Operator Mono SSm Lig (see README)
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    ZSH_COLORIZE_STYLE = "monokai";
  };

  programs.git = {
    enable = true;
    settings.user = {
      name = "Andrew Carpenter";
      email = "drewwcarpenter@gmail.com";
    };
    # Automic Vault signs every commit and tag, and picks the key itself.
    # It only runs on macOS, so other systems keep home-manager's defaults.
    signing = lib.mkIf pkgs.stdenv.isDarwin {
      format = "openpgp";
      signByDefault = true;
      signer = "/Applications/Automic Vault.app/Contents/MacOS/av-gpg";
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
      eval "$(fnm env --use-on-cd --shell zsh)"
    '';
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "z" "colorize"];
    };
    shellAliases = {
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/ghostty";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Claude Code writes to its own settings, so it isn't linked: each rebuild
  # adds only the repo keys the live file lacks, after backing it up.
  # Runs before linkGeneration so the old link becomes a regular file before
  # home-manager cleans up links from the previous generation.
  home.activation.mergeClaudeSettings = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
    ${lib.getExe (pkgs.callPackage ./scripts/merge-claude-settings.nix { })} \
      ${./home/.claude/settings.json} "$HOME/.claude/settings.json"
  '';
}
