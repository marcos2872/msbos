#!/usr/bin/env bash
# 10-gpu.sh — detecta GPUs (Intel / AMD / NVIDIA, incluindo setups híbridos)
# e instala os drivers adequados.
#
# Perfis: auto (detecta) | intel | amd | nvidia | hybrid | none
#
# Híbrido (iGPU + dGPU NVIDIA): instala o driver NVIDIA, habilita modeset e
# configura offload GL via __GLX_VENDOR_LIBRARY_NAME=nvidia (por app).

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

install_nvidia_driver() {
  log "gpu: NVIDIA detectada — instalando driver proprietário (Wayland exige KMS)"
  # 1) driver binário pronto (mais leve; não exige toolchain); fallback: akmod
  if ! run_cmd dnf -y "${DNFOPT}" install nvidia; then
    warn "pacote binário 'nvidia' indisponível; tentando 'akmod-nvidia' (compila localmente)"
    if ! run_cmd dnf -y install akmod-nvidia; then
      err "falha ao instalar o driver NVIDIA"
      return 1
    fi
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
