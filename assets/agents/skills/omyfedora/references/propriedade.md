# Quem é dono de cada arquivo

O omyfedora separa o que é **do usuário** (nunca sobrescrito) do que é **do projeto** (atualizado, com backup).

| Tipo | Exemplos | Política do omyfedora | Você pode editar? |
|---|---|---|---|
| Config pessoal | `~/.config/niri/config.kdl`, `~/.config/noctalia/config.toml`, `~/.zshrc`, `~/.config/alacritty/alacritty.toml`, `~/.config/zed/*` | Instalada uma vez, nunca sobrescrita | **Sim**, com confirmação |
| Config do projeto | `/etc/xdg/niri/config.kdl`, tema GTK/dconf, `/etc/profile.d/omyfedora-*`, wallpapers, helpers em `/usr/local/` | Atualizada a cada instalação (backup `.omyfedora-bak`) | **Não** |
| Estado da GUI | `~/.local/state/noctalia/settings.toml`, plugins | Instalado só se ausente | Prefira a GUI |
| Paleta do tema | `~/.config/noctalia/palettes/macOS.json` | Atualizada com backup | **Não**; crie outra paleta |
| Módulos SELinux | `assets/selinux/*.cil` | Instalados via `semodule` | **Nunca** |
| Esta skill | `~/.agents/skills/omyfedora/*` | Atualizada pelo instalador, **exceto** `references/local.md` | Só `references/local.md` (o usuário) |

## Consequências práticas

- Se você editar um arquivo "do projeto", a próxima execução do instalador desfaz a mudança. Faça a mudança na camada do usuário.
- Se o usuário quer algo **permanente** que o projeto sobrescreve, diga isso e proponha o caminho correto (por exemplo, outra paleta, ou configuração no `config.toml`).
- Backups do projeto ficam ao lado do arquivo como `.omyfedora-bak`. Os **seus** backups ficam em `~/.local/state/omyfedora/agent-backups/` (ver `seguranca.md`).
