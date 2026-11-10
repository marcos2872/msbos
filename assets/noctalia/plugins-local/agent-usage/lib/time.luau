--!nonstrict
-- Tempo: ISO-8601 (UTC) → epoch e formatações de duração/idade/data.

local M = {}

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

-- A API devolve ISO-8601 em UTC (ex.: 2026-11-08T16:09:51.000Z).
function M.parse_iso(value)
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

-- Segundos até o instante ISO (nunca negativo; nil quando não parseia).
function M.reset_seconds(value)
  local t = M.parse_iso(value)
  if not t then return nil end
  return math.max(0, t - os.time())
end

function M.format_duration(seconds)
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

function M.format_age(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then return "—" end
  if seconds < 60 then return math.floor(seconds) .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  return math.floor(seconds / 3600) .. "h"
end

-- "2026-12-01T00:00:00.000Z" → "01/12/2026" (data civil do próprio ISO, sem
-- converter fuso: o reset é anunciado em UTC).
function M.format_date(value)
  if type(value) ~= "string" then return nil end
  local y, mo, d = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then return nil end
  return d .. "/" .. mo .. "/" .. y
end

return M
