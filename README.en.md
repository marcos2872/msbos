<p align="center">
  <img src="assets/branding/omyfedora-logo.png" alt="omyfedora logo" width="120" height="120">
  &nbsp;&nbsp;&nbsp;
  <img src="assets/branding/omyfedora-mascot.png" alt="omyfedora mascot" width="120" height="120">
</p>

<h1 align="center">omyfedora</h1>

<p align="center">
  <strong>A personal customization of Fedora KDE with niri + Noctalia v5.</strong><br>
  <a href="README.md">Português</a> ·
  <a href="docs/index.en.md">Documentation</a> ·
  <a href="docs/solucao-de-problemas.en.md">Troubleshooting</a>
</p>

**omyfedora** is neither a distribution nor its own ISO: it is a set of idempotent bash
scripts that turns an **already installed Fedora 44/45** into a lean desktop. Installation
follows **route C**: instead of building an ISO, a bootstrap script replaces the Plasma shell
with **niri** (a Wayland compositor) and **Noctalia v5**, installs the right GPU driver, and
applies the memory and performance tuning. The **KDE apps stay**, and applications keep the
**Breeze Dark** theme, KDE's default dark theme.

The goal is a personal desktop that idles **below ~600 MB of RAM** (compared with ~1.5 GB
for a typical Plasma session), without giving up the everyday apps.

> **Thanks to everyone who makes this possible.** omyfedora is just the personal glue
> between excellent projects: the [Fedora Project](https://fedoraproject.org) and the
> [KDE community](https://kde.org) provide the base and the applications;
> [niri](https://github.com/YaLTeR/niri), by **YaLTeR**, provides the compositor;
> [Noctalia](https://noctalia.dev) provides the shell and greeter; and
> [greetd](https://github.com/kennylevinsen/greetd), by **Kenny Levinsen**, handles login.
> Thanks also to every upstream project listed in the
> [full credits](docs/creditos.en.md). omyfedora is a personal project, not affiliated with
> Fedora, KDE, niri or Noctalia.

## What it is

| Layer | Choice |
|---|---|
| Base | Fedora 44/45 KDE Plasma Desktop (or a minimal install) |
| Graphical session | **niri** — a scrollable-tiling Wayland compositor |
| Shell | **Noctalia v5** — bar, launcher, notifications, OSD and lock screen |
| Login | **greetd** + Noctalia Greeter (replaces Plasma Login Manager) |
| Apps | **KDE** apps kept + Zed, Brave, ONLYOFFICE, LocalSend, lazydocker… |
| App theme | **Breeze Dark** (Qt via `kdeglobals`, GTK via dconf/`settings.ini`) |
| Terminal | translucent **alacritty** with blur + **zsh** with autocomplete |
| Dev | Rust (rustup), Node LTS via nvm, gcc/make, GitHub CLI, KVM/libvirt |

## Requirements

- Fedora **44 or 45** already installed, **x86_64**, with internet access and `sudo`.
- Recommended base: **Fedora KDE** (the script removes the Plasma shell and keeps KDE apps).
- Leaner alternative: a **minimal** Fedora install (the script adds everything else).
- On a VM, you need **virtio-gpu with 3D acceleration** and GL on Spice — niri rejects
  software rendering. See [VM and GPU](docs/instalacao.en.md#testing-in-a-vm).

## Installation (basic)

Without cloning the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh -o /tmp/omyfedora.sh

sudo bash /tmp/omyfedora.sh --dry-run   # simulate everything (recommended first)
sudo bash /tmp/omyfedora.sh             # install for real
sudo reboot
```

Or with a clone (for development):

```bash
git clone https://github.com/marcos2872/omyfedora.git
cd omyfedora

./install.sh --dry-run   # simulate everything, change nothing
./install.sh             # install (asks before removing the Plasma shell)
sudo reboot
```

The installer asks before scheduling the Plasma shell removal; nothing is stopped in the
current session. The switch to greetd/niri takes effect on the **next boot**. Do **not**
run `install.sh` from Anaconda's `%post` — see [installation](docs/instalacao.en.md).

After rebooting, the **niri** session appears on the greetd screen. On the first login,
omyfedora automatically syncs the appearance with the login screen; the wallpaper shows up on
the next logout/reboot (to repeat: `noctalia msg greeter-sync`). Basic shortcuts:
`Super+T` terminal · `Super+Space` launcher · `Super+S` control center · `Super+P` displays.

## Documentation

| Document | Contents |
|---|---|
| [Installation](docs/instalacao.en.md) | Base images, VM, bootstrap, options, Anaconda and first steps |
| [Daily use](docs/uso.en.md) | niri/Noctalia shortcuts, wallpapers, default apps, theme and personal configs |
| [Architecture and steps](docs/arquitetura.en.md) | Script flow, the 7 steps, `lib/common.sh`, assets and verification |
| [Troubleshooting](docs/solucao-de-problemas.en.md) | dnf, VM/GPU, flatpak, Noctalia, greeter and recovery |
| [Credits](docs/creditos.en.md) | Projects and people that make omyfedora possible |
| [Index](docs/index.en.md) | Entry point for all documentation |

Every document has a Portuguese version without the `.en.md` suffix (for example,
[README.md](README.md) and [docs/index.md](docs/index.md)).

## License

[MIT](LICENSE) — use, modify and redistribute as you wish.
