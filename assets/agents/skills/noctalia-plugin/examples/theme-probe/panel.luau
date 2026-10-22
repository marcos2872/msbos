--!nonstrict
-- Panel: palette roles as swatches + hex, then the effective system values.
-- Layout uses the standard tokens: gap 12 between sections, 6 inside lists.

local ROLES = {
  "primary", "on_primary", "secondary", "on_secondary",
  "tertiary", "on_tertiary", "error", "on_error",
  "surface", "on_surface", "surface_variant", "on_surface_variant",
  "outline", "shadow", "hover", "on_hover",
}

local snapshot = noctalia.state.get("theme_probe") or {}
local render

local function valueRow(label, value)
  return ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = label, color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = tostring(value), maxLines = 1 }),
  })
end

local function colorRow(role, hex, showHex)
  local children = {
    -- swatch: the role itself, so it tracks the palette live
    ui.box({ fill = role, width = 16, height = 16, radius = 4, border = "outline", borderWidth = 1 }),
    ui.label({ text = role, flexGrow = 1 }),
  }
  if showHex then
    table.insert(children, ui.label({
      text = tostring(hex or "—"),
      fontSize = 10,
      color = "on_surface_variant",
    }))
  end
  return ui.row({ gap = 8, align = "center", key = role }, children)
end

local function colorColumn(roles, colors, showHex)
  local rows = {}
  for _, role in ipairs(roles) do
    table.insert(rows, colorRow(role, colors[role], showHex))
  end
  -- ui.scroll clips and scrolls instead of overlapping the sections below
  return ui.scroll({ gap = 6, flexGrow = 1 }, rows)
end

render = function()
  local colors = snapshot.colors or {}
  local showHex = noctalia.getConfig("show_hex") ~= false
  local half = math.ceil(#ROLES / 2)
  local left, right = {}, {}
  for index, role in ipairs(ROLES) do
    if index <= half then
      table.insert(left, role)
    else
      table.insert(right, role)
    end
  end

  local subtitle = tostring(snapshot.mode or "?")
  if snapshot.dark ~= nil and (snapshot.mode == "dark") ~= snapshot.dark then
    subtitle = subtitle .. " · shell " .. (snapshot.dark and "dark" or "light")
  end

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "palette", size = 18, color = "primary" }),
      ui.column({ gap = 0, flexGrow = 1 }, {
        ui.label({ text = "Theme probe", fontSize = 16, fontWeight = "bold" }),
        ui.label({
          text = subtitle,
          fontSize = 10,
          color = "on_surface_variant",
        }),
      }),
      ui.button({ glyph = "close", variant = "ghost", tooltip = "Fechar", onClick = function() panel.close() end }),
    }),

    ui.separator({}),

    ui.row({ gap = 12, flexGrow = 1 }, {
      colorColumn(left, colors, showHex),
      colorColumn(right, colors, showHex),
    }),

    ui.separator({}),

    ui.column({ gap = 6 }, {
      valueRow("widget_spacing", snapshot.spacing),
      valueRow("thickness", snapshot.thickness),
      valueRow("padding", snapshot.padding),
      valueRow("radius", snapshot.radius),
      valueRow("font_family", snapshot.family),
      valueRow("output", snapshot.output),
    }),

    ui.button({
      text = "Atualizar",
      variant = "secondary",
      glyph = "refresh",
      onClick = function()
        noctalia.runAsync(
          { "noctalia", "msg", "plugin", "me/theme-probe:probe", "all", "refresh" },
          function(result)
            if result.exitCode ~= 0 then
              noctalia.notifyError("theme-probe", result.stderr)
            end
          end,
          5000
        )
      end,
    }),
  }))
end

noctalia.state.watch("theme_probe", function(value)
  if type(value) == "table" then
    snapshot = value
    render()
  end
end)

function onOpen(_context)
  render()
end
