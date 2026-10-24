#!/usr/bin/env bash
# msbos — bootstrap de uma base Fedora KDE para o stack niri + Noctalia (baixo uso de RAM).
#
# Uso:
#   ./install.sh [opções]
#
# Opções:
#   --dry-run              Simula tudo (não instala, não remove, não escreve)
#   --yes, -y              Autoriza operações destrutivas (remover o shell do Plasma e limpar
#                          artefatos antigos) sem perguntar
#   --no-greeter           Não adiciona o repo Terra (usa o greeter padrão do greetd)
#   --user NOME            Usuário-alvo da configuração (padrão: quem chamou o sudo)
#   --gpu-profile PERFIL   Força: auto|intel|amd|nvidia|hybrid|none (padrão: auto)
#   --skip-remove          Nunca remove pacotes (apenas instala e ajusta serviços)
#   -h, --help             Esta ajuda
#
# Imagem base:
#   Funciona em qualquer Fedora 44/45 já instalado — Fedora KDE (remove o shell do
#   Plasma/Plasma Login Manager e mantém os apps KDE) ou instalação mínima
#   (adiciona o stack completo).
#   Download: KDE → https://fedoraproject.org/kde/download
#             mínima (Everything, "Minimal Install") → https://fedoraproject.org/misc
#
#   Para testar numa VM:
#     virt-install --name msbos --memory 4096 --vcpus 3 --disk size=25 \
#       --cdrom /caminho/Fedora-KDE-Desktop-Live-44.iso \
#       --os-variant fedora-unknown --graphics spice
#
#   Depois, dentro da VM (sem git clone):
#     curl -fsSL https://raw.githubusercontent.com/marcos2872/msbos/main/bootstrap.sh -o /tmp/msbos.sh
#     sudo bash /tmp/msbos.sh --dry-run   # e depois sem --dry-run

set -euo pipefail

MSBOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults — só valem se a variável não veio do ambiente (reexecução via sudo)
: "${DRY_RUN:=0}"
: "${YES:=0}"
: "${NO_GREETER:=0}"
: "${TARGET_USER:=}"
: "${GPU_PROFILE:=auto}"
: "${SKIP_REMOVE:=0}"

usage() { awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "${MSBOS_ROOT}/install.sh"; }

while (($#)); do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --yes|-y)       YES=1 ;;
    --no-greeter)   NO_GREETER=1 ;;
    --user)         shift; TARGET_USER="${1:?--user requer um nome}" ;;
    --gpu-profile)  shift; GPU_PROFILE="${1:?--gpu-profile requer um valor}" ;;
    --skip-remove)  SKIP_REMOVE=1 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

export DRY_RUN YES NO_GREETER TARGET_USER GPU_PROFILE SKIP_REMOVE

# Reexecuta com privilégios (mantendo as variáveis acima)
if [[ ${EUID} -ne 0 && ${DRY_RUN} -eq 0 ]]; then
  echo "→ msbos precisa de root; reexecutando com sudo..."
  exec sudo env \
    "DRY_RUN=${DRY_RUN}" "YES=${YES}" "NO_GREETER=${NO_GREETER}" \
    "TARGET_USER=${TARGET_USER}" "GPU_PROFILE=${GPU_PROFILE}" "SKIP_REMOVE=${SKIP_REMOVE}" \
    bash "${MSBOS_ROOT}/install.sh"
fi

printf '\n%s\n' "╔═══════════════════════════════════════════════════════════════╗"
printf '%s\n'   "║  msbos — Fedora KDE + niri + Noctalia (baixo uso de RAM)      ║"
printf '%s\n\n' "╚═══════════════════════════════════════════════════════════════╝"

if [[ ${DRY_RUN} == 1 ]]; then
  echo "  modo: DRY-RUN (nada será alterado)"
fi

STEPS=()
while IFS= read -r s; do STEPS+=("${s}"); done < <(cd "${MSBOS_ROOT}/scripts" && ls -1 [0-9][0-9]-*.sh | sort)

if ((${#STEPS[@]} == 0)); then
  echo "nenhuma etapa encontrada em ${MSBOS_ROOT}/scripts" >&2
  exit 1
fi

# Estado das etapas concluídas (só grava em modo real; nenhum arquivo em dry-run).
# Serve de registro/auditoria: se uma etapa falhar, o histórico em
# /var/lib/msbos/steps mostra exatamente até onde a instalação chegou.
STATE_DIR="/var/lib/msbos/steps"

for step in "${STEPS[@]}"; do
  printf '\n──── %s ────\n' "${step}"
  # Nota: "if ! cmd; then rc=$?" NÃO funciona — $? traria o status invertido
  # do pipeline negado. Por isso capturamos com "|| rc=$?".
  rc=0
  bash "${MSBOS_ROOT}/scripts/${step}" || rc=$?
  if ((rc != 0)); then
    printf '\n%s\n' "══════════════════════════════════════════════════════════"
    printf '[ER ] a etapa %s falhou (código %s).\n' "${step}" "${rc}"
    cat <<MSG

  O que fazer:
    • veja a mensagem de erro acima e corrija a causa
    • as etapas são idempotentes — rodar de novo é seguro:
        sudo ./install.sh              # tudo, desde o início
        sudo bash scripts/${step}      # só esta etapa
    • histórico do que já foi aplicado: ls ${STATE_DIR}/
MSG
    printf '%s\n\n' "══════════════════════════════════════════════════════════"
    exit "${rc}"
  fi
  if [[ ${DRY_RUN} == 0 ]]; then
    mkdir -p "${STATE_DIR}"
    date '+%Y-%m-%d %H:%M:%S' > "${STATE_DIR}/${step}"
  fi
done

printf '\n%s\n' "══════════════════════════════════════════════════════════"
echo " msbos: instalação concluída. Reinicie para entrar no niri."
printf '%s\n\n' "══════════════════════════════════════════════════════════"
