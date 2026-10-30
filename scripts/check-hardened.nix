{ writeShellApplication }:

writeShellApplication {
  name = "check-hardened";
  text = builtins.readFile ./check-hardened.sh;
}
