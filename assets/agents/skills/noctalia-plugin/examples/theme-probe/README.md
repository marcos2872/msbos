# Theme Probe

Exemplo de referência do **padrão visual** da skill: cores só por role da paleta e gaps nos
tokens do sistema. Também serve para conferir, na máquina do usuário, quais cores e valores
de barra o Noctalia está usando de verdade.

## O que mostra

- **Widget**: glifo `palette` na role `primary`, label e o `bar.default.widget_spacing` efetivo.
- **Painel**: as 16 roles da paleta com amostra (`ui.box` com `fill = role`) e hex via
  `noctalia.getColor` (API 31); abaixo, `widget_spacing`, `thickness`, `padding`, `radius`,
  `font_family` e o output focado via `noctalia.getSetting` (API 26).
- **Serviço**: lê tudo e publica em `noctalia.state`, sem polling agressivo.

## Uso

```bash
cp -r . ~/.local/share/noctalia/plugins/me-theme-probe
noctalia plugins lint ~/.local/share/noctalia/plugins/me-theme-probe
noctalia msg plugins enable me/theme-probe
```

Adicione `me/theme-probe:bar` em **Settings → Bar → Widgets** e clique no widget para abrir o
painel (ou `noctalia msg panel-toggle me/theme-probe:panel`).

## Por que `plugin_api = 31`

`getColor` exige 31; `getSetting` exige 26. Use o menor nível que cubra o que o plugin chama.

## Personalização

- Troque `id`, `name`, `author` e `version` antes de publicar.
- O painel lê `show_hex` (setting plugin-level) para esconder os hex.
- Repare que não há nenhum `#rrggbb` no código: as cores vivem na paleta do Noctalia.
