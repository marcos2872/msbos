---
name: Release do omyfedora
description: Prepara, publica e valida releases do omyfedora (tag anotada vX.Y.Z, notas em .github/release-notes, tarball com SHA256SUMS e GitHub Release). Use ao criar uma nova versão, subir tag, publicar ou republicar uma release, ou conferir uma release publicada.
---

# Release do omyfedora

Este skill define o padrão do projeto para releases. A **tag é a fonte da verdade**: não existe
arquivo `VERSION`. Uma release é uma tag anotada `vX.Y.Z` em `main`; o workflow
`.github/workflows/release.yml` valida o commit, empacota `omyfedora-<tag>.tar.gz` +
`SHA256SUMS` e cria ou atualiza a GitHub Release.

A skill fica em `.agents/skills/release/` (formato Agent Skills) e é compatível com OpenCode e
outros harnesses que leem `.agents/skills`.

## Quando usar

- Criar uma nova versão (`v0.2.0`, `v1.0.0`…).
- Escrever ou revisar as notas de uma release.
- Criar e enviar a tag que dispara o workflow.
- Republicar uma tag existente depois de uma falha.
- Validar se uma release publicada está completa e íntegra.

## Escopo

- Releases **estáveis** no formato `vMAJOR.MINOR.PATCH`.
- Não use sufixo (`-rc`, `-beta`): o workflow atual publica toda tag como estável e `Latest`.
  Para pré-release, ajuste o workflow antes.
- **Nunca** reutilize ou mova uma tag já publicada (`git tag -f`, force-push de tag).
- Notas em português em `.github/release-notes/<tag>.md`; o workflow anexa as seções de
  instalação e verificação automaticamente.

## Versionamento

| Mudança | Incremento |
|---|---|
| Correções, docs, CI ou dependências sem novo comportamento | `PATCH` |
| Nova funcionalidade ou comportamento compatível | `MINOR` |
| Mudança incompatível (requisito, instalação, config, remoção de suporte) | `MAJOR` |

Antes de 1.0, mudanças incompatíveis podem ir em `MINOR`, mas precisam ser destacadas nas notas.
Depois de 1.0, use `MAJOR`.

## 1. Confirmar o estado

```bash
cd /caminho/do/omyfedora
git status --short                    # deve estar vazio
git branch --show-current             # main
git fetch origin
git status -sb                        # sem ahead/behind
gh auth status
gh run list --branch main --limit 1   # último CI deve estar success
```

Pare se houver mudanças não commitadas, branch errada, `main` atrasada ou CI vermelho. Nunca
publique uma release a partir de uma árvore suja. Se estiver atrasada: `git pull --ff-only`.

## 2. Definir a versão

```bash
TAG=v0.2.0
git tag --list "$TAG"                 # deve estar vazio
if gh release view "$TAG" >/dev/null 2>&1; then echo "release já existe"; fi
```

Se a tag ou a release já existir, escolha a próxima versão. Não reaproveite.

## 3. Escrever as notas

Crie `.github/release-notes/${TAG}.md` usando
`references/release-notes-template.md` como base.

- Escreva em PT-BR, focado no que o usuário percebe.
- **Não** inclua as seções de instalação/verificação: o workflow as anexa.
- Destaque breaking changes e passos de migração.
- As notas são lidas **da tag**; editar a `main` depois não altera uma release já publicada.

## 4. Validar localmente

Sintaxe e lint (o host pode não ter `shellcheck`; o container abaixo cobre):

```bash
scripts=()
for f in install.sh bootstrap.sh pessoal-pc.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/*; do
  first="$(head -n1 "$f")"
  case "$first" in
    *bash*|*'/sh'*|*dash*|*ksh*) scripts+=("$f") ;;
  esac
done
for f in "${scripts[@]}"; do bash -n "$f" || exit 1; done
shellcheck -S warning "${scripts[@]}"
```

Sem `shellcheck` no host:

```bash
podman run --rm -v "$PWD:/src:Z" -w /src fedora:44 bash -c '
  dnf -q -y install ShellCheck >/dev/null 2>&1 || exit 1
  scripts=()
  for f in install.sh bootstrap.sh pessoal-pc.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/*; do
    first="$(head -n1 "$f")"
    case "$first" in
      *bash*|*"/sh"*|*dash*|*ksh*) scripts+=("$f") ;;
    esac
  done
  for f in "${scripts[@]}"; do bash -n "$f" || exit 1; done
  shellcheck -S warning "${scripts[@]}"
'
```

Simulação completa (roda as 6 etapas, sem alterar nada):

```bash
./install.sh --dry-run
```

Se o workflow mudou, valide também o YAML:

```bash
podman run --rm -v "$PWD:/src:Z" -w /src docker.io/rhysd/actionlint:latest
```

## 5. Commitar e validar a main

```bash
git add .github/release-notes/${TAG}.md
# inclua .github/workflows/release.yml se ele também mudou
git commit -m "docs(release): adiciona notas da ${TAG}"
git push origin main
```

Aguarde o CI do commit exato:

```bash
SHA=$(git rev-parse HEAD)
RUN=$(gh run list --branch main --limit 20 --json databaseId,headSha \
  --jq "map(select(.headSha == \"$SHA\"))[0].databaseId")
gh run watch "$RUN" --exit-status
```

Se `RUN` vier vazio, espere alguns segundos e repita. Confirme `git status -sb` limpo e
sincronizado.

## 6. Criar e enviar a tag

A tag deve apontar para o HEAD da `main` com CI verde:

```bash
git rev-parse HEAD
git rev-parse origin/main
git tag -a "$TAG" -m "omyfedora $TAG — <resumo curto>"
git show "$TAG" --stat --oneline | head -20
git push origin "$TAG"
```

Nunca crie a tag antes do commit das notas nem depois de um CI vermelho.

## 7. Acompanhar o workflow

```bash
sleep 5
COMMIT=$(git rev-parse "$TAG^{commit}")
RUN=$(gh run list --workflow release --limit 20 --json databaseId,headSha \
  --jq "map(select(.headSha == \"$COMMIT\"))[0].databaseId")
gh run watch "$RUN" --exit-status
```

Se falhar, veja o log e **não mova a tag**:

```bash
gh run view "$RUN" --log-failed
```

## 8. Validar a release publicada

```bash
gh release view "$TAG" --json url,tagName,name,isDraft,isPrerelease,assets \
  --jq '{url, tagName, name, isDraft, isPrerelease, assets: [.assets[].name]}'
gh release list --limit 3             # release estável deve aparecer como Latest
gh release view "$TAG" --json body --jq .body | head -40
```

Baixe e confira os assets:

```bash
tmp=$(mktemp -d)
gh release download "$TAG" --dir "$tmp"
(cd "$tmp" && sha256sum -c SHA256SUMS)
tar -tzf "$tmp/omyfedora-$TAG.tar.gz" | grep -E '/(install.sh|bootstrap.sh)$'
rm -rf "$tmp"
```

Esperado:

- release não-draft, não-prerelease e marcada como **Latest**;
- exatamente dois assets: `omyfedora-<tag>.tar.gz` e `SHA256SUMS`;
- checksum OK e tarball com `install.sh` e `bootstrap.sh`;
- corpo com os destaques + blocos de instalação/verificação.

## 9. Republicar ou corrigir

Se a tag existe e o workflow falhou/parcial:

```bash
gh workflow run release --ref main -f tag="$TAG"
sleep 5
RUN=$(gh run list --workflow release --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

O workflow existente reenvia os assets com `--clobber`, mas **não reescreve o corpo**. Para
corrigir só as notas, edite o corpo da release preservando os blocos de instalação/verificação:

```bash
gh release edit "$TAG" --notes-file /caminho/notas-completas.md
```

Se o **código** estiver errado, publique uma nova `PATCH`; não reutilize a tag. Apagar release e
tag só é permitido com aprovação explícita do usuário:

```bash
gh release delete "$TAG" --yes
git push origin --delete "$TAG"
git tag -d "$TAG"
```

## 10. Fechamento

- `main` limpa e sincronizada; tag local e remota iguais.
- Não edite a tag publicada.
- Correções depois da release viram uma nova `PATCH`.
- Se houver mudança de comportamento, atualize a documentação em um commit/PR separado.

## Limitações atuais

- O workflow trata toda tag `v*.*.*` como release estável e `Latest`; não use `-rc`/`-beta`
  sem antes ajustar o workflow.
- As notas são um snapshot da tag. Republicar via `workflow_dispatch` usa as notas da tag, não
  da `main`.
- O `GITHUB_TOKEN` do job de publicação precisa de `contents: write`; o workflow já declara essa
  permissão no job `publicar`.

## Referências

- `references/release-notes-template.md` — esqueleto das notas.
- `references/release-checklist.md` — checklist de pré-release, tag e pós-release.
