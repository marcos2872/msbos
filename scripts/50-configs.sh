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
install_file "pam.d/greetd" "/etc/pam.d/greetd"

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
run_cmd chown -R "${TU}:${TU}" "${TU_HOME}/.config/niri" "${TU_HOME}/.config/noctalia" "${TU_HOME}/.config/alacritty"
run_cmd chown "${TU}:${TU}" "${TU_HOME}/.zshrc"

cat <<EOF

──────────────────────────────────────────────────────────────
 MyOS instalado. O que esperar no próximo boot:

   • Tela de login do greetd (Noctalia Greeter, se instalado)
     com a sessão "niri" já disponível
   • Shell: Noctalia v5 (barra, launcher, notificações, lock, OSD)
   • Atalhos: Super+T terminal · Super+B Brave · Super+E Zed
              Super+Print screenshot · Super+Shift+E sair
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
