# Uso diário

[Português](uso.md) · [English](uso.en.md)

Depois do reboot, o **greetd** apresenta a sessão **niri**. O Noctalia v5 desenha a barra, o
launcher, as notificações, o OSD e a tela de bloqueio; os apps do KDE continuam disponíveis e
usam o **Breeze Dark**.

## Atalhos

Os atalhos abaixo são os padrões instalados em `~/.config/niri/config.kdl`. Se você editar o
arquivo, suas escolhas são preservadas nas reexecuções do instalador.

### Noctalia e apps

| Atalho | Ação |
|---|---|
| `Super+Space` ou `Super+D` | Launcher do Noctalia |
| `Super+S` | Control center |
| `Super+Shift+Comma` | Configurações do Noctalia |
| `Super+P` | Gerenciador de monitores (plugin Niri Displays) |
| `Alt+Tab` | Window switcher (segura para navegar) |
| `Super+Alt+L` | Bloquear a sessão |
| `Super+T` / `Super+Shift+T` | Terminal (alacritty) |
| `Super+B` | Brave |
| `Super+E` | Zed |
| `Print` | Screenshot (interface do niri) |
| `Ctrl+Print` | Screenshot da tela inteira |
| `Alt+Print` | Screenshot da janela em foco |

### Janelas e colunas (niri)

| Atalho | Ação |
|---|---|
| `Super+O` | Overview |
| `Super+Q` | Fechar a janela |
| `Super+Setas` ou `Super+H/J/K/L` | Focar coluna/janela |
| `Super+Ctrl+Setas` ou `Super+Ctrl+H/J/K/L` | Mover coluna/janela |
| `Super+Shift+Setas` ou `Super+Shift+H/J/K/L` | Focar o monitor vizinho |
| `Super+Shift+Ctrl+Setas` ou `Super+Shift+Ctrl+H/J/K/L` | Mover a coluna para outro monitor |
| `Super+R` / `Super+Shift+R` | Alternar largura predefinida da coluna (para frente/para trás) |
| `Super+Ctrl+Shift+R` | Alternar altura predefinida da janela |
| `Super+Ctrl+R` | Resetar a altura da janela |
| `Super+Minus` / `Super+Equal` | Diminuir/aumentar a largura da coluna |
| `Super+Shift+Minus` / `Super+Shift+Equal` | Diminuir/aumentar a altura da janela |
| `Super+F` | Maximizar a coluna |
| `Super+Shift+F` | Tela cheia |
| `Super+M` | Maximizar a janela até as bordas |
| `Super+Ctrl+F` | Expandir a coluna até a largura disponível |
| `Super+C` / `Super+Ctrl+C` | Centralizar a coluna / as colunas visíveis |
| `Super+V` | Alternar janela flutuante |
| `Super+Shift+V` | Alternar o foco entre flutuantes e tiling |
| `Super+W` | Alternar a coluna para abas |
| `Super+Comma` / `Super+Period` | Consumir a janela na coluna / expulsar da coluna |
| `Super+BracketLeft` / `Super+BracketRight` | Consumir ou expulsar para a esquerda/direita |
| `Super+Shift+Slash` | Overlay de atalhos |
| `Super+Shift+P` | Desligar os monitores |
| `Super+Shift+E` ou `Ctrl+Alt+Delete` | Sair do niri |
| `Super+Escape` | Inibir atalhos do compositor |

### Áreas de trabalho

| Atalho | Ação |
|---|---|
| `Super+1`…`Super+9` | Ir para a área de trabalho 1…9 |
| `Super+Ctrl+1`…`Super+Ctrl+9` | Mover a coluna para a área 1…9 |
| `Super+U` / `Super+I` ou `Super+Page_Down` / `Super+Page_Up` | Área de trabalho abaixo/acima |
| `Super+Ctrl+U` / `Super+Ctrl+I` | Mover a coluna para a área abaixo/acima |
| `Super+Shift+U` / `Super+Shift+I` | Mover a área de trabalho abaixo/acima |
| `Super+Home` / `Super+End` | Primeira/última coluna |
| `Super+Ctrl+Home` / `Super+Ctrl+End` | Mover a coluna para a primeira/última posição |

O restante (scroll do mouse com `Super`, redimensionamento, etc.) segue os defaults do niri.
A referência completa do compositor está em <https://github.com/YaLTeR/niri/wiki>.

## Noctalia v5

O Noctalia é o shell do desktop: barra, launcher, notificações, OSD, control center, lock
screen e wallpaper. O visual padrão é o **Liquid Glass** com a paleta `macOS`: barra no topo
translúcida, dock de meia altura com auto-hide, painéis em vidro e animações mais rápidas.

### As duas camadas de configuração

O Noctalia v5 monta a configuração em camadas. No omyfedora há duas que importam:

| Camada | Arquivo | O que contém | Quem escreve |
|---|---|---|---|
| Estilo | `~/.config/noctalia/config.toml` | Tema, paleta, barra, dock, painéis, animações | omyfedora (instalado uma vez; você pode editar) |
| Estado/GUI | `~/.local/state/noctalia/settings.toml` | Listas de widgets, wallpaper, plugins, geometria da lock screen, `[dock]` persistido | A GUI do Noctalia |

O `settings.toml` é lido **por último** e vence chave a chave. Por isso, se uma mudança de
aparência “não pega”, quase sempre existe uma chave repetida nele. O `config.toml` guarda o
estilo; o `settings.toml` guarda o que a GUI reescreve. Evite editar o `settings.toml` à mão.

Arquivos complementares em `~/.config/noctalia/`:

- `90-greeter-sync.toml` — liga o Auto-Sync da aparência com a tela de login (o omyfedora
  atualiza este arquivo).
- `91-widget-control-center.toml` — ícone do control center na barra (renderizado com o home
  do usuário).
- `palettes/macOS.json` — paleta do tema. O omyfedora é dono dela e a atualiza com backup
  `.omyfedora-bak`; para usar outra, crie uma paleta nova em `palettes/` e aponte
  `custom_palette` no `config.toml`.

Plugins instalados por padrão: **tmelik/system-monitor** (CPU/RAM) e
**raycursive/niri-displays** (monitores). Plugins de comunidade ficam em
`~/.local/state/noctalia/plugins/`; plugins locais ficam em
`~/.local/share/noctalia/plugins/`. O instalador só copia um plugin se ele ainda não existir.

### Wallpaper

O **Noctalia é o dono do wallpaper**. O padrão é
`/usr/share/omyfedora-walls/wp11280214-rx7-4k-wallpapers.jpg`, configurado no
`settings.toml`. Troque pelo próprio Noctalia (Configurações → Wallpaper) — a escolha é
persistida e o Auto-Sync a leva para a tela de login.

O helper `omyfedora-wallpaper` é um **fallback** para sessões sem Noctalia: ele usa `swaybg`
e procura a primeira imagem em ordem alfabética em:

1. `~/.config/omyfedora-walls/` (usuário, tem precedência)
2. `/usr/share/omyfedora-walls/` (sistema)

Formatos aceitos: PNG, JPG/JPEG e WebP. Sem imagens, ele usa a cor sólida `#0B0B0D`. O
`spawn-at-startup` do helper está comentado no `config.kdl` justamente porque o Noctalia já
cuida do wallpaper.

## Tema dos apps: Breeze Dark

O omyfedora não instala um tema próprio. Os apps usam o **Breeze Dark**, o dark padrão do
KDE, e o Noctalia mantém o visual dele (não é Qt/GTK).

- **Qt/KDE**: `~/.config/kdeglobals` recebe `ColorScheme=BreezeDark`, `widgetStyle=Breeze`,
  ícones `breeze-dark` e cursor `breeze_cursors`; o `plasma-integration` fornece o platform
  theme Qt via `QT_QPA_PLATFORMTHEME=kde`.
- **GTK**: `~/.config/gtk-3.0/settings.ini` e `gtk-4.0/settings.ini`, o padrão de sistema em
  `/etc/dconf/db/local.d/00-omyfedora-dark` e o `gsettings` do usuário deixam
  `gtk-theme=Breeze`, `color-scheme=prefer-dark`, `icon-theme=breeze-dark` e cursor
  `breeze_cursors`.
- **Compatibilidade**: o `pam-kwallet` destrava o cofre KWallet no login e o
  `org.freedesktop.secrets` é ativado sob demanda no D-Bus (apps Electron/Tauri também leem
  credenciais); o `xdg-desktop-portal-kde` e o `polkit-kde` continuam instalados para os apps
  KDE.

O instalador só **preenche chaves ainda vazias**. Se você trocar o tema pelo **System
Settings**, essa escolha é sua para sempre: o omyfedora não regride. Os arquivos de tema que
o projeto controla (GTK, dconf, `profile.d`) são atualizados com backup.

## Apps padrão

O instalador define, para o usuário-alvo:

| Tipo | App |
|---|---|
| Navegador (http/https) | Brave |
| Gerenciador de arquivos | Dolphin |
| Editor de texto | KWrite |
| Imagens | Gwenview |
| PDF | Okular |
| Vídeo | Dragon Player |
| Áudio | Elisa |

Para trocar, use as configurações do KDE ou `xdg-settings`/`xdg-mime`. O instalador define
esses padrões e os reaplica quando você roda a etapa `50-configs.sh` (ou o `install.sh`) de
novo.

## Configurações pessoais

Estes arquivos são instalados **somente se ainda não existirem** (`install_file_once`):

- `~/.config/niri/config.kdl`
- `~/.config/noctalia/config.toml`
- `~/.config/alacritty/alacritty.toml`
- `~/.zshrc`
- `~/.config/zed/settings.json` e demais arquivos de `assets/zed/`
- `~/.face` (avatar padrão)
- `~/.config/autostart/sealertauto.desktop` e `org.kde.xwaylandvideobridge.desktop`

Uma reexecução do instalador não sobrescreve esses arquivos. Para voltar ao padrão do
omyfedora, apague o arquivo e rode a etapa responsável:

```bash
rm ~/.config/niri/config.kdl
sudo bash scripts/50-configs.sh
```

Já os arquivos que o omyfedora controla — `/etc/xdg/niri/config.kdl`, os assets de tema,
wallpapers, helpers, `90-greeter-sync.toml`, `91-widget-control-center.toml` e a paleta — são
atualizados com backup `.omyfedora-bak`. O `settings.toml` e os plugins só são instalados se
ausentes.

## Tela de login (greetd + Noctalia Greeter)

O `greetd` substitui o Plasma Login Manager. O **Noctalia Greeter** vem do repositório
comunitário **Terra**; com `--no-greeter`, o greetd usa o greeter padrão em texto e o
Noctalia continua sendo o shell da sessão.

O `90-greeter-sync.toml` liga o **Auto-Sync**: mudanças de wallpaper, paleta, tema e fonte são
copiadas para a tela de login. O instalador habilita o sync sem prompt com uma regra Polkit
restrita à ação do greeter. Numa **reinstalação** (com o Noctalia já rodando), ele dispara um
**Sync Now** no fim; numa **instalação limpa**, o autostart `omyfedora-greeter-sync` faz o
primeiro sync no login e grava o marcador `~/.local/state/omyfedora/greeter-sync.done`.

Para repetir manualmente:

```bash
noctalia msg greeter-sync
```

Se o wallpaper não aparecer no login, confira
`/var/lib/noctalia-greeter/sync.toml` e o shell da sessão em `/etc/shells` (o `pkexec` exige
o shell listado). Mais detalhes em
[Solução de problemas](solucao-de-problemas.md#wallpaper-nao-aparece-na-tela-de-login).

## Remoção do shell do Plasma

No Fedora KDE, o instalador **agenda** a remoção do shell do Plasma para o próximo boot,
antes do login, via `omyfedora-remove-plasma.service`. A remoção não acontece na sessão viva
porque os scriptlets do plasmalogin/plasma-* mexem nos serviços systemd e derrubariam a
sessão no meio da transação do dnf.

O que sai: `plasma-desktop`, `plasma-workspace`, `plasma-login-manager`, `plasma-setup` e
`plasma-welcome`. O que fica: **todos os apps KDE** (Dolphin, Konsole, Kate/KWrite, Okular,
Gwenview, Spectacle, Dragon, Elisa, plasma-discover…) e os pacotes que mantêm o visual e os
portais do KDE funcionando (`plasma-integration`, `plasma-breeze`, `plasma-systemsettings`,
`polkit-kde`, `xdg-desktop-portal-kde`, `pam-kwallet`, `kde-gtk-config`, `konsole`).

Para acompanhar:

```bash
systemctl status omyfedora-remove-plasma
journalctl -u omyfedora-remove-plasma -n 50
```

Se a remoção falhar (por exemplo, sem rede no boot), o serviço continua habilitado e tenta de
novo no próximo boot. Com `--skip-remove`, o shell do Plasma permanece instalado, mas o login
já vai para o greetd/niri.

## Atualizações

O omyfedora não instala atualização automática; o `dnf-automatic` é desativado de propósito.
Atualize manualmente quando quiser:

```bash
sudo dnf upgrade --refresh
sudo reboot   # necessário para kernel, driver e initramfs
```

Reexecutar o instalador também é seguro e idempotente:

```bash
sudo ./install.sh
```

Ele reaplica o que falta, preserva suas configs pessoais e atualiza os arquivos que o projeto
controla (com backup). Zed e OpenCode se auto-atualizam pelos instaladores oficiais; o
`lazydocker` pode ser reinstalado pela etapa `20-stack.sh`.

## Próximos passos

- [Solução de problemas](solucao-de-problemas.md) — se algo não funcionar.
- [Arquitetura e etapas](arquitetura.md) — para entender o que cada script faz.
- [Créditos](creditos.md) — os projetos por trás do omyfedora.
