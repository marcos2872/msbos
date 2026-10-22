--!nonstrict
-- Bar widget: one glyph in the accent role plus a short label.
-- Colors come from palette roles and the gap is the system default (6).

local snapshot = noctalia.state.get("theme_probe") or {}

local function render()
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, {
    ui.glyph({ name = "palette", size = 16, color = "primary" }),
    ui.label({ text = "theme", maxLines = 1 }),
    ui.label({
      text = tostring(snapshot.spacing or "?"),
      fontSize = 10,
      color = "on_surface_variant",
    }),
  }))
end

noctalia.state.watch("theme_probe", function(value)
  if type(value) == "table" then
    snapshot = value
    render()
  end
end)

render()

function update()
  noctalia.setUpdateInterval(10000)
  render()
end

function onClick()
  noctalia.togglePanel("me/theme-probe:panel")
end
