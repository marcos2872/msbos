---
name: noctalia-plugin
description: Cria, altera e depura plugins do Noctalia v5 em Luau (plugin.toml, widgets, painéis, serviços, settings, IPC, layers) e integra com niri via IPC/config. Sempre usa as cores da paleta do sistema e o espaçamento padrão (só muda se o usuário pedir). Use quando o usuário pedir um plugin, widget, painel ou serviço do Noctalia, ajustar cores/espaçamento de um plugin, automação do niri, ou manutenção de um plugin existente.
---

# Noctalia + niri — desenvolvimento de plugins

## Quando usar

Use esta skill para:

- criar um plugin novo do Noctalia v5;
- adicionar/alterar bar widget, painel, serviço, layer, shortcut, launcher provider ou desktop widget;
- declarar settings traduzidos e ler valores com `noctalia.getConfig`;
- chamar a API do Noctalia em scripts (widgets, painéis, serviços) e ajustar cores/espaçamento **dentro do padrão do sistema**;
- conectar um plugin ao niri (`niri msg`, config KDL, ações e eventos);
- depurar hot reload, IPC, estado compartilhado, lint ou empacotamento.

## Regra de ouro

1. **Noctalia v5 usa Luau + `plugin.toml`**. A documentação “v4/Quickshell/QML” é legada; não copie aquele modelo.
2. **O niri não tem API de plugin.** A integração é por `niri msg` (IPC), `niri validate` e o `config.kdl` do usuário.
3. Plugins são **código confiável e sem sandbox**: podem ler/escrever arquivos, executar processos e acessar a rede como o usuário. Não instale plugin de origem desconhecida.
4. Confirme a API installada antes de usar recursos novos; a documentação web pode estar à frente do binário local.
5. **Cores e espaçamento seguem o sistema por padrão.** Só mude se o usuário pedir explicitamente — e, nesse caso, a mudança vira setting, não um valor fixo no código.

## Padrão visual obrigatório (cores e gap)

Vale para todo plugin criado ou alterado, sem exceção:

1. **Cores: só roles da paleta ativa** (`primary`, `on_surface`, `surface_variant`, `outline`, `error`, `hover`…) ou role com alfa (`primary/0.12`). Nunca hex fixo, nunca paleta própria no plugin. O tema do usuário (claro/escuro, paleta custom) já muda as roles sozinho.
2. **Gap: use os defaults do sistema.** Barra: `gap = 6` entre glifo e texto (o default do Noctalia para `capsule_padding`/`widget_spacing` é 6; a barra do usuário pode estar configurada com outro valor, mas o gap **interno** do widget não muda). Painel: `gap = 12` entre seções, `gap = 6` dentro de listas. Não invente 3, 9, 17…
3. **Não crie settings de cor ou espaçamento** por padrão. Só declare `type = "color"`/`int` quando o usuário pedir; o default do setting deve ser a role/valor padrão, nunca um hex.
4. **Translucidez**: `fill = "surface_variant/0.6"`, não `opacity` no container (opacity apaga também o texto).
5. **Exceção explícita**: se o usuário pedir "deixa roxo" ou "aumenta o gap", mude **só** aquilo, mantenha o resto no padrão e registre no README do plugin.

Tokens, tabela de roles e checklist: [`references/design.md`](references/design.md).

## Compatibilidade

```bash
noctalia --version
rpm -q noctalia
niri --version
niri msg --help
```

Neste desktop de referência: **Noctalia 5.3.0**, plugin API até **34**, niri **26.04**. A documentação oficial pode listar APIs 35–39 (idle, layers, OSD), mas o binário 5.3.0 não as aceita. Para um plugin novo aqui:

- use o **menor `plugin_api`** que cubra os recursos necessários;
- se usar recursos recentes, teste com `noctalia plugins lint` e com o plugin carregado;
- não use `[[layer]]` (API 36) nem `noctalia.idle` (API 35) sem atualizar o Noctalia.

O `plugin_api` é o nível **mínimo** exigido, não a versão do plugin nem a versão do Noctalia.

## Escolha as entradas

| Necessidade | Entrada | Comentário |
|---|---|---|
| Ícone/status na barra | `[[widget]]` | Clique, scroll, IPC, settings por instância. |
| Janela/pop-up com controles | `[[panel]]` | Tamanho no manifesto; foco de teclado; `ui.*`. |
| Processo em background | `[[service]]` | Sem UI; publica estado, HTTP/SSE, polling. |
| Overlay de tela cheia | `[[layer]]` | API 36; não disponível no 5.3.0. |
| Botão no control center | `[[shortcut]]` | Toggle/ação rápida. |
| Resultados no launcher | `[[launcher_provider]]` | Prefixo próprio, `onQuery`/`onActivate`. |
| Tile no desktop | `[[desktop_widget]]` | UI declarativa; posição é do usuário. |

Um plugin pode ter várias entradas compartilhando `noctalia.state`, settings e o mesmo ID.

## Estrutura

```text
meu-plugin/
├── plugin.toml
├── widget.luau
├── panel.luau
├── service.luau
├── translations/
│   ├── pt-BR.json
│   └── en.json
└── README.md
```

O nome do diretório deve ser a parte depois da `/` do `id` (ex.: `meu-plugin` para `me/meu-plugin`). Cada entrada é endereçada por `<author>/<plugin>:<entry-id>`.

## Fluxo de trabalho

1. **Defina o escopo**: quais entradas, o que é persistido, o que é efêmero, quais comandos do niri serão chamados.
2. **Crie o manifesto** com `id`, `name`, `version`, `plugin_api`, `author` e as entradas. Use `[[setting]]` apenas para configuração real — nunca para cor/gap sem pedido.
3. **Implemente os scripts** em Luau (`--!nonstrict`), com o topo inicializando estado e registrando watches. Use roles de cor e os gaps padrão (`references/design.md`).
4. **Adicione traduções** para toda `label_key`/`description_key` e para textos com `noctalia.tr`.
5. **Instale no diretório de plugins** para desenvolvimento; edite e deixe o hot reload agir.
6. **Rode o lint** e teste o fluxo real (IPC, painel, widget, reinício, config).
7. **Documente** no README do plugin o ID, entradas, settings, comandos IPC e requisitos.

## Manifesto mínimo

```toml
id = "me/hello"
name = "Hello"
version = "1.0.0"
plugin_api = 9
author = "me"
license = "MIT"
description = "Widget de exemplo."
icon = "puzzle"

[[widget]]
id = "hello"
entry = "widget.luau"

  [[widget.setting]]
  key = "label"
  type = "string"
  label_key = "settings.label.label"
  default = "Olá"
```

O manifesto completo, os tipos de setting e todas as opções de painel/widget estão em
[`references/manifest.md`](references/manifest.md).

## Widget declarativo mínimo

```lua
--!nonstrict
local label = noctalia.getConfig("label") or "Olá"

local function render()
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, {
    ui.glyph({ name = "puzzle", size = 16, color = "primary" }),
    ui.label({ text = label, maxLines = 1 }),
  }))
end

render()

function update()
  noctalia.setUpdateInterval(5000)
  render()
end

function onClick()
  noctalia.notify("Hello", "clique")
end

function onIpc(event, payload)
  if event == "set" then
    label = payload or label
    render()
  end
end
```

Para widgets simples, a API imperativa (`barWidget.setText`, `setGlyph`, `setTooltip`) também funciona. Não misture `render()` com `setText`/`setGlyph`: depois do `render()`, os setters não têm efeito visível.

## Serviço + estado + painel

```lua
-- service.luau
local n = 0
noctalia.setUpdateInterval(1000)

function update()
  n += 1
  noctalia.state.set("count", n)
end

function onIpc(event, payload)
  if event == "reset" then
    n = 0
    noctalia.state.set("count", n)
  end
end
```

```lua
-- panel.luau
local count = noctalia.state.get("count") or 0
local render

render = function()
  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.label({ text = "Contador: " .. tostring(count), fontSize = 16, fontWeight = "bold" }),
    ui.button({ text = "Resetar", variant = "secondary", onClick = function()
      noctalia.runAsync({ "noctalia", "msg", "plugin", "me/hello:service", "all", "reset" })
    end }),
  }))
end

noctalia.state.watch("count", function(value)
  count = value or 0
  render()
end)

function onOpen(_context)
  render()
end
```

O estado é **em memória** e compartilhado apenas entre entradas do mesmo plugin. Para persistir, grave JSON em `noctalia.pluginDataDir()`, nunca em `pluginDir()`.

## Regras de UI que mais quebram

- **Tamanho do painel é do host**: declare `width`/`height` no `[[panel]]`; não existe `setSize()` em runtime. `"fill"` só vale em painel flutuante.
- **Painel persistente** não aceita `ui.select`, exige `dismiss_on_outside_click = false` e rejeita `keyboard_focus = "exclusive"`.
- **Bar widget** não recebe teclado: `ui.input`, `ui.select` e `ui.scroll` são ignorados. Mantenha a árvore com a espessura de um controle e escolha `row`/`column` com `barWidget.isVertical()`.
- **Callbacks** recebem strings, inclusive toggle (`"true"`/`"false"`), slider e índice do select. Use `tonumber`/comparação explícita.
- **`ui.input` é não controlado**: `value` só semeia; mantenha `key` estável e leia via `onChange`/`onSubmit`.
- **Cores**: use roles (`primary`, `on_surface`, `surface_variant`) ou `role/alpha`; nunca hex fixo. Detalhes em [`references/design.md`](references/design.md).
- **Imagens**: `ui.image` só carrega arquivo local; baixe com `noctalia.download` antes.
- **Settings**: só chaves declaradas resolvem; `label_key`/`description_key` são obrigatórios e traduzidos.
- **`plugin_api`**: fechamentos em callbacks exigem 9; `runAsync` com argv exige 24; `frameVisible` exige 27; `revealKey` exige 33; `hover_highlight` exige 34.

Detalhes de cada controle: [`references/ui.md`](references/ui.md).

## Integração com niri

O padrão é: **serviço** coleta o estado com `niri msg --json ...`, publica em `noctalia.state`; o **widget** mostra; o **painel** envia ações com `niri msg action ...` ou `niri msg output ...`.

```lua
noctalia.runAsync({ "niri", "msg", "--json", "focused-output" }, function(result)
  if result.exitCode ~= 0 then
    noctalia.notifyError("niri", result.stderr)
    return
  end
  local output = noctalia.json.decode(result.stdout)
  noctalia.state.set("focused_output", output)
end, 5000)
```

- Use **argv** (`{ "niri", "msg", ... }`), não concatene strings de shell.
- `niri msg --json outputs|workspaces|windows|focused-output|focused-window|layers|overview-state` para leitura.
- `niri msg action ...` para ações; `niri msg output ...` para mudanças temporárias de monitor.
- `niri msg --json event-stream` para eventos; use `noctalia.runStream`.
- `niri validate` valida o KDL; mudanças de output via IPC **não** são persistidas.
- `NIRI_SOCKET` precisa estar disponível no ambiente do Noctalia.

Comandos, formatos JSON, exemplos e armadilhas: [`references/niri.md`](references/niri.md).

## Teste e depuração

```bash
# desenvolvimento: cópia no diretório de plugins (fonte local tem precedência)
cp -r meu-plugin ~/.local/share/noctalia/plugins/
noctalia plugins lint ~/.local/share/noctalia/plugins/meu-plugin
noctalia msg plugins enable me/meu-plugin

# abrir painel
noctalia msg panel-toggle me/meu-plugin:panel

# IPC de uma entrada
noctalia msg plugin me/meu-plugin:service all refresh
noctalia msg plugin me/meu-plugin:widget focused set "novo texto"
```

- Editar `.luau` faz hot reload; mudanças no `plugin.toml` exigem recarregar a configuração/plugin.
- Logs: `~/.cache/noctalia/noctalia.log`; filtre por `meu-plugin`.
- Use `noctalia.log()` dentro do script para diagnosticar.
- O lint verifica settings declarados × uso no código; ele **não** valida toda a semântica de UI.
- Manifesto com `plugin_api` acima do suportado é ignorado pelo host (`supported range is 3-34` no 5.3.0) e aparece como `incompatible` em `noctalia msg plugins list` — o lint não pega isso.
- Confira o tema nos dois modos (claro/escuro) e com a paleta do usuário: cores por role acompanham sozinhas; hex fixo quebra.
- Antes de concluir, teste também desabilitar/habilitar, reiniciar o Noctalia e abrir o painel pela CLI.

Checklist e empacotamento: [`references/testing.md`](references/testing.md).

## Referências internas

| Arquivo | Conteúdo |
|---|---|
| [`references/design.md`](references/design.md) | Padrão visual: 16 roles, alfa, gaps e checklist. |
| [`references/manifest.md`](references/manifest.md) | Manifesto, entradas, settings, painel/widget, API. |
| [`references/entries.md`](references/entries.md) | Callbacks, ciclo de vida, IPC, módulos e cada tipo de entrada. |
| [`references/ui.md`](references/ui.md) | Controles `ui.*`, props, painéis, bar widget, DnD. |
| [`references/runtime.md`](references/runtime.md) | `noctalia.*`, estado, subprocessos, HTTP/SSE, arquivos, dados. |
| [`references/niri.md`](references/niri.md) | IPC/config do niri e padrão de integração. |
| [`references/testing.md`](references/testing.md) | Desenvolvimento, lint, logs, publicação e checklist. |
| [`references/search.md`](references/search.md) | Base de busca web e local para quando a API não estiver clara. |
| [`references/examples.md`](references/examples.md) | Plugins oficiais e exemplos locais para estudar. |
| [`examples/minimal-widget/`](examples/minimal-widget/) | Widget mínimo com settings e IPC. |
| [`examples/niri-panel/`](examples/niri-panel/) | Serviço + widget + painel consultando/acionando o niri. |
| [`examples/theme-probe/`](examples/theme-probe/) | Mostra as 16 roles da paleta e os valores efetivos do sistema. |

## Base de busca

Quando a documentação não bastar, siga esta ordem:

1. **Código local instalado**: `~/.local/share/noctalia/plugins/` (inclui `niri-displays` e `omyfedora-ai-chat`).
2. **Docs oficiais v5**: <https://docs.noctalia.dev/noctalia/plugins/development/>.
3. **Repositório oficial**: <https://github.com/noctalia-dev/official-plugins> (`example`, `screen_recorder`, `noctalia.d.luau`).
4. **Repositório da comunidade**: <https://github.com/noctalia-dev/community-plugins>.
5. **Fonte do Noctalia**: <https://github.com/noctalia-dev/noctalia>.
6. **Niri**: <https://yalter.github.io/niri/> e <https://github.com/YaLTeR/niri/wiki/IPC>.

Consultas úteis:

```text
site:docs.noctalia.dev/noctalia/plugins "panel.render"
site:github.com/noctalia-dev "noctalia.state.watch"
site:github.com/noctalia-dev/official-plugins "runAsync" "niri"
```

```bash
gh search code 'panel.render' --repo noctalia-dev/official-plugins
gh search code 'niri msg --json' --repo noctalia-dev/community-plugins
grep -RIn 'barWidget.render\|panel.render\|noctalia.state' ~/.local/share/noctalia/plugins
```

Não copie exemplos da documentação **v4 (Quickshell/QML)**. Se a API parecer diferente, confira a versão instalada e o `noctalia.d.luau` do repositório oficial.

## Definição de pronto

- [ ] `noctalia plugins lint` sem erros.
- [ ] **Cores só por role** (nenhum hex fixo) e **gaps nos valores padrão** — ou a exceção pedida pelo usuário está registrada no README.
- [ ] Plugin habilita/desabilita e recarrega sem erro no log.
- [ ] Widget aparece na barra e responde a clique/scroll/IPC previstos.
- [ ] Painel abre pela CLI e pelos controles; fecha corretamente.
- [ ] Settings alteram o comportamento e são lidos após reload.
- [ ] Serviço não vaza processos/streams; `onExit` limpa o que for necessário.
- [ ] Comandos do niri usam argv e têm erro/validação.
- [ ] `README.md` do plugin documenta ID, entradas, settings e IPC.
