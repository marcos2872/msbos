--!nonstrict
-- Ícone do OpenCode Go na barra: só o logo (claro/escuro conforme o tema).

local WINDOWS = {
  { key = "rolling", label = "window.rolling" },
  { key = "weekly", label = "window.weekly" },
  { key = "monthly", label = "window.monthly" },
}

local dark_mode = nil

local function apply_logo(force)
  local dark = noctalia.isDarkMode() == true
  if not force and dark_mode == dark then return end
  dark_mode = dark

  -- Logo transparente: claro na barra escura, escuro na barra clara.
  local path = dark
    and "opencode-logo-transparent-light.svg"
    or "opencode-logo-transparent-dark.svg"
  if noctalia.fileExists(path) then
    barWidget.setImage(path, true, 13, 16)
  else
    barWidget.setGlyph("code")
  end
end

local function apply_tooltip()
  local usage = noctalia.state.get("usage")
  local parts = {}
  for _, w in ipairs(WINDOWS) do
    local window = type(usage) == "table" and usage[w.key] or nil
    local percent = type(window) == "table" and tonumber(window.percent) or nil
    parts[#parts + 1] = noctalia.tr(w.label) .. " "
      .. (percent and (math.floor(percent + 0.5) .. "%") or "—")
  end
  local err = noctalia.state.get("error")
  if type(err) == "string" and err ~= "" then
    parts[#parts + 1] = err
  end
  local credits = noctalia.state.get("credits")
  if type(credits) == "table" and tonumber(credits.available) then
    parts[#parts + 1] = noctalia.tr("panel.credits") .. " "
      .. string.format("US$ %.2f", credits.available / 1e8)
  end
  barWidget.setTooltip({ "OpenCode Go", table.concat(parts, " · ") })
end

apply_logo(true)
apply_tooltip()
noctalia.setUpdateInterval(5000)

function update()
  apply_logo(false)
end

function onClick()
  noctalia.togglePanel("msbos/opencode-go:panel")
end

noctalia.state.watch("usage", apply_tooltip)
noctalia.state.watch("credits", apply_tooltip)
noctalia.state.watch("error", apply_tooltip)
