# omyfedora

Distro pessoal baseada em **Fedora KDE** com o compositor **niri** e o shell **Noctalia v5**,
focada em **baixo uso de RAM** e desempenho — com os **apps do KDE mantidos** e o tema dark
padrão do KDE (**Breeze Dark**) nos aplicativos.

A instalação segue a *rota C*: em vez de gerar uma ISO própria, um **script de bootstrap**
transforma um Fedora KDE já instalado no omyfedora — trocando o shell do Plasma pelo niri/Noctalia,
instalando os drivers de GPU e aplicando todas as otimizações de memória.

---

## O que é

| Camada | Escolha |
|---|---|
| Base | Fedora 44/45 KDE Plasma Desktop (ou instalação mínima) |
| Sessão gráfica | **niri** (compositor Wayland com tiling rolável) |
| Shell | **Noctalia v5** — barra, launcher, notificações, OSD e lock screen |
| Login | **greetd** + Noctalia Greeter (substitui o Plasma Login Manager) |
| Tema dos apps | **Breeze Dark** — o dark padrão do KDE (Qt via `kdeglobals` + GTK via dconf); o Noctalia mantém o visual próprio dele |
| Noctalia (defaults) | **Tema Liquid Glass** (inspirado no macOS atual): barra no topo translúcida com itens em texto puro, dock de meia altura com auto-hide, painéis em vidro e paleta própria `macOS` (accent cinza); barra em `control-center workspaces` · `clock` · `media`, com `cpu`/`ram` num grupo cápsula e tray/status no fim; plugins **tmelik/system-monitor** e **raycursive/niri-displays**; wallpaper padrão do omyfedora |
| Terminal | **alacritty** com o tema macOS (cores espelhadas da paleta do Noctalia) e **translúcido com blur** (niri 26.04+) + **zsh com autocomplete** (sugestões inline do histórico, syntax highlight, fzf no Ctrl+R) — `Super+T` |
| Dev | Rust (rustup), Node.js LTS via nvm (npm/pnpm/yarn), gcc/make, GitHub CLI e **virtualização (KVM/libvirt + virt-manager)** |
| Apps | Zed (editor), OpenCode v2 (IA no terminal, configurado com o [agents-config](https://github.com/marcos2872/agents-config)), Brave (navegador padrão), ONLYOFFICE, SSH_Orchestrator (RPM da release oficial), lazydocker (TUI para containers), LocalSend (arquivos na LAN, flatpak) |

Nada do shell do Plasma permanece (os apps KDE ficam): o objetivo é um desktop enxuto
que fica **abaixo de ~600 MB de RAM em idle** (contra ~1,5 GB de um Plasma típico).

## De onde rodar (base)

O script precisa de um **Fedora já instalado** (físico ou VM), x86_64, com internet.
O estável atual é o **Fedora 44** (o 45 entra em breve; os mesmos links servem trocando a versão):

- **Fedora KDE** → o script remove o shell do Plasma/Plasma Login Manager, **mantém os apps
  KDE** (Dolphin, Konsole, Kate/KWrite, Okular, Gwenview, Spectacle…) e adiciona o stack;
- **Instalação mínima** → o script apenas adiciona o que falta (mais enxuto, ideal para a versão final).

### Onde baixar as imagens

| Imagem | Para quê | Onde |
|---|---|---|
| **Fedora KDE** (Live ISO) | base recomendada (já vem com o Plasma, cujo shell o script remove — os apps KDE ficam) | <https://fedoraproject.org/kde/download> |
| **Fedora Everything** (netinstall ISO) | instalação **mínima** — no instalador (Anaconda) escolha **"Minimal Install"** | <https://fedoraproject.org/misc> |

Espelhos diretos (troque `44` pela versão desejada; lista completa em <https://mirrors.fedoraproject.org>):

- KDE: <https://download.fedoraproject.org/pub/fedora/linux/releases/44/KDE/x86_64/iso/>
- Everything (mínimo): <https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/>

> Dica: verifique o checksum das ISOs com os arquivos `-CHECKSUM` (e a assinatura OpenPGP do Fedora)
> antes de instalar.

Para testar numa VM, use a ISO escolhida. **Atenção ao `--video`:** o **niri rejeita
renderização por software** (llvmpipe) — a VM precisa de virtio-gpu **com aceleração 3D**
e GL no Spice, senão a sessão fica em tela preta:

```bash
virt-install --name omyfedora --memory 4096 --vcpus 3 --disk size=25 \
  --cdrom /caminho/Fedora-KDE-Desktop-Live-44.x86_64.iso \
  --os-variant fedora-unknown \
  --graphics spice,gl=on --video virtio,accel3d=yes
```

## Como rodar

```bash
git clone <url-do-repo> omyfedora
cd omyfedora

./install.sh --dry-run   # simula tudo, sem alterar nada (recomendado 1º)
./install.sh             # instala de verdade (pergunta antes de remover o shell do Plasma)
./install.sh --yes       # sem perguntas (VMs descartáveis / CI)
```

| Opção | Efeito |
|---|---|
| `--dry-run` | Simula tudo (não instala, não remove, não escreve) |
| `--yes`, `-y` | Autoriza remoções (shell do Plasma) sem perguntar |
| `--no-greeter` | Não adiciona o repo Terra (usa o greeter padrão do greetd) |
| `--user NOME` | Configura para este usuário (padrão: quem chamou o sudo) |
| `--gpu-profile P` | Força `auto\|intel\|amd\|nvidia\|hybrid\|none` |
| `--skip-remove` | Nunca remove pacotes (só instala e ajusta serviços) |

## O que o script faz (6 etapas)

| Etapa | O que faz |
|---|---|
| `10-gpu.sh` | Detecta GPUs (Intel/AMD/NVIDIA, **híbridos** também) e instala o driver certo: NVIDIA (binário/akmod + `nvidia-drm.modeset=1` + offload GL), AMD/Intel (Mesa + microcódigo) |
| `20-stack.sh` | Instala o núcleo (niri, Noctalia, greetd, PipeWire, portais, fontes) e faz a **curadoria dos apps KDE** (remove jogos/PIM/ajuda; mantém Dolphin, Konsole, Kate/KWrite, Okular, Gwenview, Spectacle, Dragon, Elisa…); garante o **tema Breeze Dark** (integração Qt/GTK do KDE, sem Kvantum); apps do usuário: **Zed** e **OpenCode v2** pelos scripts oficiais (`curl`), **Brave** e **ONLYOFFICE** pelos repos oficiais e **SSH_Orchestrator** pelo RPM da release no GitHub; instala o terminal (**zsh + plugins + fonte JetBrains Mono**) e o **lazydocker**; **agenda** a remoção do shell do Plasma para o próximo boot |
| `25-devtools.sh` | Ferramentas de desenvolvimento: gcc/make, **Rust** (rustup), **Node.js LTS via nvm** (+ npm), **pnpm/yarn** e **virtualização** (grupo `@virtualization`, `libvirtd` no boot e usuário no grupo `libvirt`) — detecta e pula o que já existe |
| `30-services.sh` | greetd assume o boot (Plasma Login Manager mascarado); desativa avahi/cups/sssd/fprintd/etc. (PackageKit/Discover ficam); habilita tuned-ppd, oomd e podman.socket |
| `40-tuning.sh` | **zram** (swap comprimido zstd), sysctl de memória, **btrfs `compress=zstd`**, governor `performance` (só em desktop sem bateria), oomd conservador |
| `50-configs.sh` | Escreve as configs do niri/Noctalia/greetd, instala os wallpapers, aplica os **defaults do Noctalia** (`settings.toml` + plugins, só se ausentes), preenche o **Breeze Dark** (kdeglobals + GTK/dconf — só o que o usuário ainda não escolheu), define **Dolphin/KWrite/Gwenview/Okular/Dragon/Elisa** e o **Brave como navegador padrão**, e instala o tema do **alacritty** + `.zshrc` com autocomplete (zsh vira o shell padrão) |

## Depois de instalar

Reinicie: a tela do greetd aparece com a sessão **niri** já disponível.

| Atalho | Ação |
|---|---|
| `Super+T` / `Super+Shift+T` | Terminal (alacritty) |
| `Super+Space` / `Super+D` | Launcher (Noctalia) |
| `Super+S` | Control center (Noctalia) |
| `Super+B` | Brave |
| `Super+E` | Zed |
| `Super+P` | Gerenciador de monitores (plugin Niri Displays: liga/desliga saídas, resolução, escala, rotação, posição) |
| `Alt+Tab` | Window switcher (Noctalia) |
| `Print` | Screenshot |
| `Super+Shift+E` | Sair do niri |

Verificações úteis:

```bash
systemctl status greetd          # display manager
free -h ; zramctl                # swap comprimido ativo
ps aux --sort=-rss | head -12    # top consumidores de RAM
```

**Wallpapers:** coloque imagens em `~/.config/omyfedora-walls/` (usuário, tem precedência) ou
`/usr/share/omyfedora-walls/` (sistema). O helper `omyfedora-wallpaper` usa a 1ª em ordem alfabética.

## Estrutura do projeto

```
install.sh              # orquestrador (roda as 6 etapas em ordem)
lib/common.sh           # helpers: logs, dry-run, backups, resolução de usuário
scripts/10-gpu.sh       # detecção multi-GPU + drivers
scripts/20-stack.sh     # pacotes do stack + curadoria dos apps KDE + tema Breeze
scripts/25-devtools.sh  # ferramentas de desenvolvimento (Rust, Node/nvm, pnpm/yarn)
scripts/30-services.sh  # serviços systemd (greetd no lugar do plasmalogin)
scripts/40-tuning.sh    # otimizações de memória/desempenho
scripts/50-configs.sh   # configurações (niri, greetd, Noctalia, Breeze, Brave, zsh)
assets/                 # arquivos instalados (configs, wallpapers, helpers)
```

## Observações

- **Nada é parado durante a instalação** — a sessão atual (Plasma) continua funcionando; a
  troca para o greetd/niri vale a partir do próximo boot.
- **A remoção do shell do Plasma é agendada para o próximo boot**
  (`omyfedora-remove-plasma.service`, roda antes do login): remover o desktop em uso derruba a
  sessão (o scriptlet do plasmalogin/plasma-* mexe nos serviços systemd), então a remoção
  nunca acontece dentro da sessão. É só reiniciar após a instalação. Os **apps KDE ficam** —
  inclusive o **plasma-discover**, que segue funcionando com o PackageKit.
- **Flatpak × controle parental**: se o `accountsservice` da sua versão do Fedora expuser a
  interface `com.endlessm.ParentalControls` (build com malcontent) e o pacote `malcontent`
  estiver ausente, todo `flatpak run` falha com `Not allowed to query parental controls data`
  (flatpak/flatpak#6142). Nesse caso o omyfedora instala e protege o `malcontent`; se o daemon não
  tem o suporte (caso do Fedora 44), ele não é necessário e nada é instalado.
- **O tema dos apps é o do KDE**: o omyfedora não instala tema próprio — os apps usam o
  **Breeze Dark** (o dark padrão do KDE; o Fedora KDE de referência roda com ele). O
  instalador só *preenche* chaves ainda vazias do `~/.config/kdeglobals`/`kcminputrc`: trocar
  o tema pelo **System Settings** é para sempre, o omyfedora não regride sua escolha.
- **Configs pessoais são instaladas só uma vez**: `~/.config/niri/config.kdl`,
  `~/.config/noctalia/config.toml`, `~/.config/alacritty/alacritty.toml` e `~/.zshrc` **não
  são sobrescritos** em uma reexecução — sua personalização de atalhos/temas sobrevive.
  Para voltar ao padrão do omyfedora, apague o arquivo e rode `sudo bash scripts/50-configs.sh`.
  (Arquivos que o omyfedora é dono — wallpapers, fallback `/etc/xdg/niri/config.kdl`,
  `settings.toml`/plugins do Noctalia — seguem a mesma regra: só instalam se ausentes.)
  A **paleta do tema** segue outra: o omyfedora é dono dela, então é atualizada com
  backup `.omyfedora-bak` — para customizar, crie outra paleta em
  `~/.config/noctalia/palettes/` e aponte `custom_palette` para ela.
- **Noctalia em duas camadas**: o `~/.config/noctalia/config.toml` carrega o
  **estilo** (tema, barra, dock, painéis) e o `~/.local/state/noctalia/settings.toml`
  carrega o que a **GUI reescreve** (listas de widgets, wallpaper, plugins,
  geometria da lock screen — e o `[dock]` que o próprio dock persiste). O
  `settings.toml` é lido por último e vence chave-a-chave, então um ajuste de
  aparência que "não pega" quase sempre é uma chave repetida nele.
- **Registro de etapas**: cada etapa concluída é marcada em `/var/lib/omyfedora/steps/`. Se uma
  etapa falhar, o instalador mostra o código de erro, até onde chegou e como retomar
  (`sudo ./install.sh` ou só a etapa que falhou) — as etapas são idempotentes.
- **Se o dnf falhar com `checksum doesn't match` ou 404 de `repodata`**: é o **espelho do
  Fedora fora de sincronia** (transitório — aconteceria com qualquer `dnf`, não é do omyfedora).
  Rode `sudo dnf clean all` e o instalador de novo; se persistir por muitos minutos, troque
  de espelho (veja <https://mirrors.fedoraproject.org>).
- **VM com tela preta depois do login?** É GPU sem OpenGL de hardware na VM: o **niri rejeita
  renderização por software** (llvmpipe) por design. A VM precisa de virtio-gpu **com
  aceleração 3D** e GL no Spice. Numa VM já criada (desligada), corrija assim:

  ```bash
  virt-xml --connect qemu:///system NOME_DA_VM --edit --video model.type=virtio,model.acceleration.accel3d=yes
  virt-xml --connect qemu:///system NOME_DA_VM --edit --graphics gl.enable=yes
  ```

  (ou, no virt-manager: Vídeo → modelo **Virtio** + marcar **Aceleração 3D**). Vale para
  qualquer compositor que exija GL — o qxl, muito comum em VMs, nunca funciona com o niri.
  Com o GL ligado ainda podem aparecer **artefatos de tela e/ou o cursor de cabeça para
  baixo** (bugs de driver do QEMU/virgl — qemu#2315): descomente o bloco de VM dentro do
  `debug { }` do `~/.config/niri/config.kdl` (`disable-cursor-plane`,
  `disable-direct-scanout`, `wait-for-frame-completion-before-queueing`) e aplique com
  `niri msg action load-config-file` (ou relogue).
- `noctalia-greeter` vem do repositório **comunitário Terra** (o Fedora oficial ainda não
  o empacota); use `--no-greeter` para evitá-lo.
- Zed e OpenCode são instalados pelos **scripts oficiais** (`zed.dev/install.sh` e
  `opencode.ai/v2/install`) e se auto-atualizam depois.
- **lazydocker**: instalado do repo do Fedora quando disponível; se não estiver, o binário
  vem da release oficial do GitHub **com verificação de sha256** (nunca `curl | bash`).
- Arquivos sobrescritos no sistema ganham backup com sufixo `.omyfedora-bak`.

## Verificação

```bash
# bash -n com vários arquivos só valida o PRIMEIRO (os demais virariam $1, $2...),
# por isso o loop:
for f in install.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/*; do
  bash -n "$f" || exit 1
done
shellcheck -S warning install.sh lib/common.sh scripts/*.sh assets/bin/* assets/libexec/*
./install.sh --dry-run           # simula as 6 etapas sem alterar nada
```

O CI (`.github/workflows/ci.yml`) roda essas três verificações em `fedora:44` a cada
push/PR — inclusive o `--dry-run` completo com um usuário de teste.

## Licença

[MIT](LICENSE) — use, modifique e redistribua como quiser.

