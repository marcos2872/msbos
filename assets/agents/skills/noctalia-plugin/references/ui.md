# UI declarativa (`ui.*`)

Painéis, desktop widgets, layers e bar widgets declarativos descrevem a UI como uma árvore `ui.*`:

```lua
panel.render(ui.column({ gap = 12 }, {
  ui.label({ text = "Título", fontSize = 16, fontWeight = "bold" }),
  ui.button({ text = "OK", variant = "primary", onClick = "onOk" }),
}))
```

O host faz diff da árvore e atualiza os controles nativos. Uma árvore igual é barata; uma árvore nova substitui a anterior. Use `key` em listas para preservar identidade, foco e handlers.

## Layout e cores

- `ui.column` / `ui.row` / `ui.scroll` esticam os filhos no eixo cruzado por padrão; use `align` para mudar.
- `flexGrow` distribui o eixo principal; `ui.spacer({ flexGrow = 1 })` empurra.
- `padding`, `paddingH`, `paddingV`, `gap`, `minWidth`, `minHeight`, `radius`, `border`, `borderWidth`.
- `fill`: role (`surface_variant`), role com alfa (`primary/0.12`) ou hex (`#rrggbb` / `#rrggbbaa`).
- `align` (`start`/`center`/`end`/`stretch`) no eixo cruzado; `justify` (`start`/`center`/`end`/`space_between`) no eixo principal.
- `opacity` é opacidade de grupo (afeta filhos). Para fundo translúcido com texto opaco, use `fill` com alfa.
- `onClick` em `row`/`column`/`box`/`image` transforma o container em alvo clicável; um filho interativo consome o próprio clique.
- `onHover(state, key)` e `tooltip` em `box`, `row`, `column`, `image` (tooltip: API 32) e `button`.
- **Cores**: só roles da paleta — a lista completa das 16 e os tokens de espaçamento estão em
  [`design.md`](design.md). Resumo: `primary`, `on_primary`, `secondary`, `on_secondary`,
  `tertiary`, `on_tertiary`, `error`, `on_error`, `surface`, `on_surface`, `surface_variant`,
  `on_surface_variant`, `outline`, `shadow`, `hover`, `on_hover`; alfa com `role/0.6`.

## Controles

| Construtor | Principais props |
|---|---|
| `ui.column` / `ui.row` | layout, `onClick`, `onHover`, `tooltip`, `key`. |
| `ui.scroll` | layout de coluna + `fill`, `radius`, `border`, `borderWidth`, `stickToBottom`, `onScroll`, `scrollToBottomRev` (API 21), `revealKey` (API 33). |
| `ui.label` | `text`, `fontSize`, `color`, `fontWeight`, `fontFamily`, `baseline`, `maxWidth`, `maxLines`, `textAlign`. |
| `ui.markdown` | `text`, `width`, `height`; read-only; API 21. |
| `ui.glyph` | `name` (Tabler/Nerd-Font), `size`, `color`. |
| `ui.image` | `path` local/`~`/absoluto, `width`, `height`, `fit`, `radius`, `border`, `borderWidth`, `onHover`, `tooltip`, `onClick`. |
| `ui.box` | `fill`, `radius`, `border`, `borderWidth`, `softness`, `width`, `height`, `onHover`, `tooltip`, `onClick`. |
| `ui.separator` | `thickness`, `color`, `spacing`, `orientation`. |
| `ui.spacer` | `flexGrow`. |
| `ui.progress` | `progress` 0–1, `fill`, `track`, `radius`, `width`, `height`. |
| `ui.button` | `text`, `glyph`, `fontSize`, `glyphSize`, `variant`, `contentAlign`, `controlSize`, `tooltip`, `enabled`, `selected`, `onHover`, `onClick`, `onRightClick`. |
| `ui.graph` | `values`/`values2` (0–1), `color`/`color2`, `lineWidth`, `fillOpacity`, `width`, `height`, pointer callbacks (API 29). |
| `ui.toggle` | `checked`, `enabled`, `onChange`. |
| `ui.slider` | `min`, `max`, `step`, `value`, `controlSize`, `enabled`, `onChange`, `onDragEnd`. |
| `ui.select` | `options` (strings), `selectedIndex` (0-based), `placeholder`, `controlSize`, `enabled`, `onChange(index, text)`. |
| `ui.input` | `value` (seed), `placeholder`, `fontSize`, `controlSize`, `password`, `multiline`, `submitOnEnter`, `frameVisible`, `focus`, `enabled`, `onChange`, `onSubmit`. |
| `ui.dragSource` | `dragType`, `payload`, `previewAncestor`, `liftFromLayout`, `grabCursor`, `onClick` (API 38 em barras). |
| `ui.dropZone` | `accepts`, `value`, `onDrop`, `direction`, `expandOnDrag`, `hitSlop`. |

Todo controle aceita `width`, `height`, `flexGrow`, `opacity`, `visible` e `key`. Um prop/controle desconhecido é registrado no log e ignorado.

## Tamanhos e variantes

- `controlSize`: `sm` 32 px, `md` 38 px (padrão), `lg` 44 px. `height` explícito vence.
- `ui.button.variant`: `default`, `primary`, `secondary`, `destructive`, `outline`, `ghost`.
- `ui.glyph.size`: pixels do glifo (não confundir com `controlSize`).
- `ui.button` na barra é compacto e abraça o conteúdo; use `width`/`height`/`controlSize` se precisar.

## Callbacks

Um callback é o **nome de uma função global** do script ou uma **closure** (API 9). Os argumentos chegam como **strings**, inclusive:

- toggle: `"true"` / `"false"`;
- slider: número em string;
- select: índice em string + texto;
- input: texto;
- `onScroll`: offset/maxOffset em strings;
- `onFrameTick`: `deltaMs` em string (use `tonumber`).

```lua
function onToggle(value)
  enabled = value == "true"
  render()
end

ui.toggle({ checked = enabled, onChange = "onToggle" })

ui.select({
  options = { "Escuro", "Claro" },
  selectedIndex = theme,
  onChange = function(index, _text)
    theme = tonumber(index) or 0
    render()
  end,
})
```

Closures capturam a renderização atual; re-renderizar substitui os handlers. Use `key` em linhas de lista para que o handler certo continue associado ao item.

## `ui.input` (não controlado)

- `value` só **semeia** o campo; depois o host é dono do texto.
- Mantenha um `key` estável para preservar o que o usuário digitou.
- Leia com `onChange` (ao digitar) e `onSubmit` (Enter).
- `multiline = true`: Enter quebra linha e `onSubmit` é Ctrl+Enter.
- `submitOnEnter = true`: Enter envia e Shift+Enter quebra linha (com API 21).
- `frameVisible = false`: esconde fundo/borda nativos (API 27).
- `focus = true`: foca apenas quando o controle é **criado**; troque a `key` para focar de novo.
- `password` e `multiline` são mutuamente exclusivos.

## `ui.scroll`

- Só em painéis e desktop widgets. A barra **ignora** `ui.scroll` (sem foco de teclado).
- `stickToBottom = true` mantém no fim até o usuário rolar para cima.
- `onScroll(offset, maxOffset)` recebe strings.
- `scrollToBottomRev` força o fim quando o número muda (API 21).
- `revealKey` traz um filho com aquela `key` para a área visível (API 33).

## Painel

- `panel.render(tree)`; `panel.close()`.
- O tamanho é declarado no `[[panel]]`; não existe `setSize`.
- `placement = "floating"` permite `height = "fill"`; `attached` ancora na barra.
- `persistent = true` não aceita `ui.select` e exige `dismiss_on_outside_click = false`.
- `keyboard_focus`: `on_demand` (padrão), `exclusive` (busca/senha) ou `none`.
- `capture_keys` + `onKey` para teclas específicas; Escape sempre fecha.
- `panel.setWantsSecondTicks(true)` → `update()` por segundo; `panel.setNeedsFrameTick(true)` → `onFrameTick(deltaMs)` por frame (API 18).
- `panel.openContextMenu` só em `onRightClick` de `ui.button` (API 28).

## Bar widget

- Use `barWidget.render(container(...))`; escolha `row`/`column` conforme `barWidget.isVertical()`.
- A barra não tem foco de teclado: `ui.input`, `ui.select` e `ui.scroll` são ignorados.
- A altura é a espessura da barra; mantenha um controle de altura.
- Botões inline consomem o próprio clique; o `onClick` do widget ainda recebe cliques no restante do capsule.
- `barWidget.render` substitui o glifo/texto; não use setters depois.

## Drag and drop

- `ui.dragSource` e `ui.dropZone` em painéis (API 5) e bar widgets (API 38).
- O host cuida do ponteiro, ghost, destaque e captura; o script só recebe `onDrop(payload, value)`.
- `dragType`/`payload` são strings; `accepts` é lista de dragTypes.
- `previewAncestor = 1` mostra a linha ao redor de um grip; `liftFromLayout` remove a linha enquanto arrasta.
- `expandOnDrag` e `hitSlop` facilitam zonas finas.
- Nada muda sozinho: muta o modelo no callback e re-renderiza.

## Imagens e markdown

- `ui.image` só carrega **arquivo local**; baixe com `noctalia.download(url, dest, cb)` antes.
- `ui.markdown` renderiza headings/listas/código/tabelas; é read-only e re-parseia quando o texto muda (API 21).
- Para streaming de texto, re-renderize com o texto acumulado; não crie um markdown por delta sem parar.

## Erros comuns

| Sintoma | Causa |
|---|---|
| Controle não aparece | Prop/controle desconhecido ou API acima da instalada; veja o log. |
| Barra ignora input/select/scroll | Sem foco de teclado na barra; use painel. |
| Texto do input “volta” | Você está tratando `ui.input` como controlado; use `onChange` + `key`. |
| Select não abre em painel persistente | Não suportado; use botões/lista. |
| Painel corta conteúdo | Tamanho é do manifesto; use `ui.scroll` e `flexGrow`. |
| Conteúdo desenha por cima da seção seguinte | A árvore passou da altura do painel; ponha cada lista num `ui.scroll({ flexGrow = 1 })` e/ou aumente `height` no manifesto. |
| Clique do filho dispara o pai | Filho interativo deve consumir o clique; verifique a hierarquia e `onClick`. |
| Loop de render | Não chame `render()` dentro de `onHover`/`onChange` sem mudar estado; evite renders em cascata. |
