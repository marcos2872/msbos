# Fedora e dnf — pacotes, serviços e repositórios

O Fedora aqui usa **dnf5** (comando `dnf`). O omyfedora instala com `install_weak_deps=0`, ou seja, sem dependências fracas. O helper faz o mesmo.

## Consultas (sem root, sem confirmação de senha)

```bash
dnf search <termo>              # procurar pacote
dnf info <pacote>               # versão, repositório, descrição
rpm -q <pacote>                 # está instalado?
rpm -qf $(command -v <bin>)     # qual pacote fornece este comando
dnf repoquery --installed --whatrequires <pacote>   # o que depende dele
dnf history list                # transações anteriores
```

Consultar não é mudança: não precisa de confirmação. Mas **antes de propor instalar**, confirme que o pacote existe (`dnf info`) e diga de qual repositório vem.

> Em ambiente com `NoNewPrivs=1` (OpenCode Desktop), não rode `pkexec` direto. Use `niri msg action spawn -- alacritty -e /usr/bin/pkexec ...` e confira/foca a janela do polkit; veja `references/seguranca.md`.

## Instalar

1. Verifique com `dnf info <pacote>` e mostre ao usuário nome, versão e repositório.
2. Valide: `/usr/local/libexec/omyfedora-priv --dry-run dnf-install <pacote>` (sem `pkexec`).
3. Peça confirmação no formato da SKILL.
4. Execute: `pkexec /usr/local/libexec/omyfedora-priv dnf-install <pacote>`.
5. Confira: `rpm -q <pacote>`.

O helper instala **só de repositórios já habilitados**. Não aceita URL, caminho de arquivo `.rpm`, globs, grupos (`@x`) nem opções.
Se o pacote só existe em outro repositório (Copr, RPM Fusion, repo de terceiros), **diga ao usuário** e explique o risco; adicionar repositório não é função do helper.

## Remover

1. `pkexec /usr/local/libexec/omyfedora-priv dnf-simulate-remove <pacote>` e **mostre a lista completa** ao usuário (inclusive dependências que sairiam).
2. Peça confirmação.
3. `pkexec /usr/local/libexec/omyfedora-priv dnf-remove <pacote>`.
4. Informe como desfazer: `dnf history undo <ID>` (veja o ID em `dnf history list`).

O helper desliga a remoção em cascata de dependências órfãs e **recusa** a operação se:
- o pacote ou algo que sairia junto estiver na lista de protegidos (sistema base, niri, Noctalia, greetd, polkit, PAM, SELinux, kernel, boot, apps KDE essenciais);
- a transação afetar mais de 25 pacotes.

Nesses casos **não tente de novo por outro caminho**. Explique ao usuário.

## Serviços

Unidades permitidas por padrão: `tuned`, `tuned-ppd`, `bluetooth`, `libvirtd`, `libvirtd.socket`, `podman.socket`, `cups`, `cups.socket`, `avahi-daemon` (+ `.socket`), `fprintd`, `firewalld`, `sshd`. Ficam **fora** de propósito: `systemd-oomd` (o projeto depende dele) e `power-profiles-daemon` (conflita com o `tuned-ppd`). O administrador pode ampliar em `/etc/omyfedora/allowed-units.list` (arquivo de root; você não edita).

```bash
systemctl status <unidade>        # consultar: sem root
pkexec /usr/local/libexec/omyfedora-priv svc-enable <unidade>    # habilita e inicia
pkexec /usr/local/libexec/omyfedora-priv svc-disable <unidade>   # desabilita e para
pkexec /usr/local/libexec/omyfedora-priv svc-restart <unidade>
```

Nunca mascare, pare ou desabilite: `greetd`, `NetworkManager`, `systemd-*`, `dbus`, `polkit`. O helper já não permite.

## O que o helper NÃO faz (explique e deixe o usuário agir)

Adicionar ou remover repositórios, `dnf autoremove`, atualizar o sistema, editar `/etc` (sysctl, fstab, zram), GRUB/kernel, SELinux, PAM, greetd, drivers NVIDIA. Se o usuário pedir, diga o comando e o risco e deixe-o executar no terminal dele.

## Aplicativos sem pacote

`flatpak install --user flathub <id>` não precisa de root e é a alternativa preferida para apps que o Fedora não empacota. **Ainda assim peça confirmação.**
Evite scripts `curl | sh`. Se o usuário insistir, mostre o script antes e rode como usuário, nunca como root.

## Atualizações

O omyfedora **desativa** o `dnf-automatic` de propósito (o usuário decide quando atualizar). Não habilite atualização automática por conta própria e não rode `dnf upgrade` sem pedido explícito. Se pedirem, faça `dnf check-upgrade` primeiro e mostre o resumo.
