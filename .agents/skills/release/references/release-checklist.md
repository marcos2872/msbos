# Checklist de release — omyfedora

## Pré-release

- [ ] `main` limpa, sincronizada e com CI verde.
- [ ] Versão definida (`PATCH`/`MINOR`/`MAJOR`) e tag inexistente.
- [ ] Notas em `.github/release-notes/<tag>.md`, em PT-BR, sem as seções de instalação/verificação.
- [ ] `bash -n` em todos os arquivos com shebang shell.
- [ ] `shellcheck -S warning` sem avisos.
- [ ] `./install.sh --dry-run` conclui as 6 etapas.
- [ ] `actionlint` se o workflow mudou.
- [ ] Commit de preparação enviado para `main`.
- [ ] CI do commit exato verde.

## Tag

- [ ] Tag anotada `vX.Y.Z` no HEAD da `main`.
- [ ] Tag enviada com `git push origin <tag>`.
- [ ] Workflow `release` concluiu com sucesso.

## Pós-release

- [ ] Release não-draft, não-prerelease e marcada como **Latest**.
- [ ] Assets: `omyfedora-<tag>.tar.gz` e `SHA256SUMS`.
- [ ] `sha256sum -c SHA256SUMS` passou após o download.
- [ ] Tarball contém `install.sh` e `bootstrap.sh`.
- [ ] Corpo da release tem os destaques + blocos de instalação/verificação.
- [ ] `main` limpa/sincronizada; tag local e remota iguais.
