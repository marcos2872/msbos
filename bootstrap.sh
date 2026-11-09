#!/usr/bin/env bash
# msbos — baixa o repositório e executa o install.sh sem precisar de git clone.
#
# Uso recomendado (terminal interativo):
#   curl -fsSL https://raw.githubusercontent.com/marcos2872/msbos/main/bootstrap.sh -o /tmp/msbos.sh
#   sudo bash /tmp/msbos.sh [opções do install.sh]
#
# Uso não interativo (VM descartável / CI):
#   curl -fsSL https://raw.githubusercontent.com/marcos2872/msbos/main/bootstrap.sh | sudo bash -s -- --yes
#
# Variáveis de ambiente:
#   MSBOS_REF   branch, tag ou commit a baixar (padrão: main)
#   MSBOS_REPO  owner/repo alternativo (padrão: marcos2872/msbos)
#   MSBOS_URL   URL completa do .tar.gz (sobrepõe REPO/REF; útil para espelho/teste)
#   MSBOS_KEEP=1 mantém o diretório temporário para depuração
#
# Exemplos:
#   sudo bash /tmp/msbos.sh --dry-run
#   sudo bash /tmp/msbos.sh --yes
#   sudo env MSBOS_REF=SEU_TAG_OU_COMMIT bash /tmp/msbos.sh --yes
#
# O script só baixa o código; toda a instalação (dnf, arquivos, serviços) é feita
# pelo install.sh, que continua sendo a única fonte da verdade.

set -euo pipefail

REPO="${MSBOS_REPO:-marcos2872/msbos}"
REF="${MSBOS_REF:-main}"
URL="${MSBOS_URL:-https://github.com/${REPO}/archive/${REF}.tar.gz}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/msbos.XXXXXX")"
TARBALL="${TMP}/repo.tar.gz"

# Modo --firstboot: instala só o serviço de primeiro boot e NÃO roda o install.sh
# agora (é o que o %post de um kickstart usa — o chroot não tem systemd como PID
# 1). A instalação de verdade acontece no primeiro boot; veja
# kickstart/msbos-firstboot.ks. As demais opções seguem para o install.sh.
FIRSTBOOT=0
WITH_NIRI_ZOOM=0
ALVO_USUARIO=""
ARGS=()
while (($# > 0)); do
  case "$1" in
    --firstboot) FIRSTBOOT=1 ;;
    --with-niri-zoom) WITH_NIRI_ZOOM=1; ARGS+=("$1") ;;
    --user)
      ALVO_USUARIO="${2:-}"
      ARGS+=("$1")
      if [[ -n ${2:-} ]]; then ARGS+=("$2"); shift; fi
      ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
if ((${#ARGS[@]} > 0)); then
  set -- "${ARGS[@]}"
else
  set --
fi

cleanup() {
  local rc
  rc=$?
  trap - EXIT
  if [[ ${MSBOS_KEEP:-0} == 1 ]]; then
    echo "→ arquivos mantidos em ${TMP}" >&2
  else
    rm -rf "${TMP}"
  fi
  exit "${rc}"
}
trap cleanup EXIT

if [[ ! -r /etc/fedora-release ]]; then
  echo "erro: o msbos é feito para Fedora (arquivo /etc/fedora-release não encontrado)" >&2
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

# ─── modo --firstboot (kickstart %post) ─────────────────────────────────────
if ((FIRSTBOOT == 1)); then
  if [[ -z ${ALVO_USUARIO} ]]; then
    echo "erro: --firstboot requer --user NOME (quem recebe a configuração no primeiro boot)" >&2
    exit 1
  fi
  if [[ ${EUID} -ne 0 ]]; then
    echo "erro: --firstboot precisa de root (no %post do kickstart você já é root)" >&2
    exit 1
  fi
  if ! getent passwd "${ALVO_USUARIO}" >/dev/null 2>&1; then
    echo "erro: usuário '${ALVO_USUARIO}' não existe (crie no kickstart com 'user ...')" >&2
    exit 1
  fi
  for f in assets/libexec/msbos-firstboot assets/msbos-firstboot.service; do
    if [[ ! -r "${TMP}/${f}" ]]; then
      echo "erro: ${f} ausente no pacote baixado (${URL})" >&2
      exit 1
    fi
  done
  install -D -m 0755 "${TMP}/assets/libexec/msbos-firstboot" /usr/local/libexec/msbos-firstboot
  install -D -m 0644 "${TMP}/assets/msbos-firstboot.service" \
    /etc/systemd/system/msbos-firstboot.service
  install -d -m 0755 /etc/msbos /etc/systemd/system/multi-user.target.wants
  if [[ ! -f /etc/msbos/firstboot.conf ]]; then
    {
      echo "# msbos — instalação no primeiro boot (criado por bootstrap.sh --firstboot)."
      echo "# Usuário-alvo da configuração (o dono do desktop)."
      echo "TARGET_USER=${ALVO_USUARIO}"
      echo "# Ref e repositório de onde baixar o instalador (padrão: main e ${REPO})."
      echo "MSBOS_REF=${REF}"
      echo "MSBOS_REPO=${REPO}"
      echo "WITH_NIRI_ZOOM=${WITH_NIRI_ZOOM}"
    } >/etc/msbos/firstboot.conf
    chmod 0644 /etc/msbos/firstboot.conf
  else
    echo "→ /etc/msbos/firstboot.conf já existe — mantido"
  fi
  # enable por symlink: no chroot do %post o systemd não está rodando
  ln -sfn /etc/systemd/system/msbos-firstboot.service \
    /etc/systemd/system/multi-user.target.wants/msbos-firstboot.service
  echo "→ serviço de primeiro boot instalado e habilitado (roda no próximo boot)"
  echo "  logs: journalctl -u msbos-firstboot"
  echo "  não reiniciei a máquina: a instalação começa no próximo boot."
  exit 0
fi

if [[ ! -f "${TMP}/install.sh" ]]; then
  echo "erro: install.sh não encontrado no pacote baixado (${URL})" >&2
  exit 1
fi

echo "→ executando install.sh..."
rc=0
bash "${TMP}/install.sh" "$@" || rc=$?
exit "${rc}"
