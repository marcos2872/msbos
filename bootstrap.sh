#!/usr/bin/env bash
# omyfedora — baixa o repositório e executa o install.sh sem precisar de git clone.
#
# Uso recomendado (terminal interativo):
#   curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh -o /tmp/omyfedora.sh
#   sudo bash /tmp/omyfedora.sh [opções do install.sh]
#
# Uso não interativo (VM descartável / CI):
#   curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh | sudo bash -s -- --yes
#
# Variáveis de ambiente:
#   OMYFEDORA_REF   branch, tag ou commit a baixar (padrão: main)
#   OMYFEDORA_REPO  owner/repo alternativo (padrão: marcos2872/omyfedora)
#   OMYFEDORA_URL   URL completa do .tar.gz (sobrepõe REPO/REF; útil para espelho/teste)
#   OMYFEDORA_KEEP=1 mantém o diretório temporário para depuração
#
# Exemplos:
#   sudo bash /tmp/omyfedora.sh --dry-run
#   sudo bash /tmp/omyfedora.sh --yes
#   sudo env OMYFEDORA_REF=SEU_TAG_OU_COMMIT bash /tmp/omyfedora.sh --yes
#
# O script só baixa o código; toda a instalação (dnf, arquivos, serviços) é feita
# pelo install.sh, que continua sendo a única fonte da verdade.

set -euo pipefail

REPO="${OMYFEDORA_REPO:-marcos2872/omyfedora}"
REF="${OMYFEDORA_REF:-main}"
URL="${OMYFEDORA_URL:-https://github.com/${REPO}/archive/${REF}.tar.gz}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/omyfedora.XXXXXX")"
TARBALL="${TMP}/repo.tar.gz"

cleanup() {
  local rc
  rc=$?
  trap - EXIT
  if [[ ${OMYFEDORA_KEEP:-0} == 1 ]]; then
    echo "→ arquivos mantidos em ${TMP}" >&2
  else
    rm -rf "${TMP}"
  fi
  exit "${rc}"
}
trap cleanup EXIT

if [[ ! -r /etc/fedora-release ]]; then
  echo "erro: o omyfedora é feito para Fedora (arquivo /etc/fedora-release não encontrado)" >&2
  exit 1
fi

for cmd in curl tar; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "erro: '${cmd}' não encontrado; instale com: sudo dnf install -y curl tar" >&2
    exit 1
  }
done

# Sem TTY, o install.sh não consegue responder ao prompt de remoção do Plasma.
# --yes resolve; avisamos para evitar uma instalação parcial silenciosa.
if [[ ! -t 0 ]]; then
  echo "aviso: stdin não é um terminal; use --yes para não depender de prompts." >&2
fi

echo "→ baixando ${REPO}@${REF}..."
if ! curl -fsSL --retry 3 --retry-delay 2 "${URL}" -o "${TARBALL}"; then
  echo "erro: falha ao baixar ${URL}" >&2
  echo "      confira a ref '${REF}', o repositório '${REPO}' e a conexão." >&2
  exit 1
fi

echo "→ extraindo..."
if ! tar -xzf "${TARBALL}" -C "${TMP}" --strip-components=1; then
  echo "erro: falha ao extrair o pacote baixado de ${URL}" >&2
  exit 1
fi
rm -f "${TARBALL}"

if [[ ! -f "${TMP}/install.sh" ]]; then
  echo "erro: install.sh não encontrado no pacote baixado (${URL})" >&2
  exit 1
fi

echo "→ executando install.sh..."
rc=0
bash "${TMP}/install.sh" "$@" || rc=$?
exit "${rc}"
