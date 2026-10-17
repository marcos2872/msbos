#!/usr/bin/env bash
# 20-stack.sh — stack base (niri + Noctalia + greetd + áudio + utilitários)
# e aplicativos do usuário (Zed, OpenCode v2, Brave, ONLYOFFICE).
#
# Métodos de instalação:
#   niri/Noctalia/greetd/áudio   → dnf (repos oficiais do Fedora)
#   noctalia-greeter             → repo comunitário Terra (--no-greeter p/ pular)
#   Zed                          → script oficial  (curl -fsSL https://zed.dev/install.sh | sh)
#   OpenCode v2 CLI              → script oficial  (curl -fsSL https://opencode.ai/v2/install | bash)
#   Brave                        → repo oficial RPM da Brave Software
#   ONLYOFFICE                   → repo oficial RPM da ONLYOFFICE

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
CORE=(
  greetd niri noctalia jemalloc
  pipewire pipewire-pulse wireplumber
  xdg-desktop-portal xdg-desktop-portal-gtk
  polkit lxpolkit udisks2 gvfs-udisks2 gvfs-mtp
  NetworkManager
  tuned
  curl git xdg-utils
  google-noto-sans-fonts google-noto-sans-mono-fonts
)
log "stack: instalando núcleo: ${CORE[*]}"
if ! run_cmd dnf -y "${DNFOPT}" install "${CORE[@]}"; then
  err "falha ao instalar o núcleo do stack — abortando"
  exit 1
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
# nautilus + ntfs/exfat: sem eles o erro é "Not authorized to perform operation"
# (udisks2 sem gvfs) ou volume ilegível (NTFS/exFAT de SSDs externos).
UTILS=(alacritty grim slurp brightnessctl playerctl nautilus ntfs-3g exfatprogs dosfstools)
for p in "${UTILS[@]}"; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || warn "utilitário '${p}' indisponível — ignorado"
done
for p in swaybg wlsunset ddcutil pipewire-alsa; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || warn "opcional '${p}' indisponível — ignorado"
done

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

# ─── 8. GDM/GNOME (remoção AGENDADA para o próximo boot) ────────────────────
# NUNCA removemos o desktop em uso: o %preun do gdm executa
# "systemctl disable --now gdm.service", que para o gdm e derruba a sessão
# gráfica atual — matando o instalador no meio da transação dnf (isso já
# congelou uma máquina de verdade). A remoção é agendada via systemd para
# rodar no próximo boot, ANTES do login (myos-remove-gnome.service).
if [[ ${SKIP_REMOVE:-0} == 1 ]]; then
  log "stack: remoções desativadas (--skip-remove)"
else
  REMOVE_PKGS=()
  for heavy in gdm gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-software; do
    if rpm -q "${heavy}" >/dev/null 2>&1; then
      REMOVE_PKGS+=("${heavy}")
    fi
  done
  if ((${#REMOVE_PKGS[@]} > 0)); then
    if exige_ok "agendar a remoção do GDM/GNOME (${REMOVE_PKGS[*]}) para o próximo boot?"; then
      install_file "libexec/myos-remove-gnome" "/usr/local/libexec/myos-remove-gnome"
      run_cmd chmod 755 /usr/local/libexec/myos-remove-gnome
      install_file "myos-remove-gnome.service" "/etc/systemd/system/myos-remove-gnome.service"
      run_cmd systemctl enable myos-remove-gnome.service >/dev/null 2>&1 || true
      ok "GDM/GNOME serão removidos no PRÓXIMO BOOT (antes do login, sem sessão em uso)"
    else
      warn "GDM/GNOME mantidos — serão apenas mascarados em 30-services.sh"
    fi
  fi
fi

# ─── 9. Flatpak × controle parental (malcontent) ────────────────────────────
# Todo `flatpak run` consulta parental controls via AccountsService, e a ação
# polkit dessa consulta vive no pacote malcontent. Sem ele a consulta é negada
# e NENHUM flatpak abre ("Not allowed to query parental controls data for
# user N" — flatpak/flatpak#6142). No Workstation ele chega como dependência
# do GNOME; aqui garantimos que exista (reparo para máquinas onde a remoção o
# levou embora) e o fixamos como escolha do usuário, para a cascata do dnf5
# não removê-lo de novo (libexec/myos-remove-gnome também o protege).
if command -v flatpak >/dev/null 2>&1; then
  if rpm -q malcontent >/dev/null 2>&1; then
    run_cmd dnf -y mark user malcontent \
      || warn "malcontent: falha ao marcar como user-installed"
  else
    warn "flatpak: malcontent ausente — nenhum flatpak abriria; reinstalando"
    run_cmd dnf -y "${DNFOPT}" install malcontent \
      || warn "malcontent: falha na instalação — flatpaks podem não abrir"
    # o accounts-daemon expõe as interfaces de parental controls ao subir;
    # o try-restart recarrega (não faz nada se o serviço estiver parado)
    run_cmd systemctl try-restart accounts-daemon || true
  fi
else
  log "stack: flatpak ausente — malcontent não é necessário"
fi

run_cmd dnf clean all || true
ok "stack instalado"
