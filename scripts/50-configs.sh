#!/usr/bin/env bash
# 50-configs.sh — configurações finais:
#   • niri (config.kdl do usuário + fallback do sistema)
#   • Noctalia (esqueleto de config do usuário)
#   • greetd + PAM (greeter Noctalia se disponível)
#   • papel de parede padrão + helper myos-wallpaper
#   • Brave como navegador padrão do usuário

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
[[ -d ${TU_HOME} ]] || { err "home de ${TU} não encontrado (${TU_HOME})"; exit 1; }
log "config: configurando para o usuário: ${TU} (${TU_HOME})"

# ─── 1. niri ────────────────────────────────────────────────────────────────
install_file "niri/config.kdl" "${TU_HOME}/.config/niri/config.kdl"
install_file "niri/config.kdl" "/etc/xdg/niri/config.kdl"

# ─── 2. Noctalia (esqueleto; padrões da instalação já funcionam) ────────────
install_file "noctalia/config.toml" "${TU_HOME}/.config/noctalia/config.toml"

# ─── 2b. Noctalia: defaults do MyOS (settings + plugins) ────────────────────
# A config real do Noctalia v5 vive em ~/.local/state/noctalia/ (settings.toml
# + plugins/). Instalamos os defaults do repo SOMENTE se ainda não existirem —
# uma personalização existente nunca é sobrescrita.
NOCT_STATE="${TU_HOME}/.local/state/noctalia"
if [[ -f ${NOCT_STATE}/settings.toml ]]; then
  log "noctalia: settings.toml já existe — mantendo a personalização atual"
else
  install_file "noctalia/settings.toml" "${NOCT_STATE}/settings.toml"
fi
if [[ ${DRY_RUN} == 1 ]]; then
  log "dry-run: copiaria assets/noctalia/plugins/* → ${NOCT_STATE}/plugins/ (somente os ausentes)"
  log "dry-run: copiaria assets/noctalia/plugins-local/* → ${TU_HOME}/.local/share/noctalia/plugins/ (somente os ausentes)"
else
  for plug in "${MYOS_ROOT}"/assets/noctalia/plugins/*/*/*; do
    [[ -d ${plug} ]] || continue
    rel="${plug#"${MYOS_ROOT}"/assets/noctalia/plugins/}"
    if [[ -d ${NOCT_STATE}/plugins/${rel} ]]; then
      log "noctalia: plugin '${rel}' já instalado — mantido"
    else
      mkdir -p "${NOCT_STATE}/plugins/$(dirname "${rel}")"
      cp -a "${plug}" "${NOCT_STATE}/plugins/${rel}"
      log "noctalia: plugin '${rel}' instalado"
    fi
  done
  # plugins locais (documentado: ~/.local/share/noctalia/plugins/<plugin>/ é
  # descoberto como "local source" — funciona sem rede e sem registro)
  for plug in "${MYOS_ROOT}"/assets/noctalia/plugins-local/*; do
    [[ -d ${plug} ]] || continue
    name="$(basename "${plug}")"
    if [[ -d ${TU_HOME}/.local/share/noctalia/plugins/${name} ]]; then
      log "noctalia: plugin local '${name}' já instalado — mantido"
    else
      mkdir -p "${TU_HOME}/.local/share/noctalia/plugins"
      cp -a "${plug}" "${TU_HOME}/.local/share/noctalia/plugins/${name}"
      log "noctalia: plugin local '${name}' instalado"
    fi
  done
fi

# ─── 3. Papel de parede + helper ────────────────────────────────────────────
install_file "bin/myos-wallpaper" "/usr/local/bin/myos-wallpaper"
run_cmd chmod 755 /usr/local/bin/myos-wallpaper
for w in "${MYOS_ROOT}"/assets/wallpapers/*; do
  [[ -f ${w} ]] || continue
  install_file "wallpapers/$(basename "${w}")" "/usr/share/myos-walls/$(basename "${w}")"
done

# ─── 4. greetd — escolhe o greeter disponível ───────────────────────────────
GREETER_BIN="$(command -v noctalia-greeter-session 2>/dev/null || true)"
if [[ -z ${GREETER_BIN} && ${DRY_RUN} == 1 && ${NO_GREETER} != 1 ]]; then
  GREETER_BIN="/usr/bin/noctalia-greeter-session"   # esperado após a instalação
fi
if [[ -n ${GREETER_BIN} ]]; then
  GREETER_CMD="${GREETER_BIN} -- --session niri"
  ok "greeter: Noctalia (${GREETER_BIN})"
else
  GREETER_CMD="greetd"
  log "greeter: padrão do greetd (noctalia-greeter não instalado)"
fi
render_file "greetd/config.toml" "/etc/greetd/config.toml" "__GREETER_CMD__" "${GREETER_CMD}"

# PAM do greetd: o pacote do Fedora já traz o arquivo correto (com pam_selinux —
# sem ele o SELinux em enforcing bloqueia o systemctl --user da sessão e o niri
# volta para a tela de login). NÃO sobrescrevemos; apenas restauramos se
# detectarmos uma versão antiga do MyOS sem pam_selinux.
if [[ -f /etc/pam.d/greetd ]] && ! grep -q 'pam_selinux' /etc/pam.d/greetd; then
  if [[ -f /etc/pam.d/greetd.myos-bak ]]; then
    warn "greetd: /etc/pam.d/greetd sem pam_selinux — restaurando backup do pacote"
    run_cmd cp -f /etc/pam.d/greetd.myos-bak /etc/pam.d/greetd
  else
    warn "greetd: /etc/pam.d/greetd sem pam_selinux — instalando versão correta do MyOS"
    install_file "pam.d/greetd" "/etc/pam.d/greetd"
  fi
elif [[ ! -f /etc/pam.d/greetd ]]; then
  install_file "pam.d/greetd" "/etc/pam.d/greetd"
else
  log "greetd: /etc/pam.d/greetd ok (mantendo o do pacote)"
fi

# ─── 5. OpenCode — configuração pessoal (agents-config) ─────────────────────
# Repo público https://github.com/marcos2872/agents-config: agentes, skills,
# commands e plugins. O sync.sh do repo copia tudo para ~/.config/opencode/
# (com backup automático do que já existir).
AGENTS_REPO="https://github.com/marcos2872/agents-config.git"
AGENTS_DIR="${TU_HOME}/.local/share/agents-config"
log "config: OpenCode (agents-config: agentes, skills, commands, plugins)"
if [[ ${DRY_RUN} == 1 ]]; then
  log "dry-run: clonaria ${AGENTS_REPO} → ${AGENTS_DIR} e rodaria ./sync.sh"
elif [[ -d ${AGENTS_DIR}/.git ]]; then
  run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' git -C '${AGENTS_DIR}' pull --ff-only" \
    || warn "agents-config: falha no git pull (seguindo com a cópia local)"
  run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' bash '${AGENTS_DIR}/sync.sh'" \
    || warn "agents-config: falha ao aplicar o sync.sh"
else
  run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' git clone '${AGENTS_REPO}' '${AGENTS_DIR}'" \
    && run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' bash '${AGENTS_DIR}/sync.sh'" \
    || warn "agents-config: falha na configuração do OpenCode (clone/sync)"
fi

# ─── 6. Brave como navegador padrão (do usuário) ────────────────────────────
if command -v brave-browser >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; then
  run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' xdg-settings set default-web-browser brave-browser.desktop >/dev/null 2>&1 || true"
  run_sh "runuser -u ${TU} -- env HOME='${TU_HOME}' xdg-mime default brave-browser.desktop x-scheme-handler/https x-scheme-handler/http >/dev/null 2>&1 || true"
  ok "Brave definido como navegador padrão (https/http)"
fi

# ─── 7. Terminal: tema do alacritty + zsh com autocomplete ──────────────────
install_file "alacritty/alacritty.toml" "${TU_HOME}/.config/alacritty/alacritty.toml"
install_file "zsh/zshrc" "${TU_HOME}/.zshrc"
if command -v zsh >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; then
  run_sh "chsh -s /usr/bin/zsh '${TU}'" || warn "chsh: falha ao definir o zsh como shell padrão"
  ok "shell padrão: zsh (sugestões inline + syntax highlight + fzf no Ctrl+R)"
fi

# ─── 8. Permissões dos arquivos do usuário ──────────────────────────────────
run_cmd chown -R "${TU}:${TU}" "${TU_HOME}/.config/niri" "${TU_HOME}/.config/noctalia" "${TU_HOME}/.config/alacritty" "${TU_HOME}/.local/state/noctalia" "${TU_HOME}/.local/share/noctalia"
run_cmd chown "${TU}:${TU}" "${TU_HOME}/.zshrc"

cat <<EOF

──────────────────────────────────────────────────────────────
 MyOS instalado. O que esperar no próximo boot:

   • Tela de login do greetd (Noctalia Greeter, se instalado)
     com a sessão "niri" já disponível
   • Shell: Noctalia v5 (barra, launcher, notificações, lock, OSD)
   • Atalhos: Super+T terminal · Super+Space launcher · Super+S control center
              Super+B Brave · Super+E Zed · Super+P monitores · Alt+Tab switcher
              Print screenshot (o restante são os defaults oficiais do niri)
   • Editor: Zed · IA no terminal: opencode · Office: ONLYOFFICE

 Verificações pós-reboot:
   systemctl status greetd
   journalctl -u greetd -n 30
   free -h ; zramctl                 # swap comprimido ativo
   ps aux --sort=-rss | head -12     # top consumidores de RAM

 Dica: apps pesados (Brave/ONLYOFFICE/Zed) só consomem RAM quando abertos.
──────────────────────────────────────────────────────────────
EOF
ok "configuração concluída"
