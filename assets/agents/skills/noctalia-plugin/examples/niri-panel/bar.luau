--!nonstrict
-- Bar widget: focused output + focused workspace.

local snapshot = noctalia.state.get("niri_snapshot") or {}
local glyph = noctalia.getConfig("glyph") or "layout-dashboard"

local function render()
  local output = snapshot.output and snapshot.output.name or "niri"
  local workspace = snapshot.workspace and tostring(snapshot.workspace.idx) or "?"
  local color = snapshot.error and "error" or "on_surface"
  local container = barWidget.isVertical() and ui.column or ui.row

  barWidget.render(container({ gap = 6, align = "center" }, {
    ui.glyph({ name = glyph, size = 16, color = snapshot.error and "error" or "primary" }),
    ui.label({ text = output, color = color, maxLines = 1 }),
    ui.label({ text = "ws " .. workspace, fontSize = 10, color = "on_surface_variant" }),
  }))
end

noctalia.state.watch("niri_snapshot", function(value)
  if type(value) == "table" then
    snapshot = value
    render()
  end
end)

render()

function update()
  noctalia.setUpdateInterval(5000)
  render()
end

function onClick()
  noctalia.togglePanel("me/niri-panel:panel")
end
