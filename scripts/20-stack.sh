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

# ─── 1. Núcleo (obrigatório) ────────────────────────────────────────────────
CORE=(
  greetd niri noctalia jemalloc
  pipewire pipewire-pulse wireplumber
  xdg-desktop-portal xdg-desktop-portal-gtk
  polkit NetworkManager
  power-profiles-daemon tuned
  curl git xdg-utils
  google-noto-sans-fonts google-noto-sans-mono-fonts
)
log "stack: instalando núcleo: ${CORE[*]}"
if ! run_sh "dnf -y ${DNFOPT} install ${CORE[*]}"; then
  err "falha ao instalar o núcleo do stack — abortando"
  exit 1
fi
ok "núcleo instalado"

# ─── 2. Utilitários leves ───────────────────────────────────────────────────
UTILS=(alacritty grim slurp brightnessctl wl-cliphist playerctl)
for p in "${UTILS[@]}"; do
  run_sh "dnf -y ${DNFOPT} install ${p}" || warn "utilitário '${p}' indisponível — ignorado"
done
for p in swaybg wlsunset ddcutil pipewire-alsa; do
  run_sh "dnf -y ${DNFOPT} install ${p}" || warn "opcional '${p}' indisponível — ignorado"
done

# ─── 3. Bluetooth (só se houver adaptador) ──────────────────────────────────
if [[ -n "$(ls /sys/class/bluetooth 2>/dev/null)" ]]; then
  run_sh "dnf -y ${DNFOPT} install bluez" || warn "bluez: falha na instalação"
else
  log "stack: sem adaptador Bluetooth — bluez não será instalado"
fi

# ─── 4. Greeter do Noctalia (repo comunitário Terra) ────────────────────────
if [[ ${NO_GREETER} == 1 ]]; then
  log "stack: greeter Noctalia desativado (--no-greeter)"
else
  install_file "yum.repos.d/terra.repo" "/etc/yum.repos.d/myos-terra.repo"
  warn "repo comunitário Terra (fyralabs) habilitado para o pacote noctalia-greeter"
  run_sh "dnf -y ${DNFOPT} install noctalia-greeter" \
    || warn "noctalia-greeter indisponível — o greetd usará o greeter padrão"
fi

# ─── 5. Aplicativos do usuário ──────────────────────────────────────────────

# Zed — script oficial (instala em ~/.local/bin, com auto-update)
log "stack: Zed (script oficial: curl -fsSL https://zed.dev/install.sh | sh)"
run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' SHELL='${TU_SHELL}' bash -c 'curl -fsSL https://zed.dev/install.sh | sh'" \
  || warn "Zed: falha na instalação pelo script oficial"

# OpenCode v2 CLI — script oficial (instala em ~/.opencode/bin)
log "stack: OpenCode v2 CLI (script oficial: curl -fsSL https://opencode.ai/v2/install | bash)"
run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' SHELL='${TU_SHELL}' bash -c 'curl -fsSL https://opencode.ai/v2/install | bash'" \
  || warn "OpenCode: falha na instalação pelo script oficial"
# o instalador v2 instala em ~/.opencode/bin e mexe no PATH dos shells;
# o symlink abaixo garante o comando em qualquer sessão (gráfica inclusive)
run_sh "ln -sf '${TU_HOME}/.opencode/bin/opencode' /usr/local/bin/opencode" \
  || warn "OpenCode: falha ao criar symlink em /usr/local/bin"

# Brave — repo oficial da Brave Software (dnf5 em F41+; fallback dnf4)
if ! rpm -q brave-browser >/dev/null 2>&1; then
  log "stack: Brave (repo oficial RPM)"
  if command -v dnf5 >/dev/null 2>&1; then
    run_sh "dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo" \
      || warn "Brave: falha ao adicionar o repo (dnf5)"
  else
    run_sh "dnf config-manager --add-repo=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo" \
      || warn "Brave: falha ao adicionar o repo (dnf4)"
  fi
  run_sh "dnf -y ${DNFOPT} install brave-browser" || warn "Brave: falha na instalação"
else
  ok "Brave já instalado"
fi

# ONLYOFFICE — repo oficial
if ! rpm -q onlyoffice-desktopeditors >/dev/null 2>&1; then
  log "stack: ONLYOFFICE Desktop Editors (repo oficial RPM)"
  run_sh "dnf -y install https://download.onlyoffice.com/repo/centos/main/noarch/onlyoffice-repo.noarch.rpm" \
    || warn "ONLYOFFICE: falha ao adicionar o repo"
  run_sh "dnf -y ${DNFOPT} install onlyoffice-desktopeditors" \
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
    run_sh "dnf -y ${DNFOPT} install '${SSH_ORCH_URL}'" \
      || warn "SSH_Orchestrator: falha ao instalar o RPM da release"
  else
    warn "SSH_Orchestrator: não encontrei asset .x86_64.rpm na última release"
  fi
fi

# ─── 6. Peso morto (destrutivo → exige --yes) ───────────────────────────────
if [[ ${SKIP_REMOVE:-0} == 1 ]]; then
  log "stack: remoções desativadas (--skip-remove)"
else
  if rpm -q gdm >/dev/null 2>&1; then
    if exige_ok "remover o GDM (será substituído pelo greetd no próximo boot)?"; then
      run_sh "dnf -y ${DNFOPT} remove gdm" || warn "falha ao remover gdm"
    else
      warn "GDM mantido — será apenas mascarado em 30-services.sh"
    fi
  fi
  for heavy in gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-software; do
    rpm -q "${heavy}" >/dev/null 2>&1 || continue
    if exige_ok "remover '${heavy}' (substituído por niri/Noctalia)?"; then
      run_sh "dnf -y ${DNFOPT} remove ${heavy}" || warn "falha ao remover ${heavy}"
    fi
  done
fi

run_sh "dnf clean all" || true
ok "stack instalado"
