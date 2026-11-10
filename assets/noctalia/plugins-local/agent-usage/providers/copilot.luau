--!nonstrict
-- GitHub Copilot: cota de créditos do ciclo e data de reset.
--
-- IMPORTANTE: usa o endpoint INTERNO `copilot_internal/user` (o mesmo que os
-- clientes oficiais do Copilot consultam para mostrar "quota usage"). Não é a
-- API REST pública, não tem contrato de estabilidade e pode mudar sem aviso —
-- por isso o intervalo mínimo de 10 minutos e as mensagens de erro dedicadas.
--
-- Credencial: a mesma do OpenCode (`opencode auth login github-copilot`), lida
-- do opencode.db; fallback no auth.json legado. Nada de token em log.

local db = require("../lib/opencode-db.luau")

local GITHUB_API = "https://api.github.com"
local AUTH_JSON = "~/.local/share/opencode/auth.json"

local M = { id = "copilot" }

function M.interval_ms()
  local v = tonumber(noctalia.getConfig("refresh")) or 300
  if v < 600 then v = 600 end -- endpoint interno: no mínimo 10 minutos
  return v * 1000
end

-- ── credenciais ─────────────────────────────────────────────────────────────

local SQL = "SELECT json_extract(value,'$.access') AS access, "
  .. "json_extract(value,'$.refresh') AS refresh, "
  .. "json_extract(value,'$.metadata.enterpriseUrl') AS enterprise "
  .. "FROM credential WHERE integration_id='github-copilot' "
  .. "ORDER BY active DESC LIMIT 1;"

local function auth_json_credential()
  local path = noctalia.expandPath(AUTH_JSON)
  if not noctalia.fileExists(path) then return nil end
  local content = noctalia.readFile(path)
  if type(content) ~= "string" or content == "" then return nil end
  local ok, data = pcall(noctalia.json.decode, content)
  if not ok or type(data) ~= "table" then return nil end
  local node = data["github-copilot"]
  if type(node) ~= "table" then return nil end
  local token = node.access or node.refresh or node.key
  if type(token) ~= "string" or token == "" then return nil end
  local meta = type(node.metadata) == "table" and node.metadata or {}
  return {
    token = token,
    enterprise = type(meta.enterpriseUrl) == "string" and meta.enterpriseUrl or nil,
    source = "auth.json",
  }
end

local function resolve(cb)
  db.first(SQL, function(row)
    if type(row) ~= "table" then return nil end
    local token = row.access or row.refresh
    if type(token) ~= "string" or token == "" then return nil end
    return {
      token = token,
      enterprise = type(row.enterprise) == "string" and row.enterprise or nil,
      source = "opencode.db",
    }
  end, function(value, error_key)
    if value then
      cb(value)
      return
    end
    local legacy = auth_json_credential()
    if legacy then
      cb(legacy)
      return
    end
    cb(nil, error_key)
  end)
end

-- ── resposta ────────────────────────────────────────────────────────────────

local function endpoint_url(enterprise)
  if type(enterprise) == "string" and enterprise ~= "" then
    local host = enterprise:gsub("^https?://", ""):gsub("/+$", "")
    return "https://api." .. host .. "/copilot_internal/user"
  end
  return GITHUB_API .. "/copilot_internal/user"
end

local function parse(body)
  local ok, data = pcall(noctalia.json.decode, body)
  if not ok or type(data) ~= "table" then return nil, "error.cp_no_usage" end

  local snapshots = type(data.quota_snapshots) == "table" and data.quota_snapshots or nil
  local premium = snapshots and snapshots.premium_interactions
  if type(premium) ~= "table" then return nil, "error.cp_no_usage" end

  local entitlement = tonumber(premium.entitlement) or 0
  local used = tonumber(premium.credits_used) or 0
  local percent_remaining = tonumber(premium.percent_remaining)
  local percent_used
  if entitlement > 0 then
    percent_used = used / entitlement * 100
  elseif percent_remaining then
    percent_used = 100 - percent_remaining
  end
  if percent_used then
    percent_used = math.max(0, math.min(100, percent_used))
  end

  local orgs = type(data.organization_login_list) == "table" and data.organization_login_list or {}

  return {
    unlimited = premium.unlimited == true,
    has_quota = premium.has_quota ~= false,
    entitlement = entitlement,
    used = used,
    remaining = tonumber(premium.remaining),
    percent_used = percent_used,
    percent_remaining = percent_remaining,
    overage = premium.overage_permitted == true,
    token_based = premium.token_based_billing == true or data.token_based_billing == true,
    plan = type(data.copilot_plan) == "string" and data.copilot_plan or nil,
    sku = type(data.access_type_sku) == "string" and data.access_type_sku or nil,
    org = orgs[1],
    reset_at = data.quota_reset_date_utc or data.quota_reset_date,
  }
end

-- ── poll ────────────────────────────────────────────────────────────────────

-- cb(data, error_key, error_args, source); `data` = { quota = ... }.
function M.fetch(cb)
  resolve(function(cred, resolve_error)
    if not cred then
      cb(nil, resolve_error or "error.cp_no_key")
      return
    end

    local started = noctalia.http({
      url = endpoint_url(cred.enterprise),
      method = "GET",
      headers = {
        "Authorization: Bearer " .. cred.token,
        "Accept: application/json",
        "User-Agent: noctalia-agent-usage",
      },
    }, function(res)
      if type(res) ~= "table" then
        cb(nil, "error.cp_offline", nil, cred.source)
        return
      end

      local status = tonumber(res.status) or 0
      if status == 401 then
        cb(nil, "error.cp_auth", nil, cred.source)
        return
      elseif status == 403 then
        cb(nil, "error.cp_forbidden", nil, cred.source)
        return
      elseif status == 404 then
        cb(nil, "error.cp_gone", nil, cred.source)
        return
      elseif status == 0 then
        cb(nil, "error.cp_offline", nil, cred.source)
        return
      elseif status < 200 or status >= 300 then
        cb(nil, "error.cp_http", { code = tostring(status) }, cred.source)
        return
      end

      local quota, parse_error = parse(type(res.body) == "string" and res.body or "")
      if not quota then
        cb(nil, parse_error or "error.cp_no_usage", nil, cred.source)
        return
      end
      cb({ quota = quota }, nil, nil, cred.source)
    end)

    if not started then
      cb(nil, "error.cp_offline", nil, cred.source)
    end
  end)
end

return M
