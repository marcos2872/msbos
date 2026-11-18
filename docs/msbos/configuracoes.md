# msbos — anexo: configurações, assets e contratos

Inventário da implementação: **o que é instalado, onde e por qual etapa**. Derivado da leitura de
`assets/**` (118 arquivos) e das chamadas `install_file` / `install_file_once` / `render_file` /
`semodule` em `scripts/*.sh`, `bootstrap.sh` e `lib/common.sh`.

Documento principal: [README.md](README.md).

## 1. Como a instalação de arquivos funciona

| Helper | Comportamento | Modo no destino |
|---|---|---|
| `install_file <asset> <dst>` | `install -D -m "$(stat -c %a src)"`; backup `.msbos-bak` se `dst` já existe (nunca sobrescreve um backup existente) | o modo do arquivo no repo (0644 configs, 0755 helpers) |
| `install_file_once <asset> <dst>` | só instala se `dst` **não** existir; caso contrário loga “já existe — mantido” | idem |
| `render_file <asset> <dst> <VAR> <valor>` | substitui `__VAR__` com `sed` num `mktemp` e instala | **0644 explícito** (necessário para `/etc/greetd/config.toml`, lido pelo usuário `greeter`) |

Regras gerais:

- `DRY_RUN=1` → apenas loga a intenção; nenhum backup, nenhuma escrita.
- O backup é sempre `<dst>.msbos-bak` e só é criado uma vez.
- Configs pessoais usam `install_file_once`: apagar o arquivo restaura o padrão na próxima execução.
- `assets/` é a fonte da verdade; nenhuma etapa gera config dinamicamente (exceto os três
  placeholders da seção 9).

## 2. Origem → destino no sistema

| Asset | Destino | Etapa | Modo |
|---|---|---|---|
| `niri/config.kdl` | `/etc/xdg/niri/config.kdl` | `50` | `install_file` (fallback de sistema) |
| `greetd/config.toml` | `/etc/greetd/config.toml` | `50` | `render_file` (`__GREETER_CMD__`) |
| `pam.d/greetd` | `/etc/pam.d/greetd` | `50` | `install_file` **condicional** (ver §10) |
| `profile.d/msbos-theme.sh` | `/etc/profile.d/msbos-theme.sh` | `50` | `install_file` |
| `profile.d/msbos-nvidia.sh` | `/etc/profile.d/msbos-nvidia.sh` | `10` | `install_file` (perfil NVIDIA/híbrido) |
| `dconf/db/local.d/00-msbos-dark` | `/etc/dconf/db/local.d/00-msbos-dark` | `50` | `install_file` + `dconf update` |
| `etc/xdg/plasma-welcomerc` | `/etc/xdg/plasma-welcomerc` | `50` | `install_file` |
| `sysctl.d/99-msbos.conf` | `/etc/sysctl.d/99-msbos.conf` | `40` | `render_file` (`__MINFREE__`) |
| `zram-generator.conf` | `/etc/systemd/zram-generator.conf` | `40` | `install_file` |
| `oomd.conf` | `/etc/systemd/oomd.conf` | `40` | `install_file` (se `systemd-oomd.service` existe) |
| `msbos-cpu-governor.service` | `/etc/systemd/system/msbos-cpu-governor.service` | `40` | `install_file` (só sem bateria) |
| `msbos-remove-plasma.service` | `/etc/systemd/system/msbos-remove-plasma.service` | `20` | `install_file` (após preflight + `--yes`) |
| `msbos-firstboot.service` | `/etc/systemd/system/msbos-firstboot.service` | `bootstrap.sh --firstboot` | `install -D -m 0644` + symlink em `multi-user.target.wants` |
| `yum.repos.d/terra.repo` | `/etc/yum.repos.d/msbos-terra.repo` | `20` | `install_file` (pulado com `--no-greeter`) |
| `etc/msbos/allowed-units.list` | `/etc/msbos/allowed-units.list` | `60` | `install_file_once` + `root:root 0644` |
| `etc/msbos/protected.list` | `/etc/msbos/protected.list` | `60` | `install_file_once` + `root:root 0644` |
| `polkit/org.msbos.priv.policy` | `/usr/share/polkit-1/actions/org.msbos.priv.policy` | `60` | `install_file` + `root:root 0644` |
| `libexec/msbos-priv` | `/usr/local/libexec/msbos-priv` | `60` | `install_file` + `root:root 0755` + `bin_t` |
| `libexec/msbos-remove-plasma` | `/usr/local/libexec/msbos-remove-plasma` | `20` | `install_file` + `chmod 755` |
| `libexec/msbos-firstboot` | `/usr/local/libexec/msbos-firstboot` | `bootstrap.sh --firstboot` | `install -D -m 0755` |
| `bin/msbos-doctor` | `/usr/local/bin/msbos-doctor` | `50` | `install_file` + `chmod 755` |
| `bin/msbos-wallpaper` | `/usr/local/bin/msbos-wallpaper` | `50` | `install_file` + `chmod 755` |
| `bin/msbos-cpu-governor` | `/usr/local/bin/msbos-cpu-governor` | `40` | `install_file` + `chmod 755` |
| `bin/msbos-greeter-sync` | `/usr/local/bin/msbos-greeter-sync` | `50` | `install_file` (só com `GREETER_SYNC_READY=1`) |
| `bin/msbos-seapplet` | `/usr/local/bin/msbos-seapplet` | `50` | `install_file` (se existe o `.desktop` do setroubleshoot) |
| `bin/msbos-zoom-reset` | `/usr/local/bin/msbos-zoom-reset` | `55` | `install_file` (opt-in) |
| `bin/msbos-niri-zoom-remove` | `/usr/local/bin/msbos-niri-zoom-remove` | `55` | `install_file` (opt-in) |
| `wallpapers/*` | `/usr/share/msbos-walls/<arquivo>` | `50` | `install_file` (loop) |
| `plymouth/msbos/msbos.plymouth` | `/usr/share/plymouth/themes/msbos/msbos.plymouth` | `50` | `install_file` (se existe o tema `spinner`) |
| `plymouth/msbos/watermark.png` | `/usr/share/plymouth/themes/msbos/watermark.png` | `50` | `install_file` |
| `branding/msbos-logo.png` | `/usr/share/icons/hicolor/512x512/apps/msbos.png` | `50` | `install_file` + `gtk-update-icon-cache` |
| `branding/msbos-logo.png` | `/usr/share/pixmaps/msbos-logo.png` | `50` | `install_file` |
| `branding/msbos-logo.png` | `~/.local/share/msbos/msbos-logo.png` | `50` | `install_file` |
| `branding/msbos-mascot.svg` | `/usr/share/msbos/greeter-assets/noctalia.svg` | `50` | `install_file` (bundle do greeter) |
| `selinux/msbos-loadkeys-dontaudit.cil` | — | `30` | `semodule -i` direto do repo (não é copiado) |
| `niri-zoom/*` | — | `55` | lido do repo em tempo de build (não é copiado) |

## 3. Origem → destino no home do usuário-alvo

`TU` = usuário-alvo; `TU_HOME` = home resolvido por `getent passwd`.

| Asset | Destino | Etapa | Modo |
|---|---|---|---|
| `niri/config.kdl` | `~/.config/niri/config.kdl` | `50`, `55` | `install_file_once` |
| `niri/zoom.kdl` | `~/.config/niri/zoom.kdl` | `55` | `install_file_once` |
| `xdg-desktop-portal/niri-portals.conf` | `~/.config/xdg-desktop-portal/niri-portals.conf` | `50` | `install_file` |
| `noctalia/config.toml` | `~/.config/noctalia/config.toml` | `50` | `install_file_once` |
| `noctalia/90-greeter-sync.toml` | `~/.config/noctalia/90-greeter-sync.toml` | `50` | `install_file` |
| `noctalia/91-widget-control-center.toml` | `~/.config/noctalia/91-widget-control-center.toml` | `50` | `render_file` (`__TU_HOME__`) |
| `noctalia/palettes/*.json` | `~/.config/noctalia/palettes/<arquivo>` | `50` | `install_file` (loop) |
| `noctalia/settings.toml` | `~/.local/state/noctalia/settings.toml` | `50` | `install_file` só se não existir |
| `noctalia/plugins/materialized/community/system-monitor/*` | `~/.local/state/noctalia/plugins/materialized/community/system-monitor/*` | `50` | `install_file` via `copia_plugin` (só se o diretório do plugin não existe) |
| `noctalia/plugins-local/agent-usage/*` | `~/.local/share/noctalia/plugins/agent-usage/*` | `50` | idem |
| `noctalia/plugins-local/niri-displays/*` | `~/.local/share/noctalia/plugins/niri-displays/*` | `50` | idem |
| `gtk-3.0/settings.ini` | `~/.config/gtk-3.0/settings.ini` | `50` | `install_file` |
| `gtk-4.0/settings.ini` | `~/.config/gtk-4.0/settings.ini` | `50` | `install_file` |
| `dbus-1/services/org.freedesktop.secrets.service` | `~/.local/share/dbus-1/services/org.freedesktop.secrets.service` | `50` | `install_file` (se `ksecretd` existe) |
| `branding/msbos-mascot.png` | `~/.face` | `50` | `install_file_once` |
| `zed/settings.json` | `~/.config/zed/settings.json` | `50` | `install_file_once` (árvore `assets/zed/**`) |
| `jupyter/kernels/zed-python/kernel.json` | `~/.local/share/jupyter/kernels/zed-python/kernel.json` | `50` | `install_file` (se `python3-ipykernel`) |
| `applications/msbos-usuarios.desktop` | `~/.local/share/applications/msbos-usuarios.desktop` | `50` | `install_file` |
| `alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` | `50` | `install_file_once` |
| `zsh/zshrc` | `~/.zshrc` | `50` | `install_file_once` |
| `autostart/sealertauto.desktop` | `~/.config/autostart/sealertauto.desktop` | `50` | `install_file_once` |
| `autostart/org.kde.xwaylandvideobridge.desktop` | `~/.config/autostart/org.kde.xwaylandvideobridge.desktop` | `50` | `install_file_once` |
| `autostart/msbos-greeter-sync.desktop` | `~/.config/autostart/msbos-greeter-sync.desktop` | `50` | `install_file_once` (só com `GREETER_SYNC_READY=1`) |
| `agents/skills/msbos/SKILL.md` + `references/{niri,noctalia,fedora-dnf,propriedade,seguranca}.md` | `~/.agents/skills/msbos/…` | `60` | `install_file` (sempre atualizado) |
| `agents/skills/msbos/references/local.md` | `~/.agents/skills/msbos/references/local.md` | `60` | `install_file_once` |
| `agents/skills/noctalia-plugin/**` | `~/.agents/skills/noctalia-plugin/**` | `60` | `install_file` (árvore, sempre atualizada) |

Cópias fora do esquema `assets/`:

| Operação | Efeito |
|---|---|
| PNGs de `/usr/share/plymouth/themes/spinner/*.png` | copiados para `/usr/share/plymouth/themes/msbos/` (fundo do tema) |
| symlink `/usr/share/msbos/greeter-assets/fonts` | aponta para `/usr/share/noctalia-greeter/assets/fonts` |
| `~/.local/share/noctalia/plugins/opencode-go` | arquivado em `~/.local/share/noctalia/plugin-archives/opencode-go-<timestamp>` (fora de `plugins/`, senão o Noctalia o redescobre) |
| `https://github.com/marcos2872/agents-config.git` | clonado em `~/.local/share/agents-config`; o `sync.sh` do repo copia agentes/skills/commands/plugins para `~/.config/opencode` (com backup do que existir) |
| `~/.local/bin/zed`, `~/.opencode/bin/opencode` | symlinks para `/usr/local/bin/{zed,opencode}` quando o binário do usuário existe |

## 4. Units systemd

Todas são units **de sistema**, sem units de usuário em `assets/`.

| Unit | Tipo | Dependências | Comportamento | Habilitada por |
|---|---|---|---|---|
| `msbos-cpu-governor.service` | `oneshot`, `RemainAfterExit=yes` | `After/Wants=multi-user.target` | `ExecStart=/usr/local/bin/msbos-cpu-governor` | `40` (`systemctl enable`), só sem bateria |
| `msbos-remove-plasma.service` | `oneshot` | `Before=graphical.target`, `After=local-fs.target network.target` | `ExecStart=/usr/local/libexec/msbos-remove-plasma`; em sucesso se desabilita e apaga a si mesmo | `20`, após `preflight_remocao` + `exige_ok` |
| `msbos-firstboot.service` | `oneshot`, `RemainAfterExit=yes`, `TimeoutStartSec=infinity` | `ConditionPathExists=!/var/lib/msbos/firstboot.done` e `=/etc/msbos/firstboot.conf`; `Wants/After=network-online.target`; `Before=greetd.service display-manager.service graphical.target` | `ExecStart=/usr/local/libexec/msbos-firstboot` | `bootstrap.sh --firstboot` (symlink em `multi-user.target.wants`) |

## 5. Helpers executáveis

| Helper | Linguagem | Propósito | Interface | Instalado em / usado por |
|---|---|---|---|---|
| `msbos-doctor` | bash (671 linhas) | diagnóstico **somente-leitura** do sistema instalado | `--user NOME`, `--strict`, `--no-color`, `-h`; exit 0/1/2 | `/usr/local/bin`, uso manual |
| `msbos-wallpaper` | bash | define wallpaper com `swaybg`; procura `~/.config/msbos-walls/` e `/usr/share/msbos-walls/`; fallback cor `#0B0B0D` | — | `/usr/local/bin`, uso manual |
| `msbos-greeter-sync` | bash | sync único da aparência com o greeter no primeiro login (espera o IPC, roda `noctalia msg greeter-sync`) | —; marcador `~/.local/state/msbos/greeter-sync.done` | autostart `msbos-greeter-sync.desktop` |
| `msbos-cpu-governor` | bash | grava `performance` em todos os `scaling_governor` graváveis | — | `msbos-cpu-governor.service` |
| `msbos-seapplet` | Python 3 (`#!/usr/bin/python3 -Es`) | cópia do `seapplet` com patch em `_close_notifications` (captura `GLib.GError` “NotFound”) | applet GUI | `sealertauto.desktop` |
| `msbos-zoom-reset` | bash | destrava e volta o zoom do niri para 1.0 (`niri msg zoom-state`); exige `jq` | `[OUTPUT]`, `--all`, `-h` | bind `Mod+Alt+0` em `niri/zoom.kdl` |
| `msbos-niri-zoom-remove` | bash | remove `/usr/local/bin/niri`, o marcador e o include do zoom; nunca toca `/usr/bin/niri` | `--user NOME`, `--purge`, `--force`, `-h` | `sudo msbos-niri-zoom-remove` |
| `msbos-priv` | bash (341 linhas) | helper root via `pkexec` com listas permitidas, limites e trilha de auditoria | `--dry-run`, `dnf-install`, `dnf-simulate-remove`, `dnf-remove`, `dnf-upgrade`, `svc-enable`, `svc-disable`, `svc-restart`, `version`, `help` | skill `msbos` |
| `msbos-remove-plasma` | bash | remove o shell do Plasma no boot com `KEEP_PKGS`/`APP_PKGS`, preflight `--assumeno` e `--no-autoremove` | — | `msbos-remove-plasma.service` |
| `msbos-firstboot` | bash | instalação desatendida no primeiro boot; valida `firstboot.conf`, baixa o `bootstrap.sh` e roda `--yes`; até 3 tentativas, teto de 2 h | lê `TARGET_USER`, `MSBOS_REF`, `MSBOS_REPO`, `WITH_NIRI_ZOOM` | `msbos-firstboot.service` |
| `build-in-container.sh` | bash | build do niri patchado dentro do container (`dnf`, `patch`, `cargo build --release`) | dependências de build como argumentos | **não instalado** — lido do repo pela etapa `55` |

## 6. Polkit e `msbos-priv`

Política instalada em `/usr/share/polkit-1/actions/org.msbos.priv.policy`. Todas as ações têm
`allow_any=no` e `allow_inactive=no`; ficam restritas à **sessão ativa local**. O casamento é pelo
`argv[1]` do helper (`org.freedesktop.policykit.exec.argv1`), com `exec.path=/usr/local/libexec/msbos-priv`
e `allow_gui=true`.

| Ação | `allow_active` | Subcomando |
|---|---|---|
| `org.msbos.priv.dnf-install` | `auth_admin` | `dnf-install` |
| `org.msbos.priv.dnf-simulate-remove` | `auth_admin_keep` | `dnf-simulate-remove` (não altera nada) |
| `org.msbos.priv.dnf-remove` | `auth_admin` | `dnf-remove` |
| `org.msbos.priv.dnf-upgrade` | `auth_admin` | `dnf-upgrade` |
| `org.msbos.priv.svc-enable` | `auth_admin` | `svc-enable` (`systemctl enable --now`) |
| `org.msbos.priv.svc-disable` | `auth_admin` | `svc-disable` (`systemctl disable --now`) |
| `org.msbos.priv.svc-restart` | `auth_admin` | `svc-restart` |

Validações feitas **pelo próprio helper**, depois do polkit:

| Regra | Valor |
|---|---|
| Nome de pacote | `^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$` (sem globs, caminhos, URLs ou flags) |
| Máximo por instalação | 20 pacotes |
| Máximo por remoção | 25 pacotes (conta a cascata simulada) |
| Remoção | sempre `--no-autoremove`; recusa se um pacote protegido aparecer como alvo ou efeito |
| Unidades | só de `UNITS_BASE` ou de `/etc/msbos/allowed-units.list` (arquivo precisa ser de root, sem escrita de grupo/outros) |
| Concorrência | `flock -n` em `/run/msbos-priv.lock` |
| Auditoria | toda ação e recusa em `/var/log/msbos/actions.log` (diretório 0750) |

`UNITS_BASE` (embutida): `tuned`, `tuned-ppd`, `bluetooth`, `libvirtd.{service,socket}`,
`podman.socket`, `cups.{service,socket}`, `avahi-daemon.{service,socket}`, `fprintd`, `firewalld`,
`sshd`. Fora de propósito: `systemd-oomd`, `power-profiles-daemon`, `greetd`, `NetworkManager`,
`systemd-*`, `dbus`, `polkit`.

`PROTEGIDOS_BASE` (embutida) cobre sistema base/boot/segurança (`systemd*`, `glibc*`, `rpm*`,
`dnf*`, `kernel*`, `grub2*`, `polkit*`, `pam*`, `selinux-policy*`…), a stack do msbos (`greetd`,
`niri`, `noctalia`, `pipewire`, `tuned`, `zram-generator`…), `zsh`/`python3`, os apps KDE do dia a
dia e o suporte que os mantém funcionais, além do shell do Plasma (`plasma-desktop`,
`plasmalogin`) — esse só sai pelo `msbos-remove-plasma`, nunca pelo agente na sessão viva.

Não há arquivos `.rules` de polkit em `assets/`. A regra do sync do greeter
(`org.noctalia.greeter.sync-appearance`) é criada por `noctalia-greeter passwordless-sync enable`.

## 7. SELinux

| Objeto | Efeito |
|---|---|
| `msbos-loadkeys-dontaudit.cil` → módulo `msbos-loadkeys-dontaudit` | `(dontaudit loadkeys_t loadkeys_t (capability (dac_override)))`: silencia o AVC benigno quando o `systemd-vconsole-setup` roda `loadkeys -q -C /dev/tty1` e o VT já pertence ao usuário da sessão. O fallback `O_RDONLY` aplica o keymap; nada é concedido além do silenciamento |
| `/usr/local/libexec/msbos-priv` | `semanage fcontext -a -t bin_t` (ou `-m`); sem `semanage`, `chcon -t bin_t` (o rótulo pode voltar após relabel) |
| `/var/lib/noctalia-greeter` | `semanage fcontext -a -t xdm_var_lib_t '/var/lib/noctalia-greeter(/.*)?'` + `restorecon -R` |

Instalação do módulo: `30-services.sh` só com `/sys/fs/selinux` presente, `semodule` no PATH e o
módulo ainda não listado por `semodule -l` (idempotente). Falha vira aviso.

## 8. Configs com placeholders

| Asset | Placeholder | Etapa | Valor |
|---|---|---|---|
| `greetd/config.toml` | `__GREETER_CMD__` | `50` | `/usr/bin/env NOCTALIA_GREETER_ASSETS_DIR=<bundle> <noctalia-greeter-session> -- --session niri`, sem a variável quando o bundle está incompleto, ou `greetd` quando o greeter não está instalado |
| `noctalia/91-widget-control-center.toml` | `__TU_HOME__` | `50` | home do usuário-alvo |
| `sysctl.d/99-msbos.conf` | `__MINFREE__` | `40` | `MemTotal_kB / 64`, piso 8192, teto 8388608 (KB) |

Nenhum outro asset usa `__VAR__`; os demais são instalados literalmente.

## 9. Valores de tuning

| Arquivo | Valores |
|---|---|
| `/etc/systemd/zram-generator.conf` | `[zram0]`, `zram-size = min(ram * 0.75, 16384)`, `compression-algorithm = zstd` |
| `/etc/sysctl.d/99-msbos.conf` | `vm.swappiness=60`, `vm.vfs_cache_pressure=50`, `vm.min_free_kbytes=__MINFREE__` |
| `/etc/systemd/oomd.conf` | `[oomd]` `SwapFull=40%`, `SwapUsed=45%`, `MemoryPressure=50%` |
| `/etc/fstab` (btrfs) | `compress=zstd:1` na linha do `/` (edição in-place com backup `fstab.msbos-bak`) |
| tuned | perfil `latency-performance` |
| governor | `performance` em todos os `scaling_governor` (só desktop sem bateria) |

## 10. Condições que alteram o destino

| Config | Condição |
|---|---|
| `pam.d/greetd` | não sobrescreve o arquivo do pacote (que já traz `pam_selinux`): só restaura `greetd.msbos-bak`/`greetd.omyfedora-bak` ou instala o asset quando o arquivo falta ou perdeu `pam_selinux` |
| `niri/config.kdl` (home) | `install_file_once` — personalização de atalhos nunca é sobrescrita; `/etc/xdg/niri/config.kdl` é sempre atualizado como fallback |
| `noctalia/settings.toml` | só se não existir (conteúdo da GUI é do usuário) |
| plugins Noctalia | `copia_plugin` só age se o diretório do plugin ainda não existe |
| `noctalia/90-*`, `91-*` e paletas | sempre atualizados (política do dono do msbos) |
| `dbus-1/services/org.freedesktop.secrets.service` | só se `/usr/bin/ksecretd` existe (ou em dry-run) |
| `jupyter/kernels/zed-python` | só se `python3-ipykernel` está instalado (ou em dry-run) |
| `oomd.conf` | só se `/usr/lib/systemd/system/systemd-oomd.service` existe |
| `msbos-cpu-governor.*` | só se nenhum `/sys/class/power_supply/*/type` é `Battery` |
| `terra.repo` | só com `NO_GREETER != 1` |
| `profile.d/msbos-nvidia.sh` | só nos perfis `nvidia`/`hybrid` |
| tema Plymouth | só se `/usr/share/plymouth/themes/spinner` existe (ou em dry-run) |
| bundle do greeter | só com `noctalia-greeter-session` presente e `tabler.ttf` + `tabler.json` + `noctalia.svg` no bundle |
| sync do greeter (`bin` + autostart) | só se `noctalia-greeter passwordless-sync enable` funcionou (`GREETER_SYNC_READY=1`) |
| `msbos-seapplet` | só se `/etc/xdg/autostart/sealertauto.desktop` existe |
| helpers do zoom | só com `--with-niri-zoom` |

## 11. Assets que não são instalados

| Arquivo | Situação |
|---|---|
| `assets/selinux/msbos-loadkeys-dontaudit.cil` | aplicado via `semodule -i` direto do repo |
| `assets/niri-zoom/niri-zoom-anchored.patch` | enviado ao container de build pela etapa `55` (SHA-256 fixo) |
| `assets/niri-zoom/build-in-container.sh` | executado dentro do container pela etapa `55` |
| `assets/branding/msbos-mascot.jpg` | **sem referência** em scripts, README ou docs — resíduo, não instalado |

## 12. Origens de terceiros

| Origem | Usada para | Proteção |
|---|---|---|
| RPM Fusion (`free`/`nonfree` release) | `akmod-nvidia`, drivers/microcode | RPM oficial do projeto, idempotente por `rpm -q` |
| Terra (`repos.fyralabs.com`) | `noctalia-greeter` | `includepkgs=noctalia-greeter*`, `priority=200`, `skip_if_unavailable=1`, GPG + repo_gpgcheck |
| Brave (`brave-browser.repo`) | `brave-browser` | repo oficial assinado |
| ONLYOFFICE (`onlyoffice-repo.noarch.rpm`) | `onlyoffice-desktopeditors` | repo oficial assinado |
| GitHub API (SSH_Orchestrator) | RPM `.x86_64.rpm` | release oficial |
| GitHub releases (lazydocker) e `raw.githubusercontent.com` (nvm) | binário do lazydocker e instalador do nvm | lazydocker: `checksums.txt` + `sha256sum -c`; nvm: tag da release mais recente da API |
| Flathub | `org.localsend.localsend_app` | flatpak assinado |
| `zed.dev/install.sh`, `sh.rustup.rs`, `opencode.ai/v2/install`, `github.com/marcos2872/agents-config` | Zed, Rust, OpenCode, config de agentes | execução de código de terceiros (fora do dry-run) |
| `Atan-D-RP4/niri` (commit fixado) | niri com zoom (opt-in) | commit + SHA-256 do tarball e do patch; build isolado em podman |

## 13. Propriedade: o que o msbos sobrescreve e o que o usuário controla

| Grupo | Estratégia | Efeito ao repetir a instalação |
|---|---|---|
| Tema, portais, units, helpers, política polkit, paletas, `90`/`91` do Noctalia, skills (`msbos` e `noctalia-plugin`, exceto `local.md`) | `install_file` | **sobrescreve** (com backup `.msbos-bak`) |
| `~/.config/niri/config.kdl`, `~/.config/noctalia/config.toml`, `~/.config/zed/settings.json`, `~/.config/alacritty/alacritty.toml`, `~/.zshrc`, `~/.face`, autostarts, `references/local.md`, `/etc/msbos/*.list` | `install_file_once` | **mantém** a versão do usuário |
| `/etc/pam.d/greetd` | condicional | mantém a versão do pacote |
| `/etc/fstab` | `sed` com backup | só adiciona `compress=` se ainda não houver |
| `~/.config/kdeglobals`, `~/.config/kcminputrc` | `kwriteconfig6` | só escreve chaves vazias/ausentes |
| `~/.local/state/noctalia/settings.toml` | instala só se ausente | mantém |
| Plugins em `~/.local/{share,state}/noctalia/plugins/` | instala só se o diretório do plugin não existe | mantém (para atualizar, remova o diretório do plugin) |
