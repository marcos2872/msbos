# Análise de estabilidade e consistência — omyfedora

Repositório analisado: <https://github.com/marcos2872/omyfedora>
Data da análise: 21/10/2026

---

## 1. Escopo e limitações

**Lido por completo ou em parte:**

- `README.md`
- `docs/arquitetura.md`
- `install.sh` (121 linhas)
- `scripts/20-stack.sh` (colado por você, código real)

**Não lido** (o que digo sobre eles vem só da documentação e está marcado como *verificar no código*):

- `bootstrap.sh`
- `lib/common.sh`
- `scripts/10-gpu.sh`, `25-devtools.sh`, `30-services.sh`, `40-tuning.sh`, `50-configs.sh`
- `assets/libexec/omyfedora-remove-plasma` e `assets/omyfedora-remove-plasma.service` (**o mais importante dos pendentes**, ver seção 6)
- `assets/yum.repos.d/terra.repo`
- `.github/workflows/ci.yml`

Nada aqui foi executado. É revisão estática, sem teste em VM.

---

## 2. Resumo executivo

O projeto é bem construído para um bootstrap pessoal: idempotente, com dry-run, backups, proteção de configs pessoais e remoção do Plasma adiada para o boot. Os riscos reais estão concentrados em quatro áreas:

| # | Área | Risco | Prioridade |
|---|------|-------|------------|
| 1 | Tuning de memória (zram com piso de 16 GiB) | Thrashing em máquinas com pouca RAM | Alta |
| 2 | Remoção do Plasma + troca de login sem rollback | Ficar sem login gráfico | Alta |
| 3 | Proteção dos apps KDE durante a remoção | Apps quebrados ou removidos em cascata | Alta |
| 4 | Código e pacotes externos sem versão/checksum | Cadeia de suprimentos, reprodutibilidade | Alta |

Em seguida vêm os conflitos de configuração (tuned × governor), a ausência de migração das configs, e a falta de validação real no CI.

---

## 3. Pontos fortes (manter)

- **Idempotência real**: detecção com `rpm -q`, `command -v` e existência de arquivos antes de agir.
- **`--dry-run` completo**, inclusive sem rede (ex.: `install_lazydocker_verified` retorna cedo em dry-run).
- **Remoção do Plasma agendada para o boot**, evitando derrubar a sessão no meio da transação dnf.
- **`install_file_once`** para configs pessoais: reexecutar não apaga atalhos nem temas.
- **Backups `.omyfedora-bak`** que nunca sobrescrevem o primeiro backup.
- **lazydocker com sha256** verificado contra o `checksums.txt` da mesma release, com checagem de formato do hash e falha segura (não instala se não bater).
- **Tentativa dupla no núcleo**: limpa o cache do dnf e repete uma vez quando o espelho está fora de sincronia.
- **Instaladores `curl | sh` rodam como usuário**, via `runuser`, e não como root.
- **Atenção a SELinux e PAM** (`pam_selinux` no `/etc/pam.d/greetd`, `xdm_var_lib_t`, módulo `dontaudit`).
- **Cuidado com o `malcontent`/flatpak** (seção 9 do `20-stack.sh`): detalhe raro e bem tratado.
- **Reconstrução do KSycoca** ao final, que resolve o "Abrir com" vazio do Dolphin.
- **CI** com `bash -n`, shellcheck e dry-run.

---

## 4. Achados detalhados

Legenda: **[código]** = confirmado no código lido; **[doc]** = baseado só na documentação, verificar.

### 4.1 Prioridade alta

#### A1. zram com piso de 16 GiB [doc — verificar `40-tuning.sh`]

A documentação descreve `max(ram * 0.75, 16384)`. Com `max`, uma máquina de 4 GB (o próprio README sugere VM de 4 GB) recebe zram de 16 GiB, quatro vezes a RAM. Com compressão de 2 a 3x, quase toda a RAM pode acabar ocupada por páginas comprimidas antes de o kernel começar a recusar, e o resultado é thrashing. Isso contradiz o objetivo de baixo uso de RAM. A intenção parece ter sido `min(...)`, com teto, e não piso.

**Correção sugerida** (`/etc/systemd/zram-generator.conf`):

```ini
[zram0]
zram-size = min(ram * 0.5, 8192)
compression-algorithm = zstd
```

Ajuste conforme o hardware-alvo. O padrão do Fedora é `min(ram, 8192)`. Valide sempre com `zramctl` e `swapon --show` depois do reboot.

**Nota relacionada:** `vm.swappiness=60` é conservador para quem usa zram. Valores de 100 a 180 são comuns nesse cenário. Meça antes de mudar.

#### A2. Sem caminho de recuperação se o niri/greetd não subir [doc]

O instalador mascara `plasmalogin`/`gdm`/`sddm`, habilita o `greetd` e agenda a remoção do shell do Plasma. Se a GPU não inicializa, o akmod da NVIDIA não compilou, o PAM está errado ou o greeter do Terra falha, o usuário fica sem login gráfico e já sem Plasma.

**Correções sugeridas:**

1. Só agendar a remoção do Plasma depois de uma verificação pós-boot (por exemplo, o niri ter iniciado uma sessão com sucesso uma vez). Pode ser um marcador gravado pelo autostart do niri.
2. Criar um comando de rollback (`omyfedora-rescue`) que:
   - desmascara `plasmalogin`/`sddm`;
   - desabilita o `greetd`;
   - reinstala o mínimo do shell se necessário.
3. Documentar em `docs/solucao-de-problemas.md` a recuperação por TTY (`Ctrl+Alt+F3`), com os comandos exatos.

#### A3. Proteção do dnf movida temporariamente [doc — verificar `omyfedora-remove-plasma`]

A documentação diz que o serviço "move temporariamente a proteção do dnf" (o arquivo de `protected.d` que impede remover o `plasma-desktop`). Se o script morrer entre mover e restaurar (queda de energia, erro, sinal), o sistema fica sem proteção.

**Verificar no código:**

- Existe `trap '...restaurar...' EXIT INT TERM`?
- A restauração ocorre mesmo em falha do dnf?
- A transação de remoção é refeita com simulação antes (ver B1 abaixo)?

Alternativa mais segura: **não mover o arquivo**. Usar `dnf remove --setopt=protected_packages=` ou o equivalente no dnf5 para a transação isolada, sem tocar no disco.

#### A4. Cadeia de suprimentos e reprodutibilidade [código + doc]

Pontos confirmados no `20-stack.sh`:

| Origem | Problema |
|--------|----------|
| `bootstrap.sh` baixa `main` | Sem tag, sem checksum; roda como root código de uma branch móvel [doc] |
| Zed (`curl -fsSL https://zed.dev/install.sh \| sh`) | Sem versão fixa, sem verificação |
| OpenCode (`curl ... opencode.ai/v2/install \| bash`) | Idem; a "versão mais recente" vem de um endpoint de API não verificado |
| `agents-config` + `sync.sh` (etapa 50) | Clona e executa script de outro repositório [doc — verificar commit fixo] |
| SSH_Orchestrator | RPM da última release do GitHub instalado por URL, **sem checksum e sem verificação de assinatura** |
| ONLYOFFICE | `dnf -y install https://download.onlyoffice.com/repo/.../onlyoffice-repo.noarch.rpm` instala um RPM de repo por URL sem conferir assinatura |
| Brave | Repo oficial por `.repo`: aceitável, mas sem fixar chave |
| Terra | Repo comunitário de terceiros via `terra.repo`: **conferir `gpgcheck=1`, `priority` e `includepkgs=noctalia-greeter`**, para que não sobrescreva pacotes do Fedora |
| nvm / rustup | "Última release" sem versão fixa [doc] |

Também: `ln -sf ~/.local/bin/zed /usr/local/bin/zed` cria symlink pendente se o Zed falhou na instalação.

**Correções sugeridas:**

1. Criar **tags de release** e fazer o `bootstrap.sh` baixar por tag (com sha256 publicado junto na release).
2. Para binários e RPMs de releases (SSH_Orchestrator, lazydocker): reutilizar o padrão `install_lazydocker_verified`. Já é bom; vale transformá-lo numa função genérica em `lib/common.sh`:
   `install_verified_release <url-base> <regex-asset> <checksums> <destino>`.
3. Para repos de terceiros, no `terra.repo`:

   ```ini
   [terra]
   ...
   gpgcheck=1
   repo_gpgcheck=1
   priority=200
   includepkgs=noctalia-greeter*
   ```

   (ajuste os nomes conforme o repo real; `includepkgs` é o que impede que o Terra substitua pacotes do Fedora.)
4. Para scripts `curl | sh`: baixar para arquivo temporário, registrar o sha256 no log e rodar. Não evita o risco, mas dá rastreabilidade. Onde houver release versionada (nvm, rustup), fixar a versão.
5. Para o `agents-config`: fixar um commit (`git checkout <sha>`) em vez de seguir a branch padrão.
6. Remover o symlink se o binário de destino não existir:

   ```bash
   [[ -x ${TU_HOME}/.local/bin/zed ]] && run_cmd ln -sf ... || warn "Zed ausente: symlink não criado"
   ```

#### A5. Regra Polkit do sync do greeter [doc — verificar `50-configs.sh` e assets]

"Habilita o sync sem prompt via Polkit" é superfície de escalada de privilégio.

**Verificar:**

- A regra autoriza **uma ação específica** (`org.freedesktop.policykit.exec` com `annotate` do caminho exato) e apenas para o grupo/usuário-alvo?
- O helper chamado via `pkexec` fica em local só gravável por root?
- Ele não aceita argumentos que alterem o destino de escrita?

---

### 4.2 Proteção dos apps KDE na remoção do Plasma

Aqui há achados confirmados no código (`20-stack.sh`).

#### B1. Falta simular antes de agendar a remoção [código]

A seção 8 monta `REMOVE_PKGS` e chama `exige_ok`, mas **nunca simula** a transação. Se algo na lista de apps depender do `plasma-workspace`, o dnf o remove junto e ninguém percebe até depois do reboot.

**Correção sugerida** (adicionar antes do `exige_ok`, e repetir a mesma simulação no `libexec/omyfedora-remove-plasma` imediatamente antes de remover):

```bash
# Pacotes que NÃO podem sair junto com o shell do Plasma
KEEP=(
  dolphin konsole kwrite okular gwenview ark spectacle kcalc
  plasma-integration plasma-breeze kde-cli-tools pam-kwallet
  polkit-kde redhat-menus breeze-icon-theme breeze-cursor-theme
  kio-extras kio-admin
)

preflight_remocao() {
  local sim p conflitos=()
  sim="$(dnf remove --assumeno "${REMOVE_PKGS[@]}" 2>&1 || true)"
  for p in "${KEEP[@]}"; do
    rpm -q "${p}" >/dev/null 2>&1 || continue
    grep -Eq "^[[:space:]]*${p}[[:space:]]" <<<"${sim}" && conflitos+=("${p}")
  done
  if ((${#conflitos[@]})); then
    warn "a remoção do Plasma levaria junto: ${conflitos[*]} — remoção NÃO agendada"
    return 1
  fi
}
```

Teste o `grep` uma vez com a saída real do dnf5 (o formato da tabela pode variar). Só agende o serviço se `preflight_remocao` passar.

#### B2. `dnf mark user` protege menos do que o comentário afirma [código]

`dnf mark user` impede só a remoção como **dependência órfã** (autoremove). Não impede que o dnf remova um pacote que **exige** o `plasma-workspace`. Se algum app exigir algo do workspace, ele sai junto, mesmo marcado.

Candidatos a verificar via simulação: `plasma-systemsettings`, `kinfocenter`, `plasma-systemmonitor`, `kde-connect`, `krfb`, `spectacle`, `plasma-discover`. Não afirmo que algum dependa; só a simulação (B1) responde.

#### B3. Descompasso entre comentário e código na marcação [código]

O comentário da seção 2c diz que `plasma-integration`, `plasma-breeze`, `breeze-gtk-common`, `pam-kwallet`, `kde-cli-tools` e `dconf` ficam marcados como user-installed. O array `KDE_INSTALADOS` só reúne `KDE_APPS` e `redhat-menus`.

O `dnf install` de um pacote já instalado **como dependência** não garante promovê-lo a user-installed. Esses pacotes, e os do `CORE` (`polkit-kde`, `breeze-icon-theme`, `breeze-cursor-theme`), são os primeiros candidatos a sumir na cascata.

**Correção:**

```bash
SUPORTE=(
  plasma-integration plasma-breeze breeze-gtk-common pam-kwallet
  kde-cli-tools dconf polkit-kde breeze-icon-theme breeze-cursor-theme
  redhat-menus kio-extras kio-admin kdegraphics-thumbnailers ffmpegthumbs
)
for p in "${KDE_APPS[@]}" "${SUPORTE[@]}"; do
  rpm -q "${p}" >/dev/null 2>&1 && KDE_INSTALADOS+=("${p}")
done
```

Para descobrir o pacote dono de uma função em vez de adivinhar o nome: `rpm -qf "$(command -v kwalletd6)"`.

#### B4. Pacotes de suporte não aparecem em nenhuma lista [código]

O Dolphin e o KWrite dependem de componentes que vieram como dependência do Plasma e não estão em `CORE`, `KDE_APPS` nem na marcação:

| Pacote | Efeito se faltar |
|--------|------------------|
| `kio-extras` | Dolphin sem vários protocolos (SFTP, MTP, thumbnails) |
| `kio-admin` | "Editar como administrador" no KWrite/Dolphin |
| `kdegraphics-thumbnailers`, `ffmpegthumbs` | Sem miniaturas |
| pacote do `kwalletd6` | Sem cofre; apps pedem senha toda hora |
| `kglobalacceld`, `kded6` (via kf6) | Atalhos globais e serviços D-Bus |

Com `install_weak_deps=0`, o que era dependência fraca **não volta** depois de removido. Confirme os nomes reais no Fedora 44/45 com `dnf repoquery`.

#### B5. Nomes de pacotes possivelmente desatualizados [código]

Suspeitos na lista `KDE_APPS`: `kwalletmanager5`, `kde-connect`, `elisa-player`, `kjournald`, `kamoso`, `kfind`. Como a falha vira só `warn ... ignorado`, o app simplesmente **não é instalado e não entra na marcação**, sem ninguém notar.

**Correção:** acumular os ignorados num array e imprimir um resumo no final:

```bash
FALHAS=()
for p in "${KDE_APPS[@]}"; do
  run_cmd dnf -y "${DNFOPT}" install "${p}" || { warn "kde: '${p}' indisponível"; FALHAS+=("${p}"); }
done
((${#FALHAS[@]})) && warn "pacotes KDE não instalados: ${FALHAS[*]}"
```

#### B6. Ordem: curadoria antes da marcação [código]

A seção 2b remove apps (cascata `clean_requirements_on_remove`) **antes** de 2c marcar os apps garantidos como user-installed. Risco baixo (as dependências compartilhadas com o Dolphin continuam necessárias), mas a ordem segura é marcar **antes** de remover qualquer coisa.

#### B7. Discover [código]

O comentário diz que o `plasma-discover` "segue funcionando", mas ele não está em nenhuma lista de proteção nem no preflight. Declare-o em `KEEP` e marque-o, ou remova a afirmação.

#### B8. Instalações um pacote por vez [código]

Há dezenas de chamadas `dnf install` individuais (loops sobre `UTILS`, `KDE_APPS`, `TERM_PKGS`...). Consequências: lentidão (resolução de dependências repetida), perda de atomicidade e resultado que depende da ordem.

**Alternativa:** instalar em lote com `--skip-unavailable` (dnf5) e tratar as falhas depois:

```bash
run_cmd dnf -y "${DNFOPT}" install --skip-unavailable "${KDE_APPS[@]}"
```

Perde o `warn` por pacote, mas ganha velocidade e uma transação única. Compare com `rpm -q` depois para listar o que faltou.

---

### 4.3 Prioridade média

#### M1. tuned, governor e perfis de energia com duas fontes de verdade [doc]

O projeto fixa o governor `performance` no boot (desktops sem bateria), usa o perfil `latency-performance` do tuned e instala o `tuned-ppd` (que expõe a API de perfis). O tuned gerencia o governor; quem vence depende da ordem de execução. A troca de perfil pelo control center (Super+S) pode ser sobrescrita sem aviso. O perfil `performance` + `latency-performance` também aumenta consumo e temperatura em idle.

**Correção:** escolher **um** controlador (o tuned) e remover o ajuste manual do governor. Se quiser perfil fixo no boot, usar `tuned-adm profile ...`.

#### M2. `vm.min_free_kbytes` = RAM/64 [doc]

Bem acima do padrão do kernel. Em 16 GB reserva cerca de 256 MB; em 64 GB, cerca de 1 GB. Contradiz o objetivo de economizar RAM. Meça o benefício antes de manter, ou reduza (por exemplo, RAM/256 com piso e teto).

#### M3. Configs "uma vez" nunca migram [código + doc]

`install_file_once` protege o usuário, mas melhorias futuras no `config.kdl` do niri e no `config.toml` do Noctalia **nunca chegam** a quem já instalou. Como niri e Noctalia v5 evoluem rápido, a sintaxe pode mudar e a config antiga quebrar depois de um `dnf upgrade`. O fallback em `/etc/xdg/niri/config.kdl` é sobrescrito, o que cria divergência entre os dois.

**Correção sugerida:**

- Gravar uma versão na config (`// omyfedora-config-version: N`).
- Criar `omyfedora-migrate`, que mostre o diff entre a config do usuário e a nova e aplique só com confirmação.
- Rodar `niri validate` (se disponível) como verificação após o upgrade.

#### M4. O CI não valida o que mais falha [doc]

O dry-run em container não acessa a rede, então não confirma que os pacotes existem (`niri`, `noctalia`, `jemalloc`, `kwalletmanager5` etc.) nem que os repos respondem. O CI só testa Fedora 44; o README promete 44 e 45.

**Correção sugerida:**

1. Job que roda `dnf install --assumeno` (ou `dnf repoquery`) com **todas as listas** de pacotes de `CORE`, `UTILS`, `KDE_APPS` etc. Pega pacote renomeado antes do usuário.
2. Matriz `fedora:44` e `fedora:45` (ou marcar 45 como experimental).
3. Teste periódico em VM (virt-install, com virtio-gpu 3D) que sobe o greetd e o niri e captura o log. Mesmo semanal já ajuda.

#### M5. `install_weak_deps=0` em tudo [código]

Reduz o tamanho, mas remove dependências recomendadas (codecs, plugins de apps KDE, fontes, integrações de portal). Falhas sutis e difíceis de diagnosticar. Mantenha uma lista explícita de "recomendados que importam" e instale-os.

#### M6. NVIDIA [doc]

A documentação cita `nvidia` e `akmod-nvidia`, mas não vi onde o **RPM Fusion** é habilitado (**verificar `10-gpu.sh`**). O akmod precisa recompilar a cada kernel novo e depende da assinatura para Secure Boot; se falhar, o niri não sobe.

**Correção:** antes de pedir o reboot, verificar `modinfo nvidia` e `akmods --force`, com aviso claro se Secure Boot estiver ativo sem chave enrolada.

#### M7. Estado das etapas é só auditoria [código]

`/var/lib/omyfedora/steps/<etapa>` é gravado mas nunca consultado. Toda execução refaz tudo, incluindo downloads. É coerente com idempotência, mas vale gravar também a versão/commit do omyfedora no arquivo, para saber de qual versão veio o estado.

#### M8. Sem atualização automática [doc]

Decisão consciente (dnf-automatic desativado), mas como niri e Noctalia saem da Terra/Fedora em ritmo rápido, o usuário pode ficar meses sem atualizações de segurança. Considere ao menos um aviso (notificação) quando houver atualizações pendentes há mais de N dias.

---

### 4.4 Prioridade baixa e melhorias gerais

- **Log persistente:** `tee` da instalação para `/var/log/omyfedora/install.log`.
- **Lock:** `flock` para impedir duas instalações simultâneas.
- **`oomd` em duas etapas:** a etapa 30 habilita e a 40 configura. Funciona, mas junte a responsabilidade num só lugar.
- **KWallet como Secret Service** via D-Bus sob demanda: solução esperta, mas frágil com login automático ou sem senha (a carteira não destrava). Documente a limitação.
- **Remoções:** documente como reverter (`dnf history undo`, ou reinstalar os grupos).
- **`pessoal-pc.sh` na raiz:** mover para `examples/`.
- **Nomenclatura:** a descrição do repo diz "distro pessoal", o README diz "não é uma distro". Alinhar.
- **Meta de "< 600 MB em idle" não é medida:** criar um `omyfedora-doctor` que reporte RAM em idle, serviços ativos, estado de zram/tuned/SELinux e pacotes protegidos.
- **Opção `--skip-remove`:** pacote instalado e sem uso **não consome RAM**. Só processos em execução consomem. Como o niri não inicia o `plasmashell`, a economia vem de não rodar o Plasma, não de desinstalá-lo. Remover traz ganho de disco (cerca de 1 GB) e menu menos poluído, mas é a parte de maior risco do projeto. Considere tornar **`--skip-remove` o padrão**, com a remoção como opt-in (`--remove-plasma`).
- **Re-pull do Plasma por upgrade:** um `dnf upgrade` futuro pode reinstalar pacotes do Plasma se um app novo passar a exigi-los. Documente a verificação (`rpm -q plasma-workspace`).

---

## 5. Plano de implementação sugerido

Ordem recomendada, do maior retorno em estabilidade ao menor:

### Fase 1 — Evitar dano (alta prioridade)

- [ ] **A1** Corrigir a fórmula do zram (`min` em vez de `max`) e validar com `zramctl`.
- [ ] **B1** Adicionar `preflight_remocao` (simulação com `--assumeno`) no `20-stack.sh` **e** no script de boot.
- [ ] **B3 / B4** Marcar como `user` também `SUPORTE` e `CORE`; incluir `kio-extras`, `kio-admin`, thumbnailers, polkit-kde.
- [ ] **B6** Mover a marcação para **antes** da curadoria.
- [ ] **A3** Garantir `trap` que restaura a proteção do dnf (ou eliminar a necessidade de movê-la).
- [ ] **A2** Criar `omyfedora-rescue` e documentar a recuperação por TTY.

### Fase 2 — Reprodutibilidade e segurança

- [ ] **A4** Criar tags de release; fazer o `bootstrap.sh` baixar por tag + sha256.
- [ ] **A4** Generalizar `install_lazydocker_verified` para `lib/common.sh` e usar no SSH_Orchestrator.
- [ ] **A4** Endurecer o `terra.repo` (`gpgcheck`, `priority`, `includepkgs`).
- [ ] **A4** Fixar versões de nvm/rustup e commit do `agents-config`.
- [ ] **A5** Revisar a regra Polkit e o helper do sync.

### Fase 3 — Consistência

- [ ] **B5** Resumo de pacotes ignorados; corrigir nomes (`kwalletmanager`, etc.).
- [ ] **B7** Decidir sobre o Discover (proteger ou retirar a afirmação).
- [ ] **B8** Instalar em lote com `--skip-unavailable`.
- [ ] **M1** Unificar tuned/governor.
- [ ] **M2** Reavaliar `vm.min_free_kbytes`.
- [ ] **M3** Versão de config + `omyfedora-migrate`.
- [ ] **M5** Lista de weak deps que importam.
- [ ] **M6** Verificação do akmod/Secure Boot antes do reboot.

### Fase 4 — Qualidade e observabilidade

- [ ] **M4** Job de CI que valida todos os pacotes (`dnf install --assumeno`); matriz F44/F45.
- [ ] **M4** Teste periódico em VM.
- [ ] Log persistente, `flock`, `omyfedora-doctor`.
- [ ] Avaliar `--skip-remove` como padrão.

---

## 6. O que ler a seguir (para fechar a análise)

Em ordem de importância:

1. `assets/libexec/omyfedora-remove-plasma` e `assets/omyfedora-remove-plasma.service` — decidem se o sistema fica estável após a remoção. Verificar: `trap`, restauração do `protected.d`, simulação prévia, lista do que é marcado, e comportamento em falha parcial.
2. `scripts/40-tuning.sh` — confirmar a fórmula do zram, `swappiness`, `min_free_kbytes`, governor e perfil do tuned.
3. `scripts/30-services.sh` — ordem entre mascarar o login antigo e habilitar o greetd; criação do usuário `greeter`; SELinux.
4. `scripts/10-gpu.sh` — RPM Fusion, akmod, `grubby`, tratamento de Secure Boot.
5. `lib/common.sh` — `exige_ok`, `install_file`, `run_cmd` (tratamento de erro e `set -e` dentro de funções).
6. `assets/yum.repos.d/terra.repo` e a regra Polkit.
7. `.github/workflows/ci.yml` — confirmar o que o dry-run de fato valida.

---

## 7. Roteiro de validação pós-instalação

Rodar no primeiro login em sessão niri, depois do reboot que executou a remoção:

```bash
# 1. A remoção do Plasma rodou sem erro?
journalctl -u omyfedora-remove-plasma -b --no-pager | tail -50
dnf history list | head

# 2. Pacotes de suporte ainda instalados e marcados como user?
for p in plasma-integration plasma-breeze kde-cli-tools pam-kwallet polkit-kde \
         redhat-menus kio-extras kio-admin breeze-icon-theme; do
  rpm -q "$p" >/dev/null 2>&1 && echo "ok   $p" || echo "FALTA $p"
done
dnf repoquery --userinstalled | grep -E 'plasma-integration|kde-cli-tools|kio-extras'

# 3. Dependências quebradas ou bibliotecas faltando?
rpm -Va --nofiles --nodigest
for b in dolphin kwrite okular gwenview konsole spectacle; do
  command -v "$b" >/dev/null && ldd "$(command -v $b)" | grep 'not found' && echo "FALTA lib em $b"
done

# 4. Serviços essenciais
systemctl is-active greetd tuned systemd-oomd
swapon --show
zramctl
free -h

# 5. SELinux sem negações recentes
sudo ausearch -m avc -ts boot 2>/dev/null | tail -20
```

**Checklist manual (no niri):**

- [ ] Abrir um PDF no Okular e uma imagem no Gwenview.
- [ ] "Abrir com..." no Dolphin lista aplicativos.
- [ ] Miniaturas de imagens e vídeos aparecem no Dolphin.
- [ ] Montar e desmontar um pendrive pelo Dolphin.
- [ ] Salvar um arquivo de sistema como administrador no KWrite (polkit).
- [ ] Tema escuro consistente em apps Qt e GTK; diálogos de arquivo com o visual Breeze.
- [ ] Notificações aparecem; ícones de bandeja funcionam (KDE Connect, se instalado).
- [ ] Cofre (KWallet) destrava no login e o Brave/Zed encontram o Secret Service.
- [ ] `flatpak run org.localsend.localsend_app` abre.
- [ ] Sleep/resume e troca de perfil de energia (Super+S) funcionam.
- [ ] RAM em idle medida (`free -h` após 5 minutos) comparada à meta de ~600 MB.

**Rollback, se algo falhar:**

```bash
dnf history list
sudo dnf history undo <ID>     # desfaz a transação de remoção
```

---

## 8. Observação final

Se a prioridade é **estabilidade**, o caminho de menor risco é: manter o Plasma instalado (`--skip-remove`), garantir só a troca de login para o greetd e continuar usando os apps KDE com todas as dependências. Se o objetivo é **disco e menu limpos**, a remoção é viável, mas só com as correções da Fase 1 (simulação, marcação completa, `trap` e rollback).
