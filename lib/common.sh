#!/usr/bin/env bash
# Funções e utilidades compartilhadas pela suíte de instalação do MyOS.
# Este arquivo é carregado (source) pelos scripts/NN-*.sh.
#
# Variáveis de ambiente reconhecidas:
#   DRY_RUN    1 = simula (loga ações, não executa)
#   YES        1 = autoriza operações destrutivas sem interagir
#   NO_GREETER 1 = não adiciona o repo do greeter Noctalia
#   TARGET_USER usuário-alvo para configuração (opcional)
#   GPU_PROFILE auto|intel|amd|nvidia|hybrid|none
#   SKIP_REMOVE 1 = nunca remove pacotes

: "${DRY_RUN:=0}"
: "${YES:=0}"
: "${NO_GREETER:=0}"
: "${GPU_PROFILE:=auto}"

# Cores (apenas se stdout for tty)
if [[ -t 1 ]]; then
  C_OK=$'\033[0;32m' C_WARN=$'\033[0;33m' C_ERR=$'\033[0;31m' C_INFO=$'\033[0;36m' C_RST=$'\033[0m'
else
  C_OK='' C_WARN='' C_ERR='' C_INFO='' C_RST=''
fi

log()  { printf '%s[  ]%s %s\n' "${C_INFO}" "${C_RST}" "$1"; }
ok()   { printf '%s[OK ]%s %s\n' "${C_OK}" "${C_RST}" "$1"; }
warn() { printf '%s[AV ]%s %s\n' "${C_WARN}" "${C_RST}" "$1" >&2; }
err()  { printf '%s[ER ]%s %s\n' "${C_ERR}" "${C_RST}" "$1" >&2; }

# raiz do repositório MyOS (parente de lib/)
MYOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# run_cmd — executa um comando respeitando DRY_RUN (apenas registra)
run_cmd() {
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: seria executado: $*"
    return 0
  fi
  "$@"
}

# run_sh — executa uma string de shell respeitando DRY_RUN
run_sh() {
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: seria executado: $1"
    return 0
  fi
  bash -c "$1"
}

# exige_ok — bloqueia operações destrutivas sem --yes (ou aprovação interativa)
exige_ok() {
  local msg=$1
  if [[ ${YES} == 1 ]]; then
    return 0
  fi
  if [[ ${DRY_RUN} == 1 ]]; then
    log "ok: '${msg}' — bloqueado neste modo (use --yes para executar)"
    return 1
  fi
  local ans=''
  # shellcheck disable=SC2059
  read -r -p "${C_WARN}[? ]${C_RST} ${msg} [s/N] " ans || ans=''
  [[ ${ans} =~ ^[sSyY] ]]
}

# require_fedora — valida que estamos num Fedora (ou derivada) com dnf
require_fedora() {
  [[ -r /etc/os-release ]] || { err "não encontrei /etc/os-release"; exit 1; }
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "fedora" && ! "${ID_LIKE:-}" =~ fedora ]]; then
    err "este script exige Fedora (detectado: ${PRETTY_NAME:-desconhecido})"
    exit 1
  fi
  FEDORA_VERSION="${VERSION_ID:-?}"
  command -v dnf >/dev/null 2>&1 || { err "dnf não encontrado no PATH"; exit 1; }
  log "base" "Sistema: ${PRETTY_NAME:-Fedora} (versão ${FEDORA_VERSION}) — OK"
  export FEDORA_VERSION
}

# resolve_target_user — resolve o usuário normal que receberá a configuração
resolve_target_user() {
  local u=''
  if [[ -n ${TARGET_USER:-} ]]; then
    if id "${TARGET_USER}" >/dev/null 2>&1; then
      echo "${TARGET_USER}"
    else
      err "usuário alvo '${TARGET_USER}' não existe"
      return 1
    fi
    return 0
  fi
  if [[ -n ${SUDO_USER:-} && "${SUDO_USER}" != "root" ]]; then
    if id "${SUDO_USER}" >/dev/null 2>&1; then
      echo "${SUDO_USER}"
      return 0
    fi
  fi
  u="$(awk -F: '$3>=1000 && $3<65000 {print $1; exit}' /etc/passwd)" || u=''
  if [[ -z ${u} ]]; then
    err "nenhum usuário normal (UID >= 1000) encontrado; use --user NOME"
    return 1
  fi
  echo "${u}"
}

# user_home <usuário> — imprime o home do usuário
user_home() {
  getent passwd "$1" | cut -d: -f6
}

# install_file <asset_rel> <dst> — copia asset do repositório para o sistema
# (faz backup .myos-bak da primeira vez que sobrescrever um arquivo existente)
install_file() {
  local src="${MYOS_ROOT}/assets/$1" dst="$2"
  if [[ ! -r ${src} ]]; then
    err "asset ausente no repositório: ${src}"
    return 1
  fi
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: copiaria ${src} → ${dst}"
    return 0
  fi
  if [[ -f ${dst} && ! -f ${dst}.myos-bak ]]; then
    cp -a "${dst}" "${dst}.myos-bak" 2>/dev/null || true
  fi
  run_cmd mkdir -p "$(dirname "${dst}")"
  run_cmd cp -f "${src}" "${dst}"
}

# render_file <asset_rel> <dst> <VAR> <valor> — copia asset substituindo __VAR__
render_file() {
  local src="${MYOS_ROOT}/assets/$1" dst="$2" var="$3" val="$4"
  if [[ ! -r ${src} ]]; then
    err "asset ausente no repositório: ${src}"
    return 1
  fi
  local tmp
  tmp="$(mktemp)" || return 1
  sed "s|${var}|${val}|g" "${src}" > "${tmp}"
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: renderizaria ${src} (${var}=${val}) → ${dst}"
    rm -f "${tmp}"
    return 0
  fi
  if [[ -f ${dst} && ! -f ${dst}.myos-bak ]]; then
    cp -a "${dst}" "${dst}.myos-bak" 2>/dev/null || true
  fi
  mkdir -p "$(dirname "${dst}")"
  cp -f "${tmp}" "${dst}"
  rm -f "${tmp}"
}
