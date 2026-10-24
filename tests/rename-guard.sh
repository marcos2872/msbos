#!/usr/bin/env bash
# tests/rename-guard.sh — impede que o nome antigo volte ao repositório.
#
# O nome pode aparecer apenas onde é intencional: scripts de migração/detecção,
# notas de release históricas e a documentação do próprio rebranding.
# Roda no CI e no workflow de release.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Caminhos que podem citar os nomes antigos de propósito.
ALLOW_RE='^(scripts/(00-migrate-names|99-cleanup-legacy|40-tuning|50-configs)\.sh|assets/bin/msbos-doctor|tests/rename-guard\.sh|docs/(historico|migracao-msbos)(\.en)?\.md|\.github/release-notes/v[0-9]+\.[0-9]+\.[0-9]+\.md)$'

fail=0

# 1) Nenhum arquivo rastreado pode ter o nome antigo no próprio caminho.
if git ls-files | grep -iE 'omyfedora|myos' >/dev/null 2>&1; then
  echo "erro: caminho com nome antigo no repositório:" >&2
  git ls-files | grep -iE 'omyfedora|myos' >&2 || true
  fail=1
fi

# 2) Conteúdo: só os arquivos da allowlist podem citar os nomes antigos.
while IFS= read -r f; do
  [[ ${f} =~ ${ALLOW_RE} ]] && continue
  case "${f}" in
    *.png|*.jpg|*.jpeg|*.webp|*.ico|*.gif|*.svg|*.pdf) continue ;;
  esac
  # -I ignora binários; -q . evita tentar grep em arquivo vazio.
  if ! grep -Iq . "${f}" 2>/dev/null; then
    continue
  fi
  if grep -nE 'omyfedora|OMYFEDORA|Omyfedora' "${f}" >&2; then
    echo "erro: nome antigo em ${f}" >&2
    fail=1
  fi
  if grep -nE '(^|[^[:alnum:]_])[Mm]y[Oo][Ss]([^[:alnum:]_]|$)|myos-|my-os' "${f}" >&2; then
    echo "erro: nome legado em ${f}" >&2
    fail=1
  fi
done < <(git ls-files)

if ((fail)); then
  echo "rename-guard: falhou — veja os arquivos acima." >&2
  exit 1
fi
echo "rename-guard: OK — nenhum nome antigo fora da allowlist"
