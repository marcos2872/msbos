# Minimal Widget

Widget declarativo de exemplo para Noctalia v5.

## Uso

```bash
cp -r . ~/.local/share/noctalia/plugins/meu-hello
noctalia plugins lint ~/.local/share/noctalia/plugins/meu-hello
noctalia msg plugins enable me/minimal-widget
```

Adicione `me/minimal-widget:hello` em **Settings → Bar → Widgets**.

## IPC

```bash
noctalia msg plugin me/minimal-widget:hello focused set "Olá"
noctalia msg plugin me/minimal-widget:hello focused reset
```

## Personalização

- Troque `id`, `name`, `author` e `version` em `plugin.toml`.
- O diretório deve ser a parte após `/` do id (`me/minimal-widget` → `minimal-widget`).
- `plugin_api = 9` cobre `barWidget.render` com closures; reduza apenas se souber que o recurso existe em versões anteriores.
