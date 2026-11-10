--!nonstrict
-- Fundo do painel: preto fixo com alfa (padrão do msbos-ai-chat) ou o tema.
--
-- O host desenha fundo/borda do painel; para o preto cobrir também a borda e o
-- raio, o frame usa padding negativo do tamanho do inset do host (mesma técnica
-- do plugin msbos-ai-chat). Com fundo fixo, as cores de texto saem do tema e
-- passam a tons claros — senão um tema claro deixaria texto escuro no preto.

local M = {}

-- Inset que o host aplica ao conteúdo do plugin: Style::panelPadding (14 px) ×
-- contentScale (1.0 por padrão).
M.INSET = 14

function M.mode()
  return noctalia.getConfig("background_mode") == "theme" and "theme" or "dark"
end

function M.opacity()
  local value = tonumber(noctalia.getConfig("background_opacity")) or 45
  if value < 0 then return 0 end
  if value > 100 then return 100 end
  return value
end

-- "#000000" + alfa (0–100 → 00–ff).
function M.fill()
  return string.format("#000000%02x", math.floor(M.opacity() * 255 / 100 + 0.5))
end

function M.text()
  return M.mode() == "theme" and "on_surface" or "#F5F7FA"
end

function M.muted()
  return M.mode() == "theme" and "on_surface_variant" or "#D2D7E1"
end

return M
