--!nonstrict
-- Acesso somente-leitura ao opencode.db (tabela `credential` das integrações).
-- O token nunca é impresso: quem chama só publica a fonte.

local M = {}

function M.available()
  return noctalia.commandExists("sqlite3") == true
end

function M.paths()
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

-- "-cmd .timeout" em vez de "PRAGMA busy_timeout": o PRAGMA também emite uma
-- linha em modo -json e seria confundido com o resultado da consulta.
function M.query(db, sql, cb)
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

-- Percorre os bancos candidatos e para no primeiro em que `pick(row)` devolver
-- algo não-nil. `cb(value, error_key)`.
function M.first(sql, pick, cb)
  if not M.available() then
    cb(nil, "error.no_sqlite")
    return
  end
  local dbs = M.paths()

  local function attempt(i)
    if i > #dbs then
      cb(nil)
      return
    end
    local db = dbs[i]
    if not noctalia.fileExists(db) then
      attempt(i + 1)
      return
    end
    M.query(db, sql, function(row)
      local value = pick(type(row) == "table" and row or nil)
      if value ~= nil then
        cb(value)
        return
      end
      attempt(i + 1)
    end)
  end

  attempt(1)
end

return M
