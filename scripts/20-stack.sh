#!/usr/bin/env bash
# 20-stack.sh — stack base (niri + Noctalia + greetd + áudio + utilitários)
# sobre a base Fedora KDE: apps KDE mantidos, tema dark do KDE (Breeze Dark)
# e aplicativos do usuário (Zed, OpenCode v2, Brave, ONLYOFFICE).
#
# Métodos de instalação:
#   niri/Noctalia/greetd/áudio   → dnf (repos oficiais do Fedora)
#   noctalia-greeter             → repo comunitário Terra (--no-greeter p/ pular)
#   Zed                          → script oficial  (curl -fsSL https://zed.dev/install.sh | sh)
#   OpenCode v2 CLI              → script oficial  (curl -fsSL https://opencode.ai/v2/install | bash)
#   Brave                        → repo oficial RPM da Brave Software
#   ONLYOFFICE                   → repo oficial RPM da ONLYOFFICE
#   LocalSend                    → flatpak oficial do Flathub (o Fedora não empacota; a release não tem RPM)
#
# A base é o Fedora KDE: os APPS KDE ficam (o usuário pediu mantê-los) e só o
# shell do Plasma sai de cena — remoção AGENDADA para o próximo boot (seção 8).

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
TU_SHELL="$(getent passwd "${TU}" | cut -d: -f7)"
[[ -n ${TU_SHELL} ]] || TU_SHELL=/bin/bash
log "stack: usuário-alvo: ${TU} (${TU_HOME})"

DNFOPT='--setopt=install_weak_deps=0'

# install_lazydocker_verified — baixa o binário do lazydocker da última release
# oficial e só instala se o sha256 do tarball bater com o checksums.txt da MESMA
# release. Substitui o antigo "curl | bash" (que executa código remoto sem
# verificação nenhuma). Falha = não instala (nunca instala algo não verificado).
install_lazydocker_verified() {
  local dest='/usr/local/bin/lazydocker'
  local base='https://github.com/jesseduffield/lazydocker/releases/latest/download'
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: baixaria ${base}/checksums.txt + tarball Linux_x86_64, verificaria o sha256 e instalaria em ${dest}"
    return 0
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    warn "lazydocker: sha256sum indisponível — não é possível verificar o binário"
    return 1
  fi
  local tmp asset esperado
  tmp="$(mktemp -d)" || return 1
  # 1) checksums oficiais da release
  if ! curl -fsSL --retry 2 --max-time 60 "${base}/checksums.txt" -o "${tmp}/checksums.txt"; then
    warn "lazydocker: falha ao baixar checksums.txt"
    rm -rf "${tmp}"; return 1
  fi
  # 2) nome do tarball linux/x86_64 dentro do checksums.txt
  asset="$(awk '$2 ~ /_Linux_x86_64\.tar\.gz$/ {print $2; exit}' "${tmp}/checksums.txt")"
  if [[ -z ${asset} ]]; then
    warn "lazydocker: tarball Linux_x86_64 não encontrado no checksums.txt"
    rm -rf "${tmp}"; return 1
  fi
  esperado="$(awk -v f="${asset}" '$2 == f {print $1}' "${tmp}/checksums.txt")"
  # sanidade: hash tem de ser sha256 em hex (evita instalar algo valendo-se de
  # uma linha malformada do checksums.txt)
  if [[ ! ${esperado} =~ ^[0-9a-fA-F]{64}$ ]]; then
    warn "lazydocker: hash inválido no checksums.txt para ${asset}"
    rm -rf "${tmp}"; return 1
  fi
  # 3) baixa o tarball
  if ! curl -fsSL --retry 2 --max-time 180 "${base}/${asset}" -o "${tmp}/${asset}"; then
    warn "lazydocker: falha ao baixar ${asset}"
    rm -rf "${tmp}"; return 1
  fi
  # 4) VERIFICA — hash divergente aborta a instalação
  printf '%s  %s\n' "${esperado}" "${tmp}/${asset}" > "${tmp}/sha256sum"
  if ! run_cmd sha256sum -c "${tmp}/sha256sum" >/dev/null; then
    warn "lazydocker: checksum de ${asset} NÃO confere — instalação abortada"
    rm -rf "${tmp}"; return 1
  fi
  # 5) extrai e instala (busca o binário em qualquer nível do archive — o
  # layout da release já mudou de formato no passado)
  run_cmd tar -xzf "${tmp}/${asset}" -C "${tmp}" || { rm -rf "${tmp}"; return 1; }
  local bin
  bin="$(find "${tmp}" -type f -name lazydocker -print -quit 2>/dev/null || true)"
  if [[ -z ${bin} ]]; then
    warn "lazydocker: binário não encontrado dentro de ${asset}"
    rm -rf "${tmp}"; return 1
  fi
  run_cmd install -m 0755 "${bin}" "${dest}" || { rm -rf "${tmp}"; return 1; }
  rm -rf "${tmp}"
  ok "lazydocker ${asset} instalado e verificado (sha256 OK) em ${dest}"
}

# ─── 1. Núcleo (obrigatório) ────────────────────────────────────────────────
# breeze-icon-theme/breeze-cursor-theme: ícones (breeze-dark) e cursor
# (breeze_cursors) do KDE — entram no CORE para sobreviverem a qualquer
# limpeza/remoção (a cascata do dnf não leva pacotes instalados como user).
CORE=(
  greetd niri noctalia jemalloc
  pipewire pipewire-pulse wireplumber
  xdg-desktop-portal xdg-desktop-portal-gtk
  polkit polkit-kde udisks2 gvfs gvfs-mtp
  NetworkManager
  tuned
  curl git xdg-utils
  google-noto-sans-fonts google-noto-sans-mono-fonts
  breeze-icon-theme breeze-cursor-theme
)
log "stack: instalando núcleo: ${CORE[*]}"
if ! run_cmd dnf -y "${DNFOPT}" install "${CORE[@]}"; then
  # espelho fora de sincronia (checksum de repomd/404 de repodata) é
  # transitório: limpa o cache e tenta UMA vez de novo antes de desistir
  warn "núcleo: falha na 1ª tentativa (espelho fora de sincronia?) — limpando cache e tentando de novo"
  run_cmd dnf clean all || true
  if ! run_cmd dnf -y "${DNFOPT}" install "${CORE[@]}"; then
    err "falha ao instalar o núcleo do stack — abortando"
    exit 1
  fi
fi
ok "núcleo instalado"

# perfis de energia: Fedora 44+ traz tuned-ppd (mesma API do power-profiles-daemon);
# instalar os dois causa conflito de provides (ppd-service)
if rpm -q tuned-ppd >/dev/null 2>&1; then
  log "stack: perfis de energia: tuned-ppd (API PPD do tuned)"
elif rpm -q power-profiles-daemon >/dev/null 2>&1; then
  log "stack: perfis de energia: power-profiles-daemon"
else
  run_cmd dnf -y "${DNFOPT}" install power-profiles-daemon \
    || warn "sem gerenciador de perfis de energia (tuned-ppd/PPD indisponíveis)"
fi

# ─── 2. Utilitários leves ───────────────────────────────────────────────────
# dolphin + gvfs/ntfs-exfat: sem eles o erro é "Not authorized to perform
# operation" (udisks2 sem gvfs) ou volume ilegível (NTFS/exFAT de SSDs externos).
# spectacle: capturas/anotações (grim/slurp saíram — os atalhos Print usam o
# screenshot nativo do niri).
# Cofre: a base KDE usa o KWallet (kwalletd + pam-kwallet — destrava no login
# pelo PAM do greetd); não há seahorse/gnome-keyring no stack.
UTILS=(alacritty brightnessctl playerctl ntfs-3g exfatprogs dosfstools)
for p in "${UTILS[@]}"; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || warn "utilitário '${p}' indisponível — ignorado"
done
for p in swaybg wlsunset ddcutil pipewire-alsa; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || warn "opcional '${p}' indisponível — ignorado"
done

# ─── 2b. Curadoria: apps KDE e LibreOffice que o MyOS não usa ───────────────
# A base KDE já traz os apps padrão; o MyOS remove só o que não se usa num
# desktop de dev: jogos, a suíte PIM/e-mail (substituível por webmail), o
# pacote de ajuda/acessibilidade e o LibreOffice (a suíte de escritório do
# MyOS é o ONLYOFFICE, instalado na seção 7). Remoção ao vivo é segura — são
# apps, sem scriptlet que derruba a sessão (o SHELL do Plasma sai de cena no
# próximo boot, agendado na seção 8: esse sim derrubaria a sessão).
if [[ ${SKIP_REMOVE:-0} == 1 ]]; then
  log "stack: curadoria: remoções desativadas (--skip-remove)"
else
  KDE_REMOVE=(
    kmahjongg kmines kpat                            # jogos
    kmail kontact korganizer kaddressbook akregator  # PIM/e-mail (cascata kdepim-*)
    neochat                                          # cliente Matrix
    kmouth kcharselect khelpcenter                   # fala/char picker/ajuda
  )
  for p in "${KDE_REMOVE[@]}"; do
    if rpm -q "${p}" >/dev/null 2>&1; then
      run_cmd dnf -y "${DNFOPT}" remove "${p}" || warn "manter '${p}': falha na remoção"
    fi
  done
  # LibreOffice inteiro (writer/calc/impress... + langpacks): o glob leva junto
  # as dependências exclusivas dele (ex.: java headless) pela cascata padrão do
  # dnf. Idempotente: só age se a suíte estiver instalada.
  if rpm -q libreoffice-core >/dev/null 2>&1; then
    log "curadoria: removendo o LibreOffice (escritório do MyOS = ONLYOFFICE)"
    run_cmd dnf -y "${DNFOPT}" remove 'libreoffice*' || warn "libreoffice: falha na remoção"
  fi
fi

# ─── 2c. Tema dark do KDE (Breeze) + apps garantidos ────────────────────────
# O MyOS não entrega tema próprio: os apps usam o "Breeze Dark", o dark padrão
# do KDE (o mesmo que o Plasma usa). Nada de Kvantum/qt6ct/qt5ct — o visual vem
# de:
#   • ~/.config/kdeglobals (ColorScheme=BreezeDark, widgetStyle=Breeze,
#     ícones breeze-dark, cursor breeze_cursors) — preenchido na etapa
#     50-configs via kwriteconfig6 (o System Settings mexe no MESMO arquivo e
#     o MyOS só preenche chaves ainda vazias);
#   • plasma-integration: platform theme Qt6 "kde" (QT_QPA_PLATFORMTHEME em
#     /etc/profile.d/myos-theme.sh) — sem ele os apps Qt ficam sem o Breeze;
#   • breeze-gtk-common: tema GTK Breeze/Breeze-Dark (lido pelo settings.ini);
#   • pam-kwallet: destrava o cofre KWallet no login (o PAM do greetd no
#     Fedora já chama o pam_kwallet5.so).
# Todos são exigidos pelo Plasma: após a remoção do shell (seção 8) eles são
# marcados como user-installed para a cascata do dnf não levá-los embora.
for p in plasma-integration plasma-breeze breeze-gtk-common pam-kwallet kde-cli-tools dconf; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" \
    || warn "tema: '${p}' indisponível — o visual dos apps pode divergir do KDE"
done
# Apps KDE que o MyOS garante presentes (a base KDE já os tem — o Dolphin, o
# Konsole, o Kate/KWrite etc. são os apps do dia a dia; numa instalação mínima
# eles completam o desktop). Sem haruna/strawberry/ksystemlog: os equivalentes
# padrão do KDE são dragon/elisa/kjournald.
KDE_APPS=(dolphin dolphin-plugins konsole kwrite okular gwenview ark kcalc
  kamoso spectacle skanpage krdc krfb kolourpaint kde-connect kfind
  keditbookmarks kwalletmanager5 kjournald dragon elisa-player filelight
  kde-partitionmanager plasma-systemmonitor plasma-systemsettings kinfocenter)
for p in "${KDE_APPS[@]}"; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || warn "kde: '${p}' indisponível — ignorado"
done
# Marca os apps garantidos como user-installed (uma única chamada do dnf).
# Sem isso, um app que já veio como dependência do Plasma (ex.: o Konsole)
# poderia ser levado na cascata da remoção do shell no próximo boot
# (clean_requirements_on_remove). Marcar como user-installed protege da
# cascata, mas o pacote continua removível se o usuário quiser.
KDE_INSTALADOS=()
for p in "${KDE_APPS[@]}"; do
  rpm -q "${p}" >/dev/null 2>&1 && KDE_INSTALADOS+=("${p}")
done
if ((${#KDE_INSTALADOS[@]} > 0)); then
  run_cmd dnf -y mark user "${KDE_INSTALADOS[@]}" \
    || warn "kde: falha ao marcar os apps garantidos como user-installed"
fi
# Baloo (indexador do Dolphin): come RAM/CPU — desligado de propósito.
if command -v balooctl6 >/dev/null 2>&1; then
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" balooctl6 disable \
    || warn "baloo: falha ao desligar o indexador"
fi

# ─── 3. Terminal: zsh com autocomplete + fonte ──────────────────────────────
TERM_PKGS=(zsh zsh-autosuggestions zsh-syntax-highlighting fzf bash-completion jetbrains-mono-fonts)
for p in "${TERM_PKGS[@]}"; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || warn "terminal: '${p}' indisponível — ignorado"
done

# ─── 4. Contêineres: lazydocker (TUI) + compat docker/podman ────────────────
# Idempotente: se o binário já existe, não faz nada.
if command -v lazydocker >/dev/null 2>&1; then
  ok "lazydocker já instalado"
else
  # 1ª tentativa: repo do Fedora
  if ! run_cmd dnf -y "${DNFOPT}" install lazydocker; then
    # 2ª tentativa: binário da release oficial COM verificação de sha256.
    # Não usamos o instalador oficial (curl | bash): baixamos o tarball e o
    # checksums.txt da mesma release e só instalamos se o hash bater.
    warn "lazydocker fora dos repos — instalando binário verificado (sha256) da release oficial"
    install_lazydocker_verified || warn "lazydocker: falha na instalação verificada"
  fi
fi
run_cmd dnf -y "${DNFOPT}" install podman-docker \
  || warn "contêineres: 'podman-docker' indisponível — ignorado"

# ─── 5. Bluetooth (só se houver adaptador) ──────────────────────────────────
if [[ -n "$(ls /sys/class/bluetooth 2>/dev/null)" ]]; then
  run_cmd dnf -y "${DNFOPT}" install bluez || warn "bluez: falha na instalação"
else
  log "stack: sem adaptador Bluetooth — bluez não será instalado"
fi

# ─── 6. Greeter do Noctalia (repo comunitário Terra) ────────────────────────
if [[ ${NO_GREETER} == 1 ]]; then
  log "stack: greeter Noctalia desativado (--no-greeter)"
else
  install_file "yum.repos.d/terra.repo" "/etc/yum.repos.d/myos-terra.repo"
  warn "repo comunitário Terra (fyralabs) habilitado para o pacote noctalia-greeter"
  run_cmd dnf -y "${DNFOPT}" install noctalia-greeter \
    || warn "noctalia-greeter indisponível — o greetd usará o greeter padrão"
fi

# ─── 7. Aplicativos do usuário ──────────────────────────────────────────────

# Zed — script oficial (instala em ~/.local/bin, com auto-update).
# run_cmd com o script interno entre aspas simples: nada é interpolado pelo
# shell de fora (só as variáveis que passamos via env).
log "stack: Zed (script oficial: curl -fsSL https://zed.dev/install.sh | sh)"
run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" "SHELL=${TU_SHELL}" \
  bash -c 'curl -fsSL https://zed.dev/install.sh | sh' \
  || warn "Zed: falha na instalação pelo script oficial"
# o instalador oficial instala em ~/.local/bin, fora do PATH de sessões
# gráficas (niri); o symlink garante o comando no Super+E e em qualquer shell
run_cmd ln -sf "${TU_HOME}/.local/bin/zed" /usr/local/bin/zed \
  || warn "Zed: falha ao criar symlink em /usr/local/bin"

# OpenCode v2 CLI — script oficial (instala em ~/.opencode/bin).
# Se já houver versão >= a mais recente instalada, pula a instalação e vai
# direto para a configuração (agents-config, em 50-configs.sh).
OC_BIN="$(command -v opencode 2>/dev/null || true)"
OC_LOCAL=''; OC_LATEST=''
if [[ -n ${OC_BIN} ]]; then
  OC_LOCAL="$("${OC_BIN}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -n1 || true)"
fi
# consulta a versão remota só em modo real — dry-run não acessa a rede
if [[ ${DRY_RUN} == 0 ]]; then
  OC_LATEST="$(curl -fsSL --retry 2 --max-time 15 https://opencode.ai/update/api/latest/cli/npm 2>/dev/null \
    | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n1 || true)"
else
  OC_LATEST="${OC_LOCAL}"   # em dry-run: assume atualizado e não baixa nada
fi
if [[ -n ${OC_LOCAL} && -n ${OC_LATEST} ]] \
   && [[ "$(printf '%s\n%s\n' "${OC_LOCAL}" "${OC_LATEST}" | sort -V | tail -n1)" == "${OC_LOCAL}" ]]; then
  ok "OpenCode já está atualizado (${OC_LOCAL}) — pulando instalação; indo para a configuração"
else
  log "stack: OpenCode v2 CLI (script oficial: curl -fsSL https://opencode.ai/v2/install | bash)"
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" "SHELL=${TU_SHELL}" \
    bash -c 'curl -fsSL https://opencode.ai/v2/install | bash' \
    || warn "OpenCode: falha na instalação pelo script oficial"
fi
# o instalador v2 instala em ~/.opencode/bin e mexe no PATH dos shells;
# o symlink abaixo garante o comando em qualquer sessão (gráfica inclusive)
run_cmd ln -sf "${TU_HOME}/.opencode/bin/opencode" /usr/local/bin/opencode \
  || warn "OpenCode: falha ao criar symlink em /usr/local/bin"

# Brave — repo oficial da Brave Software (dnf5 em F41+; fallback dnf4)
if ! rpm -q brave-browser >/dev/null 2>&1; then
  log "stack: Brave (repo oficial RPM)"
  if command -v dnf5 >/dev/null 2>&1; then
    run_cmd dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
      || warn "Brave: falha ao adicionar o repo (dnf5)"
  else
    run_cmd dnf config-manager --add-repo=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
      || warn "Brave: falha ao adicionar o repo (dnf4)"
  fi
  run_cmd dnf -y "${DNFOPT}" install brave-browser || warn "Brave: falha na instalação"
else
  ok "Brave já instalado"
fi

# ONLYOFFICE — repo oficial
if ! rpm -q onlyoffice-desktopeditors >/dev/null 2>&1; then
  log "stack: ONLYOFFICE Desktop Editors (repo oficial RPM)"
  run_cmd dnf -y install https://download.onlyoffice.com/repo/centos/main/noarch/onlyoffice-repo.noarch.rpm \
    || warn "ONLYOFFICE: falha ao adicionar o repo"
  run_cmd dnf -y "${DNFOPT}" install onlyoffice-desktopeditors \
    || warn "ONLYOFFICE indisponível — instale manualmente o RPM oficial"
else
  ok "ONLYOFFICE já instalado"
fi

# SSH_Orchestrator — cliente SSH/SFTP (Tauri), RPM da release oficial no GitHub
if rpm -qa | grep -qi '^ssh-orchestrator'; then
  ok "SSH_Orchestrator já instalado"
else
  log "stack: SSH_Orchestrator (RPM da release mais recente no GitHub)"
  SSH_ORCH_API="https://api.github.com/repos/marcos2872/SSH_Orchestrator/releases/latest"
  SSH_ORCH_URL=""
  if [[ ${DRY_RUN} == 0 ]]; then
    SSH_ORCH_URL="$(curl -fsSL "${SSH_ORCH_API}" 2>/dev/null \
      | grep -oE '"browser_download_url":[[:space:]]*"[^"]*x86_64\.rpm"' \
      | head -n1 | sed -E 's/.*"([^"]+)"$/\1/' || true)"
  fi
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: baixaria o RPM x86_64 da última release (${SSH_ORCH_API}) e instalaria com dnf"
  elif [[ -n ${SSH_ORCH_URL} ]]; then
    run_cmd dnf -y "${DNFOPT}" install "${SSH_ORCH_URL}" \
      || warn "SSH_Orchestrator: falha ao instalar o RPM da release"
  else
    warn "SSH_Orchestrator: não encontrei asset .x86_64.rpm na última release"
  fi
fi

# LocalSend — compartilhamento de arquivos na LAN (alternativa ao AirDrop).
# O Fedora não empacota e a release oficial não publica RPM: instalamos o
# flatpak OFICIAL do desenvolvedor no Flathub (org.localsend.localsend_app —
# o mesmo canal indicado no site oficial). O remote flathub é criado se faltar.
# Idempotente: se o app já está instalado, não faz nada.
LOCALSEND_ID='org.localsend.localsend_app'
if ! command -v flatpak >/dev/null 2>&1; then
  warn "LocalSend: flatpak ausente — instale pelo Flathub (${LOCALSEND_ID})"
elif flatpak list --app --columns=application 2>/dev/null | grep -qx "${LOCALSEND_ID}"; then
  ok "LocalSend já instalado (flatpak)"
else
  log "stack: LocalSend (flatpak oficial do Flathub)"
  flatpak remotes --columns=name 2>/dev/null | grep -qx flathub \
    || run_cmd flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || warn "LocalSend: falha ao adicionar o remote flathub"
  run_cmd flatpak install -y flathub "${LOCALSEND_ID}" \
    || warn "LocalSend: falha na instalação pelo flatpak"
fi

# ─── 8. Shell do Plasma (remoção AGENDADA para o próximo boot) ──────────────
# NUNCA removemos o desktop em uso: o %preun do plasmalogin/plasma-* mexe nos
# serviços systemd (remove-system-units para/desabilita o plasmalogin), o que
# derruba a sessão gráfica atual — matando o instalador no meio da transação
# dnf (o mesmo valia para o gdm). A remoção é agendada via systemd para rodar
# no próximo boot, ANTES do login (myos-remove-plasma.service).
# Sai só o SHELL do Plasma (desktop/workspace/login manager + wizard de
# primeiro login). Os apps KDE ficam — inclusive o plasma-discover, que segue
# funcionando com o PackageKit.
if [[ ${SKIP_REMOVE:-0} == 1 ]]; then
  log "stack: remoções desativadas (--skip-remove)"
else
  REMOVE_PKGS=()
  for heavy in plasma-desktop plasma-workspace plasma-login-manager plasma-setup plasma-welcome; do
    if rpm -q "${heavy}" >/dev/null 2>&1; then
      REMOVE_PKGS+=("${heavy}")
    fi
  done
  if ((${#REMOVE_PKGS[@]} > 0)); then
    if exige_ok "agendar a remoção do shell do Plasma (${REMOVE_PKGS[*]}) para o próximo boot?"; then
      install_file "libexec/myos-remove-plasma" "/usr/local/libexec/myos-remove-plasma"
      run_cmd chmod 755 /usr/local/libexec/myos-remove-plasma
      install_file "myos-remove-plasma.service" "/etc/systemd/system/myos-remove-plasma.service"
      run_cmd systemctl enable myos-remove-plasma.service >/dev/null 2>&1 || true
      ok "shell do Plasma será removido no PRÓXIMO BOOT (antes do login, sem sessão em uso)"
    else
      warn "shell do Plasma mantido — será apenas mascarado em 30-services.sh"
    fi
  fi
fi

# ─── 9. Flatpak × controle parental (malcontent) ────────────────────────────
# Só importa quando o accounts-daemon desta versão do Fedora tem o suporte a
# parental controls compilado (interface com.endlessm.ParentalControls). Nesse
# caso, se o pacote malcontent (dono da regra polkit da consulta) for removido,
# TODO `flatpak run` falha com "Not allowed to query parental controls data
# for user N" (flatpak/flatpak#6142). A checagem abaixo é compile-time: sem a
# interface no daemon, o flatpak usa o fallback e o malcontent é dispensável.
if command -v flatpak >/dev/null 2>&1; then
  if grep -qs 'com\.endlessm\.ParentalControls' /usr/libexec/accounts-daemon 2>/dev/null; then
    if rpm -q malcontent >/dev/null 2>&1; then
      run_cmd dnf -y mark user malcontent \
        || warn "malcontent: falha ao marcar como user-installed"
    else
      warn "flatpak + parental controls: malcontent ausente — reparando (sem ele nenhum flatpak abriria)"
      run_cmd dnf -y "${DNFOPT}" install malcontent \
        || warn "malcontent: falha na instalação — flatpaks podem não abrir"
      # o accounts-daemon expõe as interfaces de parental controls ao subir;
      # o try-restart recarrega (não faz nada se o serviço estiver parado)
      run_cmd systemctl try-restart accounts-daemon || true
    fi
  else
    log "stack: accounts-daemon sem parental controls — malcontent não é necessário"
  fi
else
  log "stack: flatpak ausente — malcontent não é necessário"
fi

run_cmd dnf clean all || true
ok "stack instalado"
