# AGENTS.md — omyfedora

Personalização pessoal do **Fedora 44/45 KDE** que transforma um sistema já instalado (rota C,
sem ISO própria) num desktop com **niri** (compositor Wayland) + **Noctalia v5**, focada em baixo
uso de RAM (alvo: < ~600 MB em idle) — mantendo os **apps do KDE** e o tema dark padrão do KDE
(**Breeze Dark**) nos aplicativos. O repositório é uma suíte de **scripts bash idempotentes** —
não há código compilado, pacote ou build. A documentação do usuário fica no `README.md` (enxuto)
e em `docs/` (PT), com versões em inglês `*.en.md`.

## Comandos

Não existe `package.json` nem `Makefile`. O ponto de entrada é o `install.sh`, que descobre e roda
`scripts/NN-*.sh` em ordem; o CI em `.github/workflows/ci.yml` roda três jobs em `fedora:44`
(bash -n, shellcheck e dry-run). Não há suíte de testes unitários — a verificação disponível é
sintaxe, lint, `--dry-run` e os checks pós-instalação.

```bash
./install.sh --help        # ajuda (extraída do cabeçalho do próprio install.sh)
./install.sh --dry-run     # simula tudo, sem alterar nada (roda as 6 etapas; 1ª verificação recomendada)
./install.sh               # instala de verdade (reexecuta com sudo; pergunta antes de remover o shell do Plasma)
./install.sh --yes         # sem perguntas (VMs descartáveis / CI)
```

| Opção | Efeito |
|---|---|
| `--dry-run` | Simula tudo (não instala, não remove, não escreve) |
| `--yes`, `-y` | Autoriza remoções (shell do Plasma) sem perguntar |
| `--no-greeter` | Não adiciona o repo Terra (usa o greeter padrão do greetd) |
| `--user NOME` | Usuário-alvo da configuração (padrão: quem chamou o sudo) |
| `--gpu-profile P` | Força `auto\|intel\|amd\|nvidia\|hybrid\|none` |
| `--skip-remove` | Nunca remove pacotes (só instala e ajusta serviços) |

Rodar uma etapa isolada (as etapas leem as mesmas variáveis de ambiente do `install.sh`):

```bash
DRY_RUN=1 bash scripts/40-tuning.sh   # simula uma etapa (não muta; roda sem root)
sudo bash scripts/40-tuning.sh        # aplica de verdade (precisa de root)
```

Verificação local (os jobs de sintaxe/lint da CI rodam os mesmos comandos):

```bash
# assets/bin/omyfedora-seapplet é Python: filtre só arquivos com shebang shell.
scripts=()
for f in install.sh bootstrap.sh pessoal-pc.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/*; do
  first="$(head -n1 "$f")"
  case "$first" in
    *bash*|*'/sh'*|*dash*|*ksh*) scripts+=("$f") ;;
  esac
done
# bash -n com vários arquivos só valida o PRIMEIRO (os demais virariam $1, $2...)
for f in "${scripts[@]}"; do bash -n "$f" || exit 1; done
shellcheck -S warning "${scripts[@]}"
./install.sh --dry-run           # simula tudo, sem alterar nada
```

Na CI, o job dry-run cria um usuário `ci` e roda `./install.sh --dry-run --user ci`; localmente,
use `./install.sh --dry-run` (ou `--user NOME`). Depende de `shellcheck`
(`dnf install ShellCheck`); o `bash -n` e o `--dry-run` não dependem de nada além do próprio
Fedora.

Variáveis de ambiente — contrato entre `install.sh` e as etapas: `DRY_RUN`, `YES`, `NO_GREETER`,
`TARGET_USER`, `GPU_PROFILE`, `SKIP_REMOVE` (todas exportadas pelo orquestrador).

Checks pós-instalação (no sistema instalado): `omyfedora-doctor`, `systemctl status greetd`,
`free -h ; zramctl`, `journalctl -u greetd -n 30`.

## Arquitetura

Fluxo: `install.sh` (orquestrador) → `lib/common.sh` (helpers) → `scripts/NN-*.sh` (etapas) →
`assets/**` (arquivos instalados no sistema).

- `install.sh` — parseia flags, exporta as variáveis, reexecuta via `sudo` (exceto em `--dry-run`)
  e executa `scripts/[0-9][0-9]-*.sh` em ordem lexicográfica. Basta criar `scripts/60-foo.sh` para
  entrar no fluxo automaticamente.
- `bootstrap.sh` — baixa o repositório como `.tar.gz`, extrai em diretório temporário e chama o
  `install.sh` (sem `git`); aceita as mesmas flags e `OMYFEDORA_REF`/`REPO`/`URL`/`KEEP`.
- `pessoal-pc.sh` — script pessoal de layout de monitores + Chrome; **não** entra no `install.sh`.
- `lib/common.sh` — carregado (`source`) por toda etapa. Fornece: `log/ok/warn/err`,
  `run_cmd`/`run_sh` (respeitam `DRY_RUN`), `exige_ok` (portão de operações destrutivas),
  `require_fedora`, `resolve_target_user`, `user_home`, `install_file` (com backup `.omyfedora-bak`),
  `install_file_once` (só instala se o destino não existir — para configs pessoais) e
  `render_file` (substituição de `__VAR__` em assets, instalando com modo 0644 explícito).
- Etapas:
  - `10-gpu.sh` — detecta GPUs (PCI: vendor `10de`/`1002`/`8086` + módulos carregados); perfis
    `auto/intel/amd/nvidia/hybrid/none`; NVIDIA (binário ou `akmod`, `nvidia-drm.modeset=1`,
    offload GL via `/etc/profile.d/omyfedora-nvidia.sh`).
  - `20-stack.sh` — núcleo (niri, Noctalia, greetd, PipeWire, portais), utilitários, zsh + fonte,
    lazydocker, apps (Zed, OpenCode v2, Brave, ONLYOFFICE, SSH_Orchestrator, LocalSend), **curadoria dos
    apps KDE e do LibreOffice** (remove jogos/PIM/ajuda e a suíte LibreOffice — o escritório do omyfedora é o
    ONLYOFFICE — respeitando `--skip-remove`; garante Dolphin, Konsole, Kate/KWrite, Okular, Spectacle,
    Dragon, Elisa…, marcando os garantidos como user-installed — imunes à cascata; tema Breeze Dark
    via plasma-integration/breeze-*) e **agendamento** da remoção do shell do Plasma.
  - `25-devtools.sh` — gcc/make, gh, ipykernel/matplotlib, Rust (rustup), Node LTS via nvm,
    pnpm/yarn e virtualização (@virtualization + libvirtd no boot + usuário no grupo libvirt) —
    idempotente.
  - `30-services.sh` — greetd assume o boot (plasmalogin/gdm/sddm mascarados), desativa daemons
    dispensáveis (PackageKit/Discover ficam), habilita tuned/tuned-ppd/oomd/podman.socket e instala
    o módulo SELinux local que silencia o falso positivo do `loadkeys` no VT da sessão;
    **nada é parado na sessão atual**.
  - `40-tuning.sh` — zram zstd, sysctl de memória (`__MINFREE__` calculado), `compress=zstd:1` no
    `/etc/fstab` (se btrfs), governor `performance` (só sem bateria), oomd, perfil tuned.
  - `50-configs.sh` — configurações finais: niri (config uma vez + fallback de sistema), Noctalia
    (`config.toml` uma vez; `settings.toml`/plugins só se ausentes; `90`/`91` e paleta atualizados),
    Breeze Dark (kdeglobals/kcminputrc só com chaves vazias + GTK/dconf/gsettings), greetd/PAM e
    sync do greeter, Plymouth/branding, wallpapers, apps padrão
    (Dolphin/KWrite/Gwenview/Okular/Dragon/Elisa), alacritty/zsh, **autostart do usuário**
    (XwaylandVideoBridge desligado e seapplet com patch), Secret Service do KWallet no D-Bus,
    Zed e agents-config do OpenCode.
- Documentação do usuário: `README.md`/`README.en.md` e `docs/*.md`/`*.en.md`; não participa da
  instalação. O README é enxuto (o que é + instalação básica + créditos); os detalhes ficam em
  `docs/`.
- `assets/` espelha os caminhos de destino e é instalado via `install_file`/`render_file`:
  `niri/`, `greetd/`, `pam.d/` (não sobrescrever o pam_selinux do pacote!), `alacritty/`, `zsh/`,
  `gtk-3.0/` + `gtk-4.0/` (settings.ini com Breeze), `dconf/db/local.d/00-omyfedora-dark`,
  `dbus-1/services/` (→ `~/.local/share/dbus-1/services/`), `profile.d/`, `sysctl.d/`,
  `oomd.conf`, `zram-generator.conf`, `yum.repos.d/terra.repo`,
  `wallpapers/` (→ `/usr/share/omyfedora-walls/`), `plugins-local/`
  (→ `~/.local/share/noctalia/plugins/`), `autostart/` (→ `~/.config/autostart/`).
  `assets/bin/` e `assets/libexec/` trazem helpers (`omyfedora-wallpaper`, `omyfedora-cpu-governor`,
  `omyfedora-seapplet` — cópia do applet do setroubleshoot com patch do GLib.GError —,
  `omyfedora-doctor` — diagnóstico somente-leitura do sistema instalado — e
  `omyfedora-remove-plasma`) e units systemd (`omyfedora-cpu-governor.service`,
  `omyfedora-remove-plasma.service`).
  `assets/selinux/` não é copiado: contém módulos CIL instalados via `semodule` (ex.:
  `omyfedora-loadkeys-dontaudit`, que suprime o AVC benigno do `loadkeys` no VT da sessão).
- Segurança de sessão: nada é parado durante a instalação; efeitos valem no próximo boot. A
  remoção do shell do Plasma é agendada via `omyfedora-remove-plasma.service` (roda antes do login) —
  nunca na sessão viva (o `%preun` do plasmalogin mexe nos serviços systemd e derruba a sessão no
  meio da transação dnf). O script move `/etc/dnf/protected.d/plasma-desktop.conf` durante a
  remoção e protege da cascata o que mantém os apps KDE funcionais (`plasma-integration`,
  `plasma-breeze`, `plasma-systemsettings`, `polkit-kde`, `xdg-desktop-portal-kde`) e o
  `konsole` (terminal do dia a dia: nunca pode ser removido).
- Malcontent (condicional): o `flatpak` consulta parental controls via AccountsService; **se** o
  `accountsservice` da versão expõe a interface `com.endlessm.ParentalControls` (build com
  malcontent) e o pacote `malcontent` for removido, todo `flatpak run` falha ("Not allowed to
  query parental controls data for user N" — flatpak/flatpak#6142). O `omyfedora-remove-plasma` o
  protege quando presente, e a seção 9 do `20-stack.sh` só instala/repara quando o daemon tem o
  suporte (checagem compile-time via `strings`); no Fedora 44 ele não tem, então nada é instalado.
- VM de teste: o niri **rejeita renderização por software** (`llvmpipe`) por design — a VM
  precisa de virtio-gpu com `accel3d=yes` + `gl=on` no Spice, senão a sessão fica em tela preta
  (só aparece o aviso de depreciação do `systemd` no VT). Com o GL ligado ainda podem surgir
  artefatos/cursor invertido (bug do QEMU — qemu#2315): o bloco `debug` comentado no
  `assets/niri/config.kdl` (`disable-cursor-plane`, `disable-direct-scanout`,
  `wait-for-frame-completion-before-queueing`) é o contorno — flags confirmadas no niri 26.04.

## Convenções

- Bash estrito: `set -euo pipefail` em todo script; cada etapa começa com
  `source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"` (robusto ao cwd) e
  chama `require_fedora` quando depende de dnf.
- Tudo em português: comentários, logs e mensagens de erro.
- Toda ação que altera o sistema passa por `run_cmd`/`run_sh` (para o `--dry-run` funcionar);
  nunca execute comando mutante direto.
- Escrita de arquivos via `install_file`/`install_file_once`/`render_file` (garante backup
  `.omyfedora-bak` e respeito ao `DRY_RUN`) — nunca `cp` direto. Use `install_file_once` para
  configs que o usuário pode personalizar e `install_file` para o que o omyfedora é dono.
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
