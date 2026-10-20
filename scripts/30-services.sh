#!/usr/bin/env bash
# 30-services.sh — ajusta serviços do systemd para um desktop enxuto:
#   greetd no lugar do Plasma Login Manager, menos daemons residentes,
#   zram/oomd/tuned ligados e o socket rootless do Podman (lazydocker sem sudo).
#
# Importante: nada é PARADO agora (isso derrubaria a sessão gráfica atual).
# As mudanças valem a partir do próximo boot.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
[[ -d ${TU_HOME} ]] || { err "home de ${TU} não encontrado (${TU_HOME})"; exit 1; }
log "serviços: usuário-alvo: ${TU} (${TU_HOME})"

off() {  # desativa no boot, se a unit existir
  local s=$1
  run_cmd systemctl disable "${s}" >/dev/null 2>&1 || true
  log "serviço: '${s}' desativado no boot"
}

mask() {  # impede totalmente a inicialização
  local s=$1
  run_cmd systemctl mask "${s}" >/dev/null 2>&1 || true
  log "serviço: '${s}' mascarado"
}

on() {  # habilita no boot
  local s=$1
  run_cmd systemctl enable "${s}" >/dev/null 2>&1 || true
  log "serviço: '${s}' habilitado no boot"
}

# ─── 1. Display manager: greetd assume; o DM do desktop atual sai de cena ───
# Fedora KDE usa o Plasma Login Manager (plasmalogin): ele é mascarado aqui e
# removido no próximo boot pelo omyfedora-remove-plasma.service. gdm/sddm também
# são mascarados (bases alternativas). Nada é PARADO agora: mascarar só vale
# a partir do próximo boot.
if rpm -q plasma-login-manager >/dev/null 2>&1; then
  off plasmalogin
  mask plasmalogin
fi
if rpm -q gdm >/dev/null 2>&1; then
  off gdm
  mask gdm
fi
if rpm -q sddm >/dev/null 2>&1; then
  off sddm
  mask sddm
fi
on greetd

# ─── 2. Usuário do greeter (noctalia-greeter) ───────────────────────────────
if command -v noctalia-greeter-session >/dev/null 2>&1 || [[ ${DRY_RUN} == 1 ]]; then
  if ! id greeter >/dev/null 2>&1; then
    run_cmd useradd -r -d /var/lib/noctalia-greeter -s /usr/sbin/nologin \
      -c 'Noctalia Greeter' greeter
  fi
  # O diretório de estado tem de existir e pertencer ao greeter mesmo quando o
  # usuário já existia (reinstalação, pacote anterior): o apply-appearance grava
  # o sync.toml ali e falha silenciosamente se o diretório não existir.
  run_cmd mkdir -p /var/lib/noctalia-greeter
  run_cmd chown greeter:greeter /var/lib/noctalia-greeter

  # SELinux: sem uma regra de contexto, os arquivos criados no home do greeter
  # herdam var_lib_t — e o domínio xdm_t (sessão do greeter) não pode gravar
  # nesse tipo. Sem isso, o greeter gera AVCs a cada boot (cache do Mesa,
  # sync.toml) e o setroubleshoot notifica o usuário. Homes de DM em /var/lib
  # usam xdm_var_lib_t (mesmo tipo do /var/lib/gdm). Idempotente: registra a
  # regra apenas se ela ainda não existir e reaplica o restorecon.
  if [[ -d /sys/fs/selinux && ( -d /var/lib/noctalia-greeter || ${DRY_RUN} == 1 ) ]] &&
    command -v semanage >/dev/null 2>&1 && command -v restorecon >/dev/null 2>&1; then
    if ! semanage fcontext -l 2>/dev/null | grep -q '^/var/lib/noctalia-greeter'; then
      run_cmd semanage fcontext -a -t xdm_var_lib_t '/var/lib/noctalia-greeter(/.*)?' ||
        warn "semanage: falha ao registrar o contexto do home do greeter"
    fi
    run_cmd restorecon -R /var/lib/noctalia-greeter ||
      warn "restorecon: falha ao aplicar o contexto do home do greeter"
  fi
fi

# ─── 2b. SELinux: falso positivo do loadkeys no login ───────────────────────
# Quando o niri assume o console, o fbcon faz o deferred takeover e o udev
# reinicia o systemd-vconsole-setup. Ele roda `loadkeys -C /dev/tty1`; o tty1
# já pertence ao usuário da sessão (logind, modo 0600), então o loadkeys_t
# tenta abrir o VT com O_RDWR e O_WRONLY, o SELinux nega dac_override nas duas
# tentativas e o setroubleshoot notifica um falso positivo a cada login. O
# fallback O_RDONLY funciona via dac_read_search e o keymap é aplicado — não há
# arquivo com permissão errada nem motivo para conceder dac_override. O módulo
# local apenas suprime o AVC. Idempotente: instala só se ainda não existir.
if [[ -d /sys/fs/selinux ]] && command -v semodule >/dev/null 2>&1; then
  if ! semodule -l 2>/dev/null | awk '{print $1}' | grep -qx 'omyfedora-loadkeys-dontaudit'; then
    run_cmd semodule -i "${OMYFEDORA_ROOT}/assets/selinux/omyfedora-loadkeys-dontaudit.cil" ||
      warn "SELinux: falha ao instalar o módulo local omyfedora-loadkeys-dontaudit"
  else
    log "SELinux: módulo omyfedora-loadkeys-dontaudit já instalado — mantido"
  fi
fi

# ─── 3. Daemons dispensáveis num desktop Wayland enxuto ─────────────────────
# Nota: cups.service sai de cena, mas o cups.socket continua — a impressão
# segue funcionando sob demanda (socket activation). O PackageKit fica ativo
# (o plasma-discover, mantido a pedido, usa ele).
off avahi-daemon
off cups
off sssd
off fprintd
off dnf-automatic
off dnf-automatic.timer
off systemd-pstore
mask dnf-automatic
mask dnf-automatic.timer

# wizard de primeiro login do Plasma: sem efeito sob o niri (o pacote sai na
# remoção do shell; mascarado aqui para o caso de --skip-remove)
if rpm -q plasma-setup >/dev/null 2>&1; then
  off plasma-setup
  mask plasma-setup
fi

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
  run_cmd ln -sf /run/podman/podman.sock /var/run/docker.sock
  log "serviço: /var/run/docker.sock → socket do Podman (compatibilidade)"
fi

# ─── 4b. Podman rootless: lazydocker sem sudo ───────────────────────────────
# O podman.socket do SISTEMA expõe /run/podman/podman.sock (root): clientes da
# API Docker (lazydocker) só o acessam com sudo. O socket ROOTLESS vive em
# /run/user/<uid>/podman/podman.sock, pertence ao usuário e é o alvo do
# DOCKER_HOST que o pacote podman-docker exporta via /etc/profile.d. Habilitamos
# o unit de usuário do alvo e, se o user manager já estiver rodando, iniciamos
# agora; senão o symlink garante a subida no próximo login.
if rpm -q podman >/dev/null 2>&1; then
  UID_TU="$(id -u "${TU}")"
  UNIT_USER='/usr/lib/systemd/user/podman.socket'
  WANTS="${TU_HOME}/.config/systemd/user/sockets.target.wants"
  if [[ -f ${UNIT_USER} ]]; then
    run_cmd install -d -o "${TU}" -g "${TU}" -m 755 "${WANTS}"
    run_cmd ln -sf "${UNIT_USER}" "${WANTS}/podman.socket"
    if [[ -d /run/user/${UID_TU} ]] && command -v runuser >/dev/null 2>&1; then
      run_cmd runuser -u "${TU}" -- env "XDG_RUNTIME_DIR=/run/user/${UID_TU}" \
        systemctl --user start podman.socket \
        || warn "podman rootless: falha ao iniciar o socket agora (sobe no próximo login)"
    fi
    ok "podman rootless: socket do usuário habilitado (lazydocker sem sudo)"
  else
    warn "podman rootless: ${UNIT_USER} não existe — socket do usuário não habilitado"
  fi
fi

if [[ -f /usr/lib/systemd/system/systemd-oomd.service ]]; then
  on systemd-oomd
else
  log "serviço: systemd-oomd não disponível nesta versão do systemd"
fi

run_cmd systemctl daemon-reload
ok "serviços ajustados (efeito no próximo boot)"
