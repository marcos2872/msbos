# Credits

[Português](creditos.md) · [English](creditos.en.md)

omyfedora is a personal customization project: it would not exist without the work of many
people. This page records the main projects and communities that make this configuration
possible. omyfedora is **not affiliated with, endorsed by, or maintained by** any of them.

## Base and desktop

| Project | Role in omyfedora | Where |
|---|---|---|
| **Fedora Project** | System base, packages, dnf, SELinux, systemd and release cycle | <https://fedoraproject.org> |
| **KDE Community** | KDE apps kept, Breeze Dark, `plasma-integration`, portals and `polkit-kde` | <https://kde.org> |
| **Fedora KDE** | Reference image used as the recommended base | <https://fedoraproject.org/kde> |

Thanks to the Fedora Project and the KDE community for building and packaging the base on top
of which omyfedora applies a personal layer.

## Compositor, shell and login

| Project | Author/team | Role in omyfedora | Where |
|---|---|---|---|
| **niri** | YaLTeR | Scrollable-tiling Wayland compositor | <https://github.com/YaLTeR/niri> |
| **Noctalia** | Noctalia team | Shell (bar, launcher, OSD, lock screen, wallpaper) and greeter | <https://noctalia.dev> |
| **greetd** | Kenny Levinsen | Minimal display manager | <https://github.com/kennylevinsen/greetd> |
| **Terra** | Terra/Fyra Labs community | Community repository that packages `noctalia-greeter` | <https://terrapkg.com> |

Without niri, Noctalia and greetd there would be no desktop to assemble. Thank you for making
these projects open and well documented.

## System, audio and services

| Project | Role in omyfedora | Where |
|---|---|---|
| **systemd** | Services, units, `systemd-oomd`, boot integration | <https://systemd.io> |
| **PipeWire / WirePlumber** | Audio and audio session management | <https://pipewire.org> |
| **zram-generator** | Compressed swap in RAM (zram + zstd) | <https://github.com/systemd/zram-generator> |
| **tuned** | Performance profiles and `tuned-ppd` | <https://github.com/redhat-performance/tuned> |
| **Plymouth** | omyfedora boot theme | <https://www.freedesktop.org/wiki/Software/Plymouth/> |
| **SELinux** | Contexts and local modules that keep the session working | <https://selinuxproject.org> |
| **dnf** | Package manager and dependency resolution | <https://github.com/rpm-software-management/dnf5> |

## Applications and tools

| Project | Role in omyfedora | Where |
|---|---|---|
| **Zed** | Code editor and REPL/Jupyter | <https://zed.dev> |
| **OpenCode** | AI in the terminal; configuration via `agents-config` | <https://opencode.ai> |
| **agents-config** | OpenCode agents, skills, commands and plugins | <https://github.com/marcos2872/agents-config> |
| **Brave** | Default browser | <https://brave.com> |
| **ONLYOFFICE** | Office suite | <https://www.onlyoffice.com> |
| **LocalSend** | LAN file sharing (flatpak) | <https://localsend.org> |
| **lazydocker** | Container TUI | <https://github.com/jesseduffield/lazydocker> |
| **SSH_Orchestrator** | SSH/SFTP client (official release RPM) | <https://github.com/marcos2872/SSH_Orchestrator> |
| **Alacritty** | Terminal with transparency and blur | <https://github.com/alacritty/alacritty> |
| **zsh** | Default shell with autocomplete | <https://www.zsh.org> |
| **zsh-autosuggestions** | Inline history suggestions | <https://github.com/zsh-users/zsh-autosuggestions> |
| **zsh-syntax-highlighting** | Shell syntax highlighting | <https://github.com/zsh-users/zsh-syntax-highlighting> |
| **fzf** | Fuzzy history search (Ctrl+R) and file search (Ctrl+T) | <https://github.com/junegunn/fzf> |
| **JetBrains Mono** | Terminal font | <https://www.jetbrains.com/lp/mono/> |
| **libvirt / virt-manager** | KVM/QEMU virtualization | <https://libvirt.org> · <https://virt-manager.org> |
| **GitHub CLI** | PRs, issues and releases from the terminal | <https://cli.github.com> |
| **Rust / rustup** | Rust toolchain | <https://www.rust-lang.org> · <https://rustup.rs> |
| **nvm / Node.js** | Node LTS, npm, pnpm and yarn | <https://github.com/nvm-sh/nvm> · <https://nodejs.org> |

## Communities and maintainers

Thanks also to the translation, documentation, packaging and support communities of Fedora, KDE,
niri, Noctalia and every project above. Bug reports, patches, documentation and discussions are
what keep this ecosystem alive.

If you maintain one of these projects and find something in omyfedora that violates a convention
or expectation, please open an issue in the omyfedora repository — the intent is always to
respect and highlight upstream work.

## License and trademarks

omyfedora's code is distributed under the [MIT](../LICENSE) license. The names, logos and
trademarks of Fedora, KDE, niri, Noctalia, greetd, Zed, Brave, ONLYOFFICE and the other projects
belong to their respective owners. Their use here is descriptive only, with no indication of
affiliation or endorsement.
