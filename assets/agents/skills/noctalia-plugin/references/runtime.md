# Runtime API (`noctalia.*`)

Fontes: documentação oficial `Runtime API`, `Entry Scripts` e `noctalia.d.luau`. A maioria das funções é síncrona; operações que iniciam processos, HTTP ou downloads retornam um booleano e entregam o resultado por callback.

## Runtime e settings

| Método | Retorno | Uso |
|---|---|---|
| `noctalia.setUpdateInterval(ms)` | — | Intervalo de `update()`, mínimo 16 ms. |
| `noctalia.log(msg)` | — | Log com contexto do plugin. |
| `noctalia.getConfig(key)` | valor/nil | Setting declarado no manifesto. Chave não declarada gera warning. |
| `noctalia.getSetting(path)` | valor/nil | Config efetiva do shell por caminho TOML (`shell.offline_mode`); API 26. |
| `noctalia.isDarkMode()` | bool | Tema escuro atual. |
| `noctalia.getColor(role)` | `#RRGGBB`/nil | Cor da paleta ativa; API 31. |
| `noctalia.focusedOutputName()` | string/nil | Conector do output focado. Pode vir `nil`; use `outputs()[].focused` como fallback. |
| `noctalia.outputs()` | array | `{name, description, width, height, x, y, scale, focused}`. |
| `noctalia.nowMs()` | number | Epoch ms com subsegundo; API 12. |
| `noctalia.formatTime(pattern, unixSeconds?, timezone?)` | string | Formatação local/IANA; timezone API 19. |
| `noctalia.timeFormat()` / `dateFormat()` | string | Formato efetivo do shell; API 19. |
| `noctalia.isValidTimezone(name)` | bool | API 19. |
| `noctalia.appIconPath(appId, sizePx?)` | string/nil | Ícone de um app id resolvido pelo tema; cacheie. |

`getConfig` vs `getSetting`: o primeiro lê **settings do plugin** (declarados); o segundo lê a **configuração global do shell**. Valores de `getSetting` são copiados; índices de arrays são zero-based.

## Painéis, outputs e diálogos

| Método | Uso |
|---|---|
| `noctalia.togglePanel("autor/plugin:panel")` | Abre/fecha um painel do plugin. Prefira isto a chamar a CLI. |
| `noctalia.openSettings()` | Abre Settings na página do plugin; API 15. |
| `noctalia.openColorPicker(initial, cb)` | Color picker nativo; callback recebe `#RRGGBB` ou `nil`; um pendente por entrada. |
| `noctalia.outputs()` | Lista outputs para montar seletores. |
| `noctalia.setWallpaper(path)` / `(connector, path)` | Aplica/persiste wallpaper. |
| `noctalia.setWallpaperEnabled(connector, enabled)` | Liga/desliga a superfície de wallpaper (runtime). |
| `noctalia.wallpaperDirectory()` | Pasta de wallpapers do modo atual. |
| `noctalia.wallpaperPath(connector)` | Caminho fonte; API 25. |
| `noctalia.setWallpaperMask(connector, mask?)` | Máscara de desktop widgets; API 25. |

## Notificações e clipboard

```lua
noctalia.notify("Título", "Mensagem")   -- corpo é opcional
noctalia.notifyError("Falhou", "Detalhe")
noctalia.copyToClipboard("texto", "text/plain")
local text = noctalia.clipboardText()
```

- `copyToClipboard` exige MIME explícito.
- `clipboardText` retorna `nil` para vazio/não-texto.
- Use `notifyError` para falha de processo/HTTP, não para log interno.

## Subprocessos

```lua
-- argv: sem shell, recomendado para dados dinâmicos (API 24)
noctalia.runAsync({ "niri", "msg", "--json", "focused-output" }, function(result)
  if result.exitCode ~= 0 then
    noctalia.log(result.stderr)
    return
  end
  local data = noctalia.json.decode(result.stdout)
end, 5000)

-- string: roda em /bin/sh -c; use só com comando fixo
noctalia.runAsync("notify-send 'Oi'")
```

`runAsync` retorna `bool` (aceitou iniciar). Com callback, o resultado é:

```lua
{
  exitCode = 0,
  stdout = "...",
  stderr = "...",
  timedOut = false,
  stdoutTruncated = false,
  stderrTruncated = false,
}
```

- Sem callback, é detached e não captura saída.
- `timeoutMs` é limitado a 50–60000 ms.
- `runStream(cmd, onLine)` para stdout linha a linha (processos longos, `niri msg event-stream`).
- `runInTerminal(cmd)` abre um terminal; `commandExists(name)` verifica PATH.
- `processMatches(cb, ...needles)` verifica processos; `getenv`, `expandPath`.
- `flatpakAppInstalled(id)` / `portalAvailable()` para decidir entre flatpak e portal.

**Segurança:** nunca concatene entrada do usuário/settings em uma string de shell. Use argv.

## Arquivos e persistência

| Método | Uso |
|---|---|
| `readFile(path)` | `(contents, err)`. |
| `readFileAsync(path, cb)` | Leitura limitada (4 MiB, 4 pendentes); API 23. |
| `writeFile(path, content)` | `(ok, err)`. |
| `mkdirAll`, `removeFile`, `renameFile` | Operações de arquivo. |
| `fileExists`, `fileInfo`, `listDir` | Inspeção. |
| `pluginDir()` | Diretório runtime do plugin (pode ser cópia descartável). |
| `pluginDataDir()` | Diretório persistente por plugin; use para dados que sobrevivem a updates. |
| `loadFont(path)` | Registra uma fonte; retorna `family` ou `nil, err`. |

Caminhos: `~` expande; absoluto é literal; relativo resolve no diretório do plugin.

**Não persista em `pluginDir()`**: ele pode ser reescrito em updates. Use `pluginDataDir()`:

```lua
local dir = noctalia.pluginDataDir()
noctalia.writeFile(dir .. "/state.json", noctalia.json.encode(data, true))
local raw = noctalia.readFile(dir .. "/state.json")
```

## Som (API 20)

```lua
noctalia.sound.load("click", "sounds/click.ogg", function(ok, err)
  if not ok then noctalia.notifyError("Som", err) return end
  noctalia.sound.play("click")
end)
```

- `load(name, path, onLoaded)` aceita boolean; o callback confirma a decodificação.
- `play(name)` só toca depois de `load` bem-sucedido; tocar o mesmo som enquanto ele toca é suprimido.
- Nomes são por runtime; reload cancela loads pendentes e libera os nomes.
- Caminhos relativos resolvem no diretório do plugin; assets de som não precisam de declaração.

## HTTP e SSE

```lua
noctalia.http({
  url = "https://api.exemplo",
  method = "GET",
  headers = { "Accept: application/json" },
}, function(res)
  if res.ok and res.status == 200 then
    local data = noctalia.json.decode(res.body)
  end
end)
```

- `http` retorna `bool`; callback recebe `{ok, status, body}`.
- `httpStream` (API 4) retorna handle `{stop()}` ou `nil`; `onLine` recebe cada linha; `onClose` recebe `{ok, status}` uma vez.
- `download(url, dest, cb)` baixa para arquivo local.
- `allow_insecure_tls` (API 7) só para endpoint confiável.
- Respeita `shell.offline_mode`.
- Não há timeout global no stream; reconecte no `onClose`.

## Estado compartilhado

```lua
noctalia.state.set("snapshot", { output = "DP-3", workspaces = { 1, 2 } })
local snapshot = noctalia.state.get("snapshot")
noctalia.state.watch("snapshot", function(value)
  -- chamado em cada mudança
end)
```

- Valores precisam ser dados planos: string, number, boolean, tabelas desses.
- Não compartilha funções/objetos.
- É **em memória** e vive enquanto o plugin está carregado.
- Um serviço publica; widget/painel observam.
- O estado sobrevive a reinício do serviço, mas não a restart do Noctalia.

## Traduções e helpers

| Método | Uso |
|---|---|
| `noctalia.tr(key, subst?)` | Traduz uma chave; placeholders `{name}`. |
| `noctalia.trp(key, count, subst?)` | Plural: `<key>.one`/`<key>.other`. |
| `noctalia.json.decode(str)` | `value` ou `nil, err`. |
| `noctalia.json.encode(value, pretty?)` | JSON compacto/pretty. |
| `noctalia.string.trim/urlEncode/urlDecode` | Strings. |
| `noctalia.fuzzyScore(pattern, text)` | Score ou `nil`. |

## System stats

| Método | Uso |
|---|---|
| `noctalia.systemStats()` | `cpu`, `ram`, `swap`, `gpu`, `net`, `loadAvg`, `sampledAtMs` (API 12/16). |
| `noctalia.cpuCores()` | Uso por core; API 12; custo extra. |
| `noctalia.diskMounts()` | Filesystems físicos; API 16. |
| `noctalia.diskStats(path)` | `usagePercent`, `totalBytes`, `freeBytes`, `availableBytes`; API 16. |

Sensores ausentes são `nil`, não `0`. `systemStats()` pode retornar `nil` se o monitor do sistema estiver desligado.

## Recursos por API (não disponíveis no 5.3.0)

| Recurso | API |
|---|---|
| `noctalia.idle.watch/unwatch` | 35 |
| `noctalia.layer.show/hide/configure` e `[[layer]]` | 36 |
| `noctalia.calendarEvents()` | 37 |
| DnD em bar widget | 38 |
| `noctalia.osd.show()` | 39 |

Use somente se o Noctalia instalado suportar. O `plugin_api` do manifesto precisa refletir o maior recurso usado.

## Exemplo de serviço com HTTP + estado

```lua
local function refresh()
  noctalia.http({ url = "https://api.exemplo/status" }, function(res)
    if not res.ok or res.status ~= 200 then
      noctalia.state.set("api", { error = "HTTP " .. tostring(res.status) })
      return
    end
    local data = noctalia.json.decode(res.body)
    noctalia.state.set("api", data or { error = "JSON inválido" })
  end)
end

function update()
  refresh()
end

function onIpc(event)
  if event == "refresh" then refresh() end
end
```

## Erros comuns

- `runAsync` com string e entrada dinâmica → injeção de shell.
- `runAsync` com argv e API < 24 → erro; declare `plugin_api = 24`.
- `http` callback após reload → a VM é descartada; não assuma que o callback roda.
- `pluginDataDir()` sem tratar `nil, err` → falha silenciosa.
- `state` com função/objeto → cópia inválida; use dados planos.
- `getConfig` de chave não declarada → `nil` + warning.
- `getSetting("caminho.inexistente")` → warning `matched no config key` + `nil`; confira o nome.
- `focusedOutputName()` pode vir `nil` mesmo com monitor focado; use `outputs()[].focused`.
