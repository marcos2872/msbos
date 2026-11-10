--!nonstrict
-- Agent Usage — coleta o uso dos providers configurados e publica no estado
-- compartilhado do plugin (widget, painel e este serviço leem daqui).
--
--   go.usage / go.credits / go.error / go.busy / go.updated_at / go.source / go.configured
--   cp.quota  /             cp.error / cp.busy / cp.updated_at / cp.source / cp.configured
--
-- Cada provider tem o próprio intervalo (o Copilot nunca abaixo de 10 min) e
-- só é consultado quando vence. Um cache em disco mantém os últimos valores
-- quando a consulta falha.

local go = require("./providers/go.luau")
local copilot = require("./providers/copilot.luau")

local CACHE_VERSION = 2
-- Passo do relógio interno: curto para cada provider vencer no seu tempo, sem
-- que um poll dependa do outro.
local TICK_MS = 15 * 1000

local ENTRIES = {
  { key = "go", module = go },
  { key = "cp", module = copilot },
}

local state = {
  go = { configured = false, busy = false, updated_at = 0, error_key = nil, error_args = nil, source = nil, data = {} },
  cp = { configured = false, busy = false, updated_at = 0, error_key = nil, error_args = nil, source = nil, data = {} },
}

local logged = {}

-- ── estado compartilhado ────────────────────────────────────────────────────

local function publish(key)
  local p = state[key]
  noctalia.state.set(key .. ".configured", p.configured)
  noctalia.state.set(key .. ".busy", p.busy)
  noctalia.state.set(key .. ".updated_at", p.updated_at)
  noctalia.state.set(key .. ".source", p.source or "")
  noctalia.state.set(key .. ".error", p.error_key and noctalia.tr(p.error_key, p.error_args) or "")
  if key == "go" then
    noctalia.state.set("go.usage", p.data.usage)
    noctalia.state.set("go.credits", p.data.credits)
  else
    noctalia.state.set("cp.quota", p.data.quota)
  end
end

local function publish_all()
  for _, entry in ipairs(ENTRIES) do publish(entry.key) end
end

local function log_once(key, message)
  if logged[key] == message then return end
  logged[key] = message
  noctalia.log("agent-usage: " .. key .. ": " .. message)
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
  local payload = {
    version = CACHE_VERSION,
    active_tab = noctalia.state.get("active_tab"),
  }
  for _, entry in ipairs(ENTRIES) do
    local p = state[entry.key]
    payload[entry.key] = {
      data = p.data,
      updated_at = p.updated_at,
      source = p.source,
      configured = p.configured,
    }
  end
  local ok, encoded = pcall(noctalia.json.encode, payload)
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

  if tonumber(data.version) == CACHE_VERSION then
    for _, entry in ipairs(ENTRIES) do
      local node = data[entry.key]
      if type(node) == "table" then
        local p = state[entry.key]
        if type(node.data) == "table" then p.data = node.data end
        p.updated_at = tonumber(node.updated_at) or 0
        p.source = type(node.source) == "string" and node.source ~= "" and node.source or nil
        p.configured = node.configured == true
      end
    end
    if type(data.active_tab) == "string" and data.active_tab ~= "" then
      noctalia.state.set("active_tab", data.active_tab)
    end
    return
  end

  -- cache v1 (plugin OpenCode Go): tudo pertencia ao provider Go.
  if type(data.usage) == "table" or type(data.credits) == "table" then
    local p = state.go
    if type(data.usage) == "table" then p.data.usage = data.usage end
    if type(data.credits) == "table" then p.data.credits = data.credits end
    p.updated_at = tonumber(data.updated_at) or 0
    p.source = type(data.source) == "string" and data.source ~= "" and data.source or nil
    p.configured = p.updated_at > 0
  end
end

-- ── poll ────────────────────────────────────────────────────────────────────

local function fetch_provider(entry, force)
  local p = state[entry.key]
  if p.busy then return end

  local now = noctalia.nowMs()
  if not force and p.updated_at > 0 and (now - p.updated_at) < entry.module.interval_ms() then
    return
  end

  p.busy = true
  publish(entry.key)

  entry.module.fetch(function(data, error_key, error_args, source)
    p.busy = false

    if type(source) == "string" and source ~= "" then
      p.source = source
    end

    if error_key then
      p.error_key = error_key
      p.error_args = error_args
      -- "sem credencial" esconde a aba; os demais erros mantêm o provider
      -- visível com o último valor conhecido.
      if error_key == "error.no_key" or error_key == "error.cp_no_key" or error_key == "error.no_sqlite" then
        p.configured = false
      end
      log_once(entry.key, error_key .. (error_args and (" " .. tostring(error_args.code or "")) or ""))
    else
      if type(data) == "table" then
        for field, value in pairs(data) do
          if value ~= nil then p.data[field] = value end
        end
      end
      p.configured = true
      p.updated_at = noctalia.nowMs()
      p.error_key = nil
      p.error_args = nil
      log_once(entry.key, "ok")
    end

    publish(entry.key)
    save_cache()
  end)
end

local function tick()
  for _, entry in ipairs(ENTRIES) do
    fetch_provider(entry, false)
  end
end

-- ── ciclo de vida ───────────────────────────────────────────────────────────

load_cache()
publish_all()
noctalia.setUpdateInterval(TICK_MS)
noctalia.state.watch("active_tab", function()
  save_cache()
end)
tick()

function update()
  tick()
end

function onConfigChanged()
  -- Os intervalos são lidos a cada tick; basta seguir.
end

function onIpc(event, payload)
  if event == "refresh" then
    for _, entry in ipairs(ENTRIES) do
      fetch_provider(entry, true)
    end
  elseif event == "provider" and type(payload) == "string" and payload ~= "" then
    -- Atualiza um provider só (o painel pede quando a aba aberta vence, sem
    -- gastar uma consulta do outro).
    for _, entry in ipairs(ENTRIES) do
      if entry.key == payload then
        fetch_provider(entry, true)
      end
    end
  elseif event == "tab" and type(payload) == "string" and payload ~= "" then
    noctalia.state.set("active_tab", payload)
  end
end
