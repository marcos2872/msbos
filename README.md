# MyOS

Distro pessoal baseada em **Fedora** com o compositor **niri** e o shell **Noctalia v5**,
focada em **baixo uso de RAM** e desempenho.

A instalação segue a *rota C*: em vez de gerar uma ISO própria, um **script de bootstrap**
transforma um Fedora já instalado no MyOS — instalando o stack, os drivers de GPU e
todas as otimizações de memória.

---

## O que é

| Camada | Escolha |
|---|---|
| Base | Fedora 44/45 (Workstation ou instalação mínima) |
| Sessão gráfica | **niri** (compositor Wayland com tiling rolável) |
| Shell | **Noctalia v5** — barra, launcher, notificações, OSD e lock screen |
| Login | **greetd** + Noctalia Greeter (substitui o GDM) |
| Terminal | alacritty + **zsh com autocomplete** (sugestões inline do histórico, syntax highlight, fzf no Ctrl+R) — `Super+T` |
| Dev | Rust (rustup), Node.js LTS via nvm (npm/pnpm/yarn), gcc/make |
| Apps | Zed (editor), OpenCode v2 (IA no terminal, configurado com o [agents-config](https://github.com/marcos2872/agents-config)), Brave (navegador padrão), ONLYOFFICE, SSH_Orchestrator (RPM da release oficial), lazydocker (TUI para containers) |

Nada do GNOME/GDM permanece: o objetivo é um desktop enxuto que fica **abaixo de ~600 MB
de RAM em idle** (contra ~1,5 GB de um GNOME típico).

## De onde rodar (base)

O script precisa de um **Fedora já instalado** (físico ou VM), x86_64, com internet.
O estável atual é o **Fedora 44** (o 45 entra em breve; os mesmos links servem trocando a versão):

- **Fedora Workstation** → o script remove GDM/GNOME e adiciona o stack (mais fácil para testar);
- **Instalação mínima** → o script apenas adiciona o que falta (mais enxuto, ideal para a versão final).

### Onde baixar as imagens

| Imagem | Para quê | Onde |
|---|---|---|
| **Fedora Workstation** (Live ISO) | base recomendada para testar (já vem com GNOME, que o script remove) | <https://fedoraproject.org/workstation/download> |
| **Fedora Everything** (netinstall ISO) | instalação **mínima** — no instalador (Anaconda) escolha **"Minimal Install"** | <https://fedoraproject.org/misc> |

Espelhos diretos (troque `44` pela versão desejada; lista completa em <https://mirrors.fedoraproject.org>):

- Workstation: <https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/>
- Everything (mínimo): <https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/>

> Dica: verifique o checksum das ISOs com os arquivos `-CHECKSUM` (e a assinatura OpenPGP do Fedora)
> antes de instalar.

Para testar numa VM, use a ISO escolhida:

```bash
virt-install --name myos --memory 4096 --vcpus 3 --disk size=25 \
  --cdrom /caminho/Fedora-Workstation-Live-x86_64-44.iso \
  --os-variant fedora-unknown --graphics spice
```

## Como rodar

```bash
git clone <url-do-repo> my-os
cd my-os

./install.sh --dry-run   # simula tudo, sem alterar nada (recomendado 1º)
./install.sh             # instala de verdade (pergunta antes de remover GDM/GNOME)
./install.sh --yes       # sem perguntas (VMs descartáveis / CI)
```

| Opção | Efeito |
|---|---|
| `--dry-run` | Simula tudo (não instala, não remove, não escreve) |
| `--yes`, `-y` | Autoriza remoções (GDM/GNOME) sem perguntar |
| `--no-greeter` | Não adiciona o repo Terra (usa o greeter padrão do greetd) |
| `--user NOME` | Configura para este usuário (padrão: quem chamou o sudo) |
| `--gpu-profile P` | Força `auto\|intel\|amd\|nvidia\|hybrid\|none` |
| `--skip-remove` | Nunca remove pacotes (só instala e ajusta serviços) |

## O que o script faz (6 etapas)

| Etapa | O que faz |
|---|---|
| `10-gpu.sh` | Detecta GPUs (Intel/AMD/NVIDIA, **híbridos** também) e instala o driver certo: NVIDIA (binário/akmod + `nvidia-drm.modeset=1` + offload GL), AMD/Intel (Mesa + microcódigo) |
| `20-stack.sh` | Instala o núcleo (niri, Noctalia, greetd, PipeWire, portais, fontes) e os apps: **Zed** e **OpenCode v2** pelos scripts oficiais (`curl`), **Brave** e **ONLYOFFICE** pelos repos oficiais e **SSH_Orchestrator** pelo RPM da release no GitHub; instala o terminal (**zsh + plugins + fonte JetBrains Mono**) e o **lazydocker**; **agenda** a remoção do GDM/GNOME para o próximo boot |
| `25-devtools.sh` | Ferramentas de desenvolvimento: gcc/make, **Rust** (rustup), **Node.js LTS via nvm** (+ npm) e **pnpm/yarn** — detecta e pula o que já existe |
| `30-services.sh` | greetd assume o boot (GDM mascarado); desativa avahi/cups/sssd/fprintd/etc.; habilita zram, oomd, tuned e power-profiles-daemon |
| `40-tuning.sh` | **zram** (swap comprimido zstd), sysctl de memória, **btrfs `compress=zstd`**, governor `performance` (só em desktop sem bateria), oomd conservador |
| `50-configs.sh` | Escreve as configs do niri/Noctalia/greetd, instala os wallpapers, aplica o **agents-config** no OpenCode (agentes/skills/commands), define o **Brave como navegador padrão** e instala o tema do **alacritty** + `.zshrc` com autocomplete (zsh vira o shell padrão) |

## Depois de instalar

Reinicie: a tela do greetd aparece com a sessão **niri** já disponível.

| Atalho | Ação |
|---|---|
| `Super+T` | Terminal (alacritty) |
| `Super+Space` / `Super+D` | Launcher (Noctalia) |
| `Super+S` | Control center (Noctalia) |
| `Super+B` | Brave |
| `Super+E` | Zed |
| `Alt+Tab` | Window switcher (Noctalia) |
| `Print` | Screenshot |
| `Super+Shift+E` | Sair do niri |

Verificações úteis:

```bash
systemctl status greetd          # display manager
free -h ; zramctl                # swap comprimido ativo
ps aux --sort=-rss | head -12    # top consumidores de RAM
```

**Wallpapers:** coloque imagens em `~/.config/myos-walls/` (usuário, tem precedência) ou
`/usr/share/myos-walls/` (sistema). O helper `myos-wallpaper` usa a 1ª em ordem alfabética.

## Estrutura do projeto

```
install.sh              # orquestrador (roda as 6 etapas em ordem)
lib/common.sh           # helpers: logs, dry-run, backups, resolução de usuário
scripts/10-gpu.sh       # detecção multi-GPU + drivers
scripts/20-stack.sh     # pacotes do stack + aplicativos
scripts/25-devtools.sh  # ferramentas de desenvolvimento (Rust, Node/nvm, pnpm/yarn)
scripts/30-services.sh  # serviços systemd
scripts/40-tuning.sh    # otimizações de memória/desempenho
scripts/50-configs.sh   # configurações (niri, greetd, Noctalia, Brave, alacritty, zsh)
assets/                 # arquivos instalados (configs, wallpapers, helpers)
```

## Observações

- **Nada é parado durante a instalação** — a sessão atual continua funcionando; a troca
  para o greetd/niri vale a partir do próximo boot.
- **A remoção do GDM/GNOME é agendada para o próximo boot**
  (`myos-remove-gnome.service`, roda antes do login): remover o desktop em uso derruba a
  sessão (o scriptlet do gdm executa `systemctl disable --now gdm.service`), então a
  remoção nunca acontece dentro da sessão. É só reiniciar após a instalação.
- `noctalia-greeter` vem do repositório **comunitário Terra** (o Fedora oficial ainda não
  o empacota); use `--no-greeter` para evitá-lo.
- Zed e OpenCode são instalados pelos **scripts oficiais** (`zed.dev/install.sh` e
  `opencode.ai/v2/install`) e se auto-atualizam depois.
- Arquivos sobrescritos no sistema ganham backup com sufixo `.myos-bak`.
