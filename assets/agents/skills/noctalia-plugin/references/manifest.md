# Manifesto e settings

Fontes: documentação oficial v5 (`Manifest & Settings`, `Plugin API Versions`) e o exemplo oficial `noctalia/example`. Confirme sempre a versão instalada com `noctalia --version` e `noctalia plugins lint`.

## Exemplo completo

```toml
id = "me/hello"
name = "Hello"
version = "1.0.0"
plugin_api = 9
author = "me"
license = "MIT"
description = "Widget e painel de exemplo."
icon = "puzzle"
tags = ["demo"]
dependencies = ["niri"] # metadados; não bloqueia a habilitação

# Plugin-level: compartilhado por todas as entradas.
[[setting]]
key = "interval"
type = "int"
label_key = "settings.interval.label"
description_key = "settings.interval.description"
default = 5
min = 1
max = 60

[[widget]]
id = "status"
entry = "bar.luau"

  # Widget-level: só esta instância do widget.
  [[widget.setting]]
  key = "glyph"
  type = "glyph"
  label_key = "settings.glyph.label"
  default = "puzzle"

  [widget.actions] # API 14; padrões, o usuário pode sobrescrever
  right = "settings-open-widget"

[[panel]]
id = "panel"
entry = "panel.luau"
width = 420
height = 340
placement = "floating"
position = "center"
open_near_click = false
dismiss_on_outside_click = true
keyboard_focus = "on_demand"
persistent = false

[[service]]
id = "worker"
entry = "service.luau"
```

## Campos de identidade

| Campo | Obrigatório | Regra |
|---|---|---|
| `id` | sim | `<author>/<plugin>`, globalmente único; o diretório deve ser a parte após `/`. |
| `name` | sim | Nome exibido. |
| `version` | sim | Semver `MAJOR.MINOR.PATCH`, sem prerelease/build. |
| `plugin_api` | sim | Inteiro; **menor** nível de API necessário. |
| `author` | sim | Autor/catalogador. |
| `license` | não | Padrão MIT quando omitido. |
| `deprecated` | não | Booleano; marca o plugin como obsoleto. |
| `icon` | não | Nome de glifo Tabler/Nerd-Font. |
| `description` | não | Texto curto para catálogo. |
| `tags` | não | Lista para busca no catálogo. |
| `dependencies` | não | Lista de ferramentas/pacotes externos; só metadados. |

`id`, `name`, `version` e `plugin_api` são obrigatórios. O lint e o host rejeitam manifesto inválido.

## Tipos de entrada

| Tabela | Uso | Chaves específicas |
|---|---|---|
| `[[widget]]` | Bar widget | `id`, `entry`, `hover_highlight` (API 34), `[widget.actions]` (API 14), `[[widget.setting]]`. |
| `[[panel]]` | Painel/pop-up | `id`, `entry`, `width`, `height`, `placement`, `position`, `open_near_click`, `dismiss_on_outside_click`, `keyboard_focus`, `persistent`, `capture_keys`, `layer`; `[[panel.setting]]`. |
| `[[service]]` | Processo headless | `id`, `entry`; sem UI. |
| `[[shortcut]]` | Tile do control center | `id`, `entry`; `shortcut.*` no script. |
| `[[launcher_provider]]` | Resultados no launcher | `id`, `entry`, `prefix`; opcionais `glyph`, `include_in_global_search`, `debounce_ms`. |
| `[[desktop_widget]]` | Tile no desktop | `id`, `entry`; `[[desktop_widget.setting]]`. |
| `[[layer]]` | Layer-shell do plugin (API 36) | `id`, `entry`, `layer`, `anchors`, `width`, `height`, `margins`, `exclusive_zone`, `keyboard`, `click_through`, `output`, `visible`. Não disponível no Noctalia 5.3.0. |

Cada `id` de entrada é único dentro do plugin. O ID completo para IPC/painel é `<author>/<plugin>:<entry>`.

## Painel

```toml
[[panel]]
id = "panel"
entry = "panel.luau"
width = 420          # px lógico ou "fill"
height = 340         # px lógico ou "fill"
placement = "floating" # attached | floating
position = "center"  # auto | center | âncora da tela
open_near_click = false
dismiss_on_outside_click = true
keyboard_focus = "on_demand" # on_demand | exclusive | none
persistent = false
```

| Chave | Observações |
|---|---|
| `width` / `height` | O host é dono do tamanho; não existe resize em runtime. `"fill"` exige `placement = "floating"`. |
| `placement` | `attached` ancora na borda da barra; `floating` é destacado. |
| `position` | `auto`, `center` ou âncora; só relevante em flutuante. |
| `open_near_click` | Abre perto do widget que chamou o painel. |
| `dismiss_on_outside_click` | Padrão `true`; use `false` para prompt de senha/API. API 8. |
| `keyboard_focus` | `on_demand` padrão; `exclusive` para busca/senha; `none` nunca recebe teclado (exige `dismiss_on_outside_click = false`). API 10. |
| `persistent` | Fora do slot de painéis; sempre flutuante, sem dismiss externo, sem `ui.select`, rejeita `keyboard_focus = "exclusive"`. API 11. |
| `capture_keys` | Lista de acordes entregues a `onKey`; API 13. |
| `layer` | `top` (padrão) ou `overlay`; API 30; só flutuante. |

O host injeta settings `position`, `placement`, `open_near_click` e `layer` mesmo que o manifesto não os declare. O usuário pode sobrescrever em Settings → Plugins ou no `settings.toml`:

```toml
[plugin_settings."me/hello"]
panel_placement = "floating"
panel_position  = "bottom_left"
panel_layer     = "overlay"
```

Não declare cor nem espaçamento como setting “por precaução”: o padrão é seguir o tema e os gaps do sistema (`references/design.md`).

## Widget

```toml
[[widget]]
id = "status"
entry = "bar.luau"
hover_highlight = false # API 34; desliga o tint do capsule inteiro

  [widget.actions]
  right = "media toggle"
  scroll_up = "volume-up"
```

- Gestos: `left`, `right`, `middle`, `back`, `forward`, `scroll_up`, `scroll_down`, `scroll_left`, `scroll_right`.
- Ação: comando IPC, `exec <linha de comando>` ou `none`.
- Binding do usuário vence o callback do script.
- `middle` tem binding padrão para abrir settings; declare `middle = "none"` se quiser `onMiddleClick`.
- `hover_highlight = false` deve ficar antes de `[widget.actions]`.

## Settings

Escopos:

- `[[setting]]`: plugin-level, compartilhado por todas as entradas.
- `[[widget.setting]]`: só aquela instância de widget.
- `[[panel.setting]]`: settings do painel, exibidos no gear do plugin.
- `[[desktop_widget.setting]]`: settings daquele tile.
- `[[layer.setting]]`: **não existe**; use plugin-level.

| Tipo | Valor/observação |
|---|---|
| `string` | Texto. |
| `string_list` | Lista de strings. |
| `string_map` | Mapa string→string; API 6. |
| `bool` | Booleano. |
| `int` | Inteiro; `min`/`max`. |
| `double` | Decimal; `min`/`max`. |
| `select` | `options = [{ value, label_key }]`; ambos obrigatórios. |
| `file` | Caminho; `extensions` opcional. |
| `folder` | Pasta. |
| `glyph` | Nome de glifo. |
| `color` | Cor. |

Campos comuns: `key`, `type`, `label_key` (obrigatório), `description_key`, `default`, `min`, `max`, `options`, `extensions`, `visible_when = { key = "...", values = ["true"] }`, `advanced = true`.

Somente chaves declaradas resolvem em `noctalia.getConfig(key)`. Chave não declarada gera warning e `nil`. Settings de widget vencem plugin-level quando a mesma chave existe.

## Traduções

`translations/<lang>.json` é um objeto **achatado** com chaves pontuadas:

```json
{
  "settings.interval.label": "Intervalo",
  "settings.interval.description": "Segundos entre atualizações.",
  "panel.title": "Status do niri",
  "panel.refresh": "Atualizar"
}
```

- Toda `label_key`/`description_key` precisa existir pelo menos em `en.json`.
- No script: `noctalia.tr("panel.title")`, `noctalia.tr("welcome", { name = "Ana" })`, `noctalia.trp("items", count)`.
- `tr` cai para a própria chave se faltar tradução.

## Compatibilidade e lint

```bash
noctalia --version
noctalia plugins lint ~/.local/share/noctalia/plugins/meu-plugin
```

- O lint cruza settings declarados com `noctalia.getConfig` no código.
- Ele não valida toda a semântica de UI; teste o plugin carregado.
- No 5.3.0, `plugin_api` acima de 34 é rejeitado (verificado: `supported range is 3-34`); o
  plugin aparece como `incompatible` em `noctalia msg plugins list` e o lint **não** acusa. A
  documentação lista 35–39 como “Unreleased”.
- Use o menor nível que cubra o que o plugin usa. Isso mantém compatibilidade com versões anteriores.

## Catálogo e publicação

Um repositório de plugins usa um `catalog.toml` na raiz:

```toml
[[plugin]]
id = "me/hello"
name = "Hello"
version = "1.0.0"
author = "me"
license = "MIT"
icon = "puzzle"
description = "Widget de exemplo."
plugin_api = 9
tags = ["demo"]
```

Para a store da comunidade, o plugin precisa de `README.md`, `thumbnail.webp`, `translations/en.json` e passar no CI de `noctalia-dev/community-plugins`.
