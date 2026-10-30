# dotfiles

My personal Mac setup, managed with nix-darwin and home-manager.
One repo, one command, and a fresh Mac ends up configured the same way every time [^1]

## Contributing / Using This Repo

These are my personal dotfiles, shared publicly so people can read them, learn from them, and fork them freely.
Feature requests and pull requests are not accepted here, and PRs are auto-closed.
If you find a bug, please open a GitHub Issue using the bug report template.

## What you get

Running the switch builds:

- System settings (dark mode, key repeat, dock, Finder, trackpad)
- Touch ID for sudo, with the password as fallback
- Apps from Nix (Ghostty, OpenSuperWhisper), copied into `/Applications/Nix Apps`
- Homebrew CLI tools (formulae and command-line casks)
- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font, gh)
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (Ghostty config with the Monokai Pro theme, the Operator Mono SSm Lig font with ligatures, and dimmed unfocused windows)
- Agent configs (Claude, and Codex share one AGENTS.md)

## Prerequisites

- Apple Silicon Mac, by default.
- Intel Mac: change one line.
  In `configuration.nix`, set `nixpkgs.hostPlatform = "x86_64-darwin";` (the comment right there tells you the same thing).
  OpenSuperWhisper only ships for Apple Silicon, so an Intel build leaves it out.

## Fresh-machine setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/kunchenguid/dotfiles.git
cd dotfiles
```

Before you run it: review "Make it yours" below.
Change the host label or CPU architecture if needed, and read the note on what a rerun leaves alone.
`bootstrap.sh` applies the config to your machine, so do this first.

```sh
./bootstrap.sh
```

`bootstrap.sh` does four things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
   This has to happen before the first build, because `home.nix` points at config files through `~/.dotfiles`.
3. Checks the `user` configured in `flake.nix` against your actual macOS username, and offers to fix it for you if they differ.
4. Runs the first `darwin-rebuild switch`.
   It fetches the `darwin-rebuild` tool from the nix-darwin 26.05 release branch, then applies this repo's locked flake config.
   With hardened Homebrew, it then runs `brew-sync`, as `rebuild.sh` does.

After that, `darwin-rebuild` exists and you're on the normal workflow below.

### Validate without applying

Once Nix is installed (`bootstrap.sh` step 1 handles that), you can check that the config builds without touching your system - handy when you have edited something:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

If you renamed the host label in "Make it yours", substitute your label for `mac` in these commands.

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

That's it.
No separate build-and-copy step.

## Make it yours

This repo is mine.
If you clone it, review these before you run `bootstrap.sh`:

- **Username**: run `./bootstrap.sh` (it detects your macOS username and offers to set it) OR change the single `user = "ahcarpenter"` line in `flake.nix`.
  Everything else (`configuration.nix`, `home.nix`, home directory paths) is threaded from that one variable.
- **Host label** `"mac"`, in three places: `flake.nix` (the `darwinConfigurations."mac"` name), `rebuild.sh:5` (the `#mac` at the end of the flake reference), and `bootstrap.sh`'s first-switch command (also `#mac`).
  All three have to match.
- **CPU architecture**, `hostPlatform` in `configuration.nix` (see Prerequisites above).
- **Hardened Homebrew**, `hardenedHomebrew = true` at the top of `configuration.nix`.
  Set it to `false` unless Automic Vault has hardened this Mac's Homebrew (see "Hardened Homebrew" below).

**Git identity and signing:** Managed declaratively, within `home.nix` via:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Andrew Carpenter";
    email = "drewwcarpenter@gmail.com";
  };
  signing = lib.mkIf pkgs.stdenv.isDarwin {
    format = "openpgp";
    signByDefault = true;
    signer = "/Applications/Automic Vault.app/Contents/MacOS/av-gpg";
  };
};
```

Every commit and tag is signed through [Automic Vault](https://github.com/automic-vault/automic-vault).
Install it yourself from its [latest release](https://github.com/automic-vault/automic-vault/releases/latest): it isn't in the Homebrew lists, because its cask installs an app, which hardened Homebrew refuses.
If you don't use it, remove the `signing` block in your copy, or your commits will fail.

**Hardened Homebrew:** once you run Automic Vault's `av harden brew`, its `brew` in `/usr/local/bin` is the only thing that may change Homebrew, and it refuses `brew bundle`.
`hardenedHomebrew` in `configuration.nix` says whether that's done on this Mac.
When it's `true`, nix-homebrew sets Homebrew up as Automic Vault's `automic` account and nix-darwin's `brew bundle` step is off.
After the switch, `rebuild.sh` runs `brew-sync` as you, which installs whatever is missing from `taps`, `brews` and `casks` one at a time through Automic Vault's `brew`, so each install waits for your approval in Automic Vault.
A denied or failed install prints a warning with the command to run yourself, and the rest carry on.
When it's `false`, a switch runs `brew bundle` as usual.
On a fresh Mac, start with `false`; after `av harden brew`, set it to `true` and run `./rebuild.sh`.
`casks` can only hold command-line casks, since hardened Homebrew refuses app casks; apps come from Nix in `configuration.nix` instead.
`/usr/local/bin` comes first in `PATH` so `brew` is Automic Vault's, and Homebrew's zsh completions aren't loaded, since zsh refuses them once Automic Vault owns them.
`~/.nix-profile` is left out of `PATH`: Home Manager installs into `/etc/profiles/per-user/$USER`, so it never exists, and any process running as you could create it ahead of `/usr/bin`.

**Hardened sudo:** `configuration.nix` turns on Touch ID for sudo, which is what Automic Vault's `av harden sudo` does.
nix-darwin owns `/etc/pam.d/sudo_local`, so `av harden sudo` can't add its line there; instead every switch writes `auth sufficient pam_tid.so` into it, and Automic Vault reports sudo as hardened.
The switch also adds `pam_reattach` ahead of it, so Touch ID works inside herdr, tmux and other terminal multiplexers, whose servers run outside the login session Touch ID needs.
Touch ID is `sufficient`, not `required`: when it can't be used (lid closed, over SSH), sudo asks for your password as before.
To turn it off, set `touchIdAuth` and `reattach` under `security.pam.services.sudo_local` in `configuration.nix` to `false` and run `./rebuild.sh`.

**Safe reruns:** a switch never removes Homebrew packages and never overwrites your Claude Code settings.
`configuration.nix` sets `homebrew.onActivation.cleanup = "none"`, so Homebrew installs what's in `brews` and `casks` and leaves anything else you installed alone.
`~/.claude/settings.json` is not linked into the repo: each switch adds only the keys from `home/.claude/settings.json` that it's missing (backing it up first), and your existing values always win.
If the live file isn't valid JSON, the switch leaves it untouched and prints a warning.
Any other file home-manager finds in its way is moved aside with a `.backup` extension instead of stopping the switch.

**About `herdr`:** it's in the `brews` list.
It's a real public Homebrew formula (`brew info herdr` finds it in homebrew-core, no tap needed), so it will install fine.
If you don't use it, just remove it from `brews` in your copy.

**Heads-up:**

- `home/AGENTS.md` is my personal agent policy, and `home.nix` installs it for Claude, and Codex.
  If you clone this repo, you'd silently inherit my agent instructions - edit or delete `home/AGENTS.md` if you don't want that.
- The `cc` and `co` shell aliases in `home.nix` are high-agency shortcuts: `claude --dangerously-skip-permissions` and `codex --full-auto`.
  They're convenient for me, but know what they do before you use them.
- `home/.claude/settings.json` makes the same high-agency choices for Claude Code: auto permission mode by default, no prompt before bypass-permissions mode, and the Fable model.
  Its `SessionStart` hooks run `gh-axi`, `chrome-devtools-axi` and `lavish-axi`, which this repo doesn't install.
  A switch only adds the keys your settings lack, so edit that file first if you don't want these.

## Repo tour

- `flake.nix` - the entry point.
  Wires up nixpkgs, nix-darwin, home-manager, and nix-homebrew, and declares the `mac` machine.
- `configuration.nix` - system-level config: macOS defaults, Touch ID for sudo, apps, Homebrew.
- `home.nix` - user-level config: shell, packages, prompt, and the symlinks described below.
- `rebuild.sh` - re-applies the config after the first switch, then runs `brew-sync` if Homebrew is hardened.
  Run this every time you make a change.
- `home/` - the actual config files that get symlinked into place (except `home/.claude/settings.json`, which is merged in; see "Safe reruns"); the sections below explain the shared symlink model and Pi's narrower selective setup.
- `pkgs/` - OpenSuperWhisper, which isn't in nixpkgs, packaged from its signed release.
- `scripts/` - the Claude Code settings merge that runs on each switch, `brew-sync` for hardened Homebrew, and their tests (run by `nix flake check`).

## How the symlinks work

The files under `home/` are the real files - editing them here is editing your live config, no rebuild needed to see the change in your editor.
`home.nix` uses `mkOutOfStoreSymlink` to point paths like `~/.config/nvim` straight at `home/.config/nvim` in this repo, so the two never drift out of sync.
You only run `./rebuild.sh` when you change something that isn't just a symlinked file, like a package list or a system default.

## Notes

The first time you launch `nvim`, it bootstraps [lazy.nvim](https://github.com/folke/lazy.nvim) by cloning plugins from GitHub.
That needs network access once; after that it's offline.
Neovim uses the rose-pine moon theme, and Ghostty uses Monokai Pro.
Ghostty uses the Operator Mono SSm Lig font with its programming ligatures on.
Operator Mono SSm Lig is a paid font that is not in this repo, so install it by hand; on a machine without it, Ghostty falls back to its default font.
Nerd Font icons and powerline glyphs come from Ghostty's built-in fallbacks, so prompt and Neovim icons still render.
Neovim keeps italics off and uses a transparent background on macOS, Windows, and WSL so it matches the terminal setup.
Ghostty has no setting that dims an unfocused window, so its config loads `shaders/dim-unfocused.glsl`, a custom shader that dims any terminal without focus, including an unfocused split.
Ghostty's title bar stays blank: the config hides the folder icon and fixes the title to a space, so a tab shows only its ⌘1, ⌘2 shortcut unless you rename it.

## License

This repo is licensed under MIT No Attribution.
See `LICENSE`.

[^1]: Credit to @kunchenguid’s [dotfiles](https://github.com/kunchenguid/dotfiles) repo for the inspiration!
