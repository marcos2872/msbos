# Migração para o msbos

Este documento vale para quem já tem uma instalação chamada **omyfedora** ou
**MyOS** e quer passá-la para o **msbos** sem reinstalar o Fedora.

## O que acontece

O `install.sh` ganhou duas etapas de migração:

- `scripts/00-migrate-names.sh` — roda antes de tudo. Desabilita units antigas
  (sem parar a sessão), move estados e configurações que o instalador não
  sobrescreve e ajusta caminhos em arquivos do usuário. Nada é apagado.
- `scripts/99-cleanup-legacy.sh` — roda no fim, depois que os arquivos novos já
  existem. Remove os binários, units, políticas, tema Plymouth e diretórios
  antigos. Os backups são movidos para
  `/var/backups/msbos-migration/legacy-*` ou
  `~/.local/state/msbos/migration-backups/legacy-*`.

Em uma instalação nova as duas etapas não fazem nada.

## Como migrar

```bash
# 1. simule e leia a saída
./install.sh --dry-run

# 2. aplique; --yes autoriza a limpeza dos artefatos antigos
sudo ./install.sh --yes

# 3. reinicie para valer greetd, Plymouth e as units
sudo reboot

# 4. confira
msbos-doctor --strict
```

Sem `--yes`, a instalação nova é aplicada, mas a limpeza dos nomes antigos fica
pendente; rode de novo com `--yes` quando quiser concluir.

## O que é preservado

- `/etc/msbos/allowed-units.list` e `protected.list`;
- `/var/log/msbos/actions.log` (a trilha antiga é anexada);
- wallpapers em `~/.config/msbos-walls/` e `/usr/share/msbos-walls/`;
- `~/.config/niri/config.kdl`, `~/.config/noctalia/config.toml` e
  `~/.local/state/noctalia/settings.toml` (paths são ajustados, personalizações
  ficam);
- `~/.agents/skills/msbos/references/local.md` e o histórico
  `~/.local/state/msbos/agent-changes.log`;
- backups existentes, arquivados no diretório de migração.

## Rollback

Antes de migrar, tire um snapshot do sistema (btrfs/snapper) ou copie `/etc`,
`/usr/local`, `/usr/share/omyfedora*` e as configurações do usuário. A migração
registra cada movimento; para voltar, restaure o snapshot ou os backups. Se
precisar reinstalar o código antigo, use a tag `v0.2.0` em um clone separado.

## Plugin AI Chat

O plugin `msbos/ai-chat` é um projeto separado
(`marcos2872/msbos-ai-chat`). A versão 0.2.0 já migra o workspace, o agente e o
ID antigo no Noctalia; isso não afeta o sistema nem o helper privilegiado.
