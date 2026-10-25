{ writeShellApplication, coreutils }:

writeShellApplication {
  name = "hardened-brew-install";
  runtimeInputs = [ coreutils ];
  text = builtins.readFile ./hardened-brew-install.sh;
}
