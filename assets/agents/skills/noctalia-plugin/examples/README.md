# Exemplos

- `minimal-widget/` — widget declarativo mínimo, settings, IPC.
- `niri-panel/` — serviço + widget + painel que consultam e acionam o niri.
- `theme-probe/` — mostra as 16 roles da paleta e os valores efetivos do sistema.

Todos seguem o padrão visual da skill: cores só por role e gaps nos tokens do sistema
(`references/design.md`).

Copie o diretório para `~/.local/share/noctalia/plugins/`, ajuste `id`/`author`/nome e rode:

```bash
noctalia plugins lint <diretório-instalado>
noctalia msg plugins enable <author/plugin>
```
