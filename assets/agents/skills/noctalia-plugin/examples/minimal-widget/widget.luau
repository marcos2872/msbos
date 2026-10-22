--!nonstrict
-- Minimal declarative bar widget: glyph + label + click counter.
-- Settings are declared in plugin.toml and read with noctalia.getConfig.

local label = noctalia.getConfig("label") or "Hello, niri!"
local glyph = noctalia.getConfig("glyph") or "puzzle"
local clicks = 0

local function render()
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, {
    ui.glyph({ name = glyph, size = 16, color = "primary" }),
    ui.label({ text = label, maxLines = 1 }),
    ui.label({
      text = tostring(clicks),
      fontSize = 10,
      color = "on_surface_variant",
    }),
  }))
end

render()

function update()
  noctalia.setUpdateInterval(5000)
  render()
end

function onClick()
  clicks += 1
  render()
end

function onIpc(event, payload)
  if event == "set" then
    label = payload or label
    render()
  elseif event == "reset" then
    clicks = 0
    render()
  end
end
