# msbos — documentação técnica da implementação

Documento **de implementação**: descreve como o repositório está montado (orquestrador, helpers,
etapas, assets, contratos e garantias). Não substitui a documentação de uso — para instalar, usar o
desktop ou resolver problemas, veja [docs/index.md](../index.md).

> **Não é um backend.** O msbos não compila nada e não expõe API: é uma suíte de scripts bash
> idempotentes que transforma um Fedora 44/45 já instalado em um desktop niri + Noctalia v5. Por
> isso este documento adapta a estrutura de documentação técnica: no lugar do catálogo de
> endpoints/DTOs, há o catálogo de **etapas**, **assets**, **units** e **variáveis**. O inventário
> completo de arquivos instalados está no anexo
> [configuracoes.md](configuracoes.md).

## 1. Visão geral

| Item | Valor |
|---|---|
| Alvo | Fedora 44/45 KDE já instalado (rota C, sem ISO própria) |
| Resultado | boot pelo `greetd` → sessão `niri` + shell `Noctalia v5`, apps KDE mantidos com Breeze Dark |
| Stack de execução | bash 5 (`set -euo pipefail`), dnf/dnf5, systemd, polkit, SELinux |
| Código compilado | nenhum — exceto o niri com zoom (opt-in), compilado em podman e instalado em `/usr/local/bin/niri` |
| Entradas | `install.sh` (local), `bootstrap.sh` (sem git), `bootstrap.sh --firstboot` (kickstart) |
| Ordem das etapas | `scripts/[0-9][0-9]-*.sh` em ordem lexicográfica |
| Estado de execução | `/var/lib/msbos/steps/<etapa>` (só em modo real) |
| Modo seguro | `--dry-run`: não escreve, não instala, não acessa rede |

Fluxo macro:

```
install.sh  ──exporta flags──►  scripts/NN-*.sh  ──usa──►  lib/common.sh
     │                              │
     │                              └──instala──►  assets/**  ──►  /etc, /usr, ~/.config, ...
     ├── reexec via sudo (exceto --dry-run)
     ├── descobre scripts/NN-*.sh e roda em ordem
     └── grava /var/lib/msbos/steps/<etapa> e para na primeira falha
```

## 2. Pontos de entrada

### 2.1 `install.sh`

- Faz o parse das flags, aplica defaults **apenas se a variável não veio do ambiente**
  (`: "${DRY_RUN:=0}"` etc. — isso preserva os valores na reexecução via `sudo`), exporta todas e
  reexecuta com `exec sudo env ...` quando `EUID != 0` e `DRY_RUN == 0`.
- Descobre as etapas com `ls -1 [0-9][0-9]-*.sh | sort`; lista vazia aborta.
- Roda cada etapa em processo separado (`bash scripts/<etapa>`, capturando `rc` com `|| rc=$?`) e
  **para na primeira falha**, imprimindo o comando para repetir só aquela etapa.
- Em modo real grava `date` em `/var/lib/msbos/steps/<etapa>` — trilha de até onde a instalação
  chegou. Em dry-run nenhum arquivo é criado.

| Flag | Variável | Efeito |
|---|---|---|
| `--dry-run` | `DRY_RUN=1` | Simula tudo; não reexecuta com sudo; não grava estado |
| `--yes`, `-y` | `YES=1` | Autoriza operações destrutivas sem perguntar (`exige_ok`) |
| `--no-greeter` | `NO_GREETER=1` | Não adiciona o repo Terra nem instala `noctalia-greeter` |
| `--user NOME` | `TARGET_USER=NOME` | Usuário-alvo (padrão: quem chamou o sudo) |
| `--gpu-profile P` | `GPU_PROFILE=P` | `auto\|intel\|amd\|nvidia\|hybrid\|none` |
| `--skip-remove` | `SKIP_REMOVE=1` | Nunca remove pacotes (nem agenda a remoção do Plasma) |
| `--with-niri-zoom` | `WITH_NIRI_ZOOM=1` | Habilita a etapa opt-in `55-niri-zoom.sh` |
| `-h`, `--help` | — | `usage()` extrai o cabeçalho de comentários do próprio script |

### 2.2 `bootstrap.sh`

Baixa o repositório como `.tar.gz` (sem `git`), extrai em `mktemp -d` e chama o `install.sh` de
dentro do diretório temporário — o `MSBOS_ROOT` efetivo passa a ser esse temp.

| Variável | Default | Efeito |
|---|---|---|
| `MSBOS_REPO` | `marcos2872/msbos` | repositório de origem |
| `MSBOS_REF` | `main` | branch/tag/commit |
| `MSBOS_URL` | derivada de `REPO`/`REF` | sobrepõe a URL (espelho/teste) |
| `MSBOS_KEEP` | `0` | `1` mantém o diretório temporário ao sair |
| `TMPDIR` | sistema | base dos temporários |

Pré-checagens: `/etc/fedora-release` legível, `curl` e `tar` no PATH; avisa se `stdin` não é TTY
(sem `--yes` o `install.sh` pergunta antes de remover o Plasma). As flags são repassadas, com
tratamento especial para `--user` e `--with-niri-zoom`.

### 2.3 `bootstrap.sh --firstboot` (kickstart)

Não instala nada na hora: instala `/usr/local/libexec/msbos-firstboot`, a unit
`msbos-firstboot.service`, cria `/etc/msbos/firstboot.conf` (só se não existir) e habilita a unit
por symlink em `multi-user.target.wants` — o `%post` do Anaconda roda em chroot, sem systemd como
PID 1. No primeiro boot, `msbos-firstboot` baixa o `bootstrap.sh` da ref configurada e roda a
instalação com `--yes`.

## 3. Arquitetura

| Componente | Responsabilidade |
|---|---|
| `install.sh` | orquestrador: flags, defaults, `sudo`, descoberta/ordem, fail-fast, estado |
| `bootstrap.sh` | entrega sem git e instalação desatendida no primeiro boot |
| `lib/common.sh` | logging (`log/ok/warn/err`), wrappers de dry-run (`run_cmd`/`run_sh`), portão destrutivo (`exige_ok`), cheque de base (`require_fedora`), resolução do usuário-alvo, instalação de arquivos (`install_file`/`install_file_once`/`render_file`) |
| `scripts/NN-*.sh` | uma etapa por script, idempotente, executável isoladamente |
| `assets/**` | **fonte da verdade** das configs; espelha os caminhos de destino |
| `assets/bin`, `assets/libexec` | helpers instalados em `/usr/local/{bin,libexec}` |
| `assets/*.service` | units oneshot de sistema |

| Etapa | Papel | Efeitos principais |
|---|---|---|
| `00-migrate-names.sh` | migra instalação antiga (nomes/paths/estado) | move diretórios, desabilita units antigas, faz backup; no-op em instalação nova |
| `10-gpu.sh` | detecta GPU e instala driver | RPM Fusion, `akmod-nvidia` + `nvidia-drm.modeset=1`, microcode, `profile.d/msbos-nvidia.sh` |
| `20-stack.sh` | stack base, apps, curadoria | núcleo niri/Noctalia/greetd/áudio/portais, apps KDE, Zed/OpenCode/Brave/ONLYOFFICE/LocalSend, remoção de jogos/PIM/LibreOffice, agendamento da remoção do Plasma |
| `25-devtools.sh` | ferramentas de desenvolvimento | gcc/make, `gh`, ipykernel/matplotlib, Rust (rustup), Node (nvm), pnpm/yarn, `@virtualization` + libvirtd |
| `30-services.sh` | serviços do systemd | greetd assume o boot, DMs mascarados, daemons dispensáveis desligados, `tuned`/`oomd`, socket podman, módulo SELinux |
| `40-tuning.sh` | memória e desempenho | zram zstd, sysctl, `compress=zstd:1` no btrfs, governor `performance` (sem bateria), oomd, perfil tuned |
| `50-configs.sh` | configurações finais | niri, Noctalia, Breeze Dark/GTK/dconf, Plymouth/branding, greetd/PAM, wallpapers, apps padrão, zsh/alacritty, autostart, KWallet, Zed, skills |
| `55-niri-zoom.sh` | **opt-in** (`--with-niri-zoom`) | compila niri patchado em podman e instala `/usr/local/bin/niri` + `zoom.kdl` |
| `60-agent-skill.sh` | privilégio para agentes | `msbos-priv` + política polkit + listas em `/etc/msbos` + skills `msbos` e `noctalia-plugin` |
| `99-cleanup-legacy.sh` | remove artefatos antigos | só remove quando o equivalente novo existe; arquiva backups; exige `--yes` |

## 4. Modelo de execução e garantias

**Idempotência.** Toda etapa detecta antes de agir: `rpm -q`, `command -v`, `[[ -d ]]`,
`systemctl list-unit-files`, `semodule -l`, `grep` no arquivo de destino. `install_file_once` nunca
sobrescreve config pessoal; `install_file` sobrescreve o que o msbos é dono, sempre com backup
`.msbos-bak` (o primeiro backup existente é preservado).

**Dry-run.** `DRY_RUN=1` faz `run_cmd`/`run_sh` apenas logarem o que fariam, bloqueia
`_backup_dst`/`install_file`, impede escrita de estado e impede acessos de rede (consulta de versão
do OpenCode, download de lazydocker/SSH_Orchestrator, compilação do niri).

**Fail-fast.** `set -euo pipefail` em todos os scripts; o orquestrador para na primeira etapa que
falhar e informa como repetir. Etapas são idempotentes, então repetir é seguro.

**Dependências de ordem.** `00` prepara o terreno antes das demais; `99` só roda depois que os
arquivos novos existem; `50` depende de pacotes instalados em `20`/`25`; `55` depende do config do
niri criado em `50`.

**Operações destrutivas.** Passam por `exige_ok`: sem `YES=1`, a operação é bloqueada (e em
dry-run retorna 1 sem perguntar). Remoções em massa nunca são feitas ao vivo.

**Nada para na sessão viva.** Serviços só são `enable`/`disable`/`mask`; efeitos valem no próximo
boot. A exceção controlada é `systemctl try-restart accounts-daemon` (etapa `20`, caso malcontent).

## 5. Contrato de variáveis de ambiente

| Variável | Quem exporta | Quem lê | Valores | Efeito |
|---|---|---|---|---|
| `DRY_RUN` | `install.sh`; default em `lib/common.sh` | orquestrador, helpers e todas as etapas | `0\|1` | `1` simula tudo, sem sudo, sem estado e sem rede |
| `YES` | `install.sh` | `exige_ok` (`20`, `99`) | `0\|1` | autoriza remoções sem perguntar |
| `NO_GREETER` | `install.sh` | `20`, `50` | `0\|1` | não instala repo Terra/`noctalia-greeter`; usa o greeter padrão |
| `TARGET_USER` | `install.sh` | `resolve_target_user` (`00`, `20`, `25`, `30`, `50`, `55`, `60`, `99`) | nome de usuário | dono da configuração; vazio → `SUDO_USER` → primeiro UID 1000–64999 |
| `GPU_PROFILE` | `install.sh` | `10` | `auto\|intel\|amd\|nvidia\|hybrid\|none` | força o perfil de GPU |
| `SKIP_REMOVE` | `install.sh` | `20` | `0\|1` | desliga curadoria e agendamento da remoção do Plasma |
| `WITH_NIRI_ZOOM` | `install.sh`, `bootstrap.sh`, `firstboot.conf` | `55`, `lib/common.sh`, `msbos-firstboot` | `0\|1` | habilita o niri com zoom |
| `MSBOS_ROOT` | `install.sh`, recalculado em `lib/common.sh` | todas as etapas | path absoluto | raiz do repositório |
| `FEDORA_VERSION` | `require_fedora` | `10` | `VERSION_ID` | monta as URLs do RPM Fusion |
| `SUDO_USER` | ambiente | `resolve_target_user` | usuário | fallback do usuário-alvo |
| `NIRI_ZOOM_IMAGE` | ambiente | `55` | imagem | default `registry.fedoraproject.org/fedora:44` |
| `TARGET_USER`, `MSBOS_REF`, `MSBOS_REPO`, `WITH_NIRI_ZOOM` | `bootstrap.sh --firstboot` (`/etc/msbos/firstboot.conf`) | `msbos-firstboot` | texto/`0\|1` | parametriza a instalação desatendida |

## 6. Privilégios e fronteiras de confiança

| Fronteira | Mecanismo |
|---|---|
| Instalação | root obrigatório em modo real (reexec com `sudo`); `--dry-run` roda como o chamador |
| Agente de IA | `pkexec /usr/local/libexec/msbos-priv <subcomando>` — 7 ações polkit, `allow_any=no`, `allow_inactive=no`, `allow_active=auth_admin` (simulação com `auth_admin_keep`) |
| Limites do `msbos-priv` | regex `^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$`, máx. 20 pacotes por instalação, máx. 25 remoções por chamada, `--no-autoremove`, recusa de pacotes/unidades fora das listas, `flock -n` em `/run/msbos-priv.lock`, log em `/var/log/msbos/actions.log` |
| SELinux | helper em `/usr/local/libexec` recebe `bin_t` via `semanage fcontext` (fallback `chcon`); módulo `msbos-loadkeys-dontaudit` só suprime um AVC benigno do `loadkeys` |
| Repositórios de terceiros | Terra com `includepkgs=noctalia-greeter*` + `priority=200`; RPM Fusion para NVIDIA; repos oficiais de Brave e ONLYOFFICE; Flathub para LocalSend |
| Downloads verificados | lazydocker: `checksums.txt` da mesma release + `sha256sum -c`; niri-zoom: commit e patch fixados com SHA-256 conferido |
| Scripts remotos | `zed.dev/install.sh`, `sh.rustup.rs`, instalador do nvm, instalador do OpenCode e clone do `agents-config` executam código de terceiros — decisão consciente do projeto, fora do dry-run |

## 7. Catálogo das etapas

### 7.1 `00-migrate-names.sh`

Migra uma instalação anterior (`omyfedora`/`myos`) antes das etapas normais: move
`/etc|/var/lib|/usr/share/{omyfedora,myos}` → `msbos`, reescreve paths em configs do usuário
só quando o `grep` encontra referência antiga, remove `.repo`/`sysctl`/`dconf`/`profile.d` antigos
(com backup), desabilita units antigas **sem `--now`** e apaga os marcadores de
`greeter-sync.done` (forçando o novo sync). Em instalação nova, sai antes de qualquer escrita.

### 7.2 `10-gpu.sh`

Detecta GPUs por PCI (classe `03xx`, vendors `10de`/`1002`/`8086`) e módulos carregados; resolve
`auto|intel|amd|nvidia|hybrid|none`. Instala `akmod-nvidia` (nunca o pacote `nvidia`), adiciona
RPM Fusion quando ausente, instala microcode (`microcode_ctl`/`amd-ucode-firmware`) e
`mesa-dri-drivers`, roda `akmods --force` e registra `nvidia-drm.modeset=1` via `grubby`.
Instala `/etc/profile.d/msbos-nvidia.sh` no perfil NVIDIA/híbrido e avisa sobre Secure Boot.

### 7.3 `20-stack.sh`

A etapa mais extensa (~600 linhas) e a única que altera a composição de pacotes do sistema:

- **Núcleo obrigatório** (`greetd niri noctalia jemalloc pipewire… portais polkit udisks2 gvfs
  NetworkManager tuned curl git xdg-utils`, fontes Noto, `breeze-icon-theme`/`breeze-cursor-theme`),
  com uma retentativa após `dnf clean all`.
- **Utilitários/opcionais** instalados um a um; falha vira aviso.
- **Apps KDE** (`dolphin konsole kwrite okular gwenview ark kcalc kamoso spectacle skanpage krdc
  krfb kolourpaint kde-connect kfind keditbookmarks kwalletmanager5 kjournald dragon elisa-player
  filelight kde-partitionmanager plasma-systemmonitor plasma-systemsettings kinfocenter`) e o
  **suporte** que os mantém funcionais (`plasma-integration plasma-breeze breeze-gtk-common
  pam-kwallet kde-cli-tools dconf kio-*`…), somando falhas em `FALHAS_KDE`.
- **Apps de terceiros**: Zed (script oficial), OpenCode v2 CLI (instalador oficial, pulando se a
  versão local for maior/igual), Brave (repo RPM), ONLYOFFICE (repo RPM), SSH_Orchestrator (RPM da
  API do GitHub), LocalSend (flatpak do Flathub), lazydocker (repo do Fedora, senão binário
  verificado por sha256).
- **Curadoria**: remove jogos, PIM/e-mail, `neochat`, `kmouth`/`kcharselect`/`khelpcenter` e
  `libreoffice*`; mantém Discover/notifier, `plasma-welcome` e todos os `plasma-discover*`
  instalados.
- **Proteção anti-cascata**: `dnf mark user` em `CORE + SUPORTE + KDE_APPS` que estiverem
  instalados, mais `PackageKit`, `plasma-welcome`, cada `plasma-discover*` e `malcontent` quando
  aplicável.
- **Remoção do shell do Plasma**: `preflight_remocao` simula a transação com
  `/etc/dnf/protected.d/*` afastados, exige linha `Removing` e aborta se algum `KDE_KEEP`
  aparecer no plano; só então `exige_ok` autoriza instalar `msbos-remove-plasma` +
  `msbos-remove-plasma.service` e habilitar a unit.

### 7.4 `25-devtools.sh`

Instala `gcc/gcc-c++/make/pkgconf-pkg-config`, `gh`, `python3-ipykernel`, `python3-matplotlib`
(todos condicionais), o grupo `@virtualization` (sem `install_weak_deps=0`), habilita
`libvirtd`, adiciona o usuário ao grupo `libvirt` e instala Rust (rustup), nvm + Node LTS,
pnpm/yarn. Avisa se `/dev/kvm` não existe; o grupo só vale no próximo login.

### 7.5 `30-services.sh`

Coloca o `greetd` no boot: desabilita **e mascara** `plasmalogin`/`gdm`/`sddm` (conforme
instalados), desabilita `avahi-daemon`, `cups` (mantendo `cups.socket`), `sssd`, `fprintd`,
`dnf-automatic(.timer)`, `systemd-pstore`, `plasma-setup` e `bluetooth` sem hardware; habilita
`greetd`, `tuned` (+ `tuned-ppd` ou `power-profiles-daemon`), `podman.socket` e `systemd-oomd`.
Cria o usuário `greeter` e `/var/lib/noctalia-greeter` com contexto `xdm_var_lib_t`, instala o
módulo SELinux `msbos-loadkeys-dontaudit`, cria o symlink `/var/run/docker.sock` →
`/run/podman/podman.sock` e habilita o socket podman do usuário. **PackageKit não é desativado.**

### 7.6 `40-tuning.sh`

zram (`/etc/systemd/zram-generator.conf`, `min(ram * 0.75, 16384)`, zstd), `sysctl.d/99-msbos.conf`
com `__MINFREE__` calculado (`MemTotal/64`, piso 8192 KB, teto 8388608 KB), `compress=zstd:1` na
linha do `/` do `/etc/fstab` (só em btrfs, idempotente), `oomd.conf`, perfil
`latency-performance` e `msbos-cpu-governor.service` **apenas sem bateria**. Roda o autoteste do
`zram-generator` e aborta se o conf for inválido — um parse errado deixaria o sistema sem swap sem
erro visível no boot.

### 7.7 `50-configs.sh`

Configura o ambiente do usuário e do sistema: `plasma-welcomerc` (só a página de novidades),
config do niri (uma vez no home; sempre em `/etc/xdg/niri/config.kdl` como fallback), portais,
Noctalia (`config.toml` uma vez; `90-greeter-sync.toml` e `91-widget-control-center.toml` sempre;
`settings.toml` e plugins só se ausentes), Breeze Dark (kdeglobals/kcminputrc só com chaves
vazias, GTK3/4, dconf, gsettings), Plymouth/branding, wallpapers, apps padrão via `xdg-mime`/
`xdg-settings`, zsh (`chsh`, `/etc/shells`), alacritty, autostart, Secret Service do KWallet,
jupyter/zed, `msbos-wallpaper`, `msbos-doctor`, `msbos-seapplet` e o sync do greeter.

Decisões relevantes:

- **PAM do greetd não é sobrescrito**: o pacote do Fedora já traz `pam_selinux`; sem ele o SELinux
  em enforcing bloqueia o `systemctl --user` da sessão e o niri volta ao login. Só restaura backup
  ou instala o asset quando o arquivo falta/perdeu `pam_selinux`.
- **Sync do greeter**: `noctalia-greeter passwordless-sync enable <user>` cria a regra polkit
  restrita; o `noctalia msg greeter-sync` só roda se essa regra foi habilitada na execução (sem
  ela o `pkexec` abriria diálogo e o script ficaria preso). Numa instalação limpa, o primeiro sync
  é feito pelo autostart `msbos-greeter-sync`.
- **Bundle do greeter**: `/usr/share/msbos/greeter-assets` com symlink para as fontes do pacote e
  `noctalia.svg` próprio; `NOCTALIA_GREETER_ASSETS_DIR` só é apontado se `tabler.ttf`,
  `tabler.json` e o SVG existirem.
- **`XwaylandVideoBridge`** é desligado (`Hidden=true`) porque, sem tray do Plasma, virava janela
  que não fechava; **`seapplet`** é substituído por `msbos-seapplet` (patch do `GLib.GError`).
- Configs pessoais (`niri`, `noctalia/config.toml`, `zed`, `alacritty`, `.zshrc`, autostart,
  `~/.face`) usam `install_file_once`: apagar o arquivo restaura o padrão.

### 7.8 `55-niri-zoom.sh` (opt-in)

Sem `--with-niri-zoom` é no-op (apenas avisa se detectar instalação anterior). Com a flag: instala
`podman`/`jq` se faltarem, baixa o commit fixado de `Atan-D-RP4/niri` e o patch local, confere os
SHA-256, compila no container (`build-in-container.sh`, `cargo build --release`), valida `ldd` e
`--version`, instala em `/usr/local/bin/niri` e grava `/usr/local/share/msbos/niri-zoom.commit`.
O `/usr/bin/niri` do pacote permanece intacto. `msbos-niri-zoom-remove` faz o rollback; o zoom
(`movement-mode "anchored"`, `pan-modifier "super"`) fica em `~/.config/niri/zoom.kdl`, incluído no
config do usuário, e `msbos-zoom-reset` restaura 1.0.

### 7.9 `60-agent-skill.sh`

Instala `/usr/local/libexec/msbos-priv` (root:root 0755, contexto `bin_t`), a política
`org.msbos.priv.policy`, as listas `/etc/msbos/allowed-units.list` e `/etc/msbos/protected.list`
(só na primeira vez) e as skills `msbos` (referências sempre atualizadas, `local.md` só uma vez) e
`noctalia-plugin` (árvore sempre atualizada) em `~/.agents/skills/`. Cria `/var/log/msbos` (0750)
e valida a política com `pkaction` em modo real.

### 7.10 `99-cleanup-legacy.sh`

Remove units, binários, política, temas, ícones, diretórios e arquivos de `omyfedora`/`myos` — cada
remoção condicionada à existência do equivalente novo. Arquiva backups antigos em
`/var/backups/msbos-migration/legacy-<ts>` e `~/.local/state/msbos/migration-backups/legacy-<ts>`,
roda `daemon-reload`/`reset-failed`, remove módulos SELinux antigos, `dconf update` e
`sysctl --system`. Exige `--yes`; sem isso, a limpeza fica pendente e a instalação continua.

## 8. Curadoria de pacotes e remoção do Plasma

| Mantido | Motivo |
|---|---|
| Apps KDE do dia a dia (`dolphin`, `konsole`, `kwrite`, `okular`, `gwenview`, `ark`, `kcalc`, `spectacle`, `kde-connect`, `dragon`, `elisa-player`…) | desktop funcional com Breeze Dark |
| `plasma-integration`, `plasma-breeze`, `plasma-workspace-libs` | tema, diálogos e `kcm_users` do System Settings |
| `plasma-systemsettings`, `kinfocenter`, `plasma-systemmonitor`, `polkit-kde`, `xdg-desktop-portal-kde` | utilitários e portais |
| Discover/notifier e todos os `plasma-discover*` já instalados | notificações e atualizações; nunca são instalados se ausentes |
| `PackageKit` | backend do Discover (não é desativado em `30`) |
| `malcontent` (quando o `accounts-daemon` tem `com.endlessm.ParentalControls`) | sem ele, todo `flatpak run` falha (flatpak/flatpak#6142) |
| `redhat-menus` | sem `/etc/xdg/menus/applications.menu`, o `kbuildsycoca6` gera cache vazio |

Removido: jogos (`kmahjongg`, `kmines`, `kpat`), PIM/e-mail (`kmail`, `kontact`, `korganizer`,
`kaddressbook`, `akregator`), `neochat`, `kmouth`, `kcharselect`, `khelpcenter` e `libreoffice*`
(escritório = ONLYOFFICE). O **shell** do Plasma (`plasma-desktop`, `plasma-workspace`,
`plasma-login-manager`, `plasma-setup`) sai no **próximo boot**, via
`msbos-remove-plasma.service`, porque o `%preun` desses pacotes mexe em units systemd e derrubaria
a sessão no meio da transação dnf.

A lista `KDE_KEEP` do `20-stack.sh` precisa ficar em sincronia com `KEEP_PKGS`/`APP_PKGS` de
`assets/libexec/msbos-remove-plasma` — é o contrato que impede a cascata de levar tema, KIO ou
apps.

## 9. Boot e serviços

| Unit | Tipo | Papel | Habilitada por |
|---|---|---|---|
| `msbos-firstboot.service` | oneshot, `RemainAfterExit` | instalação desatendida no primeiro boot (só via kickstart) | `bootstrap.sh --firstboot` |
| `msbos-remove-plasma.service` | oneshot, `Before=graphical.target` | remove o shell do Plasma antes do login | `20-stack.sh` (após preflight + `--yes`) |
| `msbos-cpu-governor.service` | oneshot, `RemainAfterExit` | fixa o governor em `performance` a cada boot | `40-tuning.sh` (só sem bateria) |
| `greetd.service` | system | tela de login (Noctalia Greeter ou padrão) | `30-services.sh` |

Sequência de boot: `firstboot` (se configurado) → `msbos-remove-plasma` → `greetd` → sessão niri →
`spawn-at-startup` (noctalia, agente polkit) → autostarts do usuário (`msbos-greeter-sync`,
`sealertauto`, XwaylandVideoBridge desligado).

## 10. Estado, logs e recuperação

| Caminho | Conteúdo |
|---|---|
| `/var/lib/msbos/steps/<etapa>` | data/hora da última execução bem-sucedida de cada etapa |
| `/var/lib/msbos/firstboot.done` | marcador que desliga o `msbos-firstboot` |
| `/etc/msbos/firstboot.conf` | parâmetros da instalação desatendida |
| `/etc/msbos/{allowed-units.list,protected.list}` | extensões locais das listas do `msbos-priv` |
| `/var/log/msbos/` | diretório 0750 com `actions.log`: toda ação e recusa do helper privilegiado |
| `/var/log/msbos/niri-zoom-build.log` | log da compilação do niri patchado |
| `/usr/local/share/msbos/niri-zoom.commit` | commit/patch/hash do niri instalado (opt-in) |
| `<arquivo>.msbos-bak` | backup do primeiro arquivo sobrescrito por `install_file` |
| `/var/backups/msbos-migration/<ts>` e `~/.local/state/msbos/migration-backups/` | backups da migração e dos artefatos legados |
| `~/.local/state/msbos/greeter-sync.done` | marcador do sync único com o greeter |
| `~/.local/state/msbos/agent-backups` | backups feitos pelo agente via `msbos-priv` |

Recuperação: repetir a etapa isolada (`sudo bash scripts/NN-*.sh`) é seguro; `msbos-doctor`
diagnostica o sistema instalado; `msbos-niri-zoom-remove` desfaz o zoom; remover um
`.msbos-bak` e repetir a etapa restaura o padrão.

## 11. Verificação e observabilidade

| Recurso | O que cobre |
|---|---|
| `bash -n` por arquivo | sintaxe (um arquivo por vez — `bash -n a b` valida só o primeiro) |
| `shellcheck -S warning` | lint dos scripts shell |
| `tests/rename-guard.sh` | impede que nomes antigos apareçam fora dos scripts de migração/detecção |
| `./install.sh --dry-run` | simulação completa, sem rede e sem escrita |
| `msbos-doctor` | diagnóstico somente-leitura: base, etapas, greetd/PAM/greeter, niri/Noctalia, zoom, apps KDE, menu XDG, remoção do Plasma, Breeze Dark, zram/sysctl/governor, RAM idle, SELinux, Podman rootless, NVIDIA |
| `/var/lib/msbos/steps/` | até onde a instalação chegou |

## 12. Tratamento de erros

| Situação | Política |
|---|---|
| Pacote **essencial** ausente | `err` + `exit 1` (ex.: núcleo do `20-stack`, `podman`/`jq` no `55`) |
| Pacote **opcional** ausente | `\|\| warn "…"` e segue |
| Query que não pode falhar | falha fechada (`rpm -qa plasma-discover*` → `exit 1`) |
| Operação destrutiva | `exige_ok` (bloqueia sem `--yes`); `preflight_remocao` aborta em conflito |
| Download de terceiro | verificação de SHA-256; divergência aborta |
| Config inválida gerada | validação antes de aplicar (zram-generator, `niri validate -c`) com rollback do backup |
| Etapa interrompida | `trap`/subshell restauram `protected.d`; marcadores de estado dizem onde parou |

## 13. Migração e legado

`00-migrate-names.sh` e `99-cleanup-legacy.sh` existem para quem vem de `omyfedora`/`myos`: o
primeiro move estado e configuração para os paths `msbos` (mesclando com `cp -an` quando o destino
já existe), o segundo apaga o que sobrou **depois** que o novo está no lugar. Ambos são no-op em
instalação nova. Nomes antigos só podem aparecer nos scripts de migração/detecção (`00`, `99`,
`40-tuning.sh`, `50-configs.sh`), no `msbos-doctor`, nas notas de release históricas e em
`docs/historico*`/`docs/migracao-msbos*` — o CI garante via `tests/rename-guard.sh`.

## 14. Convenções para contribuir

- `set -euo pipefail` e `source` do `lib/common.sh` pelo caminho absoluto calculado a partir de
  `BASH_SOURCE`.
- Toda mutação via `run_cmd`/`run_sh`; escrita de arquivo via `install_file`/`install_file_once`/
  `render_file` — nunca `cp` direto.
- `run_cmd` com array (nunca interpolar variáveis dentro da string do `run_sh`; use `env`).
- Detectar antes de agir; nunca sobrescrever personalização existente.
- `install_file_once` para config que o usuário personaliza; `install_file` para o que o msbos é
  dono.
- Comentários, logs e mensagens em português; commits em Conventional Commits em português.
- `assets/` é a fonte da verdade: etapas não geram configs.

## 15. Como executar

```bash
./install.sh --help              # ajuda (cabeçalho do próprio install.sh)
./install.sh --dry-run           # simulação completa (primeira verificação recomendada)
./install.sh                     # instala de verdade (reexecuta com sudo)
./install.sh --yes               # sem perguntas (VMs descartáveis/CI)

DRY_RUN=1 bash scripts/40-tuning.sh   # simula uma etapa isolada (sem root)
sudo bash scripts/40-tuning.sh        # aplica uma etapa isolada
```

Verificação local antes de enviar mudanças:

```bash
for f in install.sh bootstrap.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/* assets/niri-zoom/*.sh; do
  first="$(head -n1 "$f")"
  case "$first" in *bash*|*'/sh'*|*dash*|*ksh*) bash -n "$f" || exit 1 ;; esac
done
shellcheck -S warning install.sh bootstrap.sh lib/common.sh scripts/*.sh
./install.sh --dry-run
```

## 16. Referências

- **Anexo — inventário de configurações, assets, units, helpers, polkit e SELinux**:
  [`configuracoes.md`](configuracoes.md)
- [Arquitetura e etapas](../arquitetura.md) — visão para quem instala
- [Instalação](../instalacao.md) · [Uso diário](../uso.md) · [Solução de problemas](../solucao-de-problemas.md)
- [Migração para o msbos](../migracao-msbos.md) · [Histórico de nomes](../historico.md)
- `AGENTS.md` na raiz — convenções operacionais do repositório
