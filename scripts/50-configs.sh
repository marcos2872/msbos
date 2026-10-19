#!/usr/bin/env bash
# 50-configs.sh — configurações finais:
#   • niri (config.kdl do usuário + fallback do sistema)
#   • Noctalia (esqueleto de config do usuário)
#   • tema dark dos apps: Breeze Dark (o dark padrão do KDE) + GTK
#   • greetd + PAM (greeter Noctalia se disponível)
#   • papel de parede padrão + helper omyfedora-wallpaper
#   • Brave como navegador padrão do usuário

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
[[ -d ${TU_HOME} ]] || { err "home de ${TU} não encontrado (${TU_HOME})"; exit 1; }
log "config: configurando para o usuário: ${TU} (${TU_HOME})"

# ─── 1. niri ────────────────────────────────────────────────────────────────
# Config do USUÁRIO: só instala se não existir (install_file_once) — o niri
# substitui TODOS os binds default quando o config define qualquer bind, então
# esse arquivo é o "default set" completo do omyfedora; sobrescrevê-lo depois comeria
# a personalização de quem mexeu nos atalhos.
install_file_once "niri/config.kdl" "${TU_HOME}/.config/niri/config.kdl"
# Fallback de sistema: o omyfedora é dono dele, pode ser sempre atualizado.
install_file "niri/config.kdl" "/etc/xdg/niri/config.kdl"

# ─── 2. Noctalia (esqueleto; padrões da instalação já funcionam) ────────────
install_file_once "noctalia/config.toml" "${TU_HOME}/.config/noctalia/config.toml"
# Auto-Sync do Greeter em arquivo separado: o Noctalia lê todos os .toml de
# ~/.config/noctalia/, então o omyfedora pode atualizar esta política sem
# tocar no config.toml personalizado do usuário.
install_file "noctalia/90-greeter-sync.toml" "${TU_HOME}/.config/noctalia/90-greeter-sync.toml"

# ─── 2a. Noctalia: paleta(s) do tema ────────────────────────────────────────
# [theme] custom_palette (config.toml) aponta para "macOS", que o Noctalia
# procura em ~/.config/noctalia/palettes/macOS.json. A paleta é parte do tema
# que o omyfedora entrega, então usa install_file (com backup .omyfedora-bak): para
# customizar, crie outra paleta nessa pasta e aponte custom_palette para ela.
NOCT_CONF="${TU_HOME}/.config/noctalia"
for paleta in "${OMYFEDORA_ROOT}"/assets/noctalia/palettes/*.json; do
  [[ -f ${paleta} ]] || continue
  install_file "noctalia/palettes/$(basename "${paleta}")" \
    "${NOCT_CONF}/palettes/$(basename "${paleta}")"
done

# ─── 2b. Noctalia: defaults do omyfedora (settings + plugins) ────────────────────
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
  # copia_plugin <dir_do_plugin_no_repo> <dir_de_destino> — copia arquivo por
  # arquivo via install_file (nunca cp direto): garante modo, dono e contexto
  # SELinux corretos no destino, além do backup .omyfedora-bak. Se o destino já
  # existe, o plugin é mantido como está.
  copia_plugin() {
    local src_dir="$1" dst_dir="$2" rel f sub
    rel="${src_dir#"${OMYFEDORA_ROOT}"/assets/}"
    if [[ -d ${dst_dir} ]]; then
      log "noctalia: plugin '${rel}' já instalado — mantido"
      return 0
    fi
    while IFS= read -r -d '' f; do
      sub="${f#"${src_dir}"/}"
      install_file "${rel}/${sub}" "${dst_dir}/${sub}" \
        || warn "noctalia: falha ao copiar ${rel}/${sub}"
    done < <(find "${src_dir}" -type f -print0 | sort -z)
    log "noctalia: plugin '${rel}' instalado"
  }

  for plug in "${OMYFEDORA_ROOT}"/assets/noctalia/plugins/*/*/*; do
    [[ -d ${plug} ]] || continue
    rel="${plug#"${OMYFEDORA_ROOT}"/assets/noctalia/plugins/}"
    copia_plugin "${plug}" "${NOCT_STATE}/plugins/${rel}"
  done
  # plugins locais (documentado: ~/.local/share/noctalia/plugins/<plugin>/ é
  # descoberto como "local source" — funciona sem rede e sem registro)
  for plug in "${OMYFEDORA_ROOT}"/assets/noctalia/plugins-local/*; do
    [[ -d ${plug} ]] || continue
    name="$(basename "${plug}")"
    copia_plugin "${plug}" "${TU_HOME}/.local/share/noctalia/plugins/${name}"
  done
fi

# ─── 2c. Tema dark dos apps: Breeze Dark (o dark padrão do KDE) ─────────────
# O omyfedora não entrega tema próprio: os apps usam o "Breeze Dark" do KDE. O
# shell (Noctalia) segue com o visual próprio dele — ele não é KDE/GTK/Qt.
# A fonte da verdade é o KDE do próprio usuário: o 1º bloco só PREENCHE chaves
# que o usuário ainda não definiu no ~/.config/kdeglobals/kcminputrc (o System
# Settings mexe nos MESMOS arquivos — uma escolha feita na GUI nunca é
# sobrescrita). O resto garante o mesmo dark nos apps GTK/Electron, que leem
# dconf/portal + settings.ini:
#   • /etc/dconf/db/local.d/00-omyfedora-dark: padrão de sistema (color-scheme +
#     gtk/icon/cursor-theme) aplicado via `dconf update` — vale para todo usuário.
#   • ~/.config/gtk-3.0|4.0/settings.ini: fallback lido direto pelo GTK, sem
#     precisar de sessão D-Bus (cobre diálogos no primeiro login).
#   • /etc/profile.d/omyfedora-theme.sh: XCURSOR_* (cursor breeze_cursors único no
#     niri e nos apps) + QT_QPA_PLATFORMTHEME=kde (platform theme do KDE,
#     plasma-integration — sem ele os apps Qt não aplicam o Breeze).
#   • gsettings como TU: atualiza o banco dconf EXISTENTE do usuário (o default
#     de sistema sozinho não muda um user db já criado como claro).
# Idempotente: arquivos de tema são dono do omyfedora (install_file, com backup
# .omyfedora-bak); o gsettings só escreve quando o valor atual ainda não é o escuro;
# o kwriteconfig6 só escreve no kdeglobals o que o usuário não escolheu.
if [[ ${DRY_RUN} == 1 ]]; then
  log "dry-run: preencheria Breeze Dark (ColorScheme/widgetStyle/Icons/cursor) no kdeglobals/kcminputrc de ${TU} — só o que ainda não foi definido"
elif command -v kwriteconfig6 >/dev/null 2>&1; then
  kcfg() {  # preenche a chave SÓ se o usuário ainda não escolheu (System Settings manda)
    local file="$1" group="$2" key="$3" val="$4"
    if [[ -f ${TU_HOME}/.config/${file} ]] \
       && grep -qE "^${key}[[:space:]]*=" "${TU_HOME}/.config/${file}"; then
      log "tema: ${file} ${key} já definido pelo usuário — mantido"
      return 0
    fi
    run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" \
      kwriteconfig6 --file "${file}" --group "${group}" --key "${key}" "${val}" \
      || warn "tema: falha ao definir ${key}=${val} em ${file}"
  }
  kcfg kdeglobals General ColorScheme BreezeDark
  kcfg kdeglobals KDE widgetStyle Breeze
  kcfg kdeglobals Icons Theme breeze-dark
  kcfg kcminputrc Mouse cursorTheme breeze_cursors
else
  warn "tema: kwriteconfig6 ausente (kde-cli-tools) — apps KDE/Qt usam o padrão do sistema"
fi
install_file "gtk-3.0/settings.ini" "${TU_HOME}/.config/gtk-3.0/settings.ini"
install_file "gtk-4.0/settings.ini" "${TU_HOME}/.config/gtk-4.0/settings.ini"
install_file "profile.d/omyfedora-theme.sh" "/etc/profile.d/omyfedora-theme.sh"
install_file "dconf/db/local.d/00-omyfedora-dark" "/etc/dconf/db/local.d/00-omyfedora-dark"
run_cmd dconf update || warn "dconf update falhou — padrão de sistema pode não aplicar"
if [[ ${DRY_RUN} == 1 ]]; then
  log "dry-run: definiria gtk-theme=Breeze, color-scheme=prefer-dark, icon-theme=breeze-dark e cursor=breeze_cursors para ${TU}"
else
  # dbus-run-session permite rodar o gsettings sem sessão gráfica ativa; o
  # dconf persiste em ~/.config/dconf/user, então vale no próximo login.
  GSET_BASE=(runuser -u "${TU}" -- env "HOME=${TU_HOME}")
  if command -v dbus-run-session >/dev/null 2>&1; then
    GSET_BASE+=(dbus-run-session --)
  fi
  gset() {
    local chave="$1" valor="$2"
    local atual
    atual="$("${GSET_BASE[@]}" gsettings get org.gnome.desktop.interface "${chave}" 2>/dev/null || true)"
    [[ ${atual} == "${valor}" ]] \
      || run_cmd "${GSET_BASE[@]}" gsettings set org.gnome.desktop.interface "${chave}" "${valor}" \
      || warn "tema: falha ao definir ${chave}=${valor} para ${TU}"
  }
  gset gtk-theme "'Breeze'"
  gset color-scheme "'prefer-dark'"
  gset icon-theme "'breeze-dark'"
  gset cursor-theme "'breeze_cursors'"
  gset cursor-size "24"
  gset font-name "'Noto Sans 10'"
fi

# ─── 2d. Plymouth — tema de boot do omyfedora ───────────────────────────────
# O splash do boot é do Plymouth (não do GRUB nem do greeter). O Fedora usa o
# tema bgrt, que mostra o watermark do Fedora quando a máquina não tem logo
# BGRT no firmware. O tema omyfedora reaproveita a animação do pacote
# plymouth-theme-spinner e troca o watermark pelo wordmark do projeto, com o
# fundo mSurface (#0B0B0D). O -R regenera o initramfs: sem ele o tema não
# entra no boot (e um rebuild é necessário sempre que os assets mudarem).
PLY_SRC="/usr/share/plymouth/themes/spinner"
PLY_DST="/usr/share/plymouth/themes/omyfedora"
if [[ -d ${PLY_SRC} || ${DRY_RUN} == 1 ]]; then
  if [[ ${DRY_RUN} == 1 && ! -d ${PLY_SRC} ]]; then
    log "dry-run: copiaria ${PLY_SRC}/*.png (exceto watermark.png) → ${PLY_DST}/"
  else
    # cópia system→system num único find+install (não install_file, que é para
    # assets do repo): mantém modo/contexto e deixa o watermark do Fedora fora
    run_cmd find "${PLY_SRC}" -maxdepth 1 -type f -name '*.png' ! -name watermark.png \
      -exec install -D -m 644 {} "${PLY_DST}/" \;
  fi
  install_file "plymouth/omyfedora/omyfedora.plymouth" "${PLY_DST}/omyfedora.plymouth"
  install_file "plymouth/omyfedora/watermark.png" "${PLY_DST}/watermark.png"
  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    if run_cmd plymouth-set-default-theme -R omyfedora; then
      ok "plymouth: tema de boot omyfedora aplicado (initramfs regenerado)"
    else
      warn "plymouth: falha ao aplicar o tema de boot omyfedora"
    fi
  else
    warn "plymouth: plymouth-set-default-theme ausente — tema de boot não aplicado"
  fi
else
  warn "plymouth: tema spinner ausente — instale plymouth-theme-spinner para o tema de boot"
fi

# Logo do sistema (mesma marca do watermark do boot): ícone hicolor + pixmap.
install_file "branding/omyfedora-logo.png" "/usr/share/icons/hicolor/512x512/apps/omyfedora.png"
install_file "branding/omyfedora-logo.png" "/usr/share/pixmaps/omyfedora-logo.png"
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  run_cmd gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor \
    || warn "ícones: falha ao atualizar o cache do hicolor"
fi

# ─── 3. Papel de parede + helper ────────────────────────────────────────────
install_file "bin/omyfedora-wallpaper" "/usr/local/bin/omyfedora-wallpaper"
run_cmd chmod 755 /usr/local/bin/omyfedora-wallpaper
for w in "${OMYFEDORA_ROOT}"/assets/wallpapers/*; do
  [[ -f ${w} ]] || continue
  install_file "wallpapers/$(basename "${w}")" "/usr/share/omyfedora-walls/$(basename "${w}")"
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
# detectarmos uma versão antiga do omyfedora sem pam_selinux.
if [[ -f /etc/pam.d/greetd ]] && ! grep -q 'pam_selinux' /etc/pam.d/greetd; then
  if [[ -f /etc/pam.d/greetd.omyfedora-bak ]]; then
    warn "greetd: /etc/pam.d/greetd sem pam_selinux — restaurando backup do pacote"
    run_cmd cp -f /etc/pam.d/greetd.omyfedora-bak /etc/pam.d/greetd
  else
    warn "greetd: /etc/pam.d/greetd sem pam_selinux — instalando versão correta do omyfedora"
    install_file "pam.d/greetd" "/etc/pam.d/greetd"
  fi
elif [[ ! -f /etc/pam.d/greetd ]]; then
  install_file "pam.d/greetd" "/etc/pam.d/greetd"
else
  log "greetd: /etc/pam.d/greetd ok (mantendo o do pacote)"
fi

# ─── 4a. Noctalia Greeter — Auto-Sync sem prompt ────────────────────────────
# O [shell.greeter_sync] auto_sync (assets/noctalia/90-greeter-sync.toml) copia
# wallpaper, paleta, tema e layout para a tela de login quando mudam. A regra
# Polkit abaixo é restrita à ação org.noctalia.greeter.sync-appearance: o
# helper valida PKEXEC_UID e o staging em /run/user/<uid>, e a regra não
# libera sudo nem outros usos do helper.
if command -v noctalia-greeter >/dev/null 2>&1; then
  if run_cmd noctalia-greeter passwordless-sync enable "${TU}"; then
    ok "greeter: Auto-Sync sem prompt habilitado para ${TU}"
  else
    warn "greeter: falha ao liberar o sync sem prompt — o Auto-Sync pedirá autenticação"
  fi
else
  log "greeter: noctalia-greeter não instalado — Auto-Sync fica indisponível"
fi

# ─── 4b. Zed — configurações, temas e extensões ─────────────────────────────
# O Zed é instalado pelo script oficial em 20-stack.sh; aqui replicamos o
# ambiente do editor:
#   • settings.json — tema, fontes, REPL/Jupyter, feature flags e a lista de
#     extensões em auto_install_extensions (o Zed baixa/atualiza sozinho no
#     primeiro start; a lista atual tem 15 extensões, incluindo temas de ícones)
#   • arquivos extras em assets/zed/ (keymap.json, tasks.json, snippets/,
#     themes/*.json) — qualquer arquivo presente é instalado no caminho espelho
#   • kernelspec "zed-python" do REPL (aponta para o python3 do sistema; o
#     pacote python3-ipykernel é instalado pelo 25-devtools.sh)
# install_file_once: são configs pessoais — uma personalização feita no Zed
# depois da instalação nunca é sobrescrita por uma reexecução do install.sh.
ZED_CONF="${TU_HOME}/.config/zed"
if [[ -d ${OMYFEDORA_ROOT}/assets/zed ]]; then
  while IFS= read -r -d '' f; do
    rel="${f#"${OMYFEDORA_ROOT}"/assets/zed/}"
    install_file_once "zed/${rel}" "${ZED_CONF}/${rel}"
  done < <(find "${OMYFEDORA_ROOT}/assets/zed" -type f -print0 | sort -z)
fi
if rpm -q python3-ipykernel >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; then
  install_file "jupyter/kernels/zed-python/kernel.json" \
    "${TU_HOME}/.local/share/jupyter/kernels/zed-python/kernel.json"
  ok "zed: settings, tema/extensões e kernel do REPL preparados"
else
  warn "zed: python3-ipykernel ausente — kernelspec do REPL não instalado (rode o 25-devtools.sh)"
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
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" git -C "${AGENTS_DIR}" pull --ff-only \
    || warn "agents-config: falha no git pull (seguindo com a cópia local)"
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" bash "${AGENTS_DIR}/sync.sh" \
    || warn "agents-config: falha ao aplicar o sync.sh"
else
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" git clone "${AGENTS_REPO}" "${AGENTS_DIR}" \
    && run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" bash "${AGENTS_DIR}/sync.sh" \
    || warn "agents-config: falha na configuração do OpenCode (clone/sync)"
fi

# ─── 6. Brave como navegador padrão (do usuário) ────────────────────────────
if command -v brave-browser >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; then
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" \
    xdg-settings set default-web-browser brave-browser.desktop >/dev/null 2>&1 || true
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" \
    xdg-mime default brave-browser.desktop x-scheme-handler/https x-scheme-handler/http >/dev/null 2>&1 || true
  ok "Brave definido como navegador padrão (https/http)"
fi

# ─── 6b. Apps KDE como padrões (do usuário) ───────────────────────────────────
mime_default() {
  local desktop="$1"; shift
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" \
    xdg-mime default "${desktop}" "$@" >/dev/null 2>&1 || true
}
if [[ -f /usr/share/applications/org.kde.dolphin.desktop ]] || [[ ${DRY_RUN} == 1 ]]; then
  mime_default org.kde.dolphin.desktop inode/directory application/x-gnome-saved-search
  ok "Dolphin definido como gerenciador de arquivos padrão"
fi
if [[ -f /usr/share/applications/org.kde.kwrite.desktop ]] || [[ ${DRY_RUN} == 1 ]]; then
  mime_default org.kde.kwrite.desktop text/plain
  ok "KWrite definido como editor de texto padrão"
fi
if [[ -f /usr/share/applications/org.kde.gwenview.desktop ]] || [[ ${DRY_RUN} == 1 ]]; then
  mime_default org.kde.gwenview.desktop image/png image/jpeg image/webp
  ok "Gwenview definido como visualizador de imagens padrão"
fi
if [[ -f /usr/share/applications/org.kde.okular.desktop ]] || [[ ${DRY_RUN} == 1 ]]; then
  mime_default org.kde.okular.desktop application/pdf
  ok "Okular definido como leitor de PDF padrão"
fi
if [[ -f /usr/share/applications/org.kde.dragonplayer.desktop ]] || [[ ${DRY_RUN} == 1 ]]; then
  mime_default org.kde.dragonplayer.desktop video/mp4 video/x-matroska
  ok "Dragon definido como player de vídeo padrão"
fi
if [[ -f /usr/share/applications/org.kde.elisa.desktop ]] || [[ ${DRY_RUN} == 1 ]]; then
  mime_default org.kde.elisa.desktop audio/mpeg audio/flac audio/x-wav
  ok "Elisa definido como player de áudio padrão"
fi

# ─── 7. Terminal: tema do alacritty + zsh com autocomplete ──────────────────
# Também install_file_once: .zshrc e alacritty.toml são configs pessoais.
install_file_once "alacritty/alacritty.toml" "${TU_HOME}/.config/alacritty/alacritty.toml"
install_file_once "zsh/zshrc" "${TU_HOME}/.zshrc"

# shell do usuário → zsh (path resolvido, nunca fixo em /usr/bin/zsh)
if command -v zsh >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; then
  ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
  [[ -n ${ZSH_BIN} ]] || ZSH_BIN='/usr/bin/zsh'   # valor esperado pós-instalação
  run_cmd chsh -s "${ZSH_BIN}" "${TU}" || warn "chsh: falha ao definir o zsh como shell padrão"
  ok "shell padrão: zsh (sugestões inline + syntax highlight + fzf no Ctrl+R)"
fi

# ─── 8. Autostart do usuário (XDG) ─────────────────────────────────────────
# O systemd (xdg-autostart-generator) lê ~/.config/autostart, e o arquivo do
# usuário tem precedência sobre o de /etc/xdg/autostart (mesmo nome).
# install_file_once nesses dois: apagar o arquivo reverte para o padrão.
if [[ -f /etc/xdg/autostart/sealertauto.desktop || ${DRY_RUN} == 1 ]]; then
  # seapplet: o applet do setroubleshoot fechava notificações órfãs tratando só
  # IOError, mas o Noctalia responde GLib.GError ("NotFound") — a exceção
  # escapava para o abrt (popup "uncaught exception" a cada AVC). Aponta para a
  # cópia com patch em /usr/local/bin/omyfedora-seapplet.
  install_file "bin/omyfedora-seapplet" "/usr/local/bin/omyfedora-seapplet"
  run_cmd chmod 755 /usr/local/bin/omyfedora-seapplet
  install_file_once "autostart/sealertauto.desktop" "${TU_HOME}/.config/autostart/sealertauto.desktop"
  ok "autostart: seapplet com patch (notificação órfã não derruba mais o applet)"
fi
if [[ -f /etc/xdg/autostart/org.kde.xwaylandvideobridge.desktop || ${DRY_RUN} == 1 ]]; then
  # XwaylandVideoBridge: o .desktop do KDE não tem OnlyShowIn — sobe em
  # qualquer sessão e, sob o niri (sem tray do Plasma), vira uma janela que
  # não fecha. Desligado com Hidden=true (apague para reativar).
  install_file_once "autostart/org.kde.xwaylandvideobridge.desktop" "${TU_HOME}/.config/autostart/org.kde.xwaylandvideobridge.desktop"
  ok "autostart: XwaylandVideoBridge desligado (janela fantasma no niri)"
fi

# ─── 9. Permissões dos arquivos do usuário ──────────────────────────────────
run_cmd chown -R "${TU}:${TU}" "${TU_HOME}/.config/niri" "${TU_HOME}/.config/noctalia" "${TU_HOME}/.config/alacritty" "${TU_HOME}/.config/autostart" "${TU_HOME}/.config/gtk-3.0" "${TU_HOME}/.config/gtk-4.0" "${TU_HOME}/.local/state/noctalia" "${TU_HOME}/.local/share/noctalia"
run_cmd chown -R "${TU}:${TU}" "${TU_HOME}/.config/zed" "${TU_HOME}/.local/share/jupyter"
run_cmd chown "${TU}:${TU}" "${TU_HOME}/.zshrc"
# o banco dconf do usuário pode ter sido criado agora pelo gsettings acima
if [[ -e ${TU_HOME}/.config/dconf ]]; then
  run_cmd chown -R "${TU}:${TU}" "${TU_HOME}/.config/dconf"
fi

cat <<EOF

──────────────────────────────────────────────────────────────
 omyfedora instalado. O que esperar no próximo boot:

   • Tela de login do greetd (Noctalia Greeter, se instalado)
     com a sessão "niri" já disponível
   • O shell do Plasma é removido no PRÓXIMO boot; os apps KDE ficam
     (Dolphin, Konsole, Kate/KWrite, Okular, Gwenview, Spectacle...)
   • Shell: Noctalia v5 (barra, launcher, notificações, lock, OSD)
   • Tema dos apps: Breeze Dark (o dark padrão do KDE); Noctalia como está
   • Atalhos: Super+T terminal (alacritty) · Super+Space launcher · Super+S control center
              Super+B Brave · Super+E Zed · Super+P monitores · Alt+Tab switcher
              Print screenshot (o restante são os defaults oficiais do niri)
   • Editor: Zed · IA no terminal: opencode · Office: ONLYOFFICE
     Arquivos na LAN: LocalSend · VMs: virt-manager (libvirt no próximo login)

 Verificações pós-reboot:
   systemctl status greetd
   journalctl -u greetd -n 30
   free -h ; zramctl                 # swap comprimido ativo
   ps aux --sort=-rss | head -12     # top consumidores de RAM

 Dica: apps pesados (Brave/ONLYOFFICE/Zed) só consomem RAM quando abertos.
──────────────────────────────────────────────────────────────
EOF
ok "configuração concluída"
