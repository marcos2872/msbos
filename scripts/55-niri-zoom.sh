#!/usr/bin/env bash
# 55-niri-zoom.sh — niri com zoom de acessibilidade por output (opt-in).
#
# O niri 26.04 da distro não tem zoom. Esta etapa, habilitada por
# --with-niri-zoom (WITH_NIRI_ZOOM=1), compila o commit fixado do PR
# niri-wm/niri#3246 + o patch local do msbos (movement-mode "anchored" e
# pan-modifier) em um container Fedora e instala o binário em
# /usr/local/bin/niri. O /usr/bin/niri do pacote fica intacto; o rollback é
# `sudo msbos-niri-zoom-remove`.
#
# Em --dry-run não há rede, podman nem compilação. Sem a flag a etapa é no-op.
#
# Atalhos (Mod = Super no TTY): Mod+Alt+scroll, Mod+Alt+=/-, Mod+Alt+0,
# Mod+Alt+Z. Segure Super e mova o mouse para o pan.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

if [[ ${DRY_RUN} != 1 && ${EUID} -ne 0 ]]; then
  err "55-niri-zoom.sh precisa de root para instalar em /usr/local/bin e /usr/local/share"
  err "rode: sudo ./install.sh --with-niri-zoom   (ou sudo bash scripts/55-niri-zoom.sh)"
  err "simulação sem root: DRY_RUN=1 bash scripts/55-niri-zoom.sh"
  exit 1
fi

require_fedora
DNFOPT='--setopt=install_weak_deps=0'

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
[[ -d ${TU_HOME} ]] || { err "home de ${TU} não encontrado (${TU_HOME})"; exit 1; }
TU_UID="$(id -u "${TU}")"
TU_GROUP="$(id -gn "${TU}")"
NIRI_CFG="${TU_HOME}/.config/niri/config.kdl"
ZOOM_CFG="${TU_HOME}/.config/niri/zoom.kdl"

ZOOM_REPO='Atan-D-RP4/niri'
ZOOM_COMMIT='6253a42509bae3f16d86357e7a870fc955f29636'
ZOOM_TARBALL_SHA256='6a1f42964e249c2547416e6089376dc7201ca512de585aaac179ee09ae1a368c'
ZOOM_PATCH_SHA256='8555fc069e0186fba4ffae3866a1e587c95f14bd8b7fa1969ed7b6844c597ef1'
ZOOM_PATCH_ASSET="${MSBOS_ROOT}/assets/niri-zoom/niri-zoom-anchored.patch"
ZOOM_BUILD_SCRIPT="${MSBOS_ROOT}/assets/niri-zoom/build-in-container.sh"
ZOOM_BIN='/usr/local/bin/niri'
ZOOM_MARKER='/usr/local/share/msbos/niri-zoom.commit'
ZOOM_LOG='/var/log/msbos/niri-zoom-build.log'
ZOOM_IMAGE="${NIRI_ZOOM_IMAGE:-registry.fedoraproject.org/fedora:44}"

# Dependências validadas no build do Fedora 44 (assets/niri-zoom/build-in-container.sh).
ZOOM_BUILD_DEPS=(
  cargo rust gcc gcc-c++ glibc-devel make cmake pkgconf-pkg-config git clang patch
  cairo-devel dbus-devel mesa-libgbm-devel gdk-pixbuf2-devel glib2-devel
  gtk4-devel libadwaita-devel libdisplay-info-devel libinput-devel
  pipewire-devel libseat-devel systemd-devel pango-devel
  wayland-devel wayland-protocols-devel libxkbcommon-devel mesa-libEGL-devel libdrm-devel
)

if [[ ${WITH_NIRI_ZOOM:-0} != 1 ]]; then
  log "zoom do niri: desativado (use --with-niri-zoom para instalar)"
  if [[ -e ${ZOOM_MARKER} || -x ${ZOOM_BIN} ]]; then
    warn "zoom do niri: instalação anterior detectada; use 'sudo msbos-niri-zoom-remove' para remover"
  fi
  exit 0
fi

# O patch é local e fixo; se o asset mudar sem atualizar o hash, falha fechado.
if [[ ! -r ${ZOOM_PATCH_ASSET} ]]; then
  err "asset ausente: ${ZOOM_PATCH_ASSET}"
  exit 1
fi
if ! printf '%s  %s\n' "${ZOOM_PATCH_SHA256}" "${ZOOM_PATCH_ASSET}" | sha256sum -c - >/dev/null 2>&1; then
  err "o hash de ${ZOOM_PATCH_ASSET} não confere (esperado ${ZOOM_PATCH_SHA256})"
  exit 1
fi
if [[ ! -r ${ZOOM_BUILD_SCRIPT} ]]; then
  err "asset ausente: ${ZOOM_BUILD_SCRIPT}"
  exit 1
fi

case "$(uname -m)" in
  x86_64|aarch64) ;;
  *) err "arquitetura não suportada: $(uname -m) (o fork é testado em x86_64/aarch64)"; exit 1 ;;
esac

for cmd in sha256sum install; do
  command -v "${cmd}" >/dev/null 2>&1 || { err "'${cmd}' não encontrado no PATH"; exit 1; }
done
if [[ ${DRY_RUN} != 1 ]]; then
  for cmd in curl tar; do
    command -v "${cmd}" >/dev/null 2>&1 || { err "'${cmd}' não encontrado no PATH"; exit 1; }
  done
fi

if ! command -v podman >/dev/null 2>&1; then
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: instalaria podman (necessário para compilar em container)"
  else
    log "zoom do niri: instalando podman (necessário para compilar em container)"
    run_cmd dnf -y "${DNFOPT}" install podman \
      || { err "não consegui instalar podman"; exit 1; }
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: instalaria jq (usado por msbos-zoom-reset)"
  else
    run_cmd dnf -y "${DNFOPT}" install jq \
      || { err "não consegui instalar jq (necessário para msbos-zoom-reset)"; exit 1; }
  fi
fi

marker_ok() {
  [[ -x ${ZOOM_BIN} && -f ${ZOOM_MARKER} ]] || return 1
  grep -qx "commit=${ZOOM_COMMIT}" "${ZOOM_MARKER}" || return 1
  grep -qx "patch=${ZOOM_PATCH_SHA256}" "${ZOOM_MARKER}" || return 1
  "${ZOOM_BIN}" --version >/dev/null 2>&1 || return 1
}

WORK_DIR=''
cleanup() {
  if [[ -n ${WORK_DIR} && -d ${WORK_DIR} ]]; then
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

build_niri() {
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/msbos-niri-zoom.XXXXXX")"
  local url="https://codeload.github.com/${ZOOM_REPO}/tar.gz/${ZOOM_COMMIT}"
  local log="${WORK_DIR}/build.log"
  local image="${ZOOM_IMAGE}"

  log "zoom do niri: baixando ${ZOOM_REPO}@${ZOOM_COMMIT:0:12}..."
  if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 300 "${url}" -o "${WORK_DIR}/niri.tar.gz"; then
    err "falha ao baixar ${url} (rede?)"
    return 1
  fi
  if ! printf '%s  %s\n' "${ZOOM_TARBALL_SHA256}" "${WORK_DIR}/niri.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
    err "o hash do tarball não confere (esperado ${ZOOM_TARBALL_SHA256})"
    return 1
  fi

  mkdir -p "${WORK_DIR}/src"
  tar -xzf "${WORK_DIR}/niri.tar.gz" -C "${WORK_DIR}/src" --strip-components=1
  install -m 0644 "${ZOOM_PATCH_ASSET}" "${WORK_DIR}/niri-zoom.patch"
  install -m 0755 "${ZOOM_BUILD_SCRIPT}" "${WORK_DIR}/build-in-container.sh"

  if ! podman image exists "${image}" >/dev/null 2>&1; then
    log "zoom do niri: baixando a imagem ${image}..."
    if ! podman pull "${image}" >/dev/null 2>&1; then
      image='fedora:44'
      warn "não consegui baixar ${ZOOM_IMAGE}; tentando ${image}"
      if ! podman pull "${image}" >/dev/null 2>&1; then
        err "não consegui obter uma imagem Fedora 44 para o build"
        return 1
      fi
    fi
  fi

  log "zoom do niri: compilando em ${image} (pode levar alguns minutos)..."
  if ! podman run --rm --pull=missing \
      -v "${WORK_DIR}:/work:Z" -w /work/src \
      "${image}" bash /work/build-in-container.sh "${ZOOM_BUILD_DEPS[@]}" \
      >"${log}" 2>&1; then
    err "a compilação do niri falhou; últimas linhas de ${log}:"
    tail -n 80 "${log}" >&2 || true
    if [[ ${DRY_RUN} == 0 ]]; then
      run_cmd install -D -m 0644 "${log}" "${ZOOM_LOG}" || true
      err "log completo: ${ZOOM_LOG}"
    fi
    return 1
  fi

  # O build-in-container.sh grava em /work/niri-built (= ${WORK_DIR}/niri-built).
  local bin="${WORK_DIR}/niri-built"
  if [[ ! -x ${bin} ]]; then
    err "o binário compilado não foi encontrado em ${bin}"
    return 1
  fi

  if ldd "${bin}" 2>/dev/null | grep -q 'not found'; then
    err "o binário compilado tem bibliotecas faltando no host:"
    ldd "${bin}" 2>/dev/null | grep 'not found' >&2 || true
    return 1
  fi
  if ! "${bin}" --version >/dev/null 2>&1; then
    err "o binário compilado não executa no host"
    return 1
  fi

  install -m 0755 "${bin}" "${ZOOM_BIN}.new"
  mv -f "${ZOOM_BIN}.new" "${ZOOM_BIN}"

  if command -v restorecon >/dev/null 2>&1; then
    run_cmd restorecon -v "${ZOOM_BIN}" || warn "restorecon falhou em ${ZOOM_BIN}"
  fi

  local bin_sha marker_tmp
  bin_sha="$(sha256sum "${ZOOM_BIN}" | awk '{print $1}')"
  marker_tmp="${WORK_DIR}/marker"
  {
    echo "commit=${ZOOM_COMMIT}"
    echo "patch=${ZOOM_PATCH_SHA256}"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "binary_sha256=${bin_sha}"
  } >"${marker_tmp}"
  run_cmd install -D -m 0644 "${marker_tmp}" "${ZOOM_MARKER}"
  if command -v restorecon >/dev/null 2>&1; then
    run_cmd restorecon -v "${ZOOM_MARKER}" || true
  fi

  ok "niri patchado instalado em ${ZOOM_BIN}"
}

install_helpers() {
  install_file "bin/msbos-zoom-reset" "/usr/local/bin/msbos-zoom-reset"
  run_cmd chmod 755 /usr/local/bin/msbos-zoom-reset
  install_file "bin/msbos-niri-zoom-remove" "/usr/local/bin/msbos-niri-zoom-remove"
  run_cmd chmod 755 /usr/local/bin/msbos-niri-zoom-remove
}

add_include_zoom() {
  local cfg="${NIRI_CFG}"
  local real="${cfg}"
  local linha='include "zoom.kdl"'
  local marca='// msbos: zoom do niri'

  if [[ ! -f ${cfg} ]]; then
    if [[ ${DRY_RUN} == 1 ]]; then
      log "dry-run: adicionaria '${linha}' em ${cfg} (o config ainda não existe na simulação)"
      return 0
    fi
    warn "config do niri ausente (${cfg}); não adicionei o include do zoom"
    return 1
  fi
  if [[ -L ${cfg} ]]; then
    real="$(readlink -f "${cfg}")"
  fi

  if grep -qE '^[[:space:]]*include[[:space:]]+"zoom\.kdl"' "${real}"; then
    log "config: include do zoom já presente em ${real}"
    return 0
  fi
  if grep -qE '^[[:space:]]*zoom[[:space:]]*\{' "${real}"; then
    warn "config: já existe um bloco 'zoom' em ${real}; não incluí o zoom.kdl do msbos"
    warn "        mescle as opções de ${ZOOM_CFG} manualmente se quiser o zoom por output"
    return 0
  fi
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: adicionaria '${linha}' em ${real}"
    return 0
  fi

  _backup_dst "${real}"
  run_cmd sh -c 'printf "\n%s\n%s\n" "$1" "$2" >> "$3"' _ "${marca}" "${linha}" "${real}"
  chown "${TU}:${TU_GROUP}" "${real}" 2>/dev/null || true

  if ! runuser -u "${TU}" -- \
       env "HOME=${TU_HOME}" "XDG_RUNTIME_DIR=/run/user/${TU_UID}" \
       "${ZOOM_BIN}" validate -c "${cfg}" >/dev/null 2>&1; then
    warn "config: '${ZOOM_BIN} validate' falhou após o include; restaurando o backup"
    if [[ -f ${real}.msbos-bak ]]; then
      run_cmd cp -a "${real}.msbos-bak" "${real}"
      chown "${TU}:${TU_GROUP}" "${real}" 2>/dev/null || true
    fi
    return 1
  fi

  ok "config: include do zoom adicionado em ${real}"
}

if marker_ok; then
  log "zoom do niri: binário já instalado no commit ${ZOOM_COMMIT:0:12} — pulando a compilação"
else
  if [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: compilaria ${ZOOM_REPO}@${ZOOM_COMMIT:0:12} + patch em ${ZOOM_IMAGE}"
    log "dry-run: instalaria o binário em ${ZOOM_BIN}"
  else
    build_niri || exit 1
  fi
fi

if [[ ${DRY_RUN} == 1 ]]; then
  install_file "bin/msbos-zoom-reset" "/usr/local/bin/msbos-zoom-reset" || exit 1
  install_file "bin/msbos-niri-zoom-remove" "/usr/local/bin/msbos-niri-zoom-remove" || exit 1
  install_file_once "niri/config.kdl" "${NIRI_CFG}" || exit 1
  install_file_once "niri/zoom.kdl" "${ZOOM_CFG}" || exit 1
  run_cmd chown "${TU}:${TU_GROUP}" "${NIRI_CFG}" "${ZOOM_CFG}"
  add_include_zoom || exit 1
  log "dry-run: zoom do niri seria instalado; nenhum arquivo foi alterado"
  exit 0
fi

install_helpers

install_file_once "niri/config.kdl" "${NIRI_CFG}"
install_file_once "niri/zoom.kdl" "${ZOOM_CFG}"
run_cmd chown "${TU}:${TU_GROUP}" "${NIRI_CFG}" "${ZOOM_CFG}"

add_include_zoom || exit 1

ok "zoom do niri pronto para o usuário ${TU}"
log "atalhos: Super+Alt+scroll (zoom), Super+Alt+0 (reset), Super+Alt+Z (trava)"
log "segure Super e mova o mouse para o pan; ao soltar, o zoom fica parado"
log "a sessão atual ainda usa o niri antigo — saia e entre de novo"
log "rollback: sudo msbos-niri-zoom-remove"
