#!/usr/bin/env bash
# 25-devtools.sh — ferramentas de desenvolvimento (por usuário):
#   • compiladores básicos (gcc/g++/make) — necessários p/ linkar crates Rust
#   • Rust via rustup (script oficial → ~/.cargo)
#   • Node.js via nvm (Node Version Manager → ~/.nvm) + npm
#   • pnpm e yarn (globais do Node)
# Idempotente: detecta o que já existe e pula.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
TU_SHELL="$(getent passwd "${TU}" | cut -d: -f7)"
[[ -n ${TU_SHELL} ]] || TU_SHELL=/bin/bash
log "dev: usuário-alvo: ${TU} (${TU_HOME})"

DNFOPT='--setopt=install_weak_deps=0'

# ─── 1. Compiladores básicos ────────────────────────────────────────────────
for p in gcc gcc-c++ make pkgconf-pkg-config; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || warn "dev: '${p}' indisponível — ignorado"
done

# ─── 2. Rust (rustup) ───────────────────────────────────────────────────────
if [[ -x ${TU_HOME}/.cargo/bin/cargo ]]; then
  ok "Rust já instalado (rustup) — pulando"
else
  log "dev: Rust via rustup (script oficial: https://sh.rustup.rs)"
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" "SHELL=${TU_SHELL}" \
    bash -c 'curl -fsSL --retry 2 https://sh.rustup.rs | sh -s -- -y' \
    || warn "dev: falha ao instalar o Rust"
fi

# ─── 3. nvm (Node Version Manager) ──────────────────────────────────────────
if [[ -s ${TU_HOME}/.nvm/nvm.sh ]]; then
  ok "nvm já instalado — pulando"
elif [[ ${DRY_RUN} == 1 ]]; then
  log "dry-run: instalaria o nvm (script oficial) em ${TU_HOME}/.nvm"
else
  log "dev: nvm (Node Version Manager) — script oficial"
  NVM_TAG="$(curl -fsSL --retry 2 --max-time 15 https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1 || true)"
  [[ -n ${NVM_TAG} ]] || NVM_TAG='v0.40.8'   # fallback (última conhecida)
  # NVM_TAG passa via env (não por interpolação na string de comando)
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" "SHELL=${TU_SHELL}" "NVM_TAG=${NVM_TAG}" \
    bash -c 'curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh" | bash' \
    || warn "dev: falha ao instalar o nvm"
fi

# ─── 4. Node LTS + pnpm/yarn (dentro do nvm) ────────────────────────────────
if [[ ${DRY_RUN} == 1 ]]; then
  log "dry-run: instalaria Node LTS (nvm install --lts) + 'npm install -g pnpm yarn'"
elif [[ -s ${TU_HOME}/.nvm/nvm.sh ]]; then
  SETUP="$(mktemp)"
  cat > "${SETUP}" <<'EOS'
set -e
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'
npm install -g pnpm yarn
EOS
  chmod 644 "${SETUP}"   # o script roda como o usuário-alvo
  run_cmd runuser -u "${TU}" -- env "HOME=${TU_HOME}" "SHELL=${TU_SHELL}" bash "${SETUP}" \
    || warn "dev: falha ao preparar Node LTS/pnpm/yarn"
  rm -f "${SETUP}"
fi

ok "dev tools prontos (Rust, Node/nvm, npm, pnpm, yarn)"
