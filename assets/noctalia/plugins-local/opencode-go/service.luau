--!nonstrict
-- OpenCode Go — coleta das cotas do plano.
--
-- A credencial é relida a cada poll (nunca fica em memória nem no log):
--   1. OPENCODE_API_KEY (env)
--   2. opencode.db: credential integration_id='opencode' (OAuth, campo "access")
--      ou 'opencode-go' (campo "key")
--   3. ~/.local/share/opencode/auth.json
--
-- A key nunca é impressa: o log só registra a fonte.

local USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
local BILLING_URL = "https://opencode.ai/console/api/billing/status"

local usage = nil
local credits = nil
local error_key = nil
local error_args = nil
local busy = false
local updated_at = 0
local source = nil
local saw_expired = false
local last_auth_source = nil

-- ── settings ────────────────────────────────────────────────────────────────

local function refresh_ms()
  local v = tonumber(noctalia.getConfig("refresh")) or 300
  if v < 60 then v = 60 end
  if v > 900 then v = 900 end
  return v * 1000
end

-- ── estado compartilhado ────────────────────────────────────────────────────

local function publish()
  noctalia.state.set("usage", usage)
  noctalia.state.set("credits", credits)
  noctalia.state.set("error", error_key and noctalia.tr(error_key, error_args) or "")
  noctalia.state.set("busy", busy)
  noctalia.state.set("updated_at", updated_at)
  noctalia.state.set("source", source or "")
end

local function set_error(key, args)
  error_key = key
  error_args = args
end

-- ── cache em disco ──────────────────────────────────────────────────────────

local function cache_path()
  local dir = noctalia.pluginDataDir()
  if type(dir) ~= "string" or dir == "" then return nil end
  return dir .. "/cache.json"
end

local function save_cache()
  local path = cache_path()
  if not path then
    noctalia.log("cache: pluginDataDir indisponível")
    return
  end
  local ok, encoded = pcall(noctalia.json.encode, {
    usage = usage,
    credits = credits,
    updated_at = updated_at,
    source = source,
  })
  if ok and type(encoded) == "string" then
    local wrote, err = noctalia.writeFile(path, encoded)
    if wrote ~= true then
      noctalia.log("cache: falha ao gravar " .. tostring(err or path))
    end
  end
end

local function load_cache()
  local path = cache_path()
  if not path or not noctalia.fileExists(path) then return end
  local content = noctalia.readFile(path)
  if type(content) ~= "string" or content == "" then return end
  local ok, data = pcall(noctalia.json.decode, content)
  if not ok or type(data) ~= "table" then return end
  if type(data.usage) == "table" then usage = data.usage end
  if type(data.credits) == "table" then credits = data.credits end
  updated_at = tonumber(data.updated_at) or 0
  source = type(data.source) == "string" and data.source ~= "" and data.source or nil
end

-- ── credenciais ─────────────────────────────────────────────────────────────

local function db_paths()
  local out = {}
  local override = noctalia.getenv("OPENCODE_DB")
  if type(override) == "string" and override ~= "" then
    table.insert(out, noctalia.expandPath(override))
  end
  local xdg = noctalia.getenv("XDG_DATA_HOME")
  if type(xdg) == "string" and xdg ~= "" then
    table.insert(out, xdg .. "/opencode/opencode.db")
  end
  table.insert(out, noctalia.expandPath("~/.local/share/opencode/opencode.db"))
  return out
end

local function sqlite_json(db, sql, cb)
  -- "-cmd .timeout" em vez de "PRAGMA busy_timeout": o PRAGMA também emite uma
  -- linha em modo -json e seria confundido com o resultado da consulta.
  noctalia.runAsync({ "sqlite3", "-json", "-readonly", "-cmd", ".timeout 2000", db, sql }, function(result)
    if type(result) ~= "table" or result.exitCode ~= 0 then
      noctalia.log("db: sqlite falhou: " .. tostring(type(result) == "table" and result.exitCode or "nil")
        .. " " .. tostring(type(result) == "table" and result.stderr or ""))
      cb(nil)
      return
    end
    local raw = result.stdout
    if type(raw) ~= "string" or raw == "" then
      cb(nil)
      return
    end
    local ok, rows = pcall(noctalia.json.decode, raw)
    if not ok or type(rows) ~= "table" then
      cb(nil)
      return
    end
    cb(rows[1])
  end, 5000)
end

local function try_db(cb)
  if not noctalia.commandExists("sqlite3") then
    cb(nil, nil, "error.no_sqlite")
    return
  end
  local dbs = db_paths()

  local function attempt(i)
    if i > #dbs then
      cb(nil, nil, saw_expired and "error.expired" or "error.no_key")
      return
    end
    local db = dbs[i]
    if not noctalia.fileExists(db) then
      attempt(i + 1)
      return
    end

    -- 1) OAuth do OpenCode Console (o "pair" do opencode auth login).
    local sql_access = "SELECT json_extract(value,'$.access') AS access, "
      .. "json_extract(value,'$.expires') AS expires "
      .. "FROM credential WHERE integration_id='opencode' "
      .. "ORDER BY active DESC LIMIT 1;"
    sqlite_json(db, sql_access, function(row)
      local token = type(row) == "table" and row.access or nil
      local expires = type(row) == "table" and tonumber(row.expires) or nil
      if type(token) == "string" and token ~= "" then
        if not expires or expires > noctalia.nowMs() then
          cb(token, "opencode.db", nil)
          return
        end
        saw_expired = true
      end

      -- 2) API key dedicada do plano Go.
      local sql_key = "SELECT json_extract(value,'$.key') AS key "
        .. "FROM credential WHERE integration_id='opencode-go' "
        .. "ORDER BY active DESC LIMIT 1;"
      sqlite_json(db, sql_key, function(row2)
        local key = type(row2) == "table" and row2.key or nil
        if type(key) == "string" and key ~= "" then
          cb(key, "opencode.db", nil)
          return
        end
        attempt(i + 1)
      end)
    end)
  end

  attempt(1)
end

local function try_auth_json(cb)
  local path = noctalia.expandPath("~/.local/share/opencode/auth.json")
  if not noctalia.fileExists(path) then
    cb(nil, nil)
    return
  end
  local content = noctalia.readFile(path)
  if type(content) ~= "string" or content == "" then
    cb(nil, nil)
    return
  end
  local ok, data = pcall(noctalia.json.decode, content)
  if not ok or type(data) ~= "table" then
    cb(nil, nil)
    return
  end
  for _, id in ipairs({ "opencode-go", "opencode" }) do
    local node = data[id]
    if type(node) == "table" and type(node.key) == "string" and node.key ~= "" then
      cb(node.key, "auth.json")
      return
    end
  end
  cb(nil, nil)
end

local function resolve_key(cb)
  local env = noctalia.getenv("OPENCODE_API_KEY")
  if type(env) == "string" and env ~= "" then
    cb(env, "env", nil)
    return
  end
  try_db(function(key, src, err)
    if key then
      cb(key, src, nil)
      return
    end
    try_auth_json(function(key2, src2)
      if key2 then
        cb(key2, src2, nil)
      else
        cb(nil, nil, err or "error.no_key")
      end
    end)
  end)
end

-- ── resposta ────────────────────────────────────────────────────────────────

local function handle_response(res, src)
  busy = false
  if type(res) ~= "table" then
    noctalia.log("poll: resposta inválida")
    set_error("error.offline")
    publish()
    return
  end

  local status = tonumber(res.status) or 0
  if status ~= 200 then
    noctalia.log("poll: HTTP " .. tostring(status) .. " (" .. tostring(src) .. ")")
  end
  if status == 401 then
    set_error("error.unauthorized")
  elseif status == 403 then
    set_error("error.no_plan")
  elseif status == 0 then
    set_error("error.offline")
  elseif status < 200 or status >= 300 then
    set_error("error.http", { code = tostring(status) })
  else
    local body = type(res.body) == "string" and res.body or ""
    local ok, data = pcall(noctalia.json.decode, body)
    if not ok or type(data) ~= "table" or type(data.usage) ~= "table" then
      set_error("error.no_usage")
    elseif type(data.usage.rolling) ~= "table"
      and type(data.usage.weekly) ~= "table"
      and type(data.usage.monthly) ~= "table" then
      set_error("error.no_usage")
    else
      usage = data.usage
      updated_at = noctalia.nowMs()
      source = src
      saw_expired = false
      set_error(nil)
      save_cache()
    end
  end
  publish()
end

-- ── créditos do billing ─────────────────────────────────────────────────────

-- "Available credits" do console (prepaid/pay-as-you-go), em microcents.
local function fetch_credits(key)
  noctalia.http({
    url = BILLING_URL,
    method = "GET",
    headers = {
      "Authorization: Bearer " .. key,
      "Accept: application/json",
    },
  }, function(res)
    if type(res) ~= "table" or tonumber(res.status) ~= 200 then
      return
    end
    local ok, data = pcall(noctalia.json.decode, type(res.body) == "string" and res.body or "")
    if not ok or type(data) ~= "table" then
      return
    end
    local available = tonumber(data.availableMicroCents or data.balanceMicroCents)
    if not available then
      return
    end
    credits = {
      available = available,
      limit = tonumber(data.creditLimitMicroCents),
      mode = type(data.mode) == "string" and data.mode or "",
      billing_mode = type(data.billingMode) == "string" and data.billingMode or "",
    }
    publish()
    save_cache()
  end)
end

-- ── poll ────────────────────────────────────────────────────────────────────

local function refresh()
  if busy then return end
  busy = true
  publish()

  resolve_key(function(key, src, err)
    if not key then
      busy = false
      noctalia.log("auth: " .. tostring(err or "error.no_key"))
      set_error(err or "error.no_key")
      publish()
      return
    end

    if src ~= last_auth_source then
      noctalia.log("auth: " .. tostring(src))
      last_auth_source = src
    end

    local started = noctalia.http({
      url = USAGE_URL,
      method = "GET",
      headers = {
        "Authorization: Bearer " .. key,
        "Accept: application/json",
      },
    }, function(res)
      handle_response(res, src)
    end)

    if not started then
      busy = false
      set_error("error.offline")
      publish()
    else
      fetch_credits(key)
    end
  end)
end

-- ── ciclo de vida ───────────────────────────────────────────────────────────

load_cache()
publish()
noctalia.setUpdateInterval(refresh_ms())
refresh()

function update()
  refresh()
end

function onConfigChanged()
  noctalia.setUpdateInterval(refresh_ms())
end

function onIpc(event, _payload)
  if event == "refresh" then
    refresh()
  end
end
