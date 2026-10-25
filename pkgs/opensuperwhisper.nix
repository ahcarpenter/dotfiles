{ lib, stdenvNoCC, fetchurl, undmg }:

# OpenSuperWhisper isn't in nixpkgs, so this installs the release the
# Homebrew cask used, straight from its signed DMG.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opensuperwhisper";
  version = "0.1.0";

  src = fetchurl {
    url = "https://github.com/starmel/OpenSuperWhisper/releases/download/${finalAttrs.version}/OpenSuperWhisper.dmg";
    hash = "sha256-r1ylFCwi5b7Tun0mQiI8CkgeSZNfWlps8bx2bH7NnWk=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";

  # Copy the app bundle as it ships: stripping or patching it would break its code signature.
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R OpenSuperWhisper.app "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "macOS dictation app";
    homepage = "https://github.com/starmel/OpenSuperWhisper";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    # The release is an arm64-only build and needs macOS 14 or later.
    platforms = [ "aarch64-darwin" ];
  };
})
