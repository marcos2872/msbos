--!nonstrict
-- Reads the effective palette and shell values, then publishes them for the
-- widget and the panel. Nothing here is hardcoded: roles come from the theme.

local ROLES = {
  "primary", "on_primary", "secondary", "on_secondary",
  "tertiary", "on_tertiary", "error", "on_error",
  "surface", "on_surface", "surface_variant", "on_surface_variant",
  "outline", "shadow", "hover", "on_hover",
}

local function readColors()
  local colors = {}
  for _, role in ipairs(ROLES) do
    colors[role] = noctalia.getColor(role)
  end
  return colors
end

-- focusedOutputName() can return nil; outputs() has the focused flag.
local function focusedOutput()
  local name = noctalia.focusedOutputName()
  if type(name) == "string" and name ~= "" then
    return name
  end
  for _, output in ipairs(noctalia.outputs() or {}) do
    if output.focused then
      return output.name
    end
  end
  return nil
end

local function publish()
  noctalia.state.set("theme_probe", {
    colors = readColors(),
    spacing = noctalia.getSetting("bar.default.widget_spacing"),
    thickness = noctalia.getSetting("bar.default.thickness"),
    padding = noctalia.getSetting("bar.default.padding"),
    family = noctalia.getSetting("bar.default.font_family"),
    radius = noctalia.getSetting("bar.default.radius"),
    mode = noctalia.getSetting("theme.mode"),
    dark = noctalia.isDarkMode(),
    output = focusedOutput(),
  })
end

function update()
  publish()
end

function onIpc(event)
  if event == "refresh" then
    publish()
  end
end

publish()
