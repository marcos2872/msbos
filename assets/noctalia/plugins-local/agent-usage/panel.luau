--!nonstrict
-- Painel do Agent Usage: cotas por provider, com abas no topo.
--
-- Aba única (só o OpenCode Go configurado) mantém o visual antigo, sem a
-- linha de abas. O GitHub Copilot aparece quando há credencial dele.

local time = require("./lib/time.luau")
local money = require("./lib/money.luau")
local frame = require("./lib/frame.luau")

local WINDOWS = {
  { key = "rolling", label = "window.rolling" },
  { key = "weekly", label = "window.weekly" },
  { key = "monthly", label = "window.monthly" },
}

local TABS = {
  {
    key = "go",
    title = "tab.go",
    link = "https://opencode.ai/go",
    link_label = "panel.dashboard",
  },
  {
    key = "cp",
    title = "tab.copilot",
    link = "https://github.com/settings/copilot/features",
    link_label = "panel.billing",
  },
}

local is_open = false
local active = "go"
local render

-- ── helpers ─────────────────────────────────────────────────────────────────

local function tr(key, args)
  return noctalia.tr(key, args)
end

local function state_error(key)
  local value = noctalia.state.get(key .. ".error")
  return type(value) == "string" and value or ""
end

local function state_busy(key)
  return noctalia.state.get(key .. ".busy") == true
end

local function state_updated(key)
  return tonumber(noctalia.state.get(key .. ".updated_at")) or 0
end

local function interval_ms(key)
  local v = tonumber(noctalia.getConfig("refresh")) or 300
  if v < 60 then v = 60 end
  if v > 900 then v = 900 end
  if key == "cp" and v < 600 then v = 600 end
  return v * 1000
end

local function trigger_refresh(key)
  if key then
    noctalia.runAsync({ "noctalia", "msg", "plugin", "msbos/agent-usage:poll", "all", "provider", key })
  else
    noctalia.runAsync({ "noctalia", "msg", "plugin", "msbos/agent-usage:poll", "all", "refresh" })
  end
end

local function visible_tabs()
  local out = {}
  for _, tab in ipairs(TABS) do
    local configured = noctalia.state.get(tab.key .. ".configured") == true
    if configured or state_updated(tab.key) > 0 or state_error(tab.key) ~= "" then
      out[#out + 1] = tab
    end
  end
  return out
end

local function role_for(percent)
  local value = tonumber(percent)
  if not value then return "primary" end
  if value >= 100 then return "error" end
  if value >= 80 then return "tertiary" end
  return "primary"
end

local function push_all(target, items)
  for _, item in ipairs(items) do
    target[#target + 1] = item
  end
end

local function capitalize(value)
  if type(value) ~= "string" or value == "" then return value end
  return value:gsub("^%l", string.upper)
end

-- ── status por provider ─────────────────────────────────────────────────────

local function go_status()
  local usage = noctalia.state.get("go.usage")
  local worst = 0
  local limited = false
  for _, window in ipairs(WINDOWS) do
    local data = type(usage) == "table" and usage[window.key] or nil
    local percent = type(data) == "table" and tonumber(data.percent) or nil
    if percent then worst = math.max(worst, percent) end
    if type(data) == "table" and (data.status == "rate-limited" or (percent and percent >= 100)) then
      limited = true
    end
  end
  return worst, limited
end

local function cp_status()
  local quota = noctalia.state.get("cp.quota")
  if type(quota) ~= "table" then return 0, false end
  local percent = tonumber(quota.percent_used) or 0
  return percent, percent >= 100
end

local function provider_status(key)
  local worst, limited = 0, false
  if key == "go" then
    worst, limited = go_status()
  else
    worst, limited = cp_status()
  end

  local err = state_error(key)
  if err ~= "" then
    return tr("status.error"), "error"
  end
  if state_busy(key) and worst == 0 then
    return "…", "on_surface_variant"
  end
  if limited then
    return tr("status.limited"), "error"
  end
  if worst >= 80 then
    return tr("status.warn"), "tertiary"
  end
  return tr("status.ok"), "primary"
end

-- ── UI ──────────────────────────────────────────────────────────────────────

local function tabs_row(tabs)
  local children = {}
  for _, tab in ipairs(tabs) do
    local selected = tab.key == active
    children[#children + 1] = ui.button({
      key = "tab-" .. tab.key,
      text = tr(tab.title),
      variant = selected and "primary" or "ghost",
      selected = selected,
      onClick = function()
        active = tab.key
        noctalia.state.set("active_tab", tab.key)
        if state_updated(tab.key) == 0
          or (noctalia.nowMs() - state_updated(tab.key)) >= interval_ms(tab.key) then
          trigger_refresh(tab.key)
        end
        render()
      end,
    })
  end
  return ui.row({ key = "tabs", gap = 6, align = "center" }, children)
end

local function header(tab)
  local text, role = provider_status(tab.key)
  return ui.row({ gap = 12, justify = "space_between", align = "center", key = "header" }, {
    ui.label({
      text = tr(tab.title),
      fontSize = 16,
      fontWeight = "bold",
      color = frame.mode() == "theme" and nil or frame.text(),
    }),
    ui.row({
      key = "status-pill",
      gap = 5,
      align = "center",
      paddingH = 8,
      paddingV = 2,
      radius = 10,
      fill = role .. "/0.14",
    }, {
      ui.box({ width = 6, height = 6, radius = 3, fill = role }),
      ui.label({ text = text, fontSize = 11, color = frame.text() }),
    }),
  })
end

-- ── aba OpenCode Go ─────────────────────────────────────────────────────────

local function go_window_block(window)
  local usage = noctalia.state.get("go.usage")
  local data = type(usage) == "table" and usage[window.key] or nil
  local percent = type(data) == "table" and tonumber(data.percent) or nil
  local pct = percent and math.max(0, math.min(100, percent)) or nil

  local value = pct
    and string.format("%d%% %s", math.floor(pct + 0.5), tr("panel.used"))
    or "—"

  local reset
  if type(data) ~= "table" then
    reset = "—"
  elseif data.status == "rate-limited" then
    reset = tr("panel.limit_reached")
  else
    reset = tr("panel.reset_in", {
      time = time.format_duration(time.reset_seconds(data.resetsAt)),
    })
  end

  return ui.column({ key = "block-" .. window.key, gap = 6 }, {
    ui.row({ gap = 6, justify = "space_between", align = "center" }, {
      ui.label({ text = tr(window.label), fontSize = 13, color = frame.text() }),
      ui.label({ text = value, fontSize = 12, color = frame.text() }),
    }),
    ui.progress({
      progress = (pct or 0) / 100,
      fill = role_for(pct),
      track = "surface_container",
      height = 6,
      radius = 3,
    }),
    ui.label({ text = reset, fontSize = 11, color = frame.muted() }),
  })
end

local function go_view()
  local children = {}

  local credits = noctalia.state.get("go.credits")
  if type(credits) == "table" and tonumber(credits.available) then
    children[#children + 1] = ui.row({
      key = "credits",
      gap = 6,
      justify = "space_between",
      align = "center",
    }, {
      ui.label({ text = tr("panel.credits"), fontSize = 12, color = frame.muted() }),
      ui.label({
        text = money.format_microcents(credits.available),
        fontSize = 13,
        color = frame.text(),
        fontWeight = "bold",
      }),
    })
  end

  for _, window in ipairs(WINDOWS) do
    children[#children + 1] = go_window_block(window)
  end
  return children
end

-- ── aba GitHub Copilot ──────────────────────────────────────────────────────

local function cp_reset_text(quota)
  local date = time.format_date(quota.reset_at)
  local seconds = time.reset_seconds(quota.reset_at)
  if seconds then
    local text = tr("panel.reset_in", { time = time.format_duration(seconds) })
    if date then return text .. " · " .. date end
    return text
  end
  if date then return tr("panel.reset_at") .. " " .. date end
  return "—"
end

local function cp_remaining_text(quota)
  local parts = {}
  local percent = tonumber(quota.percent_remaining)
  if percent then
    parts[#parts + 1] = string.format("%.1f%% %s", percent, tr("panel.remaining"))
  end
  local remaining = tonumber(quota.remaining)
  if remaining and remaining > 0 then
    parts[#parts + 1] = "≈ " .. money.format_credits(remaining)
  end
  if #parts == 0 then return "—" end
  return table.concat(parts, " · ")
end

local function copilot_view()
  local quota = noctalia.state.get("cp.quota")
  if type(quota) ~= "table" then
    return {
      ui.label({ text = "—", fontSize = 12, color = frame.muted() }),
    }
  end

  local children = {}

  local plan_bits = {}
  if quota.plan then plan_bits[#plan_bits + 1] = capitalize(quota.plan) end
  if quota.org then plan_bits[#plan_bits + 1] = quota.org end
  if #plan_bits > 0 then
    children[#children + 1] = ui.row({
      key = "cp-plan",
      gap = 6,
      justify = "space_between",
      align = "center",
    }, {
      ui.label({ text = tr("panel.plan"), fontSize = 12, color = frame.muted() }),
      ui.label({ text = table.concat(plan_bits, " · "), fontSize = 12, color = frame.text() }),
    })
  end

  local entitlement = tonumber(quota.entitlement) or 0
  local used = tonumber(quota.used) or 0
  local used_text
  if quota.unlimited then
    used_text = tr("panel.unlimited")
  elseif entitlement > 0 then
    used_text = money.format_int(used) .. " / " .. money.format_int(entitlement)
  else
    used_text = money.format_int(used)
  end

  children[#children + 1] = ui.column({ key = "cp-quota", gap = 6 }, {
    ui.row({ gap = 6, justify = "space_between", align = "center" }, {
      ui.label({ text = tr("panel.used_of"), fontSize = 13, color = frame.text() }),
      ui.label({ text = used_text, fontSize = 12, color = frame.text() }),
    }),
    ui.progress({
      progress = (tonumber(quota.percent_used) or 0) / 100,
      fill = role_for(quota.percent_used),
      track = "surface_container",
      height = 6,
      radius = 3,
    }),
    ui.row({ gap = 6, justify = "space_between", align = "center" }, {
      ui.label({ text = cp_remaining_text(quota), fontSize = 11, color = frame.muted() }),
      ui.label({ text = cp_reset_text(quota), fontSize = 11, color = frame.muted() }),
    }),
  })

  if quota.overage then
    children[#children + 1] = ui.label({
      text = tr("panel.overage"),
      fontSize = 11,
      color = frame.muted(),
      maxLines = 2,
    })
  end

  return children
end

-- ── rodapé ──────────────────────────────────────────────────────────────────

local function updated_line(key)
  local updated_at = state_updated(key)
  local text
  if updated_at > 0 then
    text = tr("panel.updated", {
      age = time.format_age((noctalia.nowMs() - updated_at) / 1000),
    })
  else
    text = tr("panel.never")
  end
  local source = noctalia.state.get(key .. ".source")
  if type(source) == "string" and source ~= "" then
    text = text .. " · " .. tr("panel.source", { source = source })
  end
  return ui.label({ text = text, fontSize = 11, color = frame.muted() })
end

local function footer(tab)
  return ui.row({ gap = 6, align = "center", key = "footer" }, {
    ui.button({
      text = tr("panel.refresh"),
      variant = "secondary",
      enabled = not state_busy(tab.key),
      onClick = function() trigger_refresh() end,
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      text = tr(tab.link_label),
      variant = "primary",
      onClick = function()
        noctalia.runAsync({ "xdg-open", tab.link })
      end,
    }),
  })
end

-- ── frame (fundo preto como o msbos-ai-chat) ─────────────────────────────────

local function framed(content)
  if frame.mode() == "theme" then
    return ui.column({ flexGrow = 1, gap = 0, align = "stretch" }, { content })
  end
  -- Padding negativo alcança a borda/raio do painel; o alfa preserva a
  -- transparência e o blur.
  return ui.column({
    flexGrow = 1,
    gap = 0,
    align = "stretch",
    padding = -frame.INSET,
  }, {
    ui.column({
      flexGrow = 1,
      gap = 0,
      align = "stretch",
      fill = frame.fill(),
      radius = 12,
      padding = frame.INSET,
    }, { content }),
  })
end

-- ── render ──────────────────────────────────────────────────────────────────

render = function()
  if not is_open then return end

  local tabs = visible_tabs()
  if #tabs == 0 then tabs = { TABS[1] } end

  local current = tabs[1]
  for _, tab in ipairs(tabs) do
    if tab.key == active then current = tab end
  end
  active = current.key

  local children = {}
  if #tabs > 1 then
    children[#children + 1] = tabs_row(tabs)
  end
  children[#children + 1] = header(current)

  if current.key == "go" then
    push_all(children, go_view())
  else
    push_all(children, copilot_view())
  end

  local err = state_error(current.key)
  if err ~= "" then
    children[#children + 1] = ui.label({
      text = err,
      fontSize = 11,
      color = "error",
      maxLines = 3,
    })
  end

  children[#children + 1] = ui.spacer({ flexGrow = 1 })
  children[#children + 1] = updated_line(current.key)
  children[#children + 1] = footer(current)

  panel.render(framed(ui.column({ gap = 12, padding = 16, flexGrow = 1 }, children)))
end

-- ── ciclo de vida ───────────────────────────────────────────────────────────

panel.setWantsSecondTicks(true)

function onOpen(_context)
  is_open = true

  local stored = noctalia.state.get("active_tab")
  if type(stored) == "string" and stored ~= "" then
    active = stored
  end

  if state_updated(active) == 0
    or (noctalia.nowMs() - state_updated(active)) >= interval_ms(active) then
    trigger_refresh(active)
  end

  render()
end

function onClose()
  is_open = false
end

function update()
  render()
end

function onConfigChanged()
  render()
end

noctalia.state.watch("go.usage", render)
noctalia.state.watch("go.credits", render)
noctalia.state.watch("go.error", render)
noctalia.state.watch("go.busy", render)
noctalia.state.watch("go.updated_at", render)
noctalia.state.watch("cp.quota", render)
noctalia.state.watch("cp.error", render)
noctalia.state.watch("cp.busy", render)
noctalia.state.watch("cp.updated_at", render)
