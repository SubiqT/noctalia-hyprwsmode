{
  description = "Noctalia bar widget for the hyprwsmode Hyprland plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      # NixOS + Hyprland audience is overwhelmingly on these two systems;
      # Hyprland itself only ships for these. Keep in step so an override
      # via `inputs.hyprwsmode.follows` etc. can be added later without
      # widening the system set.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = fn:
        nixpkgs.lib.genAttrs systems (system: fn nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        noctalia-hyprwsmode = pkgs.callPackage ./default.nix { };
        default = noctalia-hyprwsmode;
      });
    };
}
