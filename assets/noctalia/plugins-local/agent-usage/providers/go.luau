--!nonstrict
-- OpenCode Go: cotas do plano (janela de 5 horas, semanal e mensal) e os
-- créditos pré-pagos do console.
--
-- A credencial é relida a cada poll (nunca fica em memória nem no log):
--   1. OPENCODE_API_KEY (env)
--   2. opencode.db: credential integration_id='opencode' (OAuth, campo "access")
--      ou 'opencode-go' (campo "key")
--   3. ~/.local/share/opencode/auth.json

local db = require("../lib/opencode-db.luau")

local USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
local BILLING_URL = "https://opencode.ai/console/api/billing/status"

local M = { id = "go" }

local saw_expired = false
local credits = nil
local last_auth_source = nil

function M.interval_ms()
  local v = tonumber(noctalia.getConfig("refresh")) or 300
  if v < 60 then v = 60 end
  if v > 900 then v = 900 end
  return v * 1000
end

-- ── credenciais ─────────────────────────────────────────────────────────────

local SQL_ACCESS = "SELECT json_extract(value,'$.access') AS access, "
  .. "json_extract(value,'$.expires') AS expires "
  .. "FROM credential WHERE integration_id='opencode' "
  .. "ORDER BY active DESC LIMIT 1;"

local SQL_KEY = "SELECT json_extract(value,'$.key') AS key "
  .. "FROM credential WHERE integration_id='opencode-go' "
  .. "ORDER BY active DESC LIMIT 1;"

local function try_auth_json()
  local path = noctalia.expandPath("~/.local/share/opencode/auth.json")
  if not noctalia.fileExists(path) then return nil end
  local content = noctalia.readFile(path)
  if type(content) ~= "string" or content == "" then return nil end
  local ok, data = pcall(noctalia.json.decode, content)
  if not ok or type(data) ~= "table" then return nil end
  for _, id in ipairs({ "opencode-go", "opencode" }) do
    local node = data[id]
    if type(node) == "table" and type(node.key) == "string" and node.key ~= "" then
      return node.key, "auth.json"
    end
  end
  return nil
end

local function resolve_key(cb)
  local env = noctalia.getenv("OPENCODE_API_KEY")
  if type(env) == "string" and env ~= "" then
    cb(env, "env", nil)
    return
  end

  saw_expired = false
  db.first(SQL_ACCESS, function(row)
    local token = type(row) == "table" and row.access or nil
    if type(token) ~= "string" or token == "" then return nil end
    local expires = type(row) == "table" and tonumber(row.expires) or nil
    if not expires or expires > noctalia.nowMs() then
      return token
    end
    saw_expired = true
    return nil
  end, function(token)
    if token then
      cb(token, "opencode.db", nil)
      return
    end

    -- API key dedicada do plano Go.
    db.first(SQL_KEY, function(row)
      local key = type(row) == "table" and row.key or nil
      if type(key) == "string" and key ~= "" then return key end
      return nil
    end, function(key)
      if key then
        cb(key, "opencode.db", nil)
        return
      end
      local legacy, src = try_auth_json()
      if legacy then
        cb(legacy, src, nil)
        return
      end
      cb(nil, nil, saw_expired and "error.expired" or "error.no_key")
    end)
  end)
end

-- ── créditos do billing ─────────────────────────────────────────────────────

-- "Available credits" do console (prepaid/pay-as-you-go), em microcents.
-- Best-effort: o painel funciona sem eles.
local function fetch_credits(key, done)
  local started = noctalia.http({
    url = BILLING_URL,
    method = "GET",
    headers = {
      "Authorization: Bearer " .. key,
      "Accept: application/json",
    },
  }, function(res)
    if type(res) ~= "table" or tonumber(res.status) ~= 200 then
      done(nil)
      return
    end
    local ok, data = pcall(noctalia.json.decode, type(res.body) == "string" and res.body or "")
    if not ok or type(data) ~= "table" then
      done(nil)
      return
    end
    local available = tonumber(data.availableMicroCents or data.balanceMicroCents)
    if not available then
      done(nil)
      return
    end
    done({
      available = available,
      limit = tonumber(data.creditLimitMicroCents),
      mode = type(data.mode) == "string" and data.mode or "",
      billing_mode = type(data.billingMode) == "string" and data.billingMode or "",
    })
  end)
  if not started then done(nil) end
end

-- ── poll ────────────────────────────────────────────────────────────────────

-- cb(data, error_key, error_args, source); `data` = { usage = ..., credits = ... }.
-- Pode ser chamado duas vezes: uma com a cota e outra quando os créditos chegam.
function M.fetch(cb)
  resolve_key(function(key, src, err)
    if not key then
      cb(nil, err or "error.no_key")
      return
    end

    if src ~= last_auth_source then
      noctalia.log("go: auth via " .. tostring(src))
      last_auth_source = src
    end

    local usage = nil
    local responded = false

    local function emit(error_key, error_args)
      cb({ usage = usage, credits = credits }, error_key, error_args, src)
    end

    local started = noctalia.http({
      url = USAGE_URL,
      method = "GET",
      headers = {
        "Authorization: Bearer " .. key,
        "Accept: application/json",
      },
    }, function(res)
      responded = true
      if type(res) ~= "table" then
        emit("error.offline")
        return
      end

      local status = tonumber(res.status) or 0
      if status == 401 then
        emit("error.unauthorized")
        return
      elseif status == 403 then
        emit("error.no_plan")
        return
      elseif status == 0 then
        emit("error.offline")
        return
      elseif status < 200 or status >= 300 then
        emit("error.http", { code = tostring(status) })
        return
      end

      local ok, data = pcall(noctalia.json.decode, type(res.body) == "string" and res.body or "")
      local parsed = ok and type(data) == "table" and data.usage or nil
      if type(parsed) ~= "table"
        or (type(parsed.rolling) ~= "table" and type(parsed.weekly) ~= "table" and type(parsed.monthly) ~= "table") then
        emit("error.no_usage")
        return
      end

      usage = parsed
      saw_expired = false
      emit(nil)
    end)

    if not started then
      emit("error.offline")
      return
    end

    fetch_credits(key, function(value)
      if value == nil then return end
      credits = value
      -- Se a cota já respondeu, publica de novo para mostrar os créditos.
      if responded and usage then emit(nil) end
    end)
  end)
end

return M
