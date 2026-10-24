# Base de busca

Use esta referência quando a API, o comportamento ou a versão não estiverem claros. **Não invente** funções, props ou campos: confirme em uma fonte oficial ou no código instalado.

## Ordem de confiança

1. **Código local instalado** — a versão que está rodando de verdade.
2. **Documentação oficial v5** — declarações e exemplos.
3. **Repositório oficial `official-plugins`** — exemplos completos e `noctalia.d.luau`.
4. **Fonte do Noctalia** — implementação, se a doc divergir.
5. **Comunidade** — ideias, mas valide com a API local.

## Fontes locais

```bash
noctalia --version
rpm -q noctalia
niri --version
niri msg --help

find ~/.local/share/noctalia/plugins -maxdepth 2 -name plugin.toml -print
find ~/.local/share/noctalia/plugins -maxdepth 2 -type f -name '*.luau' -print | head -40
```

Plugins locais de referência:

- `~/.local/share/noctalia/plugins/niri-displays/` — widget + painel + serviço + IPC do niri.
- `~/.local/share/noctalia/plugins/msbos-ai-chat/` — painel complexo, SSE, formulários, serviço, settings, tamanho de painel.

Busca no código local:

```bash
grep -RIn 'barWidget.render\|panel.render\|noctalia.state' ~/.local/share/noctalia/plugins
grep -RIn 'ui.input\|ui.select\|ui.scroll' ~/.local/share/noctalia/plugins
grep -RIn 'niri msg' ~/.local/share/noctalia/plugins
```

## Documentação oficial (v5)

- Visão geral: <https://docs.noctalia.dev/noctalia/plugins/development/>
- Manifesto/settings: <https://docs.noctalia.dev/noctalia/plugins/development/manifest/>
- Entry scripts: <https://docs.noctalia.dev/noctalia/plugins/development/entries/>
- UI declarativa: <https://docs.noctalia.dev/noctalia/plugins/development/declarative-ui/>
- Runtime API: <https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/>
- Versões de API: <https://docs.noctalia.dev/noctalia/plugins/development/plugin-api/>
- Workflow/publicação: <https://docs.noctalia.dev/noctalia/plugins/development/workflow/>
- Usando plugins: <https://docs.noctalia.dev/noctalia/plugins/>
- Plugins oficiais: <https://docs.noctalia.dev/noctalia/plugins/official-plugins/>

> A página “Noctalia Shell Legacy v4” é QML/Quickshell. **Não use** para um plugin v5.

## Repositórios

- `official-plugins`: <https://github.com/noctalia-dev/official-plugins>
  - `example/` — widget, painel, serviço, shortcut, launcher, DnD e layer.
  - `screen_recorder/` — plugin real com serviço e UI.
  - `timer/` — serviço + widget + painel + desktop widget.
  - `wallhaven/` — painel com rede/download/wallpaper.
  - `noctalia.d.luau` — declaração de tipos de toda a API.
- `community-plugins`: <https://github.com/noctalia-dev/community-plugins>
- Noctalia: <https://github.com/noctalia-dev/noctalia>
- Niri: <https://github.com/YaLTeR/niri>
- Niri IPC: <https://github.com/YaLTeR/niri/wiki/IPC>
- Niri config: <https://yalter.github.io/niri/Configuration%3A-Introduction.html>

## Consultas web

Use a ferramenta de busca web com consultas específicas:

```text
site:docs.noctalia.dev/noctalia/plugins/development "plugin_api"
site:docs.noctalia.dev/noctalia/plugins/development "panel.render"
site:docs.noctalia.dev/noctalia/plugins/development "ui.select"
site:github.com/noctalia-dev/official-plugins "noctalia.state.watch"
site:github.com/noctalia-dev/official-plugins "runAsync" "niri"
site:github.com/noctalia-dev/community-plugins "panel.render"
```

Com GitHub CLI:

```bash
gh search code 'panel.render' --repo noctalia-dev/official-plugins
gh search code 'noctalia.state.watch' --repo noctalia-dev/official-plugins
gh search code 'niri msg --json' --repo noctalia-dev/official-plugins
gh search code 'ui.dragSource' --repo noctalia-dev/community-plugins
```

Se precisar do arquivo de tipos:

```bash
curl -fsSL https://raw.githubusercontent.com/noctalia-dev/official-plugins/main/noctalia.d.luau \
  -o noctalia.d.luau
```

Adicione `noctalia.d.luau` ao `luau-lsp` para autocomplete; ele é apenas tipos, não runtime.

## Como decidir se uma API existe

1. Rode `noctalia --version`.
2. Consulte `plugin_api` no manifesto e a página `plugin-api`.
3. Confira a função no `noctalia.d.luau` do repositório.
4. Procure no código local:
   ```bash
   grep -RIn 'noctalia\.minhaFuncao' ~/.local/share/noctalia/plugins
   ```
5. Teste em um plugin descartável e veja o log.
6. Se a doc mostrar API 35–39 e o binário for 5.3.0, trate como indisponível.

## Como decidir se uma prop de UI existe

1. Consulte `references/ui.md` ou a página `declarative-ui`.
2. Confira `noctalia.d.luau` (os tipos de props são exaustivos).
3. Se o log disser “unknown prop”, a prop não existe naquela versão.
4. Não assuma que uma prop de painel funciona na barra; barra tem restrições.

## Niri

```bash
niri msg --help
niri msg action --help
niri msg --json focused-output
niri msg --json workspaces
niri validate
```

Não use `niri msg action quit` nem altere outputs/monitores sem confirmação. Mudanças de output via IPC são temporárias.

## Sinais de informação desatualizada

- Exemplos com `PluginApi`, `QML`, `Quickshell`, `NIcon`, `NText` → v4 legado.
- `permissions`/`permission` do OpenCode não são API do Noctalia.
- `plugin_api` maior que o suportado pelo binário instalado.
- Campos que não aparecem no `noctalia.d.luau` nem no código local.
- Tutoriais antigos que usam `label` em vez de `label_key` em settings.

Quando houver conflito, **o binário instalado + lint + log** vencem a documentação web.
