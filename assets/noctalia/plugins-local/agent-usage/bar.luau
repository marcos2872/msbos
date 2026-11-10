--!nonstrict
-- Ícone do Agent Usage na barra: glifo neutro (o plugin cobre mais de um
-- provider) + tooltip com uma linha por provider configurado.
--
-- O glifo herda a cor da barra e resolve claro/escuro sozinho — sem os dois
-- SVGs que o logo do OpenCode exigia.

local time = require("./lib/time.luau")
local money = require("./lib/money.luau")

local WINDOWS = {
  { key = "rolling", label = "window.rolling" },
  { key = "weekly", label = "window.weekly" },
  { key = "monthly", label = "window.monthly" },
}

local GLYPH = "robot"

local last_tooltip = nil

local function apply_glyph()
  barWidget.setGlyph(GLYPH)
end

local function go_line()
  local usage = noctalia.state.get("go.usage")
  local parts = {}
  for _, w in ipairs(WINDOWS) do
    local window = type(usage) == "table" and usage[w.key] or nil
    local percent = type(window) == "table" and tonumber(window.percent) or nil
    parts[#parts + 1] = noctalia.tr(w.label) .. " "
      .. (percent and (math.floor(percent + 0.5) .. "%") or "—")
  end
  local line = "OpenCode Go: " .. table.concat(parts, " · ")
  local credits = noctalia.state.get("go.credits")
  if type(credits) == "table" and tonumber(credits.available) then
    line = line .. " · " .. noctalia.tr("panel.credits") .. " "
      .. money.format_microcents(credits.available)
  end
  return line
end

local function cp_line()
  local quota = noctalia.state.get("cp.quota")
  if type(quota) ~= "table" then return nil end

  local parts = {}
  if quota.unlimited then
    parts[#parts + 1] = noctalia.tr("panel.unlimited")
  else
    local entitlement = tonumber(quota.entitlement) or 0
    local used = tonumber(quota.used) or 0
    if entitlement > 0 then
      parts[#parts + 1] = money.format_int(used) .. "/" .. money.format_int(entitlement)
    elseif used > 0 then
      parts[#parts + 1] = money.format_int(used)
    end
    local remaining = tonumber(quota.percent_remaining)
    if remaining then
      parts[#parts + 1] = string.format("%d%% %s", math.floor(remaining + 0.5), noctalia.tr("panel.remaining"))
    end
  end
  local seconds = time.reset_seconds(quota.reset_at)
  if seconds then
    parts[#parts + 1] = "↻ " .. time.format_duration(seconds)
  end
  return "GitHub Copilot: " .. table.concat(parts, " · ")
end

local function apply_tooltip()
  local lines = { "Agent Usage" }
  lines[#lines + 1] = go_line()
  local cp = cp_line()
  if cp then lines[#lines + 1] = cp end

  local go_error = noctalia.state.get("go.error")
  if type(go_error) == "string" and go_error ~= "" then
    lines[#lines + 1] = "OpenCode Go: " .. go_error
  end
  local cp_error = noctalia.state.get("cp.error")
  if type(cp_error) == "string" and cp_error ~= "" then
    lines[#lines + 1] = "GitHub Copilot: " .. cp_error
  end

  local text = table.concat(lines, "\n")
  if text == last_tooltip then return end
  last_tooltip = text
  barWidget.setTooltip(lines)
end

apply_glyph()
apply_tooltip()
noctalia.setUpdateInterval(5000)

function update()
  apply_tooltip()
end

function onClick()
  noctalia.togglePanel("msbos/agent-usage:panel")
end

noctalia.state.watch("go.usage", apply_tooltip)
noctalia.state.watch("go.credits", apply_tooltip)
noctalia.state.watch("go.error", apply_tooltip)
noctalia.state.watch("cp.quota", apply_tooltip)
noctalia.state.watch("cp.error", apply_tooltip)
