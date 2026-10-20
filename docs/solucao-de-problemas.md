# Solução de problemas

[Português](solucao-de-problemas.md) · [English](solucao-de-problemas.en.md)

Esta página cobre os problemas mais comuns do omyfedora. Comece pelo diagnóstico rápido e
depois vá para a seção correspondente.

## Diagnóstico rápido

```bash
# Diagnóstico do projeto (somente leitura): erros, avisos e o que reparar
omyfedora-doctor

# Versão da base e estado geral
cat /etc/fedora-release
systemctl --failed

# Login e sessão
systemctl status greetd
journalctl -u greetd -n 50

# Memória e swap comprimido
free -h
zramctl
swapon --show

# Etapas concluídas e logs do boot
ls /var/lib/omyfedora/steps/
journalctl -b -p warning
```

## A instalação falhou

O `install.sh` mostra o código de erro, até onde chegou e como retomar. As etapas são
idempotentes; rodar de novo é seguro:

```bash
sudo ./install.sh              # tudo, desde o início
sudo bash scripts/50-configs.sh  # só a etapa que falhou
```

O histórico fica em `/var/lib/omyfedora/steps/`.

### dnf: “checksum doesn't match” ou 404 de repodata

É o **espelho do Fedora fora de sincronia** (transitório; aconteceria com qualquer `dnf`, não é
do omyfedora). Limpe o cache e tente de novo:

```bash
sudo dnf clean all
sudo ./install.sh
```

Se persistir por muitos minutos, troque de espelho. A lista está em
<https://mirrors.fedoraproject.org>. O `20-stack.sh` já tenta uma segunda vez automaticamente
para falhas transitórias do núcleo.

### Sem espaço em disco

```bash
df -h /
sudo dnf clean all
```

A primeira instalação baixa muitos pacotes (navegador, ONLYOFFICE, ferramentas de
desenvolvimento e virtualização). Libere espaço antes de continuar.

### O prompt não aparece / instalação não interativa

O `install.sh` precisa de um terminal para perguntar sobre a remoção do shell do Plasma. Se
você usou `curl | sudo bash`, o stdin não é um TTY. Salve o bootstrap em arquivo e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh -o /tmp/omyfedora.sh
sudo bash /tmp/omyfedora.sh
```

Ou use `--yes` em uma VM descartável/CI.

### Anaconda/Kickstart: o script não funciona no `%post`

O `%post` roda no chroot, sem systemd como PID 1. O omyfedora precisa de um sistema já
inicializado (`systemctl daemon-reload`, `runuser`, dconf/gsettings). Rode o bootstrap depois
do primeiro boot ou use o `%post` apenas para instalar um serviço de primeiro boot.

## VM com tela preta ou cursor invertido

O **niri rejeita renderização por software** (llvmpipe) por design. A VM precisa de
**virtio-gpu com aceleração 3D** e **GL no Spice**. O `qxl` não funciona com o niri.

Com a VM **desligada**, ajuste:

```bash
virt-xml --connect qemu:///system NOME_DA_VM --edit \
  --video model.type=virtio,model.acceleration.accel3d=yes
virt-xml --connect qemu:///system NOME_DA_VM --edit --graphics gl.enable=yes
```

No virt-manager: **Vídeo → modelo Virtio + Aceleração 3D** e **Display Spice → GL habilitado**.

Se a sessão abrir, mas aparecerem **artefatos de tela** ou o **cursor de cabeça para baixo**
(bugs de driver do QEMU/virgl — qemu#2315), descomente as três linhas do bloco de VM dentro do
`debug { }` em `~/.config/niri/config.kdl`:

```kdl
disable-cursor-plane
disable-direct-scanout
wait-for-frame-completion-before-queueing
```

Aplique com `niri msg action load-config-file` (ou relogue). O bloco já vem comentado com
essas linhas; não remova o `debug { }`.

## O login não aparece ou volta para o greeter

1. Veja o estado e o log:

   ```bash
   systemctl status greetd
   journalctl -u greetd -n 80
   ```

2. Confirme que o PAM tem `pam_selinux` (obrigatório para o `systemctl --user` da sessão):

   ```bash
   grep pam_selinux /etc/pam.d/greetd
   ```

   Se faltar, rode `sudo bash scripts/50-configs.sh` para restaurar a versão correta.

3. Confirme a sessão configurada:

   ```bash
   cat /etc/greetd/config.toml
   niri --version
   ```

   O comando deve terminar com `--session niri` (ou o greeter padrão, sem Noctalia Greeter).

4. Se o Noctalia Greeter não estiver instalado, o greetd usa o greeter de texto. Para instalar
   o Noctalia Greeter, rode `sudo bash scripts/20-stack.sh` sem `--no-greeter` (o repo Terra é
   necessário).

5. Se a sessão volta para o login com erro de SELinux, procure AVCs:

   ```bash
   journalctl -b | grep -i avc
   ```

   O contexto do home do greeter é ajustado por `30-services.sh`; uma reexecução da etapa
   reaplica `semanage`/`restorecon`.

## O shell do Plasma continua instalado

A remoção é **agendada para o próximo boot**, não feita na sessão viva. Verifique:

```bash
systemctl status omyfedora-remove-plasma
journalctl -u omyfedora-remove-plasma -n 80
rpm -q plasma-desktop plasma-workspace plasma-login-manager
```

Se o serviço falhou (por exemplo, sem rede no boot), ele continua habilitado e tenta de novo no
próximo boot. Você também pode executá-lo manualmente **de dentro da sessão niri**:

```bash
sudo systemctl start omyfedora-remove-plasma
```

Se você usou `--skip-remove`, a remoção não foi agendada de propósito; o shell do Plasma
permanece instalado, mas o login já usa o greetd/niri.

<a id="wallpaper-nao-aparece-na-tela-de-login"></a>

## Wallpaper não aparece na tela de login

O wallpaper do login é sincronizado pelo **Noctalia Greeter** (Auto-Sync). Numa instalação
limpa, o autostart `omyfedora-greeter-sync` faz o primeiro sync no login. Se o wallpaper não
aparecer, rode manualmente dentro da sessão:

```bash
noctalia msg greeter-sync
```

Para forçar um novo sync no próximo login, apague o marcador:

```bash
rm -f ~/.local/state/omyfedora/greeter-sync.done
```

Depois confira:

```bash
sudo grep -A3 '\[appearance\.wallpaper\]' /var/lib/noctalia-greeter/sync.toml
```

- Se o arquivo não existir ou não tiver wallpaper, rode `sudo bash scripts/50-configs.sh` e
  autentique o sync quando pedido.
- O `pkexec` exige que o **shell da sessão** esteja listado em `/etc/shells`. Confira:

  ```bash
  getent passwd "$USER" | cut -d: -f7
  grep -F "$(getent passwd "$USER" | cut -d: -f7)" /etc/shells
  ```

  O `50-configs.sh` garante o `/usr/bin/zsh` e o shell antigo; se você trocou de shell depois,
  adicione o caminho manualmente.
- O sync sem prompt usa uma regra Polkit restrita à ação do greeter. Se ela não estiver
  habilitada, o comando pede autenticação; isso é esperado.

## Uma configuração do Noctalia “não pega”

O Noctalia v5 lê `~/.config/noctalia/config.toml` (estilo) e depois
`~/.local/state/noctalia/settings.toml` (estado escrito pela GUI). O segundo **vence chave a
chave**. Se uma mudança de aparência não aparece:

1. Procure a mesma chave nos dois arquivos:

   ```bash
   grep -n 'nome_da_chave' ~/.config/noctalia/config.toml \
     ~/.local/state/noctalia/settings.toml
   ```

2. Ajuste a aparência pela **GUI do Noctalia** (que reescreve o `settings.toml`) ou edite o
   `config.toml` e remova/alinhe a chave duplicada no `settings.toml`. Não edite o
   `settings.toml` à mão sem necessidade.
3. Saia e entre novamente para recarregar o shell.

Lembrete: `~/.config/noctalia/config.toml` é instalado **uma vez**; edições suas são
preservadas. Já os arquivos `90-greeter-sync.toml`, `91-widget-control-center.toml` e a paleta
`macOS.json` são atualizados pelo instalador (com backup).

## Apps claros ou sem o Breeze Dark

1. Confira o `kdeglobals`:

   ```bash
   kreadconfig6 --file kdeglobals --group General --key ColorScheme
   kreadconfig6 --file kdeglobals --group Icons --key Theme
   ```

   O esperado é `BreezeDark` e `breeze-dark`.

2. Confira o platform theme Qt (vale após novo login):

   ```bash
   echo "$QT_QPA_PLATFORMTHEME"   # esperado: kde
   ```

3. Confira o GTK/dconf:

   ```bash
   gsettings get org.gnome.desktop.interface color-scheme
   gsettings get org.gnome.desktop.interface gtk-theme
   ```

   O esperado é `'prefer-dark'` e `'Breeze'`.

4. Feche e abra o app (apps Qt/GTK leem o tema no start). Se você trocou o tema pelo **System
   Settings**, essa escolha vence — o omyfedora só preenche chaves vazias e não regride.

Se o `kwriteconfig6` não existir, instale `kde-cli-tools` e rode
`sudo bash scripts/50-configs.sh`.

## App Electron/Tauri não lê o keychain (Secret Service)

Sintoma: **“Couldn't read your saved credentials from the keychain”** ao abrir o Delta, VS Code
ou outro app Electron/Tauri. A causa é a ausência de um provedor de `org.freedesktop.secrets`
na sessão: no niri não há Plasma para publicar o serviço, e o `ksecretd` iniciado pelo
`pam_kwallet` no greetd fica vivo sem dono do nome no D-Bus.

Confira:

```bash
busctl --user list | grep org.freedesktop.secrets
```

O nome deve aparecer com dono (`ksecretd`) ou como `(activatable)`. Se não aparecer:

```bash
ls ~/.local/share/dbus-1/services/org.freedesktop.secrets.service
sudo bash scripts/50-configs.sh   # instala o service de D-Bus
```

O `50-configs.sh` instala `~/.local/share/dbus-1/services/org.freedesktop.secrets.service` e
recarrega o barramento. O próximo app que pedir credenciais ativa o `ksecretd` sob demanda; não
é preciso criar uma unit systemd (o `ksecretd` iniciado pelo PAM continua residente, mas sem
dono do nome). Se o arquivo já existe mas o nome não aparece, recarregue o bus manualmente:

```bash
dbus-send --session --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig
```

Reabra o app e, se tiver o `secret-tool`, teste com `secret-tool store`/`secret-tool lookup`.
O `omyfedora-doctor` também aponta quando o serviço está ausente.

## Terminal sem transparência ou blur

O blur do alacritty usa `background-effect`, recurso do **niri 26.04+**. Em uma versão mais
antiga, o config inteiro falha ao carregar (nó inesperado). Confira:

```bash
niri --version
niri validate
```

Se o `niri` for mais antigo que 26.04, remova os blocos `background-effect { blur true }` do
`~/.config/niri/config.kdl` e recarregue:

```bash
niri msg action load-config-file
```

A transparência do alacritty (`opacity = 0.85`) é multiplicada pela regra global do niri
(`opacity 0.90`), resultando em ~0.77 na tela. Isso é esperado.

## Flatpak: “Not allowed to query parental controls data”

Se o `accounts-daemon` da sua versão do Fedora expõe a interface
`com.endlessm.ParentalControls` e o pacote `malcontent` está ausente, todo `flatpak run` falha
(flatpak/flatpak#6142). O omyfedora protege/instala o `malcontent` quando detecta esse build.

Confira:

```bash
grep -a com.endlessm.ParentalControls /usr/libexec/accounts-daemon
rpm -q malcontent
```

Se a interface existir e o pacote faltar:

```bash
sudo dnf install malcontent
sudo systemctl try-restart accounts-daemon
```

Se a interface não existir no daemon, o `malcontent` não é necessário e nada precisa ser feito.

## RAM acima do esperado

O alvo de **< ~600 MB em idle** considera a sessão niri/Noctalia sem apps pesados abertos.
Navegador, Zed, ONLYOFFICE e VMs consomem RAM enquanto estão rodando. Para investigar:

```bash
free -h
ps aux --sort=-rss | head -15
zramctl
balooctl6 status
```

- O Baloo (indexador do Dolphin) é desligado pelo `20-stack.sh`; se estiver ativo, rode
  `balooctl6 disable`.
- O zram é swap comprimido, não uma redução direta do uso de RAM; ele evita travar quando a
  memória aperta.
- Flatpaks e Electron apps costumam ser os maiores consumidores. Feche-os para medir o idle.

## zram não está ativo

```bash
zramctl
swapon --show
systemctl status dev-zram0.swap
```

O arquivo correto é `/etc/systemd/zram-generator.conf` (o generator **ignora**
`/etc/zram-generator.conf`). O `40-tuning.sh` instala e valida a config; uma reexecução da
etapa e um reboot devem ativar o swap:

```bash
sudo bash scripts/40-tuning.sh
sudo reboot
```

## Monitores, escala e rotação

Use `Super+P` (plugin **Niri Displays**) para ligar/desligar saídas, mudar resolução, escala,
rotação e posição. Para inspecionar ou aplicar pela linha de comando:

```bash
niri msg outputs
niri msg output HDMI-A-1 mode 2560x1080@74.991
niri msg output HDMI-A-1 position set 0 0
```

O `pessoal-pc.sh` é um exemplo **pessoal** de layout com dois monitores; ele não é executado
pelo instalador e os nomes das saídas variam de máquina para máquina.

## NVIDIA e híbridos

```bash
nvidia-smi
lsmod | grep nvidia
grep -o 'nvidia-drm.modeset=1' /proc/cmdline
```

- Wayland exige KMS; o `10-gpu.sh` adiciona `nvidia-drm.modeset=1` via `grubby`. O efeito vale
  após o reboot.
- Em híbrido, o `profile.d/omyfedora-nvidia.sh` faz offload GLX para a dGPU. Para forçar a iGPU
  em um app específico:

  ```bash
  __GLX_VENDOR_LIBRARY_NAME=mesa nome-do-app
  ```

- Se o driver não instalou, rode `sudo bash scripts/10-gpu.sh` e reinicie.

## Recuperar arquivos e voltar atrás

- Todo arquivo sobrescrito tem um backup ao lado, com sufixo `.omyfedora-bak`. Para restaurar:

  ```bash
  cp -a /caminho/arquivo.omyfedora-bak /caminho/arquivo
  ```

- Configs pessoais (`niri/config.kdl`, `noctalia/config.toml`, `.zshrc`, `alacritty.toml`,
  `zed/*`) não são sobrescritas. Para voltar ao padrão, apague o arquivo e rode
  `sudo bash scripts/50-configs.sh`.

- **Não há desinstalador automático.** O sistema continua sendo Fedora; pacotes instalados
  podem ser removidos manualmente e configs restauradas pelos backups. Se você quiser voltar a
  usar o shell do Plasma, reinstale os pacotes do Plasma e reative o `plasmalogin` (ou
  reinstale a base). O `--skip-remove` evita a remoção em uma próxima execução.

- Para interromper a remoção agendada do Plasma antes do reboot:

  ```bash
  sudo systemctl disable omyfedora-remove-plasma.service
  ```

  Isso mantém os pacotes; o login ainda usa o greetd/niri até você reativar o `plasmalogin`.

## Coletar informações para pedir ajuda

Inclua no relato:

```bash
cat /etc/fedora-release
niri --version
systemctl --failed
systemctl status greetd
journalctl -b -p warning
ls /var/lib/omyfedora/steps/
free -h
```

Issues do projeto: <https://github.com/marcos2872/omyfedora/issues>.
