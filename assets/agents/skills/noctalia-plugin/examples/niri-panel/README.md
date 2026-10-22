# Niri Panel

Plugin de exemplo com serviço, widget e painel:

- o serviço consulta `niri msg --json focused-output` e `workspaces`;
- o widget mostra o output e o workspace focados;
- o painel lista os workspaces e chama `niri msg action focus-workspace`.

## Uso

```bash
cp -r . ~/.local/share/noctalia/plugins/meu-niri-panel
noctalia plugins lint ~/.local/share/noctalia/plugins/meu-niri-panel
noctalia msg plugins enable me/niri-panel
noctalia msg panel-toggle me/niri-panel:panel
```

Adicione `me/niri-panel:bar` em **Settings → Bar → Widgets**.

## IPC

```bash
noctalia msg plugin me/niri-panel:niri all refresh
```

## Requisitos

- Sessão niri ativa (`NIRI_SOCKET`).
- `niri` no `PATH` do Noctalia.

## Personalização

- Troque `id`, `name`, `author`, `version` e o diretório.
- `plugin_api = 24` cobre `runAsync` com argv; reduza se usar apenas APIs antigas.
- O painel usa `me/niri-panel:niri` hardcoded; ajuste ao trocar o id.
- `niri msg output` (não usado aqui) é temporário; persistência exige editar o `config.kdl` do usuário.
