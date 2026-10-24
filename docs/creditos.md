# Créditos

[Português](creditos.md) · [English](creditos.en.md)

O msbos é uma distro pessoal baseada no Fedora: ele não existiria sem o trabalho de muita
gente. Esta página registra os principais projetos e comunidades que tornam essa configuração
possível. O msbos **não é afiliado, endossado ou mantido** por nenhum deles.

## Base e desktop

| Projeto | Papel no msbos | Onde |
|---|---|---|
| **Fedora Project** | Base do sistema, pacotes, dnf, SELinux, systemd e ciclo de releases | <https://fedoraproject.org> |
| **KDE Community** | Apps KDE mantidos, Breeze Dark, `plasma-integration`, portais e `polkit-kde` | <https://kde.org> |
| **Fedora KDE** | Imagem de referência usada como base recomendada | <https://fedoraproject.org/kde> |

Obrigado ao Fedora Project e à comunidade KDE por construir e empacotar a base sobre a qual o
msbos apenas aplica uma camada pessoal.

## Compositor, shell e login

| Projeto | Autor/equipe | Papel no msbos | Onde |
|---|---|---|---|
| **niri** | YaLTeR | Compositor Wayland com tiling rolável | <https://github.com/YaLTeR/niri> |
| **Noctalia** | Equipe do Noctalia | Shell (barra, launcher, OSD, lock screen, wallpaper) e greeter | <https://noctalia.dev> |
| **greetd** | Kenny Levinsen | Display manager mínimo | <https://github.com/kennylevinsen/greetd> |
| **Terra** | Comunidade Terra/Fyra Labs | Repositório comunitário que empacota o `noctalia-greeter` | <https://terrapkg.com> |

Sem o niri, o Noctalia e o greetd, não haveria desktop para montar. Obrigado por tornarem esses
projetos abertos e documentados.

## Sistema, áudio e serviços

| Projeto | Papel no msbos | Onde |
|---|---|---|
| **systemd** | Serviços, unidades, `systemd-oomd`, integração de boot | <https://systemd.io> |
| **PipeWire / WirePlumber** | Áudio e gerenciamento de sessão de áudio | <https://pipewire.org> |
| **zram-generator** | Swap comprimido em RAM (zram + zstd) | <https://github.com/systemd/zram-generator> |
| **tuned** | Perfis de desempenho e `tuned-ppd` | <https://github.com/redhat-performance/tuned> |
| **Plymouth** | Tema de boot do msbos | <https://www.freedesktop.org/wiki/Software/Plymouth/> |
| **SELinux** | Contextos e módulos locais que mantêm a sessão funcionando | <https://selinuxproject.org> |
| **dnf** | Gerenciador de pacotes e resolução de dependências | <https://github.com/rpm-software-management/dnf5> |

## Aplicativos e ferramentas

| Projeto | Papel no msbos | Onde |
|---|---|---|
| **Zed** | Editor de código e REPL/Jupyter | <https://zed.dev> |
| **OpenCode** | IA no terminal; configuração via `agents-config` | <https://opencode.ai> |
| **agents-config** | Agentes, skills, commands e plugins do OpenCode | <https://github.com/marcos2872/agents-config> |
| **Brave** | Navegador padrão | <https://brave.com> |
| **ONLYOFFICE** | Suíte de escritório | <https://www.onlyoffice.com> |
| **LocalSend** | Compartilhamento de arquivos na LAN (flatpak) | <https://localsend.org> |
| **lazydocker** | TUI para containers | <https://github.com/jesseduffield/lazydocker> |
| **SSH_Orchestrator** | Cliente SSH/SFTP (RPM da release oficial) | <https://github.com/marcos2872/SSH_Orchestrator> |
| **Alacritty** | Terminal com transparência e blur | <https://github.com/alacritty/alacritty> |
| **zsh** | Shell padrão com autocomplete | <https://www.zsh.org> |
| **zsh-autosuggestions** | Sugestões inline do histórico | <https://github.com/zsh-users/zsh-autosuggestions> |
| **zsh-syntax-highlighting** | Destaque de sintaxe no shell | <https://github.com/zsh-users/zsh-syntax-highlighting> |
| **fzf** | Busca fuzzy no histórico (Ctrl+R) e em arquivos (Ctrl+T) | <https://github.com/junegunn/fzf> |
| **JetBrains Mono** | Fonte do terminal | <https://www.jetbrains.com/lp/mono/> |
| **libvirt / virt-manager** | Virtualização KVM/QEMU | <https://libvirt.org> · <https://virt-manager.org> |
| **GitHub CLI** | PRs, issues e releases pelo terminal | <https://cli.github.com> |
| **Rust / rustup** | Toolchain Rust | <https://www.rust-lang.org> · <https://rustup.rs> |
| **nvm / Node.js** | Node LTS, npm, pnpm e yarn | <https://github.com/nvm-sh/nvm> · <https://nodejs.org> |

## Comunidades e mantenedores

Obrigado também às comunidades de tradução, documentação, empacotamento e suporte do Fedora,
KDE, niri, Noctalia e de todos os projetos acima. Bug reports, patches, documentação e
discussões são o que mantêm esse ecossistema vivo.

Se você mantém um desses projetos e encontrar algo no msbos que viole uma convenção ou
expectativa, abra uma issue no repositório do msbos — a intenção é sempre respeitar e
destacar o trabalho upstream.

## Licença e marcas

O código do msbos é distribuído sob a licença [MIT](../LICENSE). Os nomes, logotipos e
marcas de Fedora, KDE, niri, Noctalia, greetd, Zed, Brave, ONLYOFFICE e dos demais projetos
pertencem aos seus respectivos donos. O uso aqui é apenas descritivo, sem qualquer indicação de
afiliação ou endosso.
