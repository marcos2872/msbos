--!nonstrict
-- Polls niri and publishes a snapshot for the bar widget and panel.

local interval = (tonumber(noctalia.getConfig("interval")) or 2) * 1000
local snapshot = {
  output = nil,
  workspace = nil,
  workspaces = {},
  error = nil,
  updatedAt = 0,
}
local busy = false

local function publish()
  snapshot.updatedAt = noctalia.nowMs()
  noctalia.state.set("niri_snapshot", snapshot)
end

local function fail(message)
  snapshot.error = message ~= "" and message or "niri falhou"
  busy = false
  publish()
end

local function fetchWorkspaces()
  noctalia.runAsync({ "niri", "msg", "--json", "workspaces" }, function(result)
    if result.exitCode ~= 0 then
      fail(noctalia.string.trim(result.stderr or ""))
      return
    end
    local data = noctalia.json.decode(result.stdout or "")
    if type(data) ~= "table" then
      fail("JSON de workspaces inválido")
      return
    end
    local focused = nil
    for _, workspace in ipairs(data) do
      if workspace.is_focused == true then
        focused = workspace
        break
      end
    end
    snapshot.workspaces = data
    snapshot.workspace = focused
    snapshot.error = nil
    busy = false
    publish()
  end, 5000)
end

local function fetchOutput()
  noctalia.runAsync({ "niri", "msg", "--json", "focused-output" }, function(result)
    if result.exitCode ~= 0 then
      fail(noctalia.string.trim(result.stderr or ""))
      return
    end
    local data = noctalia.json.decode(result.stdout or "")
    if type(data) ~= "table" then
      fail("JSON de output inválido")
      return
    end
    snapshot.output = data
    fetchWorkspaces()
  end, 5000)
end

local function refresh()
  if busy then
    return
  end
  busy = true
  snapshot.error = nil
  fetchOutput()
end

function update()
  refresh()
end

function onIpc(event)
  if event == "refresh" then
    refresh()
  end
end

function onConfigChanged()
  interval = (tonumber(noctalia.getConfig("interval")) or 2) * 1000
  noctalia.setUpdateInterval(interval)
  refresh()
end

noctalia.setUpdateInterval(interval)
refresh()
