# Entradas, callbacks e IPC

Fontes: `Entry Scripts`, `Manifest & Settings` e o código do exemplo oficial `noctalia/example`. Cada entrada roda em uma VM Luau isolada; estado só é compartilhado via `noctalia.state`.

## Callbacks por tipo de entrada

| Callback | Widget | Shortcut | Launcher | Desktop | Panel | Layer | Service |
|---|---|---|---|---|---|---|---|
| `update()` | ✓ | — | — | ✓ | ✓ | ✓ | ✓ |
| `onClick()` / `onRightClick()` | ✓ | ✓ | — | — | — | — | — |
| `onMiddleClick()` | ✓ | — | — | — | — | — | — |
| `onScroll(axis, steps, startsGesture)` | ✓ | — | — | — | — | — | — |
| `onQuery(text)` / `onActivate(id)` | — | — | ✓ | — | — | — | — |
| `onOpen(context)` / `onClose()` | — | — | — | — | ✓ | — | — |
| `onKey(chord, pressed)` | — | — | — | — | ✓ | — | — |
| `onFrameTick(deltaMs)` | — | — | — | ✓ | ✓ | ✓ | — |
| `onIpc(event, payload)` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `onConfigChanged()` | — | — | — | — | — | ✓ | ✓ |
| `onEnable()` | — | — | — | — | — | — | ✓ |
| `onOutputsChanged()` | — | — | — | — | — | — | ✓ |
| `onExit(signal, reason)` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `onAudioSpectrum(valuesCsv, stateCsv)` | ✓ | — | — | — | — | — | — |

O topo do script roda **uma vez** ao carregar; use para estado inicial e `noctalia.state.watch`. `update()` roda no intervalo definido por `noctalia.setUpdateInterval(ms)` (mínimo 16 ms).

## Widget

### API imperativa

```lua
barWidget.setText("42%")
barWidget.setGlyph("cpu")
barWidget.setTooltip("CPU: 42%")
barWidget.setColor("primary")
barWidget.setGlyphColor("on_surface")
barWidget.setFont("Minha Fonte")
barWidget.setImage("images/status.png", true, 16, 16)
```

- `setText("")` esconde o label.
- `setGlyph` remove a imagem; `setImage` esconde o glifo.
- `setTooltip` aceita string, `{key, value}` ou lista de linhas.
- `setColor(role, mode?)`: `mode = "script"` usa o role literal em vez do default do widget.
- `setVisible(false)` esconde o capsule inteiro.
- `isVertical()` escolhe `ui.column` para barra vertical.
- `outputName()` retorna o conector daquela instância.

### API declarativa

```lua
local function render()
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, {
    ui.glyph({ name = "cpu", size = 14, color = "primary" }),
    ui.label({ text = "42%", fontWeight = "bold" }),
    ui.button({ glyph = "refresh", variant = "ghost", onClick = "onRefresh" }),
  }))
end
```

Depois de `barWidget.render`, `setText`/`setGlyph`/`setImage`/`setFont`/`setColor` não têm efeito visível. `ui.input`, `ui.select` e `ui.scroll` são ignorados na barra (sem foco de teclado). Mantenha a árvore com a espessura de um controle.

### Cliques e scroll

```lua
function onClick()
  noctalia.notify("Widget", "clique esquerdo")
end

function onRightClick()
  noctalia.notify("Widget", "clique direito")
end

function onScroll(axis, steps, startsGesture)
  if axis == "vertical" and startsGesture then
    -- steps > 0 desce; steps < 0 sobe
  end
end
```

Bindings em `[widget.actions]` vencem os callbacks. O clique do meio tem binding padrão para abrir settings; só chega em `onMiddleClick` com `middle = "none"`. `enable_scroll = false` na instância desliga `onScroll`.

## Painel

```lua
local render

render = function()
  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.label({ text = "Painel", fontSize = 16, fontWeight = "bold" }),
    ui.button({ text = "Fechar", onClick = function() panel.close() end }),
  }))
end

function onOpen(context)
  -- context é o texto opcional de `panel-toggle ...:panel [contexto]`
  render()
end

function onClose()
  -- opcional
end
```

- `panel.render(tree)` substitui a árvore; `panel.close()` fecha.
- `panel.setWantsSecondTicks(true)` faz `update()` em segundos; `panel.setNeedsFrameTick(true)` entrega `onFrameTick(deltaMs)` (API 18).
- `panel.openContextMenu(request)` só dentro de `onRightClick` de um `ui.button` (API 28).
- `onKey(chord, pressed)` só recebe acordes declarados em `capture_keys`; Escape sempre fecha.
- O tamanho vem do manifesto; não há resize em runtime.

### Context menu

```lua
function openMenu()
  panel.openContextMenu({
    items = {
      { kind = "header", label = "Ações" },
      { id = "copy", label = "Copiar" },
      { kind = "separator" },
      { id = "delete", label = "Apagar", enabled = true },
    },
    onActivate = "onMenuAction",
    context = "item-42",
  })
end

function onMenuAction(actionId, context)
  -- actionId = "copy" | "delete"; context = "item-42"
end
```

`onActivate` precisa ser nome de função global do painel. Até 64 itens; `maxVisible` 1–30.

### `capture_keys`

```toml
[[panel]]
id = "keys"
entry = "keys.luau"
capture_keys = ["space", "ctrl+r"]
```

```lua
function onKey(chord, pressed)
  if chord == "space" and pressed then
    -- ...
  end
end
```

Input focado tem prioridade para texto; Escape sempre fecha; `keyboard_focus = "none"` + `capture_keys` é inválido (o painel nunca receberia a tecla); Super não é capturável.

## Serviço

```lua
local interval = (tonumber(noctalia.getConfig("interval")) or 5) * 1000
noctalia.setUpdateInterval(interval)

function update()
  -- polling
end

function onIpc(event, payload)
  if event == "refresh" then
    update()
  end
end

function onConfigChanged()
  interval = (tonumber(noctalia.getConfig("interval")) or 5) * 1000
  noctalia.setUpdateInterval(interval)
end

function onEnable()
  -- chamado após enable explícito, não em todo boot
end

function onOutputsChanged()
  -- outputs/geometria mudaram
end

function onExit(signal, reason)
  -- reason: "reload" | "disable" | "uninstall" | "shutdown"
end
```

- Serviço é singleton, sem UI; use `all` no IPC.
- `onConfigChanged` mantém o estado em memória; sem ele, o host reinicia o serviço ao mudar setting.
- `onEnable` não roda em boot normal nem em hot reload.
- `onExit` deve ser curto; para trabalho que precisa sobreviver, use `noctalia.runAsync(cmd)` sem callback.

## Shortcut

```lua
local on = noctalia.state.get("toggle") == true
local function render()
  shortcut.setLabel(on and "On" or "Off")
  shortcut.setIcon("bulb")
  shortcut.setActive(on)
  shortcut.setEnabled(true)
end
render()

function onClick()
  on = not on
  noctalia.state.set("toggle", on)
  render()
end
```

## Launcher provider

Manifesto: `prefix` (sem `/`), `glyph`, `include_in_global_search`, `debounce_ms`.

```lua
function onQuery(text)
  local results = {}
  for _, item in ipairs({ "alpha", "beta", "gamma" }) do
    if text == "" or item:find(text, 1, true) then
      table.insert(results, {
        id = item,
        title = item,
        subtitle = "Enter para copiar",
        glyph = "tag",
      })
    end
  end
  launcher.setResults(text, results)
end

function onActivate(id)
  noctalia.copyToClipboard(id, "text/plain")
end
```

- `setResults(query, results)` deve ecoar o texto de `onQuery`.
- `setQuery(text)` mantém o launcher aberto e muda a consulta (drill-in).
- `id` volta em `onActivate`; resultado com `query` faz drill-in sem callback.
- Use `noctalia.fuzzyScore(pattern, text)` para ranking local.

## Desktop widget

```lua
function update()
  desktopWidget.setWantsSecondTicks(true)
  desktopWidget.render(ui.column({ gap = 8, align = "center" }, {
    ui.label({ text = os.date("%H:%M"), fontSize = 32, fontWeight = "bold" }),
  }))
end
```

- `render(tree)`, `setWantsSecondTicks`, `setNeedsFrameTick`.
- A posição/tamanho é do usuário no editor de desktop widgets.
- O host roda `update` por segundo quando `setWantsSecondTicks(true)`.
- Tooltips não aparecem em desktop widgets.
- `ui.scroll` e os controles visuais funcionam em desktop widgets; `ui.input`/`ui.select` são documentados para painéis.

## Layer (API 36; indisponível no Noctalia 5.3.0)

```lua
layer.render(ui.column({ fill = "#000000", flexGrow = 1 }, {}))
```

- Uma instância por output enquanto visível; `layer.outputName()`.
- `noctalia.layer.show/hide/configure` por ID local de qualquer entrada do plugin.
- `visible = true` no manifesto mostra ao carregar.
- `click_through` e `exclusive_zone` são layer-shell.
- O namespace é fixo (`noctalia-plugin:<author>/<plugin>:<entry>`); sem `[[layer.setting]]` — use settings plugin-level.

## IPC

Formato:

```bash
noctalia msg plugin <author>/<plugin>:<entry> <target> <event> [payload]
```

- `target`: `focused`, conector (`DP-3`), `DP-3:bar-name` ou `all`.
- Serviços e entradas sem output usam `all`.
- `payload` é uma string (JSON se precisar de estrutura).
- No script:

```lua
function onIpc(event, payload)
  if event == "set" then
    label = payload or label
    render()
  elseif event == "refresh" then
    refresh()
  end
end
```

Exemplos:

```bash
noctalia msg plugin me/hello:hello focused set "Oi"
noctalia msg plugin me/hello:worker all refresh
noctalia msg panel-toggle me/hello:panel
```

## Módulos

Com API 22:

```lua
local format = require("./lib/format.luau")
```

- Caminho relativo ao arquivo que faz o `require`, terminando em `.luau`.
- Cada entrada tem cache próprio; módulos têm ambiente global privado.
- Módulo deve retornar exatamente um valor não-nil.
- Hot reload recarrega o módulo junto com a entrada.

## Ciclo de vida e limpeza

- `onExit(signal, reason)` em todas as entradas; `reason` requer API 17.
- `signal`: `0` normal, `2` SIGINT, `15` SIGTERM.
- `reason`: `reload`, `disable`, `uninstall`, `shutdown`.
- Streams HTTP ativos são cancelados quando a entrada recarrega/para.
- `runStream` também é encerrado no reload.
- Não guarde segredos em log; plugins são confiáveis, mas o log não é privado.
