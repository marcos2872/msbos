--!nonstrict
-- Painel do OpenCode Go: cotas de 5 horas, semanal e mensal.

local WINDOWS = {
  { key = "rolling", label = "window.rolling" },
  { key = "weekly", label = "window.weekly" },
  { key = "monthly", label = "window.monthly" },
}

local DASHBOARD_URL = "https://opencode.ai/go"
local is_open = false

-- ── tempo ───────────────────────────────────────────────────────────────────

-- A API devolve ISO-8601 em UTC (ex.: 2026-11-08T16:09:51.000Z).
-- Aritmética de calendário (days-from-civil) em vez de os.time({...}), que
-- interpreta a tabela como hora local e deslocaria toda a contagem regressiva.
local function days_from_civil(y, m, d)
  y = y - (m <= 2 and 1 or 0)
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

local function parse_iso(value)
  if type(value) ~= "string" then return nil end
  local y, mo, d, h, mi, se, rest = value:match(
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$"
  )
  if not y then return nil end
  local epoch = days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
    + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se)
  local sign, oh, om = rest:match("^([%+%-])(%d%d):(%d%d)$")
  if sign then
    local offset = tonumber(oh) * 3600 + tonumber(om) * 60
    epoch = epoch + (sign == "-" and offset or -offset)
  end
  return epoch
end

local function reset_seconds(resets_at)
  local t = parse_iso(resets_at)
  if not t then return nil end
  return math.max(0, t - os.time())
end

local function format_duration(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then return "—" end
  local s = math.floor(seconds + 0.5)
  local m = math.floor(s / 60)
  local h = math.floor(m / 60)
  local d = math.floor(h / 24)
  if d >= 1 then
    local rh = h % 24
    return rh > 0 and (d .. "d" .. rh .. "h") or (d .. "d")
  end
  if h >= 1 then
    local rm = m % 60
    return rm > 0 and (h .. "h" .. rm .. "m") or (h .. "h")
  end
  if m >= 1 then return m .. "m" end
  return s .. "s"
end

local function format_age(seconds)
  if seconds < 60 then return math.floor(seconds) .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  return math.floor(seconds / 3600) .. "h"
end

-- Microcents (1e-6 de centavo) → "US$ 3.65".
local function format_money(microcents)
  return string.format("US$ %.2f", (tonumber(microcents) or 0) / 1e8)
end

-- ── dados ───────────────────────────────────────────────────────────────────

local function status_of(usage)
  local worst = 0
  local limited = false
  for _, w in ipairs(WINDOWS) do
    local data = type(usage) == "table" and usage[w.key] or nil
    local percent = type(data) == "table" and tonumber(data.percent) or nil
    if percent then worst = math.max(worst, percent) end
    if type(data) == "table" and (data.status == "rate-limited" or (percent and percent >= 100)) then
      limited = true
    end
  end
  return worst, limited
end

local function trigger_refresh()
  noctalia.runAsync({ "noctalia", "msg", "plugin", "msbos/opencode-go:poll", "all", "refresh" })
end

-- ── UI ──────────────────────────────────────────────────────────────────────

local render

local function percent_block(window, usage)
  local data = type(usage) == "table" and usage[window.key] or nil
  local percent = type(data) == "table" and tonumber(data.percent) or nil
  local pct = percent and math.max(0, math.min(100, percent)) or nil

  local role = "primary"
  if pct and pct >= 100 then
    role = "error"
  elseif pct and pct >= 80 then
    role = "tertiary"
  end

  local value = pct
    and string.format("%d%% %s", math.floor(pct + 0.5), noctalia.tr("panel.used"))
    or "—"

  local reset
  if type(data) ~= "table" then
    reset = "—"
  elseif data.status == "rate-limited" then
    reset = noctalia.tr("panel.limit_reached")
  else
    reset = noctalia.tr("panel.reset_in", {
      time = format_duration(reset_seconds(data.resetsAt)),
    })
  end

  return ui.column({ key = "block-" .. window.key, gap = 6 }, {
    ui.row({ gap = 6, justify = "space_between", align = "center" }, {
      ui.label({ text = noctalia.tr(window.label), fontSize = 13 }),
      ui.label({ text = value, fontSize = 12, color = "on_surface" }),
    }),
    ui.progress({
      progress = (pct or 0) / 100,
      fill = role,
      track = "surface_container",
      height = 6,
      radius = 3,
    }),
    ui.label({ text = reset, fontSize = 11, color = "on_surface_variant" }),
  })
end

local function footer(busy)
  return ui.row({ gap = 6, align = "center", key = "footer" }, {
    ui.button({
      text = noctalia.tr("panel.refresh"),
      variant = "secondary",
      enabled = not busy,
      onClick = function() trigger_refresh() end,
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      text = noctalia.tr("panel.dashboard"),
      variant = "primary",
      onClick = function()
        noctalia.runAsync({ "xdg-open", DASHBOARD_URL })
      end,
    }),
  })
end

render = function()
  if not is_open then return end

  local usage = noctalia.state.get("usage")
  local busy = noctalia.state.get("busy") == true
  local err = noctalia.state.get("error")
  local updated_at = tonumber(noctalia.state.get("updated_at")) or 0
  local source = noctalia.state.get("source")
  local err_text = type(err) == "string" and err or ""

  local worst, limited = status_of(usage)
  local status_text, status_role
  if err_text ~= "" then
    status_text, status_role = noctalia.tr("status.error"), "error"
  elseif busy and type(usage) ~= "table" then
    status_text, status_role = "…", "on_surface_variant"
  elseif limited then
    status_text, status_role = noctalia.tr("status.limited"), "error"
  elseif worst >= 80 then
    status_text, status_role = noctalia.tr("status.warn"), "tertiary"
  else
    status_text, status_role = noctalia.tr("status.ok"), "primary"
  end

  local children = {
    ui.row({ gap = 12, justify = "space_between", align = "center", key = "header" }, {
      ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "bold" }),
      ui.row({
        key = "status-pill",
        gap = 5,
        align = "center",
        paddingH = 8,
        paddingV = 2,
        radius = 10,
        fill = status_role .. "/0.14",
      }, {
        ui.box({ width = 6, height = 6, radius = 3, fill = status_role }),
        ui.label({ text = status_text, fontSize = 11, color = "on_surface" }),
      }),
    }),
  }

  local credits = noctalia.state.get("credits")
  if type(credits) == "table" and tonumber(credits.available) then
    children[#children + 1] = ui.row({
      key = "credits",
      gap = 6,
      justify = "space_between",
      align = "center",
    }, {
      ui.label({ text = noctalia.tr("panel.credits"), fontSize = 12, color = "on_surface_variant" }),
      ui.label({ text = format_money(credits.available), fontSize = 13, color = "on_surface", fontWeight = "bold" }),
    })
  end

  for _, window in ipairs(WINDOWS) do
    children[#children + 1] = percent_block(window, usage)
  end

  if err_text ~= "" then
    children[#children + 1] = ui.label({
      text = err_text,
      fontSize = 11,
      color = "error",
      maxLines = 3,
    })
  end

  children[#children + 1] = ui.spacer({ flexGrow = 1 })

  local updated_text
  if updated_at > 0 then
    updated_text = noctalia.tr("panel.updated", {
      age = format_age((noctalia.nowMs() - updated_at) / 1000),
    })
  else
    updated_text = noctalia.tr("panel.never")
  end
  if type(source) == "string" and source ~= "" then
    updated_text = updated_text .. " · " .. noctalia.tr("panel.source", { source = source })
  end
  children[#children + 1] = ui.label({
    text = updated_text,
    fontSize = 11,
    color = "on_surface_variant",
  })

  children[#children + 1] = footer(busy)

  panel.render(ui.column({ gap = 12, padding = 16, flexGrow = 1 }, children))
end

-- ── ciclo de vida ───────────────────────────────────────────────────────────

panel.setWantsSecondTicks(true)

function onOpen(_context)
  is_open = true

  local updated_at = tonumber(noctalia.state.get("updated_at")) or 0
  local interval = (tonumber(noctalia.getConfig("refresh")) or 300) * 1000
  if noctalia.nowMs() - updated_at >= interval then
    trigger_refresh()
  end

  render()
end

function onClose()
  is_open = false
end

function update()
  render()
end

noctalia.state.watch("usage", render)
noctalia.state.watch("credits", render)
noctalia.state.watch("error", render)
noctalia.state.watch("busy", render)
noctalia.state.watch("updated_at", render)
