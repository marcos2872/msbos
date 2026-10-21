#!/usr/bin/env bash
# 10-gpu.sh — detecta GPUs (Intel / AMD / NVIDIA, incluindo setups híbridos)
# e instala os drivers adequados.
#
# Perfis: auto (detecta) | intel | amd | nvidia | hybrid | none
#
# Híbrido (iGPU + dGPU NVIDIA): instala o driver NVIDIA, habilita modeset e
# configura offload GL via __GLX_VENDOR_LIBRARY_NAME=nvidia (por app).
# NVIDIA: habilita o RPM Fusion (free + nonfree) e usa akmod-nvidia; verifica
# Secure Boot e compila o módulo antes de pedir o reboot.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

# dnf enxuto: sem weak deps (mesma opção usada nas outras etapas)
DNFOPT='--setopt=install_weak_deps=0'

declare -A FOUND=() DEVS=()

_add() { FOUND[$1]=1; DEVS[$1]="${DEVS[$1]:-}${DEVS[$1]:+ }$2"; }

detect_pci_gpus() {
  local d cls ven name
  for d in /sys/bus/pci/devices/*; do
    [[ -r "${d}/class" && -r "${d}/vendor" ]] || continue
    cls="$(<"${d}/class")"; ven="$(<"${d}/vendor")"; name="$(basename "${d}")"
    cls="${cls#0x}"; ven="${ven#0x}"
    [[ "${cls:0:2}" == "03" ]] || continue   # classe 03xx = VGA/3D/display
    case "${ven}" in
      10de) _add nvidia "${name}" ;;
      1002) _add amd    "${name}" ;;
      8086) _add intel  "${name}" ;;
      *)    log "gpu: GPU de fabricante desconhecido (vendor ${ven}) em ${name} — Mesa cobre" ;;
    esac
  done
}

detect_loaded_drivers() {
  # complementa o scan PCI com módulos já carregados
  if lsmod 2>/dev/null | grep -q '^nvidia'; then _add nvidia "módulo nvidia carregado"; fi
  if lsmod 2>/dev/null | grep -q '^amdgpu'; then _add amd    "módulo amdgpu carregado"; fi
  if lsmod 2>/dev/null | grep -qE '^i915|^xe'; then _add intel "módulo i915/xe carregado"; fi
}

profile_from_detection() {
  if [[ -n ${FOUND[nvidia]:-} ]]; then
    if [[ -n ${FOUND[intel]:-} || -n ${FOUND[amd]:-} ]]; then
      echo hybrid
    else
      echo nvidia
    fi
  elif [[ -n ${FOUND[amd]:-} ]]; then
    echo amd
  elif [[ -n ${FOUND[intel]:-} ]]; then
    echo intel
  else
    echo none
  fi
}

# enable_rpmfusion — habilita o RPM Fusion free + nonfree (pré-requisito do
# akmod-nvidia). Idempotente: só instala os pacotes de release se faltarem.
enable_rpmfusion() {
  local rel="${FEDORA_VERSION:-}"
  if [[ ! ${rel} =~ ^[0-9]+$ ]]; then
    warn "gpu: versão do Fedora desconhecida ('${rel:-?}') — não sei qual RPM Fusion usar"
    return 1
  fi
  if rpm -q rpmfusion-free-release >/dev/null 2>&1 &&
     rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
    ok "gpu: RPM Fusion já habilitado"
    return 0
  fi
  log "gpu: habilitando o RPM Fusion (free + nonfree) para o driver NVIDIA"
  run_cmd dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${rel}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${rel}.noarch.rpm" \
    || { warn "gpu: falha ao habilitar o RPM Fusion"; return 1; }
}

install_nvidia_driver() {
  log "gpu: NVIDIA detectada — instalando driver proprietário (Wayland exige KMS)"
  # O pacote 'nvidia' não existe no Fedora nem no RPM Fusion: o driver vem do
  # akmod-nvidia (compila o módulo para o kernel em uso e para os próximos).
  # O RPM Fusion nonfree é pré-requisito e não vem habilitado numa base limpa.
  if ! enable_rpmfusion; then
    err "driver NVIDIA: RPM Fusion indisponível — instale o akmod-nvidia manualmente"
    return 1
  fi
  if ! run_cmd dnf -y "${DNFOPT}" install akmod-nvidia; then
    err "falha ao instalar o akmod-nvidia"
    return 1
  fi
  # Compila o módulo AGORA: o próximo boot não pode depender de uma compilação
  # que ainda não aconteceu. O serviço akmods recompila em kernels novos.
  if command -v akmods >/dev/null 2>&1; then
    run_cmd akmods --force \
      || warn "gpu: 'akmods --force' falhou — o módulo pode não estar pronto no próximo boot"
  fi
  if [[ ${DRY_RUN} == 0 ]] && ! modinfo nvidia >/dev/null 2>&1; then
    warn "gpu: módulo nvidia ainda não disponível — confira 'akmods --force' e o journal do akmods"
  fi
  # Secure Boot: o akmod assina o módulo com uma chave local que precisa ser
  # enrolada no firmware; sem isso o kernel recusa o módulo e o niri não sobe.
  if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    warn "gpu: Secure Boot ativo — o módulo NVIDIA precisa de uma chave enrolada"
    warn "     rode: sudo kmodgenca -a && sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
    warn "     (defina uma senha, reinicie e conclua o enrolamento no menu do firmware)"
  fi
  # 2) nvidia-drm.modeset=1 é obrigatório para Wayland
  if command -v grubby >/dev/null 2>&1; then
    run_cmd grubby --update-kernel=ALL --args=nvidia-drm.modeset=1
  else
    warn "grubby ausente: adicione 'nvidia-drm.modeset=1' manualmente à cmdline do kernel"
  fi
  # 3) offload GL para a NVIDIA (inofensivo em dGPU única, essencial em híbrido)
  install_file "profile.d/omyfedora-nvidia.sh" "/etc/profile.d/omyfedora-nvidia.sh"
}

ensure_igpu() {
  local vendor=$1 pkg=''
  case "${vendor}" in
    intel) pkg="microcode_ctl" ;;        # microcódigo Intel (Fedora)
    amd)   pkg="amd-ucode-firmware" ;;   # microcódigo AMD (split do linux-firmware)
  esac
  run_cmd dnf -y "${DNFOPT}" install mesa-dri-drivers \
    || warn "mesa-dri-drivers: falha na instalação"
  if [[ -n ${pkg} ]]; then
    run_cmd dnf -y "${DNFOPT}" install "${pkg}" \
      || warn "${pkg}: falha na instalação"
  fi
}

main() {
  detect_pci_gpus
  detect_loaded_drivers

  local detail='' k
  for k in nvidia amd intel; do
    if [[ -n ${FOUND[$k]:-} ]]; then
      detail+="${k} [${DEVS[$k]}] "
    fi
  done
  if [[ -n ${detail} ]]; then
    log "gpu: GPUs detectadas: ${detail}"
  else
    warn "nenhuma GPU de vídeo PCI encontrada"
  fi

  local profile="${GPU_PROFILE:-auto}"
  if [[ ${profile} == auto ]]; then
    profile="$(profile_from_detection)"
  fi
  case "${profile}" in
    intel|amd|nvidia|hybrid|none) ;;
    *) err "perfil de GPU inválido: ${profile} (use auto|intel|amd|nvidia|hybrid|none)"; exit 1 ;;
  esac
  log "gpu: perfil escolhido: ${profile}"

  case "${profile}" in
    nvidia)
      install_nvidia_driver || warn "driver NVIDIA com problema — verifique no próximo boot"
      ;;
    hybrid)
      log "gpu: setup híbrido — iGPU + dGPU NVIDIA (offload configurado)"
      # Atenção (limitação conhecida): em híbrido o driver proprietário + o
      # profile.d que força __GLX_VENDOR_LIBRARY_NAME=nvidia fazem apps GLX
      # renderizarem na dGPU, o que pode mantê-la acordada (mais ruado/energia).
      # Para forçar a iGPU num app específico:
      #   __GLX_VENDOR_LIBRARY_NAME=mesa <app>
      # Confira o consumo/estado com: nvidia-smi --query-gpu=name,power.draw
      install_nvidia_driver || warn "driver NVIDIA com problema"
      if [[ -n ${FOUND[intel]:-} ]]; then ensure_igpu intel; fi
      if [[ -n ${FOUND[amd]:-} ]]; then ensure_igpu amd; fi
      ;;
    amd)   ensure_igpu amd ;;
    intel) ensure_igpu intel ;;
    none)
      warn "sem GPU dedicada (VM?) — renderização por software (Mesa/llvmpipe)"
      ;;
  esac

  ok "etapa de GPU concluída (driver efetivo após reboot)"
}

main "$@"
