#!/usr/bin/env bash
# 99-cleanup-legacy.sh — remove os artefatos das gerações antigas (omyfedora/myos).
#
# Roda depois de todas as etapas normais, quando os arquivos novos do msbos já
# existem. Só remove o que foi substituído; se algo novo estiver faltando, avisa
# e preserva o antigo. Backups antigos são arquivados em
# /var/backups/msbos-migration/legacy-* (root) ou
# ~/.local/state/msbos/migration-backups/legacy-* (usuário).
#
# A remoção é destrutiva: sem --yes ela é bloqueada (o install continua, apenas
# deixa a limpeza pendente). Instalações novas não têm nada antigo e saem antes.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
TU_GROUP="$(id -gn "${TU}")"
TS="$(date +%Y%m%d-%H%M%S)"
ROOT_ARCHIVE="/var/backups/msbos-migration/legacy-${TS}"
USER_ARCHIVE="${TU_HOME}/.local/state/msbos/migration-backups/legacy-${TS}"

CHECK_PATHS=(
  /etc/omyfedora
  /var/log/omyfedora
  /var/lib/omyfedora
  /usr/share/omyfedora
  /usr/share/omyfedora-walls
  /usr/share/myos-walls
  /var/lib/myos
  /var/log/myos
  /usr/share/polkit-1/actions/org.omyfedora.priv.policy
  /usr/share/plymouth/themes/omyfedora
  /usr/share/icons/hicolor/512x512/apps/omyfedora.png
  /usr/share/pixmaps/omyfedora-logo.png
  /etc/systemd/system/omyfedora-cpu-governor.service
  /etc/systemd/system/omyfedora-remove-plasma.service
  /etc/systemd/system/myos-cpu-governor.service
  /etc/systemd/system/myos-remove-plasma.service
  /usr/local/libexec/omyfedora-priv
  /usr/local/libexec/omyfedora-remove-plasma
  /usr/local/bin/omyfedora-doctor
  /usr/local/bin/myos-cpu-governor
  "${TU_HOME}/.agents/skills/omyfedora"
  "${TU_HOME}/.local/share/omyfedora"
  "${TU_HOME}/.local/state/omyfedora"
  "${TU_HOME}/.config/omyfedora-walls"
  "${TU_HOME}/.config/autostart/omyfedora-greeter-sync.desktop"
)

LEGACY=0
for p in "${CHECK_PATHS[@]}"; do
  if [[ -e ${p} ]]; then
    LEGACY=1
    break
  fi
done
if ((LEGACY == 0)); then
  log "limpeza: nenhum artefato antigo encontrado"
  exit 0
fi

if [[ ${DRY_RUN} == 1 ]]; then
  log "dry-run: removeria os artefatos antigos (omyfedora/myos); nenhum arquivo será tocado"
elif ! exige_ok "remover os artefatos antigos omyfedora/myos (os backups vão para ${ROOT_ARCHIVE})?"; then
  warn "limpeza: não autorizada; os artefatos antigos ficaram no lugar (rode com --yes)"
  exit 0
fi

have_cmd() { command -v "$1" >/dev/null 2>&1; }

new_helper=0
if [[ -x /usr/local/libexec/msbos-priv ]]; then new_helper=1; fi
new_policy=0
if have_cmd pkaction && pkaction --action-id org.msbos.priv.dnf-install >/dev/null 2>&1; then new_policy=1; fi
new_selinux=0
if have_cmd semodule && semodule -l 2>/dev/null | awk '{print $1}' | grep -qx 'msbos-loadkeys-dontaudit'; then new_selinux=1; fi
new_dconf=0
if [[ -f /etc/dconf/db/local.d/00-msbos-dark ]]; then new_dconf=1; fi
new_sysctl=0
if [[ -f /etc/sysctl.d/99-msbos.conf ]]; then new_sysctl=1; fi
new_theme=0
if [[ -f /usr/share/plymouth/themes/msbos/msbos.plymouth ]] &&
  grep -q '^Theme=msbos' /etc/plymouth/plymouthd.conf 2>/dev/null; then new_theme=1; fi
new_assets=0
if [[ -d /usr/share/msbos ]]; then new_assets=1; fi
new_walls=0
if [[ -d /usr/share/msbos-walls ]]; then new_walls=1; fi
new_icon=0
if [[ -f /usr/share/icons/hicolor/512x512/apps/msbos.png ]]; then new_icon=1; fi
new_skill=0
if [[ -d "${TU_HOME}/.agents/skills/msbos" ]]; then new_skill=1; fi
new_share=0
if [[ -d "${TU_HOME}/.local/share/msbos" ]]; then new_share=1; fi
new_state=0
if [[ -d "${TU_HOME}/.local/state/msbos" ]]; then new_state=1; fi
new_greeter_autostart=0
if [[ -f "${TU_HOME}/.config/autostart/msbos-greeter-sync.desktop" ]]; then new_greeter_autostart=1; fi

rm_old() {
  local p="$1"
  [[ -e ${p} ]] || return 0
  run_cmd rm -rf -- "${p}"
  log "limpeza: removido ${p}"
}

# Move backups com o nome antigo para fora dos diretórios ativos, preservando-os.
archive_backups_in() {
  local root="$1" dest="$2" owner="$3" any=0 f
  [[ -d ${root} ]] || return 0
  while IFS= read -r -d '' f; do
    any=1
    run_cmd cp -a --parents "${f}" "${dest}/"
    run_cmd rm -f "${f}"
    log "limpeza: backup antigo arquivado: ${f}"
  done < <(find "${root}" -path "${dest}" -prune -o \
    \( -name '*omyfedora-bak*' -o -name '*myos-bak*' \) -print0 2>/dev/null)
  if ((any)) && [[ -n ${owner} && ${DRY_RUN} == 0 ]]; then
    run_cmd chown -R "${owner}" "${dest}" ||
      warn "limpeza: falha ao ajustar o dono de ${dest}"
  fi
}

# ─── 1. Units e binários antigos ────────────────────────────────────────────
for f in /etc/systemd/system/omyfedora-*.service /etc/systemd/system/myos-*.service; do
  [[ -e ${f} ]] && rm_old "${f}"
done
if have_cmd systemctl; then
  run_cmd systemctl daemon-reload || warn "limpeza: systemctl daemon-reload falhou"
  run_cmd systemctl reset-failed || true
fi

if ((new_helper)); then
  for f in /usr/local/bin/omyfedora-* /usr/local/bin/myos-* \
           /usr/local/libexec/omyfedora-* /usr/local/libexec/myos-*; do
    [[ -e ${f} ]] && rm_old "${f}"
  done
else
  warn "limpeza: helper novo ausente; mantendo os binários antigos"
fi

# ─── 2. Polkit, SELinux, tema e arquivos de sistema ─────────────────────────
if ((new_policy)); then
  rm_old /usr/share/polkit-1/actions/org.omyfedora.priv.policy
else
  warn "limpeza: policy nova não reconhecida; mantendo a antiga"
fi

if ((new_selinux)) && have_cmd semodule; then
  run_cmd semodule -r omyfedora-loadkeys-dontaudit 2>/dev/null ||
    warn "limpeza: módulo SELinux antigo não estava instalado"
  run_cmd semodule -r myos-loadkeys-dontaudit 2>/dev/null || true
fi
if have_cmd semanage; then
  run_cmd semanage fcontext -d '/usr/local/libexec/omyfedora-priv' 2>/dev/null || true
fi

if ((new_theme)); then
  rm_old /usr/share/plymouth/themes/omyfedora
else
  warn "limpeza: tema Plymouth novo não é o default; mantendo o antigo"
fi

if ((new_icon)); then
  rm_old /usr/share/icons/hicolor/512x512/apps/omyfedora.png
  rm_old /usr/share/pixmaps/omyfedora-logo.png
fi
if ((new_assets)); then
  rm_old /usr/share/omyfedora
fi
if ((new_walls)); then
  rm_old /usr/share/omyfedora-walls
  rm_old /usr/share/myos-walls
fi
rm_old /var/lib/myos
rm_old /var/log/myos

if ((new_dconf)); then
  rm_old /etc/dconf/db/local.d/00-omyfedora-dark
  if have_cmd dconf; then
    run_cmd dconf update || warn "limpeza: dconf update falhou"
  fi
fi
if ((new_sysctl)); then
  rm_old /etc/sysctl.d/99-omyfedora.conf
  if have_cmd sysctl; then
    run_cmd sysctl --system >/dev/null 2>&1 || warn "limpeza: sysctl --system falhou"
  fi
fi

# ─── 3. Estado e configs do usuário ─────────────────────────────────────────
if ((new_share)); then
  rm_old "${TU_HOME}/.local/share/omyfedora"
fi
if ((new_state)); then
  rm_old "${TU_HOME}/.local/state/omyfedora"
fi
if ((new_skill)); then
  rm_old "${TU_HOME}/.agents/skills/omyfedora"
fi
if [[ -d "${TU_HOME}/.config/msbos-walls" ]]; then
  rm_old "${TU_HOME}/.config/omyfedora-walls"
fi
if ((new_greeter_autostart)); then
  rm_old "${TU_HOME}/.config/autostart/omyfedora-greeter-sync.desktop"
fi

# Estado antigo do msbos: o 00 já moveu; se sobrou algo, copia e remove.
if ((new_state)) && [[ -d /var/lib/omyfedora ]]; then
  run_cmd cp -an /var/lib/omyfedora/. /var/lib/msbos/ 2>/dev/null || true
  rm_old /var/lib/omyfedora
fi
if [[ -d /var/log/msbos ]] && [[ -d /var/log/omyfedora ]]; then
  run_cmd cp -an /var/log/omyfedora/. /var/log/msbos/ 2>/dev/null || true
  rm_old /var/log/omyfedora
fi
if [[ -d /etc/msbos ]]; then
  rm_old /etc/omyfedora
fi

# ─── 4. Backups antigos: arquiva fora dos caminhos ativos ───────────────────
if [[ ${DRY_RUN} == 0 ]]; then
  run_cmd install -d -m 0750 -o root -g root "${ROOT_ARCHIVE}"
  run_cmd runuser -u "${TU}" -- mkdir -p "${USER_ARCHIVE}"
  run_cmd chmod 700 "${USER_ARCHIVE}"
fi
archive_backups_in /etc "${ROOT_ARCHIVE}" root
archive_backups_in /usr/local "${ROOT_ARCHIVE}" root
archive_backups_in /usr/share "${ROOT_ARCHIVE}" root
archive_backups_in /var/lib "${ROOT_ARCHIVE}" root
archive_backups_in /var/log "${ROOT_ARCHIVE}" root
archive_backups_in "${TU_HOME}/.config" "${USER_ARCHIVE}" "${TU}:${TU_GROUP}"
archive_backups_in "${TU_HOME}/.local/share" "${USER_ARCHIVE}" "${TU}:${TU_GROUP}"
archive_backups_in "${TU_HOME}/.local/state" "${USER_ARCHIVE}" "${TU}:${TU_GROUP}"
archive_backups_in "${TU_HOME}/.agents" "${USER_ARCHIVE}" "${TU}:${TU_GROUP}"

# ─── 5. Relatório final ────────────────────────────────────────────────────
if have_cmd restorecon; then
  run_cmd restorecon -R /usr/local/libexec/msbos-priv \
    /usr/share/polkit-1/actions/org.msbos.priv.policy /etc/msbos /var/log/msbos \
    /usr/share/msbos /usr/share/msbos-walls 2>/dev/null ||
    warn "limpeza: restorecon falhou"
fi

REMAINING=()
for p in "${CHECK_PATHS[@]}"; do
  if [[ -e ${p} ]]; then
    REMAINING+=("${p}")
  fi
done
if ((${#REMAINING[@]} > 0)); then
  warn "limpeza: ainda restam ${#REMAINING[@]} caminho(s) antigo(s):"
  printf '  %s\n' "${REMAINING[@]}" >&2
else
  ok "limpeza: nenhum artefato antigo restante"
fi
if [[ -x "${TU_HOME}/.local/bin/myos-wallpaper-animado" ]]; then
  warn "legado pessoal: ~/.local/bin/myos-wallpaper-animado ainda usa o nome antigo (fora do escopo automático)"
fi
