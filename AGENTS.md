# AGENTS.md — MyOS

Distro pessoal baseada em **Fedora 44/45** que transforma um sistema já instalado (rota C, sem ISO
própria) num desktop com **niri** (compositor Wayland) + **Noctalia v5**, focada em baixo uso de RAM
(alvo: < ~600 MB em idle). O repositório é uma suíte de **scripts bash idempotentes** — não há
código compilado, pacote ou build.

## Comandos

Não existe `package.json`, `Makefile` nem CI neste repo — o único ponto de entrada é `install.sh`,
que descobre e roda `scripts/NN-*.sh` em ordem. Não há testes/lint automatizados; a verificação
disponível é o modo `--dry-run` e a checagem de sintaxe.

```bash
./install.sh --help        # ajuda (extraída do cabeçalho do próprio install.sh)
./install.sh --dry-run     # simula tudo, sem alterar nada (roda as 6 etapas; 1ª verificação recomendada)
./install.sh               # instala de verdade (reexecuta com sudo; pergunta antes de remover GDM/GNOME)
./install.sh --yes         # sem perguntas (VMs descartáveis / CI)
```

| Opção | Efeito |
|---|---|
| `--dry-run` | Simula tudo (não instala, não remove, não escreve) |
| `--yes`, `-y` | Autoriza remoções (GDM/GNOME) sem perguntar |
| `--no-greeter` | Não adiciona o repo Terra (usa o greeter padrão do greetd) |
| `--user NOME` | Usuário-alvo da configuração (padrão: quem chamou o sudo) |
| `--gpu-profile P` | Força `auto\|intel\|amd\|nvidia\|hybrid\|none` |
| `--skip-remove` | Nunca remove pacotes (só instala e ajusta serviços) |

Rodar uma etapa isolada (as etapas leem as mesmas variáveis de ambiente do `install.sh`):

```bash
DRY_RUN=1 bash scripts/40-tuning.sh   # simula uma etapa (não muta; roda sem root)
sudo bash scripts/40-tuning.sh        # aplica de verdade (precisa de root)
```

Verificação (local, igual ao CI em `.github/workflows/ci.yml`):

```bash
# bash -n com vários arquivos só valida o PRIMEIRO (os demais virariam $1, $2...)
for f in install.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/*; do bash -n "$f" || exit 1; done
shellcheck -S warning install.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/*
./install.sh --dry-run           # simula tudo, sem alterar nada
```

Depende de `shellcheck` (`dnf install ShellCheck`); o `bash -n` e o `--dry-run` não
dependem de nada além do próprio Fedora.

Variáveis de ambiente — contrato entre `install.sh` e as etapas: `DRY_RUN`, `YES`, `NO_GREETER`,
`TARGET_USER`, `GPU_PROFILE`, `SKIP_REMOVE` (todas exportadas pelo orquestrador).

Checks pós-instalação (no sistema instalado): `systemctl status greetd`, `free -h ; zramctl`,
`journalctl -u greetd -n 30`.

## Arquitetura

Fluxo: `install.sh` (orquestrador) → `lib/common.sh` (helpers) → `scripts/NN-*.sh` (etapas) →
`assets/**` (arquivos instalados no sistema).

- `install.sh` — parseia flags, exporta as variáveis, reexecuta via `sudo` (exceto em `--dry-run`)
  e executa `scripts/[0-9][0-9]-*.sh` em ordem lexicográfica. Basta criar `scripts/60-foo.sh` para
  entrar no fluxo automaticamente.
- `lib/common.sh` — carregado (`source`) por toda etapa. Fornece: `log/ok/warn/err`,
  `run_cmd`/`run_sh` (respeitam `DRY_RUN`), `exige_ok` (portão de operações destrutivas),
  `require_fedora`, `resolve_target_user`, `user_home`, `install_file` (com backup `.myos-bak`),
  `install_file_once` (só instala se o destino não existir — para configs pessoais) e
  `render_file` (substituição de `__VAR__` em assets, instalando com modo 0644 explícito).
- Etapas:
  - `10-gpu.sh` — detecta GPUs (PCI: vendor `10de`/`1002`/`8086` + módulos carregados); perfis
    `auto/intel/amd/nvidia/hybrid/none`; NVIDIA (binário ou `akmod`, `nvidia-drm.modeset=1`,
    offload GL via `/etc/profile.d/myos-nvidia.sh`).
  - `20-stack.sh` — núcleo (niri, Noctalia, greetd, PipeWire, portais), utilitários, zsh + fonte,
    lazydocker, apps (Zed, OpenCode v2, Brave, ONLYOFFICE, SSH_Orchestrator) e **agendamento** da
    remoção do GDM/GNOME.
  - `25-devtools.sh` — gcc/make, Rust (rustup), Node LTS via nvm, pnpm/yarn (idempotente).
  - `30-services.sh` — greetd assume o boot (GDM mascarado), desativa daemons dispensáveis,
    habilita tuned/tuned-ppd/oomd/podman.socket; **nada é parado na sessão atual**.
  - `40-tuning.sh` — zram zstd, sysctl de memória (`__MINFREE__` calculado), `compress=zstd:1` no
    `/etc/fstab` (se btrfs), governor `performance` (só sem bateria), oomd, perfil tuned.
  - `50-configs.sh` — configurações finais: niri, Noctalia (`settings.toml` + plugins, só se
    ausentes), greetd/PAM, alacritty, zsh, wallpapers, Brave padrão e agents-config do OpenCode.
- `assets/` espelha os caminhos de destino e é instalado via `install_file`/`render_file`:
  `niri/`, `greetd/`, `pam.d/` (não sobrescrever o pam_selinux do pacote!), `alacritty/`, `zsh/`,
  `sysctl.d/`, `oomd.conf`, `zram-generator.conf`, `yum.repos.d/terra.repo`, `wallpapers/`
  (→ `/usr/share/myos-walls/`), `plugins-local/` (→ `~/.local/share/noctalia/plugins/`).
  `assets/bin/` e `assets/libexec/` trazem helpers (`myos-wallpaper`, `myos-cpu-governor`,
  `myos-remove-gnome`) e units systemd (`myos-cpu-governor.service`,
  `myos-remove-gnome.service`).
- Segurança de sessão: nada é parado durante a instalação; efeitos valem no próximo boot. A
  remoção do GDM/GNOME é agendada via `myos-remove-gnome.service` (roda antes do login) — nunca na
  sessão viva (o `%preun` do gdm derruba a sessão no meio da transação dnf).
- Malcontent protegido de propósito: todo `flatpak run` consulta parental controls via
  AccountsService, e a permissão polkit da consulta vem do pacote `malcontent` (dependência do
  GNOME). Sem ele a consulta é negada e **nenhum flatpak abre** ("Not allowed to query parental
  controls data for user N" — flatpak/flatpak#6142). `myos-remove-gnome` o marca como `user` +
  `protected_packages`, e a seção 9 do `20-stack.sh` o garante/reinstala quando há flatpak.

## Convenções

- Bash estrito: `set -euo pipefail` em todo script; cada etapa começa com
  `source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"` (robusto ao cwd) e
  chama `require_fedora` quando depende de dnf.
- Tudo em português: comentários, logs e mensagens de erro.
- Toda ação que altera o sistema passa por `run_cmd`/`run_sh` (para o `--dry-run` funcionar);
  nunca execute comando mutante direto.
- Escrita de arquivos via `install_file`/`install_file_once`/`render_file` (garante backup
  `.myos-bak` e respeito ao `DRY_RUN`) — nunca `cp` direto. Use `install_file_once` para
  configs que o usuário pode personalizar e `install_file` para o que o MyOS é dono.
- Comandos: prefira `run_cmd` com argumentos em array (`run_cmd dnf -y "${DNFOPT}" install
  "${pkgs[@]}"`); `run_sh` (string) só quando houver pipe/redirect/`&&`. Nunca interpole
  variáveis dentro da string do `run_sh` — passe via `env` (ex.: `runuser -u "${TU}" -- env
  "HOME=${TU_HOME}"`).
- Dry-run não acessa a rede: consulte APIs/baixe assets apenas quando `DRY_RUN == 0`.
- Operações destrutivas passam por `exige_ok` (bloqueadas sem `--yes`).
- Idempotência: detecte antes de agir (`rpm -q`, `command -v`, existência de paths) e nunca
  sobrescreva personalização existente (ex.: `settings.toml` do Noctalia).
- Pacote opcional: falha vira aviso (`|| warn ...`); pacote essencial: `err ... ; exit 1`.
- dnf com `--setopt=install_weak_deps=0`; comandos como o usuário-alvo via
  `runuser -u ${TU} -- env HOME=... SHELL=...`.
- Comentários `# shellcheck disable=SCxxxx` onde o lint reclamaria (SC1091, SC2059 etc.).
- Commits em Conventional Commits, em português (ex.: `feat(noctalia): ...`, `fix: ...`,
  `docs: ...`).
- `assets/` é a fonte da verdade (configs, plugins, wallpapers); as etapas não geram arquivos.

## Memória do projeto

- Ao aprender algo durável sobre este projeto (decisão, convenção, armadilha, preferência do usuário), salve com a tool `memory_write` — uma frase objetiva por memória.
- As memórias são injetadas automaticamente no seu contexto (bloco `<project-memory>`); siga-as.
- Liste com `memory_list` e remova memórias obsoletas com `memory_delete`; o usuário também gerencia via `/memory`.
