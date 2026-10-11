#!/usr/bin/env bash
# 30-services.sh — ajusta serviços do systemd para um desktop enxuto:
#   greetd no lugar do GDM, menos daemons residentes, zram/oomd/tuned ligados.
#
# Importante: nada é PARADO agora (isso derrubaria a sessão gráfica atual).
# As mudanças valem a partir do próximo boot.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

off() {  # desativa no boot, se a unit existir
  local s=$1
  run_sh "systemctl disable '${s}' >/dev/null 2>&1 || true"
  log "serviço: '${s}' desativado no boot"
}

mask() {  # impede totalmente a inicialização
  local s=$1
  run_sh "systemctl mask '${s}' >/dev/null 2>&1 || true"
  log "serviço: '${s}' mascarado"
}

on() {  # habilita no boot
  local s=$1
  run_sh "systemctl enable '${s}' >/dev/null 2>&1 || true"
  log "serviço: '${s}' habilitado no boot"
}

# ─── 1. Display manager: greetd assume, GDM sai de cena ─────────────────────
if rpm -q gdm >/dev/null 2>&1; then
  off gdm
  mask gdm
fi
on greetd

# ─── 2. Usuário do greeter (noctalia-greeter) ───────────────────────────────
if command -v noctalia-greeter-session >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; then
  if ! id greeter >/dev/null 2>&1; then
    run_cmd useradd -r -d /var/lib/noctalia-greeter -s /usr/sbin/nologin \
      -c 'Noctalia Greeter' greeter
    run_cmd mkdir -p /var/lib/noctalia-greeter
    run_cmd chown greeter:greeter /var/lib/noctalia-greeter
  fi
fi

# ─── 3. Daemons dispensáveis num desktop Wayland enxuto ─────────────────────
off avahi-daemon
off cups
off sssd
off fprintd
off dnf-automatic
off dnf-automatic.timer
off systemd-pstore
mask dnf-automatic
mask dnf-automatic.timer

if [[ -z "$(ls /sys/class/bluetooth 2>/dev/null)" ]]; then
  off bluetooth
fi

# ─── 4. Serviços que queremos no boot ───────────────────────────────────────
if rpm -q tuned-ppd >/dev/null 2>&1; then
  on tuned-ppd        # perfis de energia (API PPD do tuned, padrão no F44+)
else
  on power-profiles-daemon
fi
on tuned
on podman.socket   # API do Podman (usada pelo lazydocker)

# compat: ferramentas que esperam /var/run/docker.sock (lazydocker/docker CLI)
if [[ ! -e /var/run/docker.sock ]] && { rpm -q podman >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; }; then
  run_sh "ln -sf /run/podman/podman.sock /var/run/docker.sock"
  log "serviço: /var/run/docker.sock → socket do Podman (compatibilidade)"
fi

if [[ -f /usr/lib/systemd/system/systemd-oomd.service ]]; then
  on systemd-oomd
else
  log "serviço: systemd-oomd não disponível nesta versão do systemd"
fi

run_cmd systemctl daemon-reload
ok "serviços ajustados (efeito no próximo boot)"
