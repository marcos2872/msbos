#!/usr/bin/env bash
# 60-agent-skill.sh — skill msbos para agentes de IA (~/.agents) + helper
# privilegiado com polkit (lista permitida).
#
# O que instala:
#   • /usr/local/libexec/msbos-priv           helper (root), chamado via pkexec
#   • /usr/share/polkit-1/actions/org.msbos.priv.policy   ações do polkit (senha sempre)
#   • /etc/msbos/{allowed-units,protected}.list  listas extras (só de root; uma vez)
#   • /var/log/msbos/                         trilha das ações privilegiadas
#   • ~/.agents/skills/msbos/                 skill (references/local.md: uma vez)
#   • ~/.agents/skills/noctalia-plugin/           skill de plugins do Noctalia (sempre atualizada)
#
# Pré-requisito em runtime: um agente polkit rodando na sessão do niri (o polkit-kde
# do CORE precisa estar no autostart), senão o pkexec não consegue abrir a janela.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_fedora

TU="$(resolve_target_user)" || exit 1
TU_HOME="$(user_home "${TU}")"
TU_GROUP="$(id -gn "${TU}")"
SKILL_SRC="agents/skills/msbos"
SKILL_DST="${TU_HOME}/.agents/skills/msbos"
SKILL_NP_SRC="agents/skills/noctalia-plugin"
SKILL_NP_DST="${TU_HOME}/.agents/skills/noctalia-plugin"
log "agent-skill: usuário-alvo: ${TU} (${TU_HOME})"

command -v pkexec >/dev/null 2>&1 \
  || warn "agent-skill: pkexec ausente (pacote polkit) — o helper não poderá ser chamado"

# ─── 1. Helper privilegiado + política polkit ───────────────────────────────
install_file "libexec/msbos-priv" "/usr/local/libexec/msbos-priv"
run_cmd chown root:root /usr/local/libexec/msbos-priv
run_cmd chmod 755 /usr/local/libexec/msbos-priv

install_file "polkit/org.msbos.priv.policy" "/usr/share/polkit-1/actions/org.msbos.priv.policy"
run_cmd chown root:root /usr/share/polkit-1/actions/org.msbos.priv.policy
run_cmd chmod 644 /usr/share/polkit-1/actions/org.msbos.priv.policy

# listas extras: de root, instaladas uma vez (o administrador as edita)
run_cmd install -d -m 0755 -o root -g root /etc/msbos
for f in allowed-units.list protected.list; do
  install_file_once "etc/msbos/${f}" "/etc/msbos/${f}"
  run_cmd chown root:root "/etc/msbos/${f}"
  run_cmd chmod 644 "/etc/msbos/${f}"
done

# trilha das ações privilegiadas (escrita só por root)
run_cmd install -d -m 0750 -o root -g root /var/log/msbos

# contexto SELinux correto nos arquivos novos
if command -v restorecon >/dev/null 2>&1; then
  run_cmd restorecon -R /usr/local/libexec/msbos-priv \
    /usr/share/polkit-1/actions/org.msbos.priv.policy /etc/msbos /var/log/msbos \
    || warn "agent-skill: restorecon falhou (verifique os contextos SELinux)"
fi

# /usr/local/libexec não tem regra de fcontext: o helper novo nasce usr_t e o
# restorecon sozinho NÃO muda. Registra bin_t de forma persistente e reaplica.
if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null || true)" == Enforcing ]]; then
  if command -v semanage >/dev/null 2>&1; then
    run_sh "semanage fcontext -a -t bin_t '/usr/local/libexec/msbos-priv' 2>/dev/null || semanage fcontext -m -t bin_t '/usr/local/libexec/msbos-priv'" \
      || warn "agent-skill: falha ao registrar bin_t no semanage (o helper fica usr_t)"
    run_cmd restorecon -v /usr/local/libexec/msbos-priv \
      || warn "agent-skill: falha ao aplicar bin_t no helper"
  else
    warn "agent-skill: sem semanage (policycoreutils-python-utils); usando chcon — o rótulo bin_t pode voltar a usr_t depois de um restorecon"
    run_cmd chcon -t bin_t /usr/local/libexec/msbos-priv \
      || warn "agent-skill: falha ao aplicar chcon bin_t no helper"
  fi
fi

# sem agente polkit na sessão o pkexec não abre a janela de senha
if command -v pgrep >/dev/null 2>&1 \
   && ! pgrep -u "${TU}" -f 'polkit-kde-authentication-agent' >/dev/null 2>&1; then
  warn "agent-skill: agente polkit-kde não está rodando na sessão de ${TU}"
  warn "  adicione ao ${TU_HOME}/.config/niri/config.kdl (fora do bloco binds):"
  warn "  spawn-at-startup \"/usr/libexec/kf6/polkit-kde-authentication-agent-1\""
fi

# a política foi carregada? (só em modo real)
if [[ ${DRY_RUN} == 0 ]]; then
  pkaction --action-id org.msbos.priv.dnf-install --verbose >/dev/null 2>&1 \
    || warn "agent-skill: o polkit não reconheceu a ação org.msbos.priv.dnf-install (verifique o .policy)"
fi

# ─── 2. Skill em ~/.agents/skills/msbos ─────────────────────────────────
# Arquivos do projeto: sempre atualizados (com backup). Preferências do usuário
# (references/local.md): instalado uma vez e nunca sobrescrito.
for f in SKILL.md \
         references/niri.md references/noctalia.md references/fedora-dnf.md \
         references/propriedade.md references/seguranca.md; do
  install_file "${SKILL_SRC}/${f}" "${SKILL_DST}/${f}"
done
install_file_once "${SKILL_SRC}/references/local.md" "${SKILL_DST}/references/local.md"

# ─── 3. Skill noctalia-plugin (plugins do Noctalia v5 em Luau) ──────────────
# Skill de referência: não tem arquivo pessoal, então todo o conteúdo é
# atualizado (com backup) a cada execução. As referências e os exemplos são
# instalados pela árvore real do repositório, sem lista fixa de arquivos.
[[ -d "${MSBOS_ROOT}/assets/${SKILL_NP_SRC}" ]] \
  || { err "asset ausente no repositório: ${MSBOS_ROOT}/assets/${SKILL_NP_SRC}"; exit 1; }
while IFS= read -r -d '' _f; do
  _rel="${_f#"${MSBOS_ROOT}/assets/${SKILL_NP_SRC}/"}"
  install_file "${SKILL_NP_SRC}/${_rel}" "${SKILL_NP_DST}/${_rel}"
done < <(find "${MSBOS_ROOT}/assets/${SKILL_NP_SRC}" -type f -print0 | sort -z)
unset _f _rel

# o install -D cria diretórios como root: devolve ao usuário-alvo
run_cmd chown "${TU}:${TU_GROUP}" "${TU_HOME}/.agents" "${TU_HOME}/.agents/skills" 2>/dev/null || true
run_cmd chown -R "${TU}:${TU_GROUP}" "${SKILL_DST}" "${SKILL_NP_DST}"
run_cmd runuser -u "${TU}" -- mkdir -p "${TU_HOME}/.local/state/msbos/agent-backups"

ok "agent-skill: helper + polkit + skills (msbos, noctalia-plugin) instalados"
log "agent-skill: teste rápido (como ${TU}): /usr/local/libexec/msbos-priv --dry-run dnf-install htop"
