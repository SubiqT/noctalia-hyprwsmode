# noctalia-hyprwsmode

[Noctalia](https://noctalia.dev) bar widget for the
[hyprwsmode](https://github.com/SubiqT/hyprwsmode) Hyprland plugin. Shows the
focused workspace's current mode (`tile`, `stack`, or `float`) and toggles
it on click. All state is driven by Hyprland's socket2 stream, so the widget
idles at zero CPU when nothing is changing.

## Requirements

- **Hyprland 0.55+**.
- The [hyprwsmode](https://github.com/SubiqT/hyprwsmode) compositor plugin,
  loaded via Hyprland's `plugin = ...` config directive (or the home-manager
  module's `wayland.windowManager.hyprland.plugins`).
- **Noctalia v5**.
- `nc` on `$PATH` supporting `-U` for Unix-domain sockets. Standard on
  NixOS (via libressl), Arch (`openbsd-netcat`), Debian
  (`netcat-openbsd`), and Fedora (`nmap-ncat`). GNU netcat lacks `-U` and
  will not work.

## Behaviour

- **Label**: `tile`, `stack`, or `float`, following the focused workspace.
- **Glyph**: `layout-grid` / `stack-2` / `app-window` per mode.
- **Left click**: `hl.plugin.wsmode.toggle()`. On a managed workspace this
  flips tile ↔ stack. On a floating workspace it returns to the last
  managed type.
- **Right click**: `hl.plugin.wsmode.toggle_float()`. Flips managed ↔ float.

The compositor plugin decides the next mode atomically; the widget only
issues the toggle and re-renders on the `wsmode>>` event that comes back.

If the compositor plugin is not loaded, or `nc` is missing, the widget
stays hidden. It never emits an error toast.

## Install

### Nix flakes (recommended for NixOS)

Add both plugins to your flake inputs, then follow the compositor and shell
inputs so everything shares one nixpkgs / Hyprland pair:

```nix
{
  inputs = {
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";

    hyprwsmode = {
      url = "github:SubiqT/hyprwsmode";
      inputs.hyprland.follows = "hyprland";
    };

    noctalia-hyprwsmode = {
      url = "github:SubiqT/noctalia-hyprwsmode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Load the compositor plugin from Hyprland (home-manager module):

```nix
wayland.windowManager.hyprland = {
  enable = true;
  plugins = [ inputs.hyprwsmode.packages.${pkgs.system}.default ];
};
```

Expose the widget to Noctalia as a `path` source, and enable it:

```nix
{
  # In your Noctalia config module:
  plugins.enabled = [ "subiqt/hyprwsmode" ];
  plugins.source = [
    {
      name     = "subiqt-hyprwsmode";
      kind     = "path";
      location = "${inputs.noctalia-hyprwsmode.packages.${pkgs.system}.default}";
    }
  ];
}
```

`nixos-rebuild switch` deploys both. To bump, run `nix flake update
noctalia-hyprwsmode` (or plain `nix flake update`) then rebuild. `flake.lock`
records the exact revision so system generations roll forward and backward
together.

The flake supports `x86_64-linux` and `aarch64-linux`.

### Manual (non-Nix)

Install and load the [hyprwsmode](https://github.com/SubiqT/hyprwsmode)
compositor plugin per its README.

Add this repo as a git source in Noctalia and enable it:

```sh
noctalia msg plugins source add subiqt-hyprwsmode git https://github.com/SubiqT/noctalia-hyprwsmode
noctalia msg plugins enable subiqt/hyprwsmode
```

Or, declaratively, add to your Noctalia config:

```toml
[plugins]
enabled = ["subiqt/hyprwsmode"]

[[plugins.source]]
name     = "subiqt-hyprwsmode"
kind     = "git"
location = "https://github.com/SubiqT/noctalia-hyprwsmode"
```

Bump with `noctalia msg plugins update subiqt-hyprwsmode`.

## Placing the widget

Once enabled, the widget appears as **Hyprwsmode** in Noctalia's Add-widget
picker. To wire it explicitly in TOML:

```toml
[widget.wsmode]
type = "subiqt/hyprwsmode:wsmode"
```

## Configuration

The widget has no settings in v1. Colours follow Noctalia's palette roles
so they track theme changes automatically.

## Development

Point Noctalia at a working checkout for hot-reloading Luau edits:

```sh
noctalia msg plugins source add wsmode-dev path ~/dev/noctalia-hyprwsmode
noctalia msg plugins enable subiqt/hyprwsmode
```

`.luau` edits hot-reload on save. Manifest (`plugin.toml`) changes are
picked up on the next config reload.

## How it works

At load, the widget starts hidden and runs three parallel `hyprctl` calls:
`hyprctl instances -j` (to discover the current Hyprland session
signature), `hyprctl activeworkspace -j` (to seed the focused workspace
id), and — via chained `runAsync` — `hyprctl dispatch
'hl.plugin.wsmode.broadcast()'` (to make the compositor plugin re-emit
every workspace's current mode onto socket2).

A single `nc -U <session>/.socket2.sock` stream is kept open via
`noctalia.runStream`. Two prefixes are consumed:

- `wsmode>>N,<mode>` — from hyprwsmode. Records the mode of workspace `N`.
- `workspacev2>>id,name` — from Hyprland. Records the focused workspace.

Whenever either the focused-workspace or the focused-workspace's-mode
changes, the widget re-renders. There is no `setUpdateInterval` and no
polling; the socket2 stream is the sole update trigger.

## Non-goals

- Cross-compositor support. Hyprland-only, since the widget relies on
  hyprwsmode's dispatchers and Hyprland's socket2.
- Persisting runtime toggles across restarts. hyprwsmode itself does not
  persist them either.
- Extensive configuration. Icon vs text, colour overrides, and
  per-workspace lists were left out of v1 by design; the widget is a thin
  lens over the compositor plugin's authoritative state.

## Licence

MIT. See [LICENSE](LICENSE).
