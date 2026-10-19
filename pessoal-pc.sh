#!/usr/bin/env bash
# pessoal-pc.sh — reaplica meu layout de monitores + chrome padrão.
#
# Salvo em 2026-10-17 a partir de `niri msg outputs`:
#   • HDMI-A-1 (LG 25UM58G ultrawide, principal, à esquerda):
#     2560x1080@74.991, posição 0,0, escala 1, sem rotação
#   • DP-3 (LG FHD, retrato, à direita):
#     1920x1080@100.000, posição 2560,-420, escala 1, girado 270°
#
# Uso: ./pessoal-pc.sh
#
# Além dos monitores, instala o Google Chrome (se ausente) e o define como
# navegador padrão.
#
# Fluxo no monitor vertical (manual — o niri não permite fixar "meia altura
# só no DP-3" como padrão: window-rule não filtra por monitor e o layout por
# saída rejeita default-window-height):
#   • Largura cheia: já é o padrão (default-column-width 1.0 no DP-3).
#   • Meia altura: com o app focado, Mod+Ctrl+Shift+R
#     (switch-preset-window-height; alterna 1/3 → 1/2 → 2/3 → cheia).
#   • 2º app abaixo: abra o app e tecle Mod+Comma
#     (consume-window-into-column — empilha na mesma coluna).
#   • 3º app do lado: abre sozinho em coluna nova ao lado (padrão do niri).

set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}/niri/config.kdl"

# ─── 1. Aplica ao vivo (vale na hora, sem reboot) ────────────────────────
niri msg output "HDMI-A-1" mode "2560x1080@74.991"
niri msg output "HDMI-A-1" scale 1
niri msg output "HDMI-A-1" transform normal
niri msg output "HDMI-A-1" position set 0 0

niri msg output "DP-3" mode "1920x1080@100.000"
niri msg output "DP-3" scale 1
niri msg output "DP-3" transform 270
niri msg output "DP-3" position set 2560 -- -420

echo "ao vivo: aplicado."

# ─── 2. Garante persistência no config.kdl ───────────────────────────────
if grep -q 'output "HDMI-A-1"' "${CONFIG}" && grep -q 'output "DP-3"' "${CONFIG}"; then
  echo "config: blocos output já existem em ${CONFIG} — nada a mudar."
else
  [[ -f ${CONFIG}.omyfedora-bak ]] || cp -a "${CONFIG}" "${CONFIG}.omyfedora-bak"
  tmp="$(mktemp)"
  python3 - "${CONFIG}" "${tmp}" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
texto = open(src, encoding="utf-8").read()
texto = re.sub(r'(?m)^output\s+"(?:HDMI-A-1|DP-3)"\s*\{.*?\n\}\n\n?', "", texto, flags=re.S)
texto = re.sub(r'(?m)^// Monitores —.*\n(?:^//.*\n)?', "", texto)
open(dst, "w", encoding="utf-8").write(texto)
PY
  cat >> "${tmp}.bloco" <<'EOF'
// Monitores — layout salvo em 2026-10-17.
// Ultrawide principal à esquerda, FHD em retrato à direita.
output "HDMI-A-1" {
    mode "2560x1080@74.991"
    position x=0 y=0
    scale 1.0
    transform "normal"
}

output "DP-3" {
    mode "1920x1080@100.000"
    position x=2560 y=-420
    scale 1.0
    transform "270"

    // Monitor vertical: coluna ocupa a largura toda, ideal para empilhar.
    layout {
        default-column-width { proportion 1.0; }
    }
}

EOF
  cat "${tmp}.bloco" "${tmp}" > "${CONFIG}.novo"
  mv "${CONFIG}.novo" "${CONFIG}"
  rm -f "${tmp}" "${tmp}.bloco"
  echo "config: blocos output (re)instalados em ${CONFIG}."
fi

# ─── 3. Valida e recarrega ───────────────────────────────────────────────
niri validate && niri msg action load-config-file
echo "ok: HDMI-A-1 2560x1080@74.991 (0,0) + DP-3 1920x1080@100 retrato (2560,-420)."

# ─── 4. Chrome (instala + define como navegador padrão) ──────────────────
if rpm -q google-chrome-stable >/dev/null 2>&1; then
  echo "chrome: já instalado ($(rpm -q google-chrome-stable))."
else
  echo "chrome: instalando google-chrome-stable (repo google-chrome)..."
  sudo dnf install -y fedora-workstation-repositories
  if command -v dnf5 >/dev/null 2>&1; then
    sudo dnf config-manager setopt google-chrome.enabled=1
  else
    sudo dnf config-manager --set-enabled google-chrome
  fi
  sudo dnf install -y --setopt=install_weak_deps=0 google-chrome-stable
fi

if command -v google-chrome-stable >/dev/null 2>&1; then
  xdg-settings set default-web-browser google-chrome.desktop >/dev/null 2>&1 || true
  xdg-mime default google-chrome.desktop x-scheme-handler/https x-scheme-handler/http >/dev/null 2>&1 || true
  echo "chrome: definido como navegador padrão (https/http)."
else
  echo "chrome: instalação falhou — padrão mantido." >&2
  exit 1
fi
