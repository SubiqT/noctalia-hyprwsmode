{ lib, stdenvNoCC, nix-gitignore }:

# Static plugin bundle. No compilation needed: the plugin is a directory of
# Luau + TOML files that Noctalia loads at runtime. The derivation lays the
# repo's `hyprwsmode/` subdirectory into `$out/hyprwsmode/`, matching what a
# Noctalia `path` source expects to find (a directory containing one or more
# plugin subdirectories, each with a `plugin.toml`).
#
# Consumers:
#
#   inputs.noctalia-hyprwsmode.url = "github:SubiqT/noctalia-hyprwsmode";
#
#   # Then, in the Noctalia config file:
#   plugins = {
#     enabled = [ "subiqt/hyprwsmode" ];
#     source = [{
#       name     = "subiqt-hyprwsmode";
#       kind     = "path";
#       location = "${inputs.noctalia-hyprwsmode.packages.${pkgs.system}.default}";
#     }];
#   };
stdenvNoCC.mkDerivation {
  pname = "noctalia-hyprwsmode";
  version = "0.1.0";

  # nix-gitignore drops editor droppings, coverage.out, profile artefacts,
  # and any local files matched by .gitignore so the store path is the same
  # bytes for the same commit regardless of the developer's checkout state.
  src = nix-gitignore.gitignoreSource [ ] ./.;

  # No build. Copy the plugin directory verbatim so Noctalia's source scan
  # finds `hyprwsmode/plugin.toml` at the expected depth.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r hyprwsmode $out/
    runHook postInstall
  '';

  meta = with lib; {
    homepage    = "https://github.com/SubiqT/noctalia-hyprwsmode";
    description = "Noctalia bar widget for the hyprwsmode Hyprland plugin";
    license     = licenses.mit;
    platforms   = platforms.linux;
  };
}
