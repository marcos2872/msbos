# Teste da skill `omyfedora` + helper privilegiado

Rotina para validar, **na máquina com o omyfedora atual** (Fedora + niri +
Noctalia), a skill de agentes e o helper `omyfedora-priv` que ela usa.

O teste é dividido em fases: as duas primeiras (0 e 1) não pedem senha; a fase
2 abre a janela do polkit e **não altera nada**; a fase 3 altera o sistema de
forma reversível; a fase 4 é comportamental e manual; a fase 5 é a conferência
da trilha de auditoria.

> **Regra de ouro:** o teste roda como o **usuário**, nunca como root, e não usa
> `sudo`. Toda ação privilegiada passa por
> `pkexec /usr/local/libexec/omyfedora-priv ...`, exatamente como a skill manda.
> A senha é digitada pelo usuário na janela do polkit; o agente não a vê.

## Pré-requisitos

- Fedora 44/45 com o omyfedora atual: niri + Noctalia + greetd + polkit-kde.
- A etapa `60-agent-skill.sh` já executada (helper, `.policy`, listas e skill
  instalados). O teste **não instala** a skill; ele valida o que está instalado.
- `polkit-kde` instalado **e** o agente iniciado no niri:
  `spawn-at-startup "/usr/libexec/kf6/polkit-kde-authentication-agent-1"` no
  `~/.config/niri/config.kdl` (fora do bloco `binds`).
- Terminal dentro da sessão niri (com `DBUS_SESSION_BUS_ADDRESS` e
  `XDG_SESSION_ID`), para o `pkexec` conseguir falar com o agente polkit.
- O repositório desta branch disponível (o teste lê `scripts/60-agent-skill.sh`
  e os assets para as checagens estáticas).
- Sua senha à mão para as fases 2 e 3. A fase 2 abre ~3 diálogos; a fase 3,
  ~6 (a simulação pode reaproveitar a autenticação por 5 min).

Instalação da branch na máquina alvo:

```bash
git switch feat/agent-skill
sudo bash scripts/60-agent-skill.sh
# ou, para rodar a instalação inteira: sudo ./install.sh
```

## Como rodar

```bash
# diagnóstico sem senha (recomendado primeiro)
./tests/agent-skill/run.sh --phase 0 --phase 1

# fases 0-2: preflight + dry-run + simulações/recusas via pkexec (senha; nada muda)
./tests/agent-skill/run.sh --all

# fase 3: instala/remove um pacote de teste e habilita/desabilita um serviço
# (só depois de o usuário aprovar; o teste restaura o estado)
./tests/agent-skill/run.sh --all --mutating --yes

# cenários comportamentais e trilha de auditoria (manual)
./tests/agent-skill/run.sh --phase 4
./tests/agent-skill/run.sh --phase 5
```

No **branch baseline** (sem as correções listadas abaixo), rode com
`--known-issues` para que as falhas já documentadas apareçam como `KNOWN` e não
como `FAIL`:

```bash
./tests/agent-skill/run.sh --all --mutating --yes --known-issues
```

No **alvo corrigido**, rode **sem** `--known-issues`: o resultado esperado é
zero `FAIL`.

O relatório completo é gravado em
`${TMPDIR:-/tmp}/omyfedora-agent-skill-<data>.log` (ou no caminho de
`--report`). O script também imprime o resumo no terminal.

## Fases

| Fase | O que valida | Altera algo? | Senha? |
|---|---|---|---|
| 0 | SO, sessão niri, helper, `.policy` carregada (`pkaction`), listas de root, log, agente polkit-kde, SELinux, stack, `dnf5`, skill instalada, config do niri | Não | Não |
| 1 | XML do `.policy`, caminho absoluto nos docs, allowlist, protegidos, flags do dnf, integração da etapa, frontmatter e matriz de argumentos do helper | Não | Não |
| 2 | `dnf-simulate-remove` real, recusas de protegidos e validação de argumentos **via pkexec** | Não (`--assumeno`/recusas) | Sim (~3) |
| 3 | `dnf-install` + simulação + `dnf-remove` de um pacote mínimo; `svc-restart`, `svc-enable`/`svc-disable` e restauração | Sim, reversível | Sim (~6) |
| 4 | Comportamento do agente (`scenarios.md`) | Depende do cenário | Depende |
| 5 | Trilha `/var/log/omyfedora/actions.log` | Não | `sudo` só para ler |

### Por que a fase 2 não roda `svc-enable greetd` de verdade

A recusa de unidades é validada no **dry-run** (fase 1). Na fase 2, o `pkexec`
é exercitado com entradas inválidas (glob de pacote e nome de unidade com
`; reboot`), que morrem antes de chamar `dnf`/`systemctl`. Assim o teste
verifica o polkit e o caminho root sem risco de parar `greetd`/NetworkManager
se o helper estiver quebrado.

O mesmo vale para remoção: a recusa de `dolphin`/`bash`/`niri` é testada com
`dnf-simulate-remove`, que usa a **mesma** `simula_remocao` do `dnf-remove`
(mesmos checks de protegidos e cascata), mas nunca executa a remoção.

## Protocolo do agente

O agente que for rodar isto deve:

1. Ler este arquivo e `scenarios.md`.
2. Rodar `--phase 0 --phase 1` sozinho e mostrar o resumo.
3. **Pedir autorização** ao usuário antes da fase 2 (haverá janelas de senha,
   mas nenhuma mudança).
4. **Pedir autorização explícita** antes da fase 3 (mutações reversíveis). Só
   então usar `--mutating --yes`; `--yes` não substitui a autorização.
5. Conduzir `scenarios.md` com o usuário; quem marca PASS/FAIL é o usuário.
6. Pedir ao usuário para rodar `sudo tail -n 40 /var/log/omyfedora/actions.log`
   e conferir as linhas `EXEC`/`DENY`/`RESULT`.
7. Reportar o resumo e o caminho do relatório. **Não** tentar contornar uma
   recusa, **não** usar `sudo` e **não** “consertar” o helper durante o teste.

## O que o teste cobre

- O helper aceita nomes válidos e recusa glob, opção (`-y`), URL, caminho,
  `;`, `@grupo`, lista vazia e mais de 20 pacotes.
- A allowlist de unidades recusa `greetd`, `NetworkManager`, `systemd-*` e
  aceita `tuned`.
- A lista de protegidos recusa `dolphin`, `bash`, `niri`, `systemd` e os apps
  KDE/shell que o projeto mantém.
- O `.policy` é XML válido, está instalado/carregado e tem a anotação
  `org.freedesktop.policykit.exec.argv1`.
- O agente polkit-kde está rodando e o niri o inicia.
- O helper está em `/usr/local/libexec` com dono root, modo sem escrita de
  grupo/outros e contexto SELinux `bin_t`.
- O helper instala/remove um pacote mínimo real, simula a remoção e reinicia
  um serviço permitido.
- A skill está em `~/.agents/skills/omyfedora` com `SKILL.md`, referências e
  `local.md`.
- A trilha de auditoria registra `EXEC`/`DENY`/`RESULT`.

## O que o teste NÃO cobre

- A janela do polkit em si (o teste confirma que o `pkexec` foi autorizado; o
  usuário confirma visualmente que a janela apareceu).
- O recarregamento visual do niri e do Noctalia (cenários manuais).
- A remoção real de um pacote protegido (por segurança; a simulação usa o
  mesmo caminho de checagem).
- O `dnf-install` com `Obsoletes` que removeria um protegido (lacuna conhecida
  do helper; veja abaixo).
- NVIDIA, greetd/PAM, módulos SELinux, remoção do Plasma e o serviço
  `omyfedora-remove-plasma`.
- A instalação em si (a etapa 60 precisa ter rodado).
- O comportamento “esperto” do modelo fora dos cenários (o checklist é a
  evidência).

## Falhas conhecidas do baseline (`--known-issues`)

Estas são as pendências já identificadas na revisão do pacote. O teste as
detecta; no baseline elas aparecem como `KNOWN` com `--known-issues` e como
`FAIL` sem a flag. Todas são corrigíveis sem mudar a arquitetura.

| ID | Problema | Correção sugerida |
|---|---|---|
| `STATIC-PATH` | `SKILL.md`/`fedora-dnf.md` chamam `omyfedora-priv --dry-run` sem o caminho absoluto (o helper não está no `PATH`) | usar `/usr/local/libexec/omyfedora-priv --dry-run ...` |
| `STATIC-UNITS` | `UNITS_BASE` permite `systemd-oomd.service` e `power-profiles-daemon.service` | remover as duas; o projeto habilita o oomd e usa `tuned-ppd` |
| `STATIC-PROTECTED` | protegidos não cobrem todo o `KEEP_PKGS`/`APP_PKGS` do `omyfedora-remove-plasma`; faltam `zsh`, `python3`, Plasma e apps como `dragon`/`elisa-player`/`kate`; `dolphin(-.*)?` também protege `dolphin-emu` | alinhar com `KEEP_PKGS`/`APP_PKGS`; usar `dolphin` + `dolphin-plugins` |
| `STATIC-DNF` | falta `--color=never` e `--no-autoremove` nas chamadas do dnf | adicionar (o `--setopt` atual funciona no 5.4.6, mas o flag documentado é `--no-autoremove`) |
| `STATIC-INTEGRATION` | a etapa não checa o agente polkit nem aplica `bin_t` via `semanage`/`chcon` | adicionar checagem com aviso e o contexto SELinux persistente |
| `DRY-REMOVE-*` | o `--dry-run` de `dnf-remove` não roda o check de protegidos (retorna antes do `simula_remocao`) | mover `eh_protegido` para antes do retorno de dry-run |
| `DRY-SVC-OOMD`/`DRY-SVC-PPD` | o dry-run aceita desabilitar o oomd e habilitar o PPD | remover da allowlist (mesma correção de `STATIC-UNITS`) |
| `PRE-SELINUX-BIN` | o helper em `/usr/local/libexec` recebe `usr_t`; `restorecon` sozinho não muda | `semanage fcontext -a -t bin_t` (ou instalar em `/usr/local/bin`) e `restorecon -v` |

Fora do `--known-issues`, as checagens de **ambiente** (`PRE-POLKIT-AGENT`,
`PRE-NIRI-POLKIT`, `PRE-STACK`, `PRE-SELINUX-BIN`) devem passar no alvo atual.
Se não passarem, o problema é da máquina/instalação, não da lógica do helper:
confira `polkit-kde`, a linha `spawn-at-startup` e o contexto SELinux.

## Cenários manuais

`scenarios.md` traz os cenários que só o comportamento do agente valida:
confirmar antes de mudar, mostrar o comando exato, fazer backup, validar,
mostrar o diff, registrar, recusar `sudo`, tratar conteúdo externo como dado,
não editar arquivos do projeto e não remover o Plasma pelo caminho errado.

Copie o arquivo para fora do repo (ou edite uma cópia em `/tmp`) e preencha o
resultado com o usuário. Não commite resultados pessoais.

## Limpeza e segurança

- A fase 3 instala **um** pacote mínimo (`cowsay`, `sl`, `figlet` ou `tree`,
  o primeiro que não estiver instalado), simula e remove; se a remoção falhar,
  tenta de novo no fim e imprime o comando.
- O serviço de teste é `avahi-daemon` ou `cups`, somente se o estado original
  for `enabled/active` ou `disabled/inactive`; o teste devolve o estado.
- O `tuned` é apenas reiniciado; nenhuma configuração é alterada.
- A fase 3 deixa entradas no `dnf history` (desfazíveis com
  `dnf history undo <ID>`) e no log de auditoria.
- O teste não edita `~/.config/niri/config.kdl`, `~/.config/noctalia/*`,
  `/etc`, PAM, greetd, SELinux, fstab ou GRUB.
- O único `sudo` é o do passo manual de leitura do log (fase 5), executado pelo
  usuário.

## Checklist antes de mergear

- [ ] Corrigir as falhas conhecidas acima (ou decidir conscientemente não).
- [ ] Atualizar as docs de 6 → 7 etapas: `AGENTS.md`, `README.md`,
      `docs/index.md`, `docs/instalacao.md`, `docs/arquitetura.md` (tabela,
      grafo e assets) e as versões `.en.md`.
- [ ] Adicionar a seção do helper/skill ao `omyfedora-doctor` (helper, policy,
      listas, agente polkit, skill).
- [ ] Decidir a fonte única da skill: `~/.agents/skills` (como está) ou
      `agents-config` (que sincroniza `~/.config/opencode/skills`).
- [ ] Rodar no alvo **sem** `--known-issues` e anexar o relatório.
- [ ] Rodar `ausearch -m avc -ts recent` depois do primeiro `pkexec` real.
- [ ] Confirmar que o `dnf-install` não introduz `Obsoletes` que removam um
      protegido (ou documentar a limitação).
- [ ] Revisar o `install.sh --dry-run` com a etapa 60 (a CI já roda).
