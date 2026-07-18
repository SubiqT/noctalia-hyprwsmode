--!nonstrict

-- Bar widget for the hyprwsmode Hyprland compositor plugin.
--
-- Milestone 2 scaffold: renders a static glyph and label so the widget appears
-- in Noctalia's Add-widget picker and we can confirm the plugin loads through
-- both a `path` source and the eventual Nix package. Subsequent milestones
-- subscribe to Hyprland's socket2 stream for live wsmode updates and wire
-- click handlers to the compositor plugin's dispatchers.
--
-- Rendered once at load: no update() and no setUpdateInterval, so the widget
-- costs zero CPU until state actually changes (a design requirement for v1).

barWidget.setGlyph("layout")
barWidget.setText("hello")
