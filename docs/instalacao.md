# Instalação

[Português](instalacao.md) · [English](instalacao.en.md)

O omyfedora é instalado **sobre um Fedora já existente** (rota C): não há ISO própria. O
`install.sh` roda seis etapas idempotentes, instala os pacotes, configura os serviços e
aplica os ajustes. A troca do shell do Plasma pelo niri/Noctalia só vale depois do reboot.

## Antes de começar

- **Fedora 44 ou 45**, x86_64, já instalado e com a rede funcionando.
- Acesso a `sudo` e o usuário que vai receber a configuração (padrão: quem chamou o sudo).
- Espaço em disco e tempo proporcionais à quantidade de pacotes (a primeira instalação baixa
  bastante coisa; as etapas seguintes são incrementais).
- Faça backup do que importa. O instalador cria backups `.omyfedora-bak` dos arquivos que
  sobrescreve, mas isso não substitui um backup seu.

A base recomendada é o **Fedora KDE**: o script remove apenas o *shell* do Plasma (desktop,
workspace e Plasma Login Manager) e **mantém os apps do KDE**. Uma instalação **mínima** do
Fedora também funciona e gera um sistema ainda mais enxuto; nesse caso o script adiciona o
stack e os apps KDE que faltarem.

## Escolha a base

| Imagem | Para quê | Onde baixar |
|---|---|---|
| **Fedora KDE** (Live ISO) | Base recomendada; já traz os apps KDE | <https://fedoraproject.org/kde/download> |
| **Fedora Everything** (netinstall) | Instalação mínima — escolha **“Minimal Install”** no Anaconda | <https://fedoraproject.org/misc> |

Espelhos diretos (troque `44` pela versão desejada; a lista completa está em
<https://mirrors.fedoraproject.org>):

- KDE: <https://download.fedoraproject.org/pub/fedora/linux/releases/44/KDE/x86_64/iso/>
- Everything: <https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/>

Confira o checksum com os arquivos `-CHECKSUM` e, se possível, a assinatura OpenPGP do
Fedora antes de instalar.

## Testar em uma VM

O **niri rejeita renderização por software** (llvmpipe) por design. Uma VM precisa de
**virtio-gpu com aceleração 3D** e **GL no Spice**; sem isso a sessão fica em tela preta.
O `qxl`, muito comum em VMs, não funciona com o niri.

```bash
virt-install --name omyfedora --memory 4096 --vcpus 3 --disk size=25 \
  --cdrom /caminho/Fedora-KDE-Desktop-Live-44.x86_64.iso \
  --os-variant fedora-unknown \
  --graphics spice,gl=on --video virtio,accel3d=yes
```

Se a VM já existe, veja [VM com tela preta](solucao-de-problemas.md#vm-com-tela-preta-ou-cursor-invertido)
para corrigir vídeo/GL e os contornos de artefatos do QEMU.

## Instalar sem clonar o repositório

O `bootstrap.sh` baixa o repositório como `.tar.gz`, extrai em um diretório temporário e
chama o `install.sh`. Não precisa de `git`.

Salve o bootstrap em um arquivo antes de executar: assim os prompts interativos do
`install.sh` continuam lendo o terminal.

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh -o /tmp/omyfedora.sh

sudo bash /tmp/omyfedora.sh --dry-run   # simula tudo (recomendado na 1ª vez)
sudo bash /tmp/omyfedora.sh             # instala de verdade
```

Para fixar uma branch, tag ou commit:

```bash
sudo env OMYFEDORA_REF=SEU_TAG_OU_COMMIT bash /tmp/omyfedora.sh --yes
```

Instalação não interativa (VM descartável/CI):

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh \
  | sudo bash -s -- --yes
```

Variáveis aceitas pelo bootstrap:

| Variável | Padrão | Efeito |
|---|---|---|
| `OMYFEDORA_REF` | `main` | Branch, tag ou commit a baixar |
| `OMYFEDORA_REPO` | `marcos2872/omyfedora` | Repositório alternativo (`owner/repo`) |
| `OMYFEDORA_URL` | — | URL completa do `.tar.gz`; sobrepõe `REPO`/`REF` |
| `OMYFEDORA_KEEP` | `0` | `1` mantém o diretório temporário para depuração |

O bootstrap aceita todas as opções do `install.sh` e repassa os argumentos.

## Instalar com clone (desenvolvimento)

```bash
git clone https://github.com/marcos2872/omyfedora.git
cd omyfedora

./install.sh --dry-run   # simula tudo, sem alterar nada
./install.sh             # instala de verdade
```

Ao rodar sem root e sem `--dry-run`, o `install.sh` se reexecuta com `sudo`, preservando as
variáveis da instalação.

## Opções do `install.sh`

| Opção | Efeito |
|---|---|
| `--dry-run` | Simula tudo: não instala, não remove, não escreve e não acessa a rede |
| `--yes`, `-y` | Autoriza operações destrutivas (remoção do shell do Plasma) sem perguntar |
| `--no-greeter` | Não adiciona o repositório Terra; usa o greeter padrão do greetd |
| `--user NOME` | Usuário-alvo da configuração (padrão: quem chamou o sudo) |
| `--gpu-profile P` | Força `auto`, `intel`, `amd`, `nvidia`, `hybrid` ou `none` |
| `--skip-remove` | Nunca remove pacotes; apenas instala e ajusta serviços |
| `-h`, `--help` | Mostra a ajuda extraída do cabeçalho do `install.sh` |

As mesmas opções valem para o bootstrap, por exemplo
`sudo bash /tmp/omyfedora.sh --gpu-profile nvidia`.

## O que acontece durante a instalação

O `install.sh` descobre `scripts/[0-9][0-9]-*.sh` em ordem e executa:

| Etapa | Resumo |
|---|---|
| `10-gpu.sh` | Detecta Intel/AMD/NVIDIA (inclusive híbridos) e instala o driver adequado |
| `20-stack.sh` | Instala niri, Noctalia, greetd, áudio, utilitários, apps e agenda a remoção do shell do Plasma |
| `25-devtools.sh` | gcc/make, Rust, Node via nvm, pnpm/yarn e virtualização (KVM/libvirt) |
| `30-services.sh` | Coloca o greetd no boot, mascara outros DMs e desativa daemons dispensáveis |
| `40-tuning.sh` | zram, sysctl de memória, compressão btrfs, governor e oomd |
| `50-configs.sh` | Configura niri, Noctalia, Breeze Dark, greetd/PAM, wallpapers, Zed, zsh e apps padrão |

Detalhes de cada etapa: [Arquitetura e etapas](arquitetura.md).

**Nada é parado na sessão atual.** O Plasma continua funcionando até o reboot; a remoção do
shell do Plasma é agendada para o próximo boot, antes do login, via
`omyfedora-remove-plasma.service`. Isso evita derrubar a sessão no meio da transação do dnf.

Cada etapa concluída deixa um marcador em `/var/lib/omyfedora/steps/`. Se uma etapa falhar,
o instalador mostra o código de erro, o histórico e como retomar.

## Anaconda/Kickstart

**Não execute o `install.sh` diretamente no `%post`.** O `%post` roda no chroot do sistema
instalado, sem systemd como PID 1, e o omyfedora precisa de um sistema já inicializado
(`systemctl daemon-reload`, `runuser`, dconf/gsettings). O caminho certo é rodar o bootstrap
depois do primeiro boot — ou usar o `%post` apenas para instalar um serviço de primeiro boot
que execute o bootstrap.

## Depois de instalar

Reinicie:

```bash
sudo reboot
```

No próximo boot, a tela do **greetd** deve aparecer com a sessão **niri** disponível. Se o
Noctalia Greeter estiver instalado, ele usa o wallpaper sincronizado pelo Noctalia.

Verificações úteis no sistema instalado:

```bash
systemctl status greetd          # display manager
journalctl -u greetd -n 30       # log do login
free -h ; zramctl                # swap comprimido ativo
ps aux --sort=-rss | head -12    # maiores consumidores de RAM
```

O shell padrão passa a ser o **zsh**; o grupo `libvirt` só vale no próximo login. Para
sincronizar a aparência com a tela de login depois de entrar:

```bash
noctalia msg greeter-sync
```

Wallpapers, atalhos, apps padrão e personalização: [Uso diário](uso.md).

## Reexecutar ou retomar

As etapas são idempotentes; rodar de novo é seguro:

```bash
sudo ./install.sh              # tudo, desde o início
sudo bash scripts/50-configs.sh  # só uma etapa
DRY_RUN=1 bash scripts/40-tuning.sh  # simular uma etapa sem root
```

O histórico fica em:

```bash
ls /var/lib/omyfedora/steps/
```

Para restaurar um arquivo sobrescrito, procure o backup `.omyfedora-bak` ao lado do original.
Configurações pessoais instaladas com `install_file_once` não são sobrescritas em uma
reexecução; para voltar ao padrão, apague o arquivo e rode a etapa correspondente.

## Próximos passos

- [Uso diário](uso.md) — atalhos, Noctalia, tema e configs.
- [Arquitetura e etapas](arquitetura.md) — como o instalador funciona por dentro.
- [Solução de problemas](solucao-de-problemas.md) — se algo falhar.
