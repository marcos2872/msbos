#!/usr/bin/env bash
# MyOS — bootstrap de uma base Fedora para o stack niri + Noctalia (baixo uso de RAM).
#
# Uso:
#   ./install.sh [opções]
#
# Opções:
#   --dry-run              Simula tudo (não instala, não remove, não escreve)
#   --yes, -y              Autoriza operações destrutivas (remover GDM/GNOME) sem perguntar
#   --no-greeter           Não adiciona o repo Terra (usa o greeter padrão do greetd)
#   --user NOME            Usuário-alvo da configuração (padrão: quem chamou o sudo)
#   --gpu-profile PERFIL   Força: auto|intel|amd|nvidia|hybrid|none (padrão: auto)
#   --skip-remove          Nunca remove pacotes (apenas instala e ajusta serviços)
#   -h, --help             Esta ajuda
#
# Imagem base:
#   Funciona em qualquer Fedora 44/45 já instalado — Workstation (remove o GNOME/GDM)
#   ou instalação mínima (adiciona o stack). Para testar numa VM:
#
#     virt-install --name myos --memory 4096 --vcpus 3 --disk size=25 \
#       --cdrom /caminho/Fedora-Workstation-Live-x86_64-45.iso \
#       --os-variant fedora-unknown --graphics spice
#
#   Depois, dentro da VM: git clone <este repo> && ./install.sh

set -euo pipefail

MYOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults — só valem se a variável não veio do ambiente (reexecução via sudo)
: "${DRY_RUN:=0}"
: "${YES:=0}"
: "${NO_GREETER:=0}"
: "${TARGET_USER:=}"
: "${GPU_PROFILE:=auto}"
: "${SKIP_REMOVE:=0}"

usage() { sed -n '2,24p' "${MYOS_ROOT}/install.sh" | sed 's/^# \{0,1\}//'; }

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
  echo "→ MyOS precisa de root; reexecutando com sudo..."
  exec sudo env \
    "DRY_RUN=${DRY_RUN}" "YES=${YES}" "NO_GREETER=${NO_GREETER}" \
    "TARGET_USER=${TARGET_USER}" "GPU_PROFILE=${GPU_PROFILE}" "SKIP_REMOVE=${SKIP_REMOVE}" \
    bash "${MYOS_ROOT}/install.sh"
fi

printf '\n%s\n' "╔══════════════════════════════════════════════════════════╗"
printf '%s\n'   "║  MyOS — Fedora + niri + Noctalia (baixo uso de RAM)      ║"
printf '%s\n\n' "╚══════════════════════════════════════════════════════════╝"

if [[ ${DRY_RUN} == 1 ]]; then
  echo "  modo: DRY-RUN (nada será alterado)"
fi

STEPS=()
while IFS= read -r s; do STEPS+=("${s}"); done < <(cd "${MYOS_ROOT}/scripts" && ls -1 [0-9][0-9]-*.sh | sort)

for step in "${STEPS[@]}"; do
  printf '\n──── %s ────\n' "${step}"
  bash "${MYOS_ROOT}/scripts/${step}"
done

printf '\n%s\n' "══════════════════════════════════════════════════════════"
echo " MyOS: instalação concluída. Reinicie para entrar no niri."
printf '%s\n\n' "══════════════════════════════════════════════════════════"
