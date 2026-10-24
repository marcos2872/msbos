#!/usr/bin/env bash
# 00-migrate-names.sh — prepara uma instalação antiga (omyfedora/myos) para o msbos.
#
# Roda antes das etapas normais do install.sh. Não remove pacotes, não para a
# sessão e não apaga configurações: apenas move o que o instalador não
# sobrescreve, desabilita units antigas (sem --now) e tira do caminho arquivos
# que conflitariam com os novos. A remoção definitiva fica no
# 99-cleanup-legacy.sh, depois que os arquivos novos já existem.
#
# Instalações novas não têm nada antigo: o script sai em silêncio.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
TU_GROUP="$(id -gn "${TU}")"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/var/backups/msbos-migration/${TS}"
USER_BACKUP="${TU_HOME}/.local/state/msbos/migration-backups/${TS}"

# Nomes que existem em instalações antigas (três gerações: msbos é a nova).
LEGACY_PATHS=(
  /etc/omyfedora
  /var/log/omyfedora
  /var/lib/omyfedora
  /usr/share/omyfedora
  /usr/share/omyfedora-walls
  /usr/share/myos-walls
  /etc/yum.repos.d/omyfedora-terra.repo
  /etc/yum.repos.d/myos-terra.repo
  /etc/sysctl.d/99-omyfedora.conf
  /etc/sysctl.d/99-myos.conf
  /etc/dconf/db/local.d/00-omyfedora-dark
  /etc/systemd/system/omyfedora-cpu-governor.service
  /etc/systemd/system/omyfedora-remove-plasma.service
  /etc/systemd/system/myos-cpu-governor.service
  /usr/local/libexec/omyfedora-priv
  /usr/local/bin/omyfedora-doctor
  /usr/local/bin/myos-cpu-governor
  "${TU_HOME}/.agents/skills/omyfedora"
  "${TU_HOME}/.local/share/omyfedora"
  "${TU_HOME}/.local/state/omyfedora"
  "${TU_HOME}/.config/omyfedora-walls"
  "${TU_HOME}/.config/myos-walls"
  "${TU_HOME}/.config/autostart/omyfedora-greeter-sync.desktop"
)

LEGACY=0
for p in "${LEGACY_PATHS[@]}"; do
  if [[ -e ${p} ]]; then
    LEGACY=1
    break
  fi
done
for f in /etc/dnf/protected.d/*.omyfedora-off /etc/dnf/protected.d/*.myos-off; do
  if [[ -e ${f} ]]; then
    LEGACY=1
    break
  fi
done
if ((LEGACY == 0)); then
  log "migração: nenhum artefato antigo encontrado"
  exit 0
fi

log "migração: preparando instalação existente (omyfedora/myos) para msbos"
if [[ ${DRY_RUN} == 0 ]]; then
  run_cmd install -d -m 0750 -o root -g root "${BACKUP_DIR}"
  run_cmd runuser -u "${TU}" -- mkdir -p "${USER_BACKUP}"
  run_cmd chmod 700 "${USER_BACKUP}"
fi

backup_root() {
  local f="$1"
  [[ -e ${f} ]] || return 0
  run_cmd cp -a --parents "${f}" "${BACKUP_DIR}/"
}

backup_user() {
  local f="$1"
  [[ -e ${f} ]] || return 0
  run_cmd runuser -u "${TU}" -- cp -a --parents "${f}" "${USER_BACKUP}/"
}

# move_system_dir <antigo> <novo> — move ou mescla sem sobrescrever.
move_system_dir() {
  local old="$1" new="$2"
  [[ -e ${old} ]] || return 0
  if [[ -e ${new} ]]; then
    warn "migração: ${new} já existe; copiando itens ausentes de ${old}"
    run_cmd cp -an "${old}/." "${new}/" || warn "migração: falha ao mesclar ${old} em ${new}"
  else
    run_cmd mv "${old}" "${new}"
    log "migração: ${old} → ${new}"
  fi
}

move_user_dir() {
  local old="$1" new="$2"
  [[ -e ${old} ]] || return 0
  move_system_dir "${old}" "${new}"
  if [[ -e ${new} ]]; then
    run_cmd chown -R "${TU}:${TU_GROUP}" "${new}" ||
      warn "migração: falha ao ajustar o dono de ${new}"
  fi
}

move_log_dir() {
  [[ -d /var/log/omyfedora ]] || return 0
  if [[ -d /var/log/msbos ]]; then
    warn "migração: /var/log/msbos já existe; anexando actions.log antigo"
    if [[ -f /var/log/omyfedora/actions.log ]]; then
      run_sh 'printf "\n# --- migrado de /var/log/omyfedora ---\n" >> /var/log/msbos/actions.log; cat /var/log/omyfedora/actions.log >> /var/log/msbos/actions.log'
    fi
  else
    run_cmd mv /var/log/omyfedora /var/log/msbos
    log "migração: /var/log/omyfedora → /var/log/msbos"
  fi
}

disable_unit() {
  local u="$1"
  command -v systemctl >/dev/null 2>&1 || return 0
  if systemctl list-unit-files "${u}" --no-legend 2>/dev/null | grep -q "^${u}"; then
    run_cmd systemctl disable "${u}" || warn "migração: falha ao desabilitar ${u}"
    log "migração: unit antiga desabilitada: ${u}"
  fi
}

remove_old_config() {
  local f="$1"
  [[ -e ${f} ]] || return 0
  backup_root "${f}"
  run_cmd rm -f "${f}"
  log "migração: removido ${f} (backup em ${BACKUP_DIR})"
}

# Atualiza paths em arquivos do usuário, com backup antes.
patch_user_file() {
  local f="$1"
  shift
  [[ -f ${f} ]] || return 0
  if ! grep -qE 'omyfedora|/usr/local/bin/myos-|/usr/share/myos-|/etc/myos' "${f}" 2>/dev/null; then
    return 0
  fi
  backup_user "${f}"
  if run_cmd runuser -u "${TU}" -- sed -i "$@" "${f}"; then
    log "migração: paths atualizados em ${f}"
  else
    warn "migração: não consegui atualizar ${f} (backup em ${USER_BACKUP})"
  fi
}

# ─── 1. Units antigas: desabilita, mas não para nada da sessão atual ────────
disable_unit omyfedora-cpu-governor.service
disable_unit omyfedora-remove-plasma.service
disable_unit myos-cpu-governor.service
disable_unit myos-remove-plasma.service

# ─── 2. Estado que o instalador novo não sobrescreve ────────────────────────
move_system_dir /etc/omyfedora /etc/msbos
move_log_dir
move_system_dir /var/lib/omyfedora /var/lib/msbos
move_system_dir /usr/share/omyfedora /usr/share/msbos
move_system_dir /usr/share/omyfedora-walls /usr/share/msbos-walls
move_system_dir /usr/share/myos-walls /usr/share/msbos-walls
move_user_dir "${TU_HOME}/.local/share/omyfedora" "${TU_HOME}/.local/share/msbos"
move_user_dir "${TU_HOME}/.local/state/omyfedora" "${TU_HOME}/.local/state/msbos"
move_user_dir "${TU_HOME}/.config/omyfedora-walls" "${TU_HOME}/.config/msbos-walls"
move_user_dir "${TU_HOME}/.config/myos-walls" "${TU_HOME}/.config/msbos-walls"
move_user_dir "${TU_HOME}/.agents/skills/omyfedora" "${TU_HOME}/.agents/skills/msbos"

# ─── 3. Configs antigas que conflitariam com as novas (ordem alfabética) ─────
remove_old_config /etc/yum.repos.d/omyfedora-terra.repo
remove_old_config /etc/yum.repos.d/myos-terra.repo
remove_old_config /etc/sysctl.d/99-omyfedora.conf
remove_old_config /etc/sysctl.d/99-myos.conf
remove_old_config /etc/dconf/db/local.d/00-omyfedora-dark
for f in /etc/profile.d/omyfedora-*.sh /etc/profile.d/myos-*.sh; do
  [[ -e ${f} ]] && remove_old_config "${f}"
done

# Marcadores de uma remoção do Plasma interrompida (proteções do dnf).
for f in /etc/dnf/protected.d/*.omyfedora-off /etc/dnf/protected.d/*.myos-off; do
  [[ -e ${f} ]] || continue
  orig="${f%.omyfedora-off}"
  orig="${orig%.myos-off}"
  if [[ -e ${orig} ]]; then
    backup_root "${f}"
    run_cmd rm -f "${f}"
    log "migração: marcador antigo removido: ${f}"
  else
    run_cmd mv "${f}" "${orig}"
    log "migração: proteção restaurada: ${orig}"
  fi
done

# ─── 4. Configs do usuário que o install_file_once não atualiza ─────────────
patch_user_file "${TU_HOME}/.config/niri/config.kdl" \
  -e 's|/usr/share/omyfedora-walls|/usr/share/msbos-walls|g' \
  -e 's|/usr/share/omyfedora|/usr/share/msbos|g' \
  -e 's|/usr/local/bin/omyfedora-|/usr/local/bin/msbos-|g' \
  -e 's|omyfedora-wallpaper|msbos-wallpaper|g'

for f in \
  "${TU_HOME}/.config/noctalia/config.toml" \
  "${TU_HOME}/.local/state/noctalia/settings.toml" \
  "${TU_HOME}/.local/state/msbos/agent-changes.log" \
  "${TU_HOME}/.agents/skills/msbos/references/local.md"; do
  patch_user_file "${f}" \
    -e 's|/usr/share/omyfedora-walls|/usr/share/msbos-walls|g' \
    -e 's|/usr/share/omyfedora|/usr/share/msbos|g' \
    -e 's|/.local/share/omyfedora|/.local/share/msbos|g' \
    -e 's|/.local/state/omyfedora|/.local/state/msbos|g' \
    -e 's|/.config/omyfedora-walls|/.config/msbos-walls|g' \
    -e 's|/etc/omyfedora|/etc/msbos|g' \
    -e 's|/var/log/omyfedora|/var/log/msbos|g' \
    -e 's|/var/lib/omyfedora|/var/lib/msbos|g' \
    -e 's|/usr/local/libexec/omyfedora-priv|/usr/local/libexec/msbos-priv|g' \
    -e 's|/usr/local/bin/omyfedora-|/usr/local/bin/msbos-|g' \
    -e 's|org\.omyfedora\.|org.msbos.|g'
done

# Autostart: o seapplet e o sync do greeter guardam o caminho antigo.
SEALERT="${TU_HOME}/.config/autostart/sealertauto.desktop"
patch_user_file "${SEALERT}" \
  -e 's|/usr/local/bin/omyfedora-seapplet|/usr/local/bin/msbos-seapplet|g' \
  -e 's|/usr/local/bin/myos-seapplet|/usr/local/bin/msbos-seapplet|g' \
  -e 's|MyOS|msbos|g' \
  -e 's|omyfedora|msbos|g'

GREETER_OLD="${TU_HOME}/.config/autostart/omyfedora-greeter-sync.desktop"
GREETER_NEW="${TU_HOME}/.config/autostart/msbos-greeter-sync.desktop"
if [[ -f ${GREETER_OLD} ]]; then
  if [[ ! -e ${GREETER_NEW} ]]; then
    run_cmd mv "${GREETER_OLD}" "${GREETER_NEW}"
    log "migração: ${GREETER_OLD} → ${GREETER_NEW}"
  else
    warn "migração: ${GREETER_OLD} e ${GREETER_NEW} existem; o 99 remove o antigo"
  fi
fi
patch_user_file "${GREETER_NEW}" \
  -e 's|/usr/local/bin/omyfedora-greeter-sync|/usr/local/bin/msbos-greeter-sync|g' \
  -e 's|omyfedora|msbos|g'

# ─── 5. Força um novo sync da aparência com o greeter ───────────────────────
for m in \
  "${TU_HOME}/.local/state/msbos/greeter-sync.done" \
  "${TU_HOME}/.local/state/omyfedora/greeter-sync.done"; do
  if [[ -f ${m} ]]; then
    run_cmd rm -f "${m}"
    log "migração: marcador de greeter removido: ${m}"
  fi
done

ok "migração: estado antigo preparado; backups em ${BACKUP_DIR} e ${USER_BACKUP}"
