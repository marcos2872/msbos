<p align="center">
  <img src="assets/branding/omyfedora-logo.png" alt="Logo do omyfedora" width="120" height="120">
  &nbsp;&nbsp;&nbsp;
  <img src="assets/branding/omyfedora-mascot.png" alt="Mascote do omyfedora" width="120" height="120">
</p>

<h1 align="center">omyfedora</h1>

<p align="center">
  <strong>Uma personalização pessoal do Fedora KDE com niri + Noctalia v5.</strong><br>
  <a href="README.en.md">English</a> ·
  <a href="docs/index.md">Documentação</a> ·
  <a href="docs/solucao-de-problemas.md">Solução de problemas</a>
</p>

O **omyfedora** não é uma distro nem uma ISO própria: é um conjunto de scripts bash
idempotentes que transforma um **Fedora 44/45 já instalado** num desktop enxuto. A
instalação segue a **rota C**: em vez de gerar uma ISO, um script de bootstrap troca o shell
do Plasma pelo **niri** (compositor Wayland) e pelo **Noctalia v5**, instala o driver de GPU
e aplica os ajustes de memória e desempenho. Os **apps do KDE continuam** e o tema dos
aplicativos segue o **Breeze Dark**, o dark padrão do KDE.

O objetivo é um desktop de uso pessoal que fique **abaixo de ~600 MB de RAM em idle**
(contra ~1,5 GB de um Plasma típico), sem abrir mão dos apps do dia a dia.

> **Obrigado a quem torna isso possível.** O omyfedora é só a cola pessoal entre projetos
> excelentes: o [Fedora Project](https://fedoraproject.org) e a
> [comunidade KDE](https://kde.org) fornecem a base e os aplicativos; o
> [niri](https://github.com/YaLTeR/niri), de **YaLTeR**, oferece o compositor; o
> [Noctalia](https://noctalia.dev) traz o shell e o greeter; e o
> [greetd](https://github.com/kennylevinsen/greetd), de **Kenny Levinsen**, cuida do login.
> Obrigado também a todos os projetos upstream citados nos
> [créditos completos](docs/creditos.md). O omyfedora é um projeto pessoal, sem afiliação
> com Fedora, KDE, niri ou Noctalia.

## O que é

| Camada | Escolha |
|---|---|
| Base | Fedora 44/45 KDE Plasma Desktop (ou instalação mínima) |
| Sessão gráfica | **niri** — compositor Wayland com tiling rolável |
| Shell | **Noctalia v5** — barra, launcher, notificações, OSD e lock screen |
| Login | **greetd** + Noctalia Greeter (substitui o Plasma Login Manager) |
| Apps | Apps do **KDE** mantidos + Zed, Brave, ONLYOFFICE, LocalSend, lazydocker… |
| Tema dos apps | **Breeze Dark** (Qt via `kdeglobals`, GTK via dconf/`settings.ini`) |
| Terminal | **alacritty** translúcido com blur + **zsh** com autocomplete |
| Dev | Rust (rustup), Node LTS via nvm, gcc/make, GitHub CLI, KVM/libvirt |

## Requisitos

- Fedora **44 ou 45** já instalado, **x86_64**, com internet e acesso a `sudo`.
- Base recomendada: **Fedora KDE** (o script remove o shell do Plasma e mantém os apps KDE).
- Alternativa mais enxuta: instalação **mínima** do Fedora (o script adiciona o restante).
- Em VM, é preciso **virtio-gpu com aceleração 3D** e GL no Spice — o niri rejeita
  renderização por software. Veja [VM e GPU](docs/instalacao.md#testar-em-uma-vm).

## Instalação (básico)

Sem clonar o repositório:

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh -o /tmp/omyfedora.sh

sudo bash /tmp/omyfedora.sh --dry-run   # simula tudo (recomendado na 1ª vez)
sudo bash /tmp/omyfedora.sh             # instala de verdade
sudo reboot
```

Ou com clone (para desenvolvimento):

```bash
git clone https://github.com/marcos2872/omyfedora.git
cd omyfedora

./install.sh --dry-run   # simula tudo, sem alterar nada
./install.sh             # instala (pergunta antes de remover o shell do Plasma)
sudo reboot
```

O instalador avisa antes de agendar a remoção do shell do Plasma; nada é parado na sessão
atual. A troca para o greetd/niri vale no **próximo boot**. **Não** rode o `install.sh` no
`%post` do Anaconda — veja [instalação](docs/instalacao.md).

Depois de reiniciar, a sessão **niri** aparece na tela do greetd. Atalhos básicos:
`Super+T` terminal · `Super+Space` launcher · `Super+S` control center · `Super+P` monitores.

## Documentação

| Documento | Conteúdo |
|---|---|
| [Instalação](docs/instalacao.md) | Base, ISOs, VM, bootstrap, opções, Anaconda e primeiros passos |
| [Uso diário](docs/uso.md) | Atalhos do niri/Noctalia, wallpapers, apps padrão, tema e configs pessoais |
| [Arquitetura e etapas](docs/arquitetura.md) | Fluxo dos scripts, as 6 etapas, `lib/common.sh`, assets e verificação |
| [Solução de problemas](docs/solucao-de-problemas.md) | dnf, VM/GPU, flatpak, Noctalia, greeter e recuperação |
| [Créditos](docs/creditos.md) | Projetos e pessoas que tornam o omyfedora possível |
| [Índice](docs/index.md) | Ponto de entrada de toda a documentação |

Toda a documentação tem versão em inglês com sufixo `.en.md` (por exemplo,
[README.en.md](README.en.md) e [docs/index.en.md](docs/index.en.md)).

## Licença

[MIT](LICENSE) — use, modifique e redistribua como quiser.
