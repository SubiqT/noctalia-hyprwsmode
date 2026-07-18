--!nonstrict

-- Bar widget for the hyprwsmode Hyprland compositor plugin.
--
-- Subscribes to Hyprland's socket2 stream via a long-lived nc process and
-- filters two prefixes:
--
--   wsmode>>N,<mode>      hyprwsmode's per-workspace mode. Emitted on every
--                         mode change, on workspace creation, on
--                         `hyprctl reload`, and on an explicit
--                         `wsmode broadcast` (called once at bootstrap).
--   workspacev2>>id,name  Hyprland's active-workspace change event.
--
-- Bootstrap at load time:
--   1. `hyprctl instances -j`        discover the current session signature
--                                    so we can build the socket2 path even
--                                    when HYPRLAND_INSTANCE_SIGNATURE is
--                                    not in Noctalia's env.
--   2. Start `nc -U .../.socket2.sock` via runStream.
--   3. `hyprctl activeworkspace -j`  seed activeWsId.
--   4. `hyprctl dispatch 'hl.plugin.wsmode.broadcast()'`
--                                    ask the compositor plugin to re-emit
--                                    wsmode>>N,<mode> for every workspace
--                                    it tracks. The events flow back through
--                                    onLine below, so initial state and
--                                    every live update follow one code path.
--   5. Only when hide_on_default is on: two `hyprctl getoption -j` calls to
--      read the compositor plugin's global default mode.
--
-- Steps 3 and 4 are chained, not parallel, so nc has time to finish
-- connect(2) during the activeworkspace round-trip before broadcast events
-- start arriving.
--
-- Graceful degradation: no error toasts anywhere. If the compositor plugin
-- is not loaded, `broadcast()` fails silently and no wsmode>> lines ever
-- arrive; mode stays nil and the widget stays hidden. If nc is missing or
-- lacks -U (GNU netcat) the shell command exits and the same non-render
-- path applies.

local GLYPHS = {
  tile  = "layout-grid",
  stack = "stack-2",
  float = "app-window",
}

-- Settings read once at load. Noctalia rebuilds the widget entry on any
-- settings change, so caching in locals is safe and cheaper than a
-- noctalia.getConfig call per render.
local showGlyph     = noctalia.getConfig("show_glyph")
local showText      = noctalia.getConfig("show_text")
local hideOnDefault = noctalia.getConfig("hide_on_default")
local showTooltip   = noctalia.getConfig("show_tooltip")

local modeByWs = {}      -- workspace id -> "tile" | "stack" | "float"
local activeWsId = nil   -- currently focused workspace id (may be negative for special workspaces)

-- The compositor plugin's global default mode ("tile" | "stack" | "float"),
-- seeded via hyprctl getoption only when hide_on_default is on. Left nil
-- otherwise; render() then treats hide_on_default as inactive until it
-- lands, so the widget renders normally in the meantime instead of hiding
-- pre-bootstrap based on stale defaults.
local globalDefaultMode = nil

-- Start hidden; reveal on first successful render. The default value tree
-- (glyph + text) is meaningless until we know the mode.
barWidget.setVisible(false)

local function render()
  if activeWsId == nil then return end
  local mode = modeByWs[activeWsId]
  if mode == nil then
    barWidget.setVisible(false)
    return
  end
  if hideOnDefault and globalDefaultMode ~= nil and mode == globalDefaultMode then
    barWidget.setVisible(false)
    return
  end
  -- setGlyph on an empty string tries to resolve a glyph named "" and falls
  -- back to Noctalia's kMissingGlyph (the skull), so leave the glyph slot
  -- untouched entirely when show_glyph is off. Widget rebuilds on any
  -- settings change reset the slot, so no stale glyph from a previous
  -- lifecycle can bleed through. Empty text is safe — the label slot has
  -- no lookup, it just renders nothing.
  if showGlyph then
    barWidget.setGlyph(GLYPHS[mode] or "layout")
  end
  barWidget.setText(showText and mode or "")
  if showTooltip then
    barWidget.setTooltip("workspace " .. tostring(activeWsId) .. " · " .. mode)
  end
  barWidget.setVisible(true)
end

-- ── socket2 line parser ─────────────────────────────────────────────────────

local function onLine(line)
  -- wsmode>>N,mode  (N may be negative for special workspaces)
  local wsIdStr, mode = line:match("^wsmode>>(%-?%d+),(%w+)")
  if wsIdStr then
    local wsId = tonumber(wsIdStr)
    modeByWs[wsId] = mode
    if wsId == activeWsId then render() end
    return
  end

  -- workspacev2>>id,name  (fired on every active-workspace change)
  local newWsIdStr = line:match("^workspacev2>>(%-?%d+),")
  if newWsIdStr then
    activeWsId = tonumber(newWsIdStr)
    render()
    return
  end
end

-- ── Bootstrap: discover the Hyprland instance, then start the socket2 stream

noctalia.runAsync("hyprctl instances -j", function(res)
  if res.exitCode ~= 0 then return end
  local instances = noctalia.json.decode(res.stdout)
  if type(instances) ~= "table" or #instances == 0 then return end
  local sig = instances[1].instance
  if type(sig) ~= "string" or sig == "" then return end

  local xdgRuntime = noctalia.getenv("XDG_RUNTIME_DIR")
  if xdgRuntime == nil or xdgRuntime == "" then return end
  local socketPath = xdgRuntime .. "/hypr/" .. sig .. "/.socket2.sock"

  -- nc streams the socket line-by-line to stdout. OpenBSD-style netcat is
  -- required for -U (Unix-domain) support. runStream terminates the process
  -- automatically on script reload / entry removal.
  noctalia.runStream("nc -U '" .. socketPath .. "'", onLine)

  -- Seed activeWsId, then ask the compositor plugin to re-broadcast every
  -- workspace's current mode. See bootstrap comment at the top of the file
  -- for why these two calls are chained rather than parallel.
  noctalia.runAsync("hyprctl activeworkspace -j", function(wsRes)
    if wsRes.exitCode == 0 then
      local ws = noctalia.json.decode(wsRes.stdout)
      if type(ws) == "table" and ws.id ~= nil then
        activeWsId = ws.id
        render()
      end
    end
    noctalia.runAsync("hyprctl dispatch 'hl.plugin.wsmode.broadcast()'")
  end)
end)

-- Fetch the compositor plugin's global default mode only when
-- hide_on_default is on. `plugin:wsmode:default_managed` is "managed" or
-- "float"; when "managed", `plugin:wsmode:default_managed_type` picks
-- between "tile" and "stack". Per-workspace overrides
-- (default_managed_N / default_managed_type_N) are deliberately ignored:
-- the user asked for a global hide, not a per-workspace one.
if hideOnDefault then
  noctalia.runAsync("hyprctl getoption -j plugin:wsmode:default_managed", function(r)
    if r.exitCode ~= 0 then return end
    local opt = noctalia.json.decode(r.stdout)
    if type(opt) ~= "table" or type(opt.str) ~= "string" then return end
    if opt.str == "float" then
      globalDefaultMode = "float"
      render()
      return
    end
    noctalia.runAsync("hyprctl getoption -j plugin:wsmode:default_managed_type", function(r2)
      if r2.exitCode ~= 0 then return end
      local opt2 = noctalia.json.decode(r2.stdout)
      if type(opt2) ~= "table" or type(opt2.str) ~= "string" then return end
      globalDefaultMode = opt2.str
      render()
    end)
  end)
end

-- ── Click actions ──────────────────────────────────────────────────────────
--
-- Fire the compositor plugin's dispatchers and let it decide the next mode.
-- The wsmode>> event that the compositor emits after the mode change lands
-- back through onLine above, so the widget's state and label update through
-- the same code path as every other update. No optimistic UI mutation here.
--
-- toggle on Floating no longer needs a special case at the widget: the
-- compositor plugin's doToggle transitions Float -> Managed[lastManaged]
-- itself, so left click has one semantic ("cycle managed types, or leave
-- float") that the plugin implements atomically.

function onClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.wsmode.toggle()'")
end

function onRightClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.wsmode.toggle_float()'")
end
