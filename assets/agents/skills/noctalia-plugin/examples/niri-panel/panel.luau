--!nonstrict
-- Panel: workspace list with niri actions.

local snapshot = noctalia.state.get("niri_snapshot") or {}
local isOpen = false
local render

local function requestRefresh()
  noctalia.runAsync(
    { "noctalia", "msg", "plugin", "me/niri-panel:niri", "all", "refresh" },
    function(result)
      if result.exitCode ~= 0 then
        noctalia.notifyError("niri", result.stderr)
      end
    end,
    5000
  )
end

local function focusWorkspace(workspace)
  if workspace == nil or workspace.idx == nil then
    return
  end
  noctalia.runAsync(
    { "niri", "msg", "action", "focus-workspace", tostring(workspace.idx) },
    function(result)
      if result.exitCode ~= 0 then
        noctalia.notifyError("niri", result.stderr)
      end
    end,
    5000
  )
end

local function workspaceRow(workspace)
  local active = workspace.is_focused == true
  return ui.row({
    key = "ws-" .. tostring(workspace.id),
    gap = 8,
    align = "center",
    paddingH = 10,
    paddingV = 8,
    radius = 10,
    fill = active and "primary" or "surface_variant/0.35",
    onClick = function()
      focusWorkspace(workspace)
    end,
  }, {
    ui.label({
      text = "Workspace " .. tostring(workspace.idx),
      color = active and "on_primary" or "on_surface",
      fontWeight = "bold",
      flexGrow = 1,
    }),
    ui.label({
      text = tostring(workspace.output or ""),
      fontSize = 10,
      color = active and "on_primary/0.8" or "on_surface_variant",
    }),
  })
end

render = function()
  local rows = {}
  for _, workspace in ipairs(snapshot.workspaces or {}) do
    table.insert(rows, workspaceRow(workspace))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "Nenhum workspace.", color = "on_surface_variant" }))
  end

  local output = snapshot.output
  local outputText = output and (tostring(output.name) .. " · " .. tostring(output.make or "") .. " " .. tostring(output.model or "")) or "niri indisponível"

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "layout-dashboard", size = 18, color = "primary" }),
      ui.column({ gap = 0, flexGrow = 1 }, {
        ui.label({ text = "Niri", fontSize = 16, fontWeight = "bold" }),
        ui.label({ text = outputText, fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
      }),
      ui.button({ glyph = "close", variant = "ghost", tooltip = "Fechar", onClick = function() panel.close() end }),
    }),

    snapshot.error and ui.label({ text = snapshot.error, color = "error", fontSize = 10 }) or ui.separator({}),

    ui.scroll({ flexGrow = 1, gap = 6 }, rows),

    ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Atualizar", variant = "secondary", glyph = "refresh", fontSize = 10, onClick = requestRefresh }),
      ui.button({ text = "Configurações", variant = "ghost", glyph = "settings", fontSize = 10, onClick = function() noctalia.openSettings() end }),
    }),
  }))
end

noctalia.state.watch("niri_snapshot", function(value)
  if type(value) == "table" then
    snapshot = value
    if isOpen then
      render()
    end
  end
end)

function onOpen(_context)
  isOpen = true
  render()
end

function onClose()
  isOpen = false
end
