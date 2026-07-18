--!nonstrict

-- Bar widget for the hyprwsmode Hyprland compositor plugin.
--
-- Subscribes to Hyprland's socket2 stream via a long-lived socat process and
-- filters two prefixes:
--
--   wsmode>>N,<mode>     hyprwsmode's per-workspace mode change (also emitted
--                        as a full snapshot on workspace creation and on
--                        `hyprctl reload`).
--   workspacev2>>id,name  Hyprland's active-workspace change event.
--
-- Bootstrap at load time is three parallel hyprctl calls:
--   1. `hyprctl instances -j`     discover the current session signature so
--                                 we can build the socket2 path even when
--                                 HYPRLAND_INSTANCE_SIGNATURE is not in
--                                 Noctalia's env (systemd-user launches).
--   2. `hyprctl activeworkspace -j` seed activeWsId.
--   3. `hyprctl dispatch 'print(hl.plugin.wsmode.current())'` seed the mode
--                                 of the active workspace, since wsmode>>
--                                 only fires on changes.
--
-- After that, the socket2 stream is the source of truth for every update.
--
-- Graceful degradation: no error toasts anywhere. If the compositor plugin
-- is not loaded, `wsmode.current()` returns garbage and no wsmode>> lines
-- ever arrive, so mode stays nil and the widget stays hidden. If socat is
-- missing, the shell command exits and the same non-render path applies.

local GLYPHS = {
  tile  = "layout-grid",
  stack = "stack-2",
  float = "app-window",
}

local modeByWs = {}      -- workspace id -> "tile" | "stack" | "float"
local activeWsId = nil   -- currently focused workspace id (may be negative for special workspaces)
local pendingMode = nil  -- mode from the bootstrap dispatch, held until activeWsId lands

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
  barWidget.setGlyph(GLYPHS[mode] or "layout")
  barWidget.setText(mode)
  barWidget.setVisible(true)
end

-- Copy pendingMode into modeByWs once activeWsId is known. Handles the race
-- between the two bootstrap hyprctl calls: whichever lands last triggers the
-- first render.
local function tryApplyPending()
  if activeWsId ~= nil and pendingMode ~= nil then
    modeByWs[activeWsId] = pendingMode
    pendingMode = nil
  end
  render()
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
    tryApplyPending()
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

  -- socat streams the socket line-by-line to stdout. runStream terminates
  -- the process automatically on script reload / entry removal.
  noctalia.runStream("socat -U - 'UNIX-CONNECT:" .. socketPath .. "'", onLine)
end)

noctalia.runAsync("hyprctl activeworkspace -j", function(res)
  if res.exitCode ~= 0 then return end
  local ws = noctalia.json.decode(res.stdout)
  if type(ws) ~= "table" or ws.id == nil then return end
  activeWsId = ws.id
  tryApplyPending()
end)

-- hl.plugin.wsmode.current() returns a Lua string; the print(...) wrapper is
-- required because dispatch expects something callable and this expression
-- otherwise yields a bare value. Output shape varies across Hyprland versions
-- (some include a leading "ok" line), so scan for a known mode token.
noctalia.runAsync("hyprctl dispatch 'print(hl.plugin.wsmode.current())'", function(res)
  if res.exitCode ~= 0 then return end
  local mode = res.stdout:match("(tile)") or res.stdout:match("(stack)") or res.stdout:match("(float)")
  if mode == nil then return end
  pendingMode = mode
  tryApplyPending()
end)
