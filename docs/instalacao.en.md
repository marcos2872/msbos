# Installation

[Português](instalacao.md) · [English](instalacao.en.md)

msbos is installed **on top of an existing Fedora** (route C): there is no custom ISO.
`install.sh` runs seven idempotent steps (+ two migration steps, no-ops on a fresh install),
installs packages, configures services and applies the tuning. Replacing the Plasma shell with
niri/Noctalia only takes effect after a reboot.

## Before you start

- **Fedora 44 or 45**, x86_64, already installed with working network access.
- `sudo` access and the user who will receive the configuration (default: whoever invoked
  sudo).
- Disk space and time proportional to the number of packages (the first install downloads a
  lot; later runs are incremental).
- Back up anything important. The installer creates `.msbos-bak` backups of files it
  overwrites, but that is not a replacement for your own backup.

The recommended base is **Fedora KDE**: the script removes only the Plasma *shell* (desktop,
workspace and Plasma Login Manager) and **keeps the KDE apps**. A **minimal** Fedora install
also works and produces an even leaner system; in that case the script adds the missing
stack and KDE apps.

## Choose the base

| Image | Purpose | Download |
|---|---|---|
| **Fedora KDE** (Live ISO) | Recommended base; already includes the KDE apps | <https://fedoraproject.org/kde/download> |
| **Fedora Everything** (netinstall) | Minimal install — choose **“Minimal Install”** in Anaconda | <https://fedoraproject.org/misc> |

Direct mirrors (replace `44` with the desired version; the full list is at
<https://mirrors.fedoraproject.org>):

- KDE: <https://download.fedoraproject.org/pub/fedora/linux/releases/44/KDE/x86_64/iso/>
- Everything: <https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/iso/>

Check the checksum against the `-CHECKSUM` files and, if possible, the Fedora OpenPGP
signature before installing.

## Testing in a VM

**niri rejects software rendering** (llvmpipe) by design. A VM needs **virtio-gpu with 3D
acceleration** and **GL on Spice**; otherwise the session stays black. The `qxl` adapter,
common in VMs, does not work with niri.

```bash
virt-install --name msbos --memory 4096 --vcpus 3 --disk size=25 \
  --cdrom /path/to/Fedora-KDE-Desktop-Live-44.x86_64.iso \
  --os-variant fedora-unknown \
  --graphics spice,gl=on --video virtio,accel3d=yes
```

If the VM already exists, see
[Black screen or inverted cursor in a VM](solucao-de-problemas.en.md#black-screen-or-inverted-cursor-in-a-vm)
to fix video/GL and the QEMU artifact workarounds.

## Install without cloning the repository

`bootstrap.sh` downloads the repository as a `.tar.gz`, extracts it to a temporary directory
and calls `install.sh`. No `git` required.

Save the bootstrap to a file before running it: that way the interactive `install.sh` prompts
keep reading from the terminal.

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/msbos/main/bootstrap.sh -o /tmp/msbos.sh

sudo bash /tmp/msbos.sh --dry-run   # simulate everything (recommended first)
sudo bash /tmp/msbos.sh             # install for real
```

Pin a branch, tag or commit:

```bash
sudo env MSBOS_REF=YOUR_TAG_OR_COMMIT bash /tmp/msbos.sh --yes
```

Non-interactive install (throwaway VM/CI):

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/msbos/main/bootstrap.sh \
  | sudo bash -s -- --yes
```

Variables accepted by the bootstrap:

| Variable | Default | Effect |
|---|---|---|
| `MSBOS_REF` | `main` | Branch, tag or commit to download |
| `MSBOS_REPO` | `marcos2872/msbos` | Alternative repository (`owner/repo`) |
| `MSBOS_URL` | — | Full `.tar.gz` URL; overrides `REPO`/`REF` |
| `MSBOS_KEEP` | `0` | `1` keeps the temporary directory for debugging |

The bootstrap accepts every `install.sh` option and forwards the arguments.

## Install with a clone (development)

```bash
git clone https://github.com/marcos2872/msbos.git
cd msbos

./install.sh --dry-run   # simulate everything, change nothing
./install.sh             # install for real
```

When run without root and without `--dry-run`, `install.sh` re-executes itself with `sudo`,
preserving the installation variables.

## `install.sh` options

| Option | Effect |
|---|---|
| `--dry-run` | Simulates everything: installs nothing, removes nothing, writes nothing and does not access the network |
| `--yes`, `-y` | Authorizes destructive operations (Plasma shell removal and old-artifact cleanup) without asking |
| `--no-greeter` | Does not add the Terra repository; uses greetd's default greeter |
| `--user NAME` | Target user for the configuration (default: whoever invoked sudo) |
| `--gpu-profile P` | Forces `auto`, `intel`, `amd`, `nvidia`, `hybrid` or `none` |
| `--skip-remove` | Never removes packages; only installs and adjusts services |
| `-h`, `--help` | Shows the help extracted from the `install.sh` header |

The same options work with the bootstrap, for example
`sudo bash /tmp/msbos.sh --gpu-profile nvidia`.

## What happens during installation

`install.sh` discovers `scripts/[0-9][0-9]-*.sh` in order and runs:

| Step | Summary |
|---|---|
| `10-gpu.sh` | Detects Intel/AMD/NVIDIA (including hybrid setups) and installs the right driver |
| `20-stack.sh` | Installs niri, Noctalia, greetd, audio, utilities, apps and schedules Plasma shell removal |
| `25-devtools.sh` | gcc/make, Rust, Node via nvm, pnpm/yarn and virtualization (KVM/libvirt) |
| `30-services.sh` | Puts greetd on boot, masks other display managers and disables unnecessary daemons |
| `40-tuning.sh` | zram, memory sysctls, btrfs compression, CPU governor and oomd |
| `50-configs.sh` | Configures niri, Noctalia, Breeze Dark, greetd/PAM, wallpapers, Zed, zsh and default apps |
| `60-agent-skill.sh` | Installs the privileged helper (polkit), the root lists and the `msbos` skill for AI agents |

Details for each step: [Architecture and steps](arquitetura.en.md).

**Nothing is stopped in the current session.** Plasma keeps working until reboot; the Plasma
shell removal is scheduled for the next boot, before login, through
`msbos-remove-plasma.service`. This avoids killing the session in the middle of a dnf
transaction.

Each completed step leaves a marker in `/var/lib/msbos/steps/`. If a step fails, the
installer prints the error code, the history and how to resume.

## Anaconda/Kickstart

**Do not run `install.sh` directly from `%post`.** `%post` runs inside the installed system's
chroot without systemd as PID 1, and msbos needs a booted system (`systemctl
daemon-reload`, `runuser`, dconf/gsettings). The right approach is to run the bootstrap after
the first boot — or use `%post` only to install a first-boot service that runs the bootstrap.

## After installation

Reboot:

```bash
sudo reboot
```

On the next boot, the **greetd** screen should appear with the **niri** session available. On
the first login, the `msbos-greeter-sync` autostart syncs the appearance with the login
screen; the wallpaper shows up on the next logout/reboot.

Useful checks on the installed system:

```bash
msbos-doctor                 # full diagnosis (read-only)
systemctl status greetd          # display manager
journalctl -u greetd -n 30       # login log
free -h ; zramctl                # compressed swap active
ps aux --sort=-rss | head -12    # top RAM consumers
```

The default shell becomes **zsh**; the `libvirt` group only applies on the next login. To
repeat the appearance sync with the login screen after logging in:

```bash
noctalia msg greeter-sync
```

Wallpapers, shortcuts, default apps and customization: [Daily use](uso.en.md).

## Re-running or resuming

The steps are idempotent; running them again is safe:

```bash
sudo ./install.sh                # everything, from the start
sudo bash scripts/50-configs.sh  # a single step
DRY_RUN=1 bash scripts/40-tuning.sh  # simulate one step without root
```

The history lives in:

```bash
ls /var/lib/msbos/steps/
```

To restore an overwritten file, look for the `.msbos-bak` backup next to the original.
Personal configurations installed with `install_file_once` are not overwritten on a re-run;
to return to the default, delete the file and run the corresponding step.

## Next steps

- [Daily use](uso.en.md) — shortcuts, Noctalia, theme and configs.
- [Architecture and steps](arquitetura.en.md) — how the installer works internally.
- [Troubleshooting](solucao-de-problemas.en.md) — if something fails.
