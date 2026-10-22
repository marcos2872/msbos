# Padrão visual — cores e espaçamento

Regra da skill: **o plugin segue a paleta e o espaçamento do sistema**. Cor e gap diferentes só
quando o usuário pedir, e a exceção fica explícita (setting + README), nunca escondida no código.

Fontes: documentação oficial v5 (`Palette`, `Bar`, `Declarative UI`) e o binário instalado.

## Cores: só roles da paleta

`ui.*` aceita um **role** (`primary`), um **role com alfa** (`primary/0.6`) ou hex
(`#rrggbb`/`#rrggbbaa`). Use role. O tema claro/escuro e a paleta do usuário mudam sozinhos; hex
fixo quebra a integração com o tema.

As 16 roles são `snake_case`:

| Role | Uso |
|---|---|
| `primary` | Acento: ícone de destaque, item ativo, botão primário. |
| `on_primary` | Texto/ícone sobre `primary`. |
| `secondary` | Acento secundário. |
| `on_secondary` | Texto/ícone sobre `secondary`. |
| `tertiary` | Acento terciário; use pouco. |
| `on_tertiary` | Texto/ícone sobre `tertiary`. |
| `error` | Falha, estado inválido, ação destrutiva. |
| `on_error` | Texto/ícone sobre `error`. |
| `surface` | Fundo principal do shell. |
| `on_surface` | Texto/ícone padrão. |
| `surface_variant` | Fundo secundário: cards, chips, linhas de lista. |
| `on_surface_variant` | Texto secundário (legendas, unidades, metadados). |
| `outline` | Bordas, separadores, contornos. |
| `shadow` | Sombra. |
| `hover` | Fundo de hover. |
| `on_hover` | Texto/ícone sobre `hover`. |

Padrões que funcionam:

```lua
ui.glyph({ name = "cpu", color = "primary" })                  -- destaque
ui.label({ text = "42%", color = "on_surface" })               -- texto padrão
ui.label({ text = "de 24 GiB", color = "on_surface_variant" }) -- legenda
ui.row({ fill = "surface_variant/0.5", radius = 10 })          -- cartão translúcido
ui.label({ text = erro, color = "error" })                     -- falha
```

- **Translucidez**: `fill = "surface_variant/0.6"`. `opacity` é opacidade de grupo — apaga o
  texto junto.
- **Hex só quando o valor não é do tema** (ex.: cor de uma série de gráfico vinda de dado
  externo). Ainda assim, prefira `noctalia.getColor("primary")` (API 31) para acompanhar a paleta.
- **Não crie paleta própria** no plugin, nem tabela de hex “bonita”. Se o usuário quiser uma cor
  diferente para o desktop inteiro, a mudança é na paleta do Noctalia, não no plugin.
- Fundo de painel/cartão: `surface_variant` ou `surface_variant/0.6`; nunca `#000000`. O painel já
  tem fundo/glass do host — não pinte o `ui.column` raiz, só cartões e linhas.
- Contraste: texto sobre `primary`/`error`/`tertiary` usa `on_*` correspondente.

## Espaçamento: tokens padrão

Valores padrão do Noctalia (documentados em `Bar`) e adotados por esta skill:

| Token | Valor | Onde |
|---|---|---|
| `padding` da barra | 14 | Host; não compense dentro do widget. |
| `widget_spacing` da barra | 6 | Host: distância **entre** widgets. |
| `capsule_padding` | 6 | Host: padding interno do capsule do widget. |
| `capsule_radius` | 8 | Host (auto-pílula quando omitido). |
| `radius` da barra | 12 | Host. |

Dentro do plugin:

| Situação | Valor |
|---|---|
| Bar widget: `gap` entre glifo e texto | `6` |
| Bar widget: `align` | `"center"` (e `ui.column` quando `barWidget.isVertical()`) |
| Painel: `gap` entre seções | `12` |
| Painel: `gap` de lista (`ui.scroll`/`ui.column`) | `6` |
| Linha clicável: `paddingH` / `paddingV` | `10` / `8` |
| Linha interna (ícone + texto + botão): `gap` | `8` |
| Linha clicável / chip: `radius` | `10` |
| Cartão/seção: `radius` | `12` |
| `ui.separator` | `spacing` padrão (0) |
| Título de painel: `fontSize` | `16`, `fontWeight = "bold"` |
| Legenda: `fontSize` | `10`–`11`, `color = "on_surface_variant"` |
| Glifo: `size` | `16` na barra, `18` no cabeçalho do painel |
| Controles | `controlSize` `md` (padrão); `sm` só em painel denso |

- **A barra é do host**: espessura, padding e espaçamento entre widgets vêm da config do usuário.
  Não adicione padding compensatório no widget nem tente “corrigir” o tamanho da barra.
- **Tamanho do painel** é declarado no `[[panel]]`; o conteúdo usa `flexGrow` + `ui.scroll`, não
  gaps gigantes para empurrar.
- Não use `gap = 0` para “colar” itens que precisam de respiro; 6 é o menor gap normal.

## Ler os valores efetivos (opcional, API 26)

Quando o plugin precisa se adaptar (ex.: mostrar o spacing real na UI), leia a config efetiva em
vez de repetir um número:

```lua
local spacing = noctalia.getSetting("bar.default.widget_spacing") -- 6 (ou o que o usuário pôs)
local thickness = noctalia.getSetting("bar.default.thickness")
local family = noctalia.getSetting("bar.default.font_family")     -- "" herda o global
local mode = noctalia.getSetting("theme.mode")                    -- "dark" | "light" | ...
local primary = noctalia.getColor("primary")                      -- "#RRGGBB" (API 31)
```

- Use para **exibir/adaptar**, não para sobrescrever o tema.
- `getSetting` exige `plugin_api = 26`; `getColor` exige `31`. Só suba o `plugin_api` se usar.
- Caminho inexistente gera warning e retorna `nil` — trate com fallback.
- `noctalia.isDarkMode()` só quando houver uma decisão real de layout; as roles já se adaptam.

## Quando o usuário pede diferente

1. Pergunte o alvo (uma cor? o gap do painel? a fonte?).
2. Exponha como **setting**, não como constante:
   - cor de um papel específico → `select` com as roles (`primary`, `secondary`, `tertiary`,
     `error`, `on_surface`) — o plugin continua seguindo o tema;
   - cor exata (pedido explícito de hex) → `type = "color"`;
   - espaçamento → `type = "int"`, `default` = token padrão, `min`/`max` razoáveis.
3. Aplique a exceção só no ponto pedido; o resto permanece no padrão.
4. Registre no `README.md` do plugin a setting e o default.

```toml
[[setting]]
key = "accent"
type = "select"
label_key = "settings.accent.label"
default = "primary"
options = [
  { value = "primary", label_key = "settings.accent.primary" },
  { value = "secondary", label_key = "settings.accent.secondary" },
  { value = "tertiary", label_key = "settings.accent.tertiary" },
]
```

```lua
local accent = noctalia.getConfig("accent") or "primary"
ui.glyph({ name = "star", color = accent })
```

## Checklist

- [ ] Nenhum hex no `.luau` nem no `plugin.toml` (a não ser exceção pedida e documentada).
- [ ] Cores só por role ou `role/alpha`.
- [ ] Fundo translúcido via `fill`, nunca `opacity` no container.
- [ ] Bar widget com `gap = 6`; painel com `12` entre seções e `6` em listas.
- [ ] Nenhum setting de cor/gap criado “por precaução”.
- [ ] Testado no tema escuro **e** claro (ou com a paleta do usuário).
