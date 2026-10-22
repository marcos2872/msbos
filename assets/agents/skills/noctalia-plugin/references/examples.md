# Exemplos e código de referência

## Exemplos desta skill

### `examples/minimal-widget`

Plugin de barra com:

- `plugin.toml` com `plugin_api = 9`;
- settings `label` e `glyph` traduzidos;
- `barWidget.render` com glyph + label + contador;
- `onClick` e `onIpc`.

Use para entender o ciclo manifesto → widget → settings → IPC.

### `examples/niri-panel`

Plugin com três entradas:

- **serviço** que consulta `niri msg --json focused-output` e `workspaces`;
- **widget** que mostra output/workspace e abre o painel;
- **painel** que lista workspaces e chama `niri msg action focus-workspace`.

Demonstra o padrão recomendado: serviço coleta, estado compartilha, UI apenas lê/aciona. `plugin_api = 24` por causa de `runAsync` com argv.

Para testar:

```bash
cp -r examples/niri-panel ~/.local/share/noctalia/plugins/me-niri-panel
noctalia plugins lint ~/.local/share/noctalia/plugins/me-niri-panel
noctalia msg plugins enable me/niri-panel
noctalia msg panel-toggle me/niri-panel:panel
```

Ajuste `id`, `author`, nome e caminhos antes de publicar.

### `examples/theme-probe`

Plugin de verificação visual:

- **widget** com glifo na role `primary` e o valor de `bar.default.widget_spacing`;
- **painel** que lista as 16 roles da paleta com amostra (`ui.box` com `fill`) e hex via
  `noctalia.getColor` (API 31);
- **serviço** que lê a config efetiva com `getSetting` (API 26) e publica no estado.

Serve para conferir que o plugin acompanha o tema e para ver os tokens de espaçamento reais.
`plugin_api = 31`.

Para testar:

```bash
cp -r examples/theme-probe ~/.local/share/noctalia/plugins/me-theme-probe
noctalia plugins lint ~/.local/share/noctalia/plugins/me-theme-probe
noctalia msg plugins enable me/theme-probe
noctalia msg panel-toggle me/theme-probe:panel
```

## Exemplo oficial completo

`noctalia/example` no repositório oficial exercita:

- bar widget imperativo (`hello.luau`);
- bar widget declarativo (`declarative.luau`);
- serviço (`ticker.luau`);
- shortcut;
- launcher provider;
- painel com input/select/toggle/slider/color picker;
- drag and drop;
- layer (API 36).

Clone:

```bash
git clone --depth 1 https://github.com/noctalia-dev/official-plugins.git /tmp/noctalia-official-plugins
```

Arquivos:

```text
example/plugin.toml
example/hello.luau
example/declarative.luau
example/ticker.luau
example/panel.luau
example/shortcut.luau
example/finder.luau
example/dnd.luau
example/banner.luau
```

Não copie o `plugin_api = 36` do exemplo para um Noctalia 5.3.0; ajuste para os recursos que o seu plugin usa (ou remova as entradas de layer).

## Exemplos reais

| Referência | O que estudar |
|---|---|
| `noctalia/official-plugins/screen_recorder` | serviço + UI + IPC + configuração; plugin real. |
| `noctalia/official-plugins/timer` | serviço + widget + painel + desktop widget compartilhando estado. |
| `noctalia/official-plugins/wallhaven` | painel com HTTP/download de imagens e wallpaper. |
| `raycursive/niri-displays` (local) | serviço que consulta/aplica `niri msg`; painel e widget. |
| `omyfedora-ai-chat` (local) | painel complexo, SSE, formulários, settings, export e integração com OpenCode. |

Caminhos locais:

```text
~/.local/share/noctalia/plugins/niri-displays/
~/.local/share/noctalia/plugins/omyfedora-ai-chat/
```

## Padrões que valem copiar

### Estado compartilhado

```lua
-- service
noctalia.state.set("snapshot", data)
-- widget/panel
noctalia.state.watch("snapshot", function(value)
  snapshot = value
  render()
end)
```

### Comando externo seguro

```lua
noctalia.runAsync({ "niri", "msg", "--json", "focused-output" }, function(result)
  if result.exitCode ~= 0 then
    noctalia.notifyError("niri", result.stderr)
    return
  end
  local data = noctalia.json.decode(result.stdout)
  if data then noctalia.state.set("output", data) end
end, 5000)
```

### Painel com tamanho fixo e scroll

```toml
[[panel]]
id = "panel"
entry = "panel.luau"
width = 420
height = 360
placement = "floating"
position = "center"
```

```lua
panel.render(ui.column({ flexGrow = 1, gap = 10 }, {
  ui.label({ text = "Status", fontSize = 16, fontWeight = "bold" }),
  ui.scroll({ flexGrow = 1, gap = 6 }, rows),
  ui.button({ text = "Fechar", onClick = "onClose" }),
}))
```

### Widget responsivo à orientação

```lua
local container = barWidget.isVertical() and ui.column or ui.row
barWidget.render(container({ gap = 6, align = "center" }, children))
```

### Cores do tema

```lua
ui.glyph({ name = "cpu", color = "primary" })
ui.label({ text = "42%", color = "on_surface" })
ui.label({ text = "de 24 GiB", color = "on_surface_variant" })
ui.row({ fill = "surface_variant/0.5", radius = 10 })
```

Nunca hex fixo. Lista das 16 roles e tokens de gap: [`design.md`](design.md).

## O que não copiar

- QML/Quickshell da documentação v4.
- `plugin_api = 36` sem suporte no binário instalado.
- Hex fixo no lugar de roles de cor, ou gaps fora do padrão sem pedido do usuário.
- `ui.input`/`ui.select` em bar widget.
- `ui.select` em painel persistente.
- `setSize` de painel em runtime.
- Concatenação de strings de shell com dados dinâmicos.
- Persistência em `pluginDir()`.
- Uso de `noctalia.getConfig` para chave não declarada.
