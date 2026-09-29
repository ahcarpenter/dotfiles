{ writeShellApplication, jq, coreutils }:

writeShellApplication {
  name = "merge-claude-settings";
  runtimeInputs = [ jq coreutils ];
  text = builtins.readFile ./merge-claude-settings.sh;
}
