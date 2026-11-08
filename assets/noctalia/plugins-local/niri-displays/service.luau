--!nonstrict
-- Headless service: reads the authoritative output state from Niri's JSON IPC
-- and publishes a normalized snapshot for the bar widget and panel.

local STATE_KEY = "display_snapshot"
local DEFAULT_FALLBACK_INTERVAL_S = 30
local MIN_FALLBACK_INTERVAL_S = 5
local FOCUS_CHECK_INTERVAL_MS = 100
local COMMAND_TIMEOUT_MS = 5000

local fetching = false
local refreshQueued = false
local generation = 0
local lastRefreshNonce = noctalia.state.get("refresh_requested") or 0
local lastFullRefreshAt = 0
local lastResolutionByPort = {}
local resolutionStateReady = false
local presetApplying = {}
-- Enforce a matching preset once when the service starts or hot-reloads. This
-- also repairs a mode change that completed while the service was unavailable.
local forcePresetCheck = true
local startRefresh

local tr = noctalia.tr

local function initialSnapshot(status, message)
  return {
    revision = 0,
    status = status,
    error_message = message,
    focused_output = nil,
    displays = {},
    updated_at = "",
  }
end

local function shallowCopy(value)
  local copy = {}
  for key, item in pairs(value) do
    copy[key] = item
  end
  return copy
end

local function readFallbackIntervalSeconds()
  local seconds = tonumber(noctalia.getConfig("refresh_interval")) or DEFAULT_FALLBACK_INTERVAL_S
  return math.max(MIN_FALLBACK_INTERVAL_S, seconds)
end

local function quoteShellArgument(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function formatScale(value)
  local text = string.format("%.4f", value)
  text = text:gsub("0+$", ""):gsub("%.$", "")
  return text
end

local function presetFor(port, width, height)
  local rawPresets = noctalia.getConfig("scale_presets")
  local globalScale = nil
  local portScale = nil
  if type(rawPresets) ~= "table" then
    return nil
  end

  for _, raw in ipairs(rawPresets) do
    if type(raw) == "string" then
      local value = noctalia.string.trim(raw)
      local presetPort, presetWidth, presetHeight, presetScale =
        value:match("^([^:]+):(%d+)[xX](%d+)%s*=%s*(%d+%.?%d*)$")
      if presetPort ~= nil then
        if noctalia.string.trim(presetPort) == port
          and tonumber(presetWidth) == width
          and tonumber(presetHeight) == height
          and tonumber(presetScale) > 0 then
          portScale = tonumber(presetScale)
        end
      else
        presetWidth, presetHeight, presetScale =
          value:match("^(%d+)[xX](%d+)%s*=%s*(%d+%.?%d*)$")
        if tonumber(presetWidth) == width
          and tonumber(presetHeight) == height
          and tonumber(presetScale) > 0 then
          globalScale = tonumber(presetScale)
        end
      end
    end
  end
  return portScale or globalScale
end

local function displayLabel(output, connector)
  local make = noctalia.string.trim(output.make or "")
  local model = noctalia.string.trim(output.model or "")
  if make ~= "" and model ~= "" then
    return make .. " " .. model
  elseif model ~= "" then
    return model
  elseif make ~= "" then
    return make
  end
  return connector
end

local function normalizeModes(rawModes)
  local modes = {}
  for _, raw in ipairs(rawModes or {}) do
    local width = tonumber(raw.width)
    local height = tonumber(raw.height)
    local refresh = tonumber(raw.refresh_rate)
    if width ~= nil and height ~= nil and refresh ~= nil then
      table.insert(modes, {
        width = width,
        height = height,
        refresh_rate = refresh,
        preferred = raw.is_preferred == true,
      })
    end
  end
  return modes
end

-- Map Niri's JSON transform names to the values accepted by
-- `niri msg output <connector> transform <value>`.
local function normalizeTransform(rawTransform)
  local mapping = {
    Normal = "normal",
    ["90"] = "90",
    ["180"] = "180",
    ["270"] = "270",
    Flipped = "flipped",
    Flipped90 = "flipped-90",
    Flipped180 = "flipped-180",
    Flipped270 = "flipped-270",
  }
  if type(rawTransform) == "string" then
    return mapping[rawTransform] or "normal"
  end
  return "normal"
end

local function normalizeOutputs(rawOutputs, focusedName, revision)
  local displays = {}
  for connector, raw in pairs(rawOutputs) do
    if type(raw) == "table" then
      local modes = normalizeModes(raw.modes)
      local currentIndex = tonumber(raw.current_mode)
      local currentMode = nil
      if currentIndex ~= nil then
        currentMode = modes[currentIndex + 1]
      end
      local logical = type(raw.logical) == "table" and raw.logical or nil
      table.insert(displays, {
        name = displayLabel(raw, connector),
        port = connector,
        make = raw.make or "",
        model = raw.model or "",
        serial = raw.serial or "",
        focused = connector == focusedName,
        enabled = logical ~= nil and currentMode ~= nil,
        x = logical and (tonumber(logical.x) or 0) or 0,
        y = logical and (tonumber(logical.y) or 0) or 0,
        scale = logical and (tonumber(logical.scale) or 1) or 1,
        transform = logical and normalizeTransform(logical.transform) or "normal",
        width = currentMode and currentMode.width or 0,
        height = currentMode and currentMode.height or 0,
        refresh_rate = currentMode and currentMode.refresh_rate or 0,
        modes = modes,
      })
    end
  end

  table.sort(displays, function(a, b)
    if a.enabled ~= b.enabled then
      return a.enabled
    elseif a.x ~= b.x then
      return a.x < b.x
    elseif a.y ~= b.y then
      return a.y < b.y
    end
    return a.port < b.port
  end)

  return {
    revision = revision,
    status = "ok",
    error_message = "",
    focused_output = focusedName,
    displays = displays,
    updated_at = noctalia.formatTime("%H:%M:%S"),
  }
end

local function commandError(result, fallback)
  if result.timedOut then
    return tr("error.timeout")
  end
  local message = noctalia.string.trim(result.stderr or ""):match("^[^\r\n]*") or ""
  if message ~= "" then
    return message
  end
  return fallback
end

local function applyPresetsForResolutionChanges(snapshot)
  -- A Niri mode switch can temporarily remove an output from `outputs`
  -- altogether. Keep the last mode for known connectors so the reconnect is
  -- still recognized as a resolution change instead of a brand-new display.
  local nextResolutions = {}
  for port, resolution in pairs(lastResolutionByPort) do
    nextResolutions[port] = resolution
  end
  for _, display in ipairs(snapshot.displays) do
    if display.enabled and display.width > 0 and display.height > 0 then
      local resolution = tostring(display.width) .. "x" .. tostring(display.height)
      nextResolutions[display.port] = resolution
      local previous = lastResolutionByPort[display.port]
      if forcePresetCheck or (resolutionStateReady and previous ~= nil and previous ~= resolution) then
        local targetScale = presetFor(display.port, display.width, display.height)
        if targetScale ~= nil and math.abs(display.scale - targetScale) > 0.001
          and presetApplying[display.port] ~= targetScale then
          local port = display.port
          presetApplying[port] = targetScale
          local command = "niri msg output " .. quoteShellArgument(port)
            .. " scale " .. quoteShellArgument(formatScale(targetScale))
          noctalia.log("niri-displays: resolution changed on " .. port .. " to " .. resolution
            .. "; applying scale preset " .. formatScale(targetScale))
          local started = noctalia.runAsync(command, function(result)
            presetApplying[port] = nil
            if result.exitCode ~= 0 then
              noctalia.log("niri-displays: automatic scale failed for " .. port .. ": "
                .. commandError(result, tr("error.command")))
            else
              startRefresh()
            end
          end, COMMAND_TIMEOUT_MS)
          if not started then
            presetApplying[port] = nil
            noctalia.log("niri-displays: could not start automatic scale command for " .. port)
          end
        end
      end
    end
  end
  lastResolutionByPort = nextResolutions
  resolutionStateReady = true
  forcePresetCheck = false
end

local function syncFocusedOutput()
  local focusedName = noctalia.focusedOutputName()
  if type(focusedName) ~= "string" or focusedName == "" then
    return
  end
  local current = noctalia.state.get(STATE_KEY)
  if type(current) ~= "table" or type(current.displays) ~= "table"
    or current.focused_output == focusedName then
    return
  end

  local nextSnapshot = shallowCopy(current)
  nextSnapshot.focused_output = focusedName
  nextSnapshot.displays = {}
  for _, display in ipairs(current.displays) do
    local nextDisplay = shallowCopy(display)
    nextDisplay.focused = display.port == focusedName
    table.insert(nextSnapshot.displays, nextDisplay)
  end
  noctalia.state.set(STATE_KEY, nextSnapshot)
end

startRefresh = function()
  if fetching then
    refreshQueued = true
    return
  end
  if not noctalia.commandExists("niri") then
    noctalia.state.set(STATE_KEY, initialSnapshot("error", tr("error.niri_missing")))
    return
  end

  fetching = true
  lastFullRefreshAt = tonumber(noctalia.formatTime("%s")) or 0
  generation += 1
  local thisGeneration = generation
  local pending = 2
  local rawOutputs = nil
  local focusedName = nil
  local outputsError = ""

  local previous = shallowCopy(noctalia.state.get(STATE_KEY))
  previous.status = #previous.displays > 0 and "refreshing" or "loading"
  previous.error_message = ""
  noctalia.state.set(STATE_KEY, previous)

  local function completeOne()
    if thisGeneration ~= generation then
      return
    end
    pending -= 1
    if pending > 0 then
      return
    end

    fetching = false
    if rawOutputs == nil then
      local stale = shallowCopy(noctalia.state.get(STATE_KEY))
      stale.status = "error"
      stale.error_message = outputsError ~= "" and outputsError or tr("error.outputs")
      noctalia.state.set(STATE_KEY, stale)
    else
      local nextSnapshot = normalizeOutputs(rawOutputs, focusedName, thisGeneration)
      applyPresetsForResolutionChanges(nextSnapshot)
      noctalia.state.set(STATE_KEY, nextSnapshot)
    end

    if refreshQueued then
      refreshQueued = false
      startRefresh()
    end
  end

  local outputsStarted = noctalia.runAsync("niri msg --json outputs", function(result)
    if thisGeneration ~= generation then
      return
    end
    if result.exitCode == 0 and not result.stdoutTruncated then
      local decoded = noctalia.json.decode(result.stdout or "")
      if type(decoded) == "table" then
        rawOutputs = decoded
      else
        outputsError = tr("error.parse_outputs")
      end
    else
      outputsError = commandError(result, tr("error.outputs"))
    end
    completeOne()
  end, COMMAND_TIMEOUT_MS)
  if not outputsStarted then
    outputsError = tr("error.outputs")
    completeOne()
  end

  local focusStarted = noctalia.runAsync("niri msg --json focused-output", function(result)
    if thisGeneration ~= generation then
      return
    end
    if result.exitCode == 0 and not result.stdoutTruncated then
      local decoded = noctalia.json.decode(result.stdout or "")
      if type(decoded) == "table" and type(decoded.name) == "string" then
        focusedName = decoded.name
      end
    end
    completeOne()
  end, COMMAND_TIMEOUT_MS)
  if not focusStarted then
    completeOne()
  end
end

-- ── persistência no config do Niri ─────────────────────────────────────────
--
-- O IPC `niri msg output` é temporário. O botão Persistir grava o estado atual
-- em ~/.config/niri/msbos-displays.kdl e garante um `include` no fim do
-- config.kdl (includes do Niri são posicionais: o incluído sobrescreve o que
-- veio antes). O config é validado com `niri validate` antes do reload; se
-- falhar, os arquivos anteriores são restaurados.

local CONFIG_FILE = "config.kdl"
local INCLUDE_FILE = "msbos-displays.kdl"
local persisting = false
local startPersist

local function config_dir()
  local xdg = noctalia.getenv("XDG_CONFIG_HOME")
  if type(xdg) == "string" and xdg ~= "" then
    return xdg .. "/niri"
  end
  return noctalia.expandPath("~/.config/niri")
end

local function read_text(path)
  if not noctalia.fileExists(path) then
    return nil
  end
  local content = noctalia.readFile(path)
  if type(content) ~= "string" or content == "" then
    return nil
  end
  return content
end

local function write_atomic(path, content)
  local tmp = path .. ".tmp"
  if not noctalia.writeFile(tmp, content) then
    return false
  end
  if type(noctalia.renameFile) == "function" and noctalia.renameFile(tmp, path) then
    return true
  end
  pcall(noctalia.removeFile, tmp)
  return noctalia.writeFile(path, content)
end

local function kdl_string(value)
  return '"' .. tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function display_block(display)
  local lines = { "output " .. kdl_string(display.port) .. " {" }
  if display.enabled ~= true then
    table.insert(lines, "    off")
  else
    if (display.width or 0) > 0 and (display.height or 0) > 0 and (display.refresh_rate or 0) > 0 then
      table.insert(lines, string.format(
        '    mode "%dx%d@%.3f"',
        display.width,
        display.height,
        display.refresh_rate / 1000
      ))
    end
    if (display.scale or 0) > 0 then
      table.insert(lines, "    scale " .. formatScale(display.scale))
    end
    if type(display.transform) == "string" and display.transform ~= "" then
      table.insert(lines, "    transform " .. kdl_string(display.transform))
    end
    table.insert(lines, string.format(
      "    position x=%d y=%d",
      math.floor((display.x or 0) + 0.5),
      math.floor((display.y or 0) + 0.5)
    ))
  end
  table.insert(lines, "}")
  return table.concat(lines, "\n")
end

local function managed_content(displays)
  local parts = {
    "// Gerado pelo painel niri-displays do Noctalia (msbos).",
    "// Alterações manuais aqui são substituídas na próxima persistência.",
    "",
  }
  for _, display in ipairs(displays) do
    table.insert(parts, display_block(display))
    table.insert(parts, "")
  end
  return table.concat(parts, "\n")
end

local function has_include(content)
  return content:find('include%s+"[^"]*msbos%-displays%.kdl"') ~= nil
end

local function finish_persist(ok, message)
  persisting = false
  noctalia.log("niri-displays: persist " .. (ok and "ok" or "failed") .. " — " .. tostring(message))
  noctalia.state.set("persist_result", { ok = ok, message = message })
end

local function restore_files(config_path, config, include_path, previous_include)
  if previous_include ~= nil then
    write_atomic(include_path, previous_include)
  else
    pcall(noctalia.removeFile, include_path)
  end
  write_atomic(config_path, config)
end

startPersist = function()
  if persisting then
    return
  end

  local snapshot = noctalia.state.get(STATE_KEY)
  local displays = type(snapshot) == "table" and snapshot.displays or nil
  if type(displays) ~= "table" or #displays == 0 then
    finish_persist(false, tr("persist.no_displays"))
    return
  end

  local dir = config_dir()
  local config_path = dir .. "/" .. CONFIG_FILE
  local include_path = dir .. "/" .. INCLUDE_FILE
  local config = read_text(config_path)
  if config == nil then
    finish_persist(false, tr("persist.no_config"))
    return
  end
  local previous_include = read_text(include_path)

  persisting = true

  if not write_atomic(include_path, managed_content(displays)) then
    finish_persist(false, tr("persist.write_failed"))
    return
  end

  if not has_include(config) then
    local backup_path = config_path .. ".msbos-bak"
    if not noctalia.fileExists(backup_path) then
      noctalia.writeFile(backup_path, config)
    end

    local updated = config
    if updated:sub(-1) ~= "\n" then
      updated = updated .. "\n"
    end
    updated = updated .. '\ninclude "' .. INCLUDE_FILE .. '"\n'

    if not write_atomic(config_path, updated) then
      restore_files(config_path, config, include_path, previous_include)
      finish_persist(false, tr("persist.write_failed"))
      return
    end
  end

  local validate_command = "niri validate -c " .. quoteShellArgument(config_path)
  noctalia.log("niri-displays: " .. validate_command)
  local validate_started = noctalia.runAsync(validate_command, function(result)
    if result.exitCode ~= 0 then
      restore_files(config_path, config, include_path, previous_include)
      local message = noctalia.string.trim(result.stderr or ""):match("^[^\r\n]*") or ""
      finish_persist(false, tr("persist.invalid", { error = message }))
      return
    end

    noctalia.log("niri-displays: config valid, reloading")
    local reload_started = noctalia.runAsync("niri msg action load-config-file", function(reload)
      noctalia.log("niri-displays: reload exit " .. tostring(reload.exitCode))
      if reload.exitCode ~= 0 then
        local message = noctalia.string.trim(reload.stderr or ""):match("^[^\r\n]*") or ""
        finish_persist(false, tr("persist.reload_failed", { error = message }))
        return
      end
      finish_persist(true, tr("persist.ok"))
      startRefresh()
    end, COMMAND_TIMEOUT_MS)

    if not reload_started then
      finish_persist(false, tr("persist.reload_failed", { error = "" }))
    end
  end, COMMAND_TIMEOUT_MS)

  if not validate_started then
    restore_files(config_path, config, include_path, previous_include)
    finish_persist(false, tr("persist.write_failed"))
  end
end

noctalia.setUpdateInterval(FOCUS_CHECK_INTERVAL_MS)

noctalia.state.watch("refresh_requested", function(value)
  local nonce = tonumber(value) or 0
  if nonce ~= lastRefreshNonce then
    lastRefreshNonce = nonce
    startRefresh()
  end
end)

local lastPersistNonce = noctalia.state.get("persist_requested") or 0

noctalia.state.watch("persist_requested", function(value)
  local nonce = tonumber(value) or 0
  if nonce ~= lastPersistNonce then
    lastPersistNonce = nonce
    startPersist()
  end
end)

noctalia.state.set(STATE_KEY, initialSnapshot("loading", ""))
startRefresh()

function update()
  syncFocusedOutput()
  if (tonumber(noctalia.formatTime("%s")) or 0) - lastFullRefreshAt >= readFallbackIntervalSeconds() then
    startRefresh()
  end
end

function onConfigChanged()
  forcePresetCheck = true
  startRefresh()
end

-- Native Noctalia service hook. Niri output mode, scale, and hotplug changes
-- propagate through wl_output and arrive here without waiting for the fallback
-- polling interval.
function onOutputsChanged()
  noctalia.log("niri-displays: output change hook")
  startRefresh()
end

function onIpc(event, _payload)
  if event == "refresh" then
    startRefresh()
  elseif event == "persist" then
    startPersist()
  elseif event == "dump" then
    local snapshot = noctalia.state.get(STATE_KEY)
    noctalia.log("niri-displays: " .. (noctalia.json.encode(snapshot) or "?"))
  end
end
