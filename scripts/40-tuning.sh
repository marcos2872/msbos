#!/usr/bin/env bash
# 40-tuning.sh — otimizações de memória e desempenho:
#   • zram: swap comprimido em RAM (zstd)
#   • sysctl de memória (swappiness, vfs_cache_pressure, min_free_kbytes)
#   • btrfs: compressão zstd no root
#   • governor de CPU fixo em performance (somente desktops sem bateria)
#   • systemd-oomd: mata processos famintos antes de travar a máquina
#   • tuned: perfil latency-performance

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

# ─── 1. zram (swap comprimido) ──────────────────────────────────────────────
# Path correto: /etc/systemd/zram-generator.conf (o zram-generator IGNORA
# /etc/zram-generator.conf). O generator cria e liga as units no boot
# (swap.target → dev-zram0.swap) — não é preciso habilitar serviço.
install_file "zram-generator.conf" "/etc/systemd/zram-generator.conf"
# limpa arquivo antigo no path errado (versões anteriores; aceita o nome antigo
# e o atual, para não deixar lixo de uma instalação pré-renomeação)
if [[ -f /etc/zram-generator.conf ]] && grep -qiE 'msbos|omyfedora|my[-_ ]?os' /etc/zram-generator.conf; then
  run_cmd rm -f /etc/zram-generator.conf
  log "tuning: removido /etc/zram-generator.conf (path errado de versão antiga)"
fi
# Sanidade: roda o próprio generator contra a config recém-instalada. Um parse
# inválido (ex.: "50%") não daria erro visível no boot — apenas o sistema
# ficaria sem swap. Falha aqui = bug nosso: aborta o install na hora.
if [[ ${DRY_RUN} == 0 && -x /usr/lib/systemd/system-generators/zram-generator ]]; then
  gen_dir="$(mktemp -d)"
  if ! /usr/lib/systemd/system-generators/zram-generator "${gen_dir}" >/dev/null 2>"${gen_dir}/err"; then
    err "zram-generator rejeitou /etc/systemd/zram-generator.conf: $(head -n1 "${gen_dir}/err")"
    rm -rf "${gen_dir}"
    exit 1
  fi
  rm -rf "${gen_dir}"
fi
ok "zram configurado (~75% da RAM, teto de 16 GiB, como swap zstd; aplica no próximo boot)"

# ─── 2. sysctl de memória ───────────────────────────────────────────────────
mem_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
mfk=$(( mem_kb / 64 ))
if (( mfk < 8192 )); then mfk=8192; fi
if (( mfk > 8388608 )); then mfk=8388608; fi
render_file "sysctl.d/99-msbos.conf" "/etc/sysctl.d/99-msbos.conf" "__MINFREE__" "${mfk}"
run_cmd sysctl --system >/dev/null 2>&1 || true
ok "sysctl aplicado (min_free_kbytes=${mfk}K)"

# ─── 3. btrfs: compressão zstd no root ──────────────────────────────────────
rootfs="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
if [[ ${rootfs} == btrfs ]]; then
  if grep -E '^[^#][^[:space:]]*[[:space:]]+/[[:space:]]+btrfs[[:space:]]' /etc/fstab 2>/dev/null | grep -q 'compress='; then
    ok "btrfs: compressão já configurada no /etc/fstab"
  elif [[ ${DRY_RUN} == 1 ]]; then
    log "dry-run: adicionaria compress=zstd:1 ao /etc/fstab"
  else
    cp -a /etc/fstab /etc/fstab.msbos-bak 2>/dev/null || true
    if sed -i -E 's|^([^#][^[:space:]]*[[:space:]]+/[[:space:]]+btrfs[[:space:]]+)([a-zA-Z0-9=,_-]+)|\1compress=zstd:1,\2|' /etc/fstab \
       && grep -E '^[^#][^[:space:]]*[[:space:]]+/[[:space:]]+btrfs[[:space:]]' /etc/fstab | grep -q 'compress=zstd'; then
      ok "btrfs: compress=zstd:1 adicionado ao /etc/fstab (vale após reboot)"
    else
      warn "btrfs: não consegui editar /etc/fstab automaticamente (backup em /etc/fstab.msbos-bak)"
    fi
  fi
else
  log "tuning: root em '${rootfs:-?}' — compressão btrfs não se aplica (dica: use btrfs na próxima instalação)"
fi

# ─── 4. Governor de CPU (somente desktops sem bateria) ─────────────────────
has_battery=0
for ps in /sys/class/power_supply/*; do
  [[ -r "${ps}/type" ]] || continue
  if [[ "$(<"${ps}/type")" == "Battery" ]]; then
    has_battery=1
    break
  fi
done
if (( has_battery == 0 )); then
  install_file "msbos-cpu-governor.service" "/etc/systemd/system/msbos-cpu-governor.service"
  install_file "bin/msbos-cpu-governor" "/usr/local/bin/msbos-cpu-governor"
  run_cmd chmod 755 /usr/local/bin/msbos-cpu-governor
  run_cmd systemctl enable msbos-cpu-governor.service >/dev/null 2>&1 || true
  ok "governor: performance fixado no boot (desktop sem bateria)"
else
  log "tuning: bateria detectada — power-profiles-daemon cuida da energia"
fi

# ─── 5. systemd-oomd ────────────────────────────────────────────────────────
if [[ -f /usr/lib/systemd/system/systemd-oomd.service ]]; then
  install_file "oomd.conf" "/etc/systemd/oomd.conf"
  ok "oomd: configuração conservadora aplicada"
fi

# ─── 6. tuned ───────────────────────────────────────────────────────────────
if command -v tuned-adm >/dev/null 2>&1; then
  run_cmd tuned-adm profile latency-performance >/dev/null 2>&1 || true
  ok "tuned: perfil latency-performance"
fi

run_cmd systemctl daemon-reload
run_cmd dnf clean all >/dev/null 2>&1 || true
ok "tuning concluído"
