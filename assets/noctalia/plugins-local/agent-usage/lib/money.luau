--!nonstrict
-- Formatação de dinheiro e de contagens de créditos.

local M = {}

-- Microcents (1e-6 de centavo) → "US$ 3.65".
function M.format_microcents(value)
  return string.format("US$ %.2f", (tonumber(value) or 0) / 1e8)
end

-- Créditos do Copilot (1 crédito = US$ 0,01) → "US$ 40.01".
function M.format_credits(value)
  return string.format("US$ %.2f", (tonumber(value) or 0) / 100)
end

-- Inteiro com separador de milhar: 4001 → "4.001".
function M.format_int(value)
  local n = tonumber(value)
  if not n then return "—" end
  local text = string.format("%d", math.floor(n + 0.5))
  local sign = ""
  if text:sub(1, 1) == "-" then
    sign = "-"
    text = text:sub(2)
  end
  while true do
    local replaced, count = text:gsub("^(%d+)(%d%d%d)", "%1.%2")
    text = replaced
    if count == 0 then break end
  end
  return sign .. text
end

return M
