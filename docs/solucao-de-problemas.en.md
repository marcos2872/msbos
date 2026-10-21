# Troubleshooting

[Português](solucao-de-problemas.md) · [English](solucao-de-problemas.en.md)

This page covers the most common omyfedora problems. Start with the quick diagnosis and then
jump to the relevant section.

## Quick diagnosis

```bash
# Project diagnosis (read-only): errors, warnings and how to repair
omyfedora-doctor

# Base version and overall state
cat /etc/fedora-release
systemctl --failed

# Login and session
systemctl status greetd
journalctl -u greetd -n 50

# Memory and compressed swap
free -h
zramctl
swapon --show

# Completed steps and boot logs
ls /var/lib/omyfedora/steps/
journalctl -b -p warning
```

## The installation failed

`install.sh` prints the exit code, how far it got and how to resume. The steps are idempotent;
running them again is safe:

```bash
sudo ./install.sh              # everything, from the start
sudo bash scripts/50-configs.sh  # only the failed step
```

The history lives in `/var/lib/omyfedora/steps/`.

### dnf: “checksum doesn't match” or 404 from repodata

This is the **Fedora mirror out of sync** (transient; it would happen with any `dnf`, not just
omyfedora). Clean the cache and try again:

```bash
sudo dnf clean all
sudo ./install.sh
```

If it persists for several minutes, switch mirrors. The list is at
<https://mirrors.fedoraproject.org>. `20-stack.sh` already retries the core installation once
for transient failures.

### Out of disk space

```bash
df -h /
sudo dnf clean all
```

The first install downloads many packages (browser, ONLYOFFICE, development tools and
virtualization). Free some space before continuing.

### No prompt / non-interactive install

`install.sh` needs a terminal to ask about the Plasma shell removal. If you used
`curl | sudo bash`, stdin is not a TTY. Save the bootstrap to a file and run it:

```bash
curl -fsSL https://raw.githubusercontent.com/marcos2872/omyfedora/main/bootstrap.sh -o /tmp/omyfedora.sh
sudo bash /tmp/omyfedora.sh
```

Or use `--yes` on a throwaway VM/CI.

### Anaconda/Kickstart: the script does not work in `%post`

`%post` runs in the chroot without systemd as PID 1. omyfedora needs a booted system
(`systemctl daemon-reload`, `runuser`, dconf/gsettings). Run the bootstrap after the first boot
or use `%post` only to install a first-boot service.

## Black screen or inverted cursor in a VM

**niri rejects software rendering** (llvmpipe) by design. The VM needs **virtio-gpu with 3D
acceleration** and **GL on Spice**. `qxl` does not work with niri.

With the VM **powered off**, adjust it:

```bash
virt-xml --connect qemu:///system VM_NAME --edit \
  --video model.type=virtio,model.acceleration.accel3d=yes
virt-xml --connect qemu:///system VM_NAME --edit --graphics gl.enable=yes
```

In virt-manager: **Video → Virtio model + 3D acceleration** and **Spice display → GL enabled**.

If the session opens but you see **screen artifacts** or the **cursor upside down** (QEMU/virgl
driver bugs — qemu#2315), uncomment the three lines in the VM block inside `debug { }` in
`~/.config/niri/config.kdl`:

```kdl
disable-cursor-plane
disable-direct-scanout
wait-for-frame-completion-before-queueing
```

Apply with `niri msg action load-config-file` (or log out and back in). The block already ships
commented with these lines; do not remove `debug { }`.

## Login does not appear or returns to the greeter

1. Check the state and log:

   ```bash
   systemctl status greetd
   journalctl -u greetd -n 80
   ```

2. Confirm PAM has `pam_selinux` (required for the session's `systemctl --user`):

   ```bash
   grep pam_selinux /etc/pam.d/greetd
   ```

   If missing, run `sudo bash scripts/50-configs.sh` to restore the correct version.

3. Confirm the configured session:

   ```bash
   cat /etc/greetd/config.toml
   niri --version
   ```

   The command should end with `--session niri` (or the default greeter without Noctalia
   Greeter).

4. If Noctalia Greeter is not installed, greetd uses the text greeter. To install Noctalia
   Greeter, run `sudo bash scripts/20-stack.sh` without `--no-greeter` (the Terra repo is
   required).

5. If the session returns to login with a SELinux error, look for AVCs:

   ```bash
   journalctl -b | grep -i avc
   ```

   The greeter home context is set by `30-services.sh`; re-running the step reapplies
   `semanage`/`restorecon`.

## The Plasma shell is still installed

Removal is **scheduled for the next boot**, not done in the live session. Check:

```bash
systemctl status omyfedora-remove-plasma
journalctl -u omyfedora-remove-plasma -n 80
rpm -q plasma-desktop plasma-workspace plasma-login-manager
```

If the service failed (for example, no network at boot), it stays enabled and retries on the
next boot. You can also run it manually **from inside the niri session**:

```bash
sudo systemctl start omyfedora-remove-plasma
```

If you used `--skip-remove`, removal was intentionally not scheduled; the Plasma shell remains
installed, but login already uses greetd/niri.

## Wallpaper does not appear on the login screen

The login wallpaper is synced by **Noctalia Greeter** (Auto-Sync). On a clean install, the
`omyfedora-greeter-sync` autostart does the first sync at login. If the wallpaper does not
appear, run it manually inside the session:

```bash
noctalia msg greeter-sync
```

To force a new sync on the next login, remove the marker:

```bash
rm -f ~/.local/state/omyfedora/greeter-sync.done
```

Then check:

```bash
sudo grep -A3 '\[appearance\.wallpaper\]' /var/lib/noctalia-greeter/sync.toml
```

- If the file does not exist or has no wallpaper, run `sudo bash scripts/50-configs.sh` and
  authenticate the sync when asked.
- `pkexec` requires the **session shell** to be listed in `/etc/shells`. Check:

  ```bash
  getent passwd "$USER" | cut -d: -f7
  grep -F "$(getent passwd "$USER" | cut -d: -f7)" /etc/shells
  ```

  `50-configs.sh` ensures `/usr/bin/zsh` and the previous shell; if you changed shells later,
  add the path manually.
- Passwordless sync uses a Polkit rule restricted to the greeter action. If it is not enabled,
  the command asks for authentication; that is expected.

## A Noctalia setting “does not stick”

Noctalia v5 reads `~/.config/noctalia/config.toml` (style) and then
`~/.local/state/noctalia/settings.toml` (state written by the GUI). The second one **wins key by
key**. If an appearance change does not show up:

1. Look for the same key in both files:

   ```bash
   grep -n 'key_name' ~/.config/noctalia/config.toml \
     ~/.local/state/noctalia/settings.toml
   ```

2. Change the appearance through the **Noctalia GUI** (which rewrites `settings.toml`) or edit
   `config.toml` and remove/align the duplicate key in `settings.toml`. Do not edit
   `settings.toml` by hand unless necessary.
3. Log out and back in to reload the shell.

Reminder: `~/.config/noctalia/config.toml` is installed **once**; your edits are preserved.
The files `90-greeter-sync.toml`, `91-widget-control-center.toml` and the `macOS.json` palette
are updated by the installer (with backup).

## Apps look light or lack Breeze Dark

1. Check `kdeglobals`:

   ```bash
   kreadconfig6 --file kdeglobals --group General --key ColorScheme
   kreadconfig6 --file kdeglobals --group Icons --key Theme
   ```

   Expected: `BreezeDark` and `breeze-dark`.

2. Check the Qt platform theme (applies after a new login):

   ```bash
   echo "$QT_QPA_PLATFORMTHEME"   # expected: kde
   ```

3. Check GTK/dconf:

   ```bash
   gsettings get org.gnome.desktop.interface color-scheme
   gsettings get org.gnome.desktop.interface gtk-theme
   ```

   Expected: `'prefer-dark'` and `'Breeze'`.

4. Close and reopen the app (Qt/GTK apps read the theme at startup). If you changed the theme
   through **System Settings**, that choice wins — omyfedora only fills empty keys and does not
   override it.

If `kwriteconfig6` is missing, install `kde-cli-tools` and run
`sudo bash scripts/50-configs.sh`.

## Electron/Tauri app cannot read the keychain (Secret Service)

Symptom: **“Couldn't read your saved credentials from the keychain”** when opening Delta, VS
Code or another Electron/Tauri app. The cause is a missing `org.freedesktop.secrets` provider
in the session: niri has no Plasma to publish the service, and the `ksecretd` started by
`pam_kwallet` in greetd stays alive without owning the name on D-Bus.

Check:

```bash
busctl --user list | grep org.freedesktop.secrets
```

The name should appear with an owner (`ksecretd`) or as `(activatable)`. If it does not:

```bash
ls ~/.local/share/dbus-1/services/org.freedesktop.secrets.service
sudo bash scripts/50-configs.sh   # installs the D-Bus service
```

`50-configs.sh` installs `~/.local/share/dbus-1/services/org.freedesktop.secrets.service` and
reloads the bus. The next app that asks for credentials starts `ksecretd` on demand; there is
no need to create a systemd unit (the `ksecretd` started by PAM stays resident but does not own
the name). If the file already exists but the name does not appear, reload the bus manually:

```bash
dbus-send --session --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig
```

Reopen the app and, if `secret-tool` is available, test with `secret-tool store`/`secret-tool
lookup`. `omyfedora-doctor` also reports when the service is missing.

## Terminal without transparency or blur

Alacritty's blur uses `background-effect`, a **niri 26.04+** feature. On an older version the
whole config fails to load (unexpected node). Check:

```bash
niri --version
niri validate
```

If `niri` is older than 26.04, remove the `background-effect { blur true }` blocks from
`~/.config/niri/config.kdl` and reload:

```bash
niri msg action load-config-file
```

Alacritty's transparency (`opacity = 0.85`) is multiplied by niri's global rule
(`opacity 0.90`), resulting in ~0.77 on screen. That is expected.

## Flatpak: “Not allowed to query parental controls data”

If your Fedora version's `accounts-daemon` exposes `com.endlessm.ParentalControls` and the
`malcontent` package is missing, every `flatpak run` fails (flatpak/flatpak#6142). omyfedora
protects/installs `malcontent` when it detects that build.

Check:

```bash
grep -a com.endlessm.ParentalControls /usr/libexec/accounts-daemon
rpm -q malcontent
```

If the interface exists and the package is missing:

```bash
sudo dnf install malcontent
sudo systemctl try-restart accounts-daemon
```

If the daemon does not expose the interface, `malcontent` is not needed and nothing has to be
done.

## RAM above expectations

The **< ~600 MB idle** target assumes the niri/Noctalia session with no heavy apps open.
Browser, Zed, ONLYOFFICE and VMs consume RAM while running. To investigate:

```bash
free -h
ps aux --sort=-rss | head -15
zramctl
balooctl6 status
```

- Baloo (Dolphin's indexer) is disabled by `20-stack.sh`; if it is active, run
  `balooctl6 disable`.
- zram is compressed swap, not a direct reduction of RAM usage; it prevents thrashing when
  memory gets tight.
- Flatpaks and Electron apps are usually the biggest consumers. Close them to measure idle.

## zram is not active

```bash
zramctl
swapon --show
systemctl status dev-zram0.swap
```

The correct file is `/etc/systemd/zram-generator.conf` (the generator **ignores**
`/etc/zram-generator.conf`). `40-tuning.sh` installs and validates the config; re-running the
step and rebooting should enable swap:

```bash
sudo bash scripts/40-tuning.sh
sudo reboot
```

## Monitors, scaling and rotation

Use `Super+P` (the **Niri Displays** plugin) to enable/disable outputs and change resolution,
scale, rotation and position. To inspect or apply from the command line:

```bash
niri msg outputs
niri msg output HDMI-A-1 mode 2560x1080@74.991
niri msg output HDMI-A-1 position set 0 0
```

`pessoal-pc.sh` is a **personal** example of a two-monitor layout; it is not run by the
installer and output names vary from machine to machine.

## NVIDIA and hybrid setups

```bash
nvidia-smi
lsmod | grep nvidia
grep -o 'nvidia-drm.modeset=1' /proc/cmdline
```

- The driver comes from `akmod-nvidia` (there is no `nvidia` package in Fedora or RPM Fusion).
  `10-gpu.sh` enables RPM Fusion free + nonfree, builds the module with `akmods --force` and
  checks it with `modinfo nvidia`. If the build fails, the module will not exist on the next
  boot.
- Wayland requires KMS; `10-gpu.sh` adds `nvidia-drm.modeset=1` through `grubby`. It takes
  effect after reboot.
- With **Secure Boot** enabled, the module needs an enrolled key. If the installer warned:
  `sudo kmodgenca -a`, `sudo mokutil --import /etc/pki/akmods/certs/public_key.der`, reboot and
  finish the enrollment in the firmware menu.
- On hybrid setups, `profile.d/omyfedora-nvidia.sh` does GLX offload to the dGPU. To force the
  iGPU for a specific app:

  ```bash
  __GLX_VENDOR_LIBRARY_NAME=mesa app-name
  ```

- If the driver did not install, run `sudo bash scripts/10-gpu.sh` and reboot.

## Recovering files and going back

- Every overwritten file has a backup next to it with an `.omyfedora-bak` suffix. To restore:

  ```bash
  cp -a /path/file.omyfedora-bak /path/file
  ```

- Personal configs (`niri/config.kdl`, `noctalia/config.toml`, `.zshrc`, `alacritty.toml`,
  `zed/*`) are not overwritten. To return to the default, delete the file and run
  `sudo bash scripts/50-configs.sh`.

- **There is no automatic uninstaller.** The system is still Fedora; installed packages can be
  removed manually and configs restored from backups. If you want to go back to the Plasma
  shell, reinstall the Plasma packages and re-enable `plasmalogin` (or reinstall the base).
  `--skip-remove` prevents removal on a future run.

- To cancel the scheduled Plasma removal before reboot:

  ```bash
  sudo systemctl disable omyfedora-remove-plasma.service
  ```

  This keeps the packages; login still uses greetd/niri until you re-enable `plasmalogin`.

## Collecting information for help

Include in your report:

```bash
cat /etc/fedora-release
niri --version
systemctl --failed
systemctl status greetd
journalctl -b -p warning
ls /var/lib/omyfedora/steps/
free -h
```

Project issues: <https://github.com/marcos2872/omyfedora/issues>.
