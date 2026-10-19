# Daily use

[Português](uso.md) · [English](uso.en.md)

After rebooting, **greetd** presents the **niri** session. Noctalia v5 draws the bar, launcher,
notifications, OSD and lock screen; KDE apps remain available and use **Breeze Dark**.

## Shortcuts

The shortcuts below are the defaults installed in `~/.config/niri/config.kdl`. If you edit the
file, your choices are preserved when the installer runs again.

### Noctalia and apps

| Shortcut | Action |
|---|---|
| `Super+Space` or `Super+D` | Noctalia launcher |
| `Super+S` | Control center |
| `Super+Shift+Comma` | Noctalia settings |
| `Super+P` | Display manager (Niri Displays plugin) |
| `Alt+Tab` | Window switcher (hold to navigate) |
| `Super+Alt+L` | Lock the session |
| `Super+T` / `Super+Shift+T` | Terminal (alacritty) |
| `Super+B` | Brave |
| `Super+E` | Zed |
| `Print` | Screenshot (niri UI) |
| `Ctrl+Print` | Full-screen screenshot |
| `Alt+Print` | Focused-window screenshot |

### Windows and columns (niri)

| Shortcut | Action |
|---|---|
| `Super+O` | Overview |
| `Super+Q` | Close the window |
| `Super+Arrows` or `Super+H/J/K/L` | Focus column/window |
| `Super+Ctrl+Arrows` or `Super+Ctrl+H/J/K/L` | Move column/window |
| `Super+Shift+Arrows` or `Super+Shift+H/J/K/L` | Focus the neighboring monitor |
| `Super+Shift+Ctrl+Arrows` or `Super+Shift+Ctrl+H/J/K/L` | Move the column to another monitor |
| `Super+R` / `Super+Shift+R` | Cycle preset column width (forward/backward) |
| `Super+Ctrl+Shift+R` | Cycle preset window height |
| `Super+Ctrl+R` | Reset window height |
| `Super+Minus` / `Super+Equal` | Decrease/increase column width |
| `Super+Shift+Minus` / `Super+Shift+Equal` | Decrease/increase window height |
| `Super+F` | Maximize the column |
| `Super+Shift+F` | Fullscreen |
| `Super+M` | Maximize the window to the edges |
| `Super+Ctrl+F` | Expand the column to the available width |
| `Super+C` / `Super+Ctrl+C` | Center the column / visible columns |
| `Super+V` | Toggle floating window |
| `Super+Shift+V` | Switch focus between floating and tiling |
| `Super+W` | Toggle column tabbed display |
| `Super+Comma` / `Super+Period` | Consume window into column / expel from column |
| `Super+BracketLeft` / `Super+BracketRight` | Consume or expel to the left/right |
| `Super+Shift+Slash` | Hotkey overlay |
| `Super+Shift+P` | Power off monitors |
| `Super+Shift+E` or `Ctrl+Alt+Delete` | Quit niri |
| `Super+Escape` | Inhibit compositor shortcuts |

### Workspaces

| Shortcut | Action |
|---|---|
| `Super+1`…`Super+9` | Go to workspace 1…9 |
| `Super+Ctrl+1`…`Super+Ctrl+9` | Move the column to workspace 1…9 |
| `Super+U` / `Super+I` or `Super+Page_Down` / `Super+Page_Up` | Workspace down/up |
| `Super+Ctrl+U` / `Super+Ctrl+I` | Move the column to the workspace down/up |
| `Super+Shift+U` / `Super+Shift+I` | Move the workspace down/up |
| `Super+Home` / `Super+End` | First/last column |
| `Super+Ctrl+Home` / `Super+Ctrl+End` | Move the column to the first/last position |

Everything else (mouse wheel with `Super`, resizing, etc.) follows niri's defaults. The full
compositor reference is at <https://github.com/YaLTeR/niri/wiki>.

## Noctalia v5

Noctalia is the desktop shell: bar, launcher, notifications, OSD, control center, lock screen
and wallpaper. The default look is **Liquid Glass** with the `macOS` palette: translucent top
bar, half-height auto-hiding dock, glass panels and faster animations.

### The two configuration layers

Noctalia v5 assembles its configuration in layers. Two matter in omyfedora:

| Layer | File | Contents | Written by |
|---|---|---|---|
| Style | `~/.config/noctalia/config.toml` | Theme, palette, bar, dock, panels, animations | omyfedora (installed once; you may edit) |
| State/GUI | `~/.local/state/noctalia/settings.toml` | Widget lists, wallpaper, plugins, lock-screen geometry, persisted `[dock]` | The Noctalia GUI |

`settings.toml` is read **last** and wins key by key. So if an appearance change “does not
stick”, there is almost always a duplicate key there. `config.toml` holds style;
`settings.toml` holds what the GUI rewrites. Avoid editing `settings.toml` by hand.

Supporting files in `~/.config/noctalia/`:

- `90-greeter-sync.toml` — enables Auto-Sync of the appearance with the login screen (omyfedora
  updates this file).
- `91-widget-control-center.toml` — control-center icon in the bar (rendered with the user's
  home path).
- `palettes/macOS.json` — theme palette. omyfedora owns and updates it with an
  `.omyfedora-bak` backup; to use another one, create a new palette in `palettes/` and point
  `custom_palette` in `config.toml` to it.

Default plugins: **tmelik/system-monitor** (CPU/RAM) and **raycursive/niri-displays** (displays).
Community plugins live in `~/.local/state/noctalia/plugins/`; local plugins live in
`~/.local/share/noctalia/plugins/`. The installer only copies a plugin when it does not exist
yet.

### Wallpaper

**Noctalia owns the wallpaper.** The default is
`/usr/share/omyfedora-walls/wp11280214-rx7-4k-wallpapers.jpg`, set in `settings.toml`. Change
it through Noctalia itself (Settings → Wallpaper) — the choice is persisted and Auto-Sync
carries it to the login screen.

The `omyfedora-wallpaper` helper is a **fallback** for sessions without Noctalia: it uses
`swaybg` and looks for the first image in alphabetical order in:

1. `~/.config/omyfedora-walls/` (user, takes precedence)
2. `/usr/share/omyfedora-walls/` (system)

Accepted formats: PNG, JPG/JPEG and WebP. With no images, it uses the solid color `#0B0B0D`.
The helper's `spawn-at-startup` is commented out in `config.kdl` precisely because Noctalia
already handles the wallpaper.

## App theme: Breeze Dark

omyfedora does not install a theme of its own. Apps use **Breeze Dark**, KDE's default dark
theme, while Noctalia keeps its own look (it is not Qt/GTK).

- **Qt/KDE**: `~/.config/kdeglobals` gets `ColorScheme=BreezeDark`, `widgetStyle=Breeze`,
  `breeze-dark` icons and `breeze_cursors`; `plasma-integration` provides the Qt platform theme
  through `QT_QPA_PLATFORMTHEME=kde`.
- **GTK**: `~/.config/gtk-3.0/settings.ini` and `gtk-4.0/settings.ini`, the system default in
  `/etc/dconf/db/local.d/00-omyfedora-dark` and the user's `gsettings` set `gtk-theme=Breeze`,
  `color-scheme=prefer-dark`, `icon-theme=breeze-dark` and the `breeze_cursors` cursor.
- **Compatibility**: `pam-kwallet` unlocks the KWallet vault at login; `xdg-desktop-portal-kde`
  and `polkit-kde` remain installed for KDE apps.

The installer only **fills keys that are still empty**. If you change the theme through
**System Settings**, that choice is yours forever: omyfedora does not override it. Theme files
owned by the project (GTK, dconf, `profile.d`) are updated with a backup.

## Default apps

The installer sets these for the target user:

| Type | App |
|---|---|
| Browser (http/https) | Brave |
| File manager | Dolphin |
| Text editor | KWrite |
| Images | Gwenview |
| PDF | Okular |
| Video | Dragon Player |
| Audio | Elisa |

To change them, use KDE settings or `xdg-settings`/`xdg-mime`. The installer sets these
defaults and reapplies them when you run the `50-configs.sh` step (or `install.sh`) again.

## Personal configurations

These files are installed **only when they do not exist yet** (`install_file_once`):

- `~/.config/niri/config.kdl`
- `~/.config/noctalia/config.toml`
- `~/.config/alacritty/alacritty.toml`
- `~/.zshrc`
- `~/.config/zed/settings.json` and the other files from `assets/zed/`
- `~/.face` (default avatar)
- `~/.config/autostart/sealertauto.desktop` and `org.kde.xwaylandvideobridge.desktop`

Re-running the installer does not overwrite these files. To return to the omyfedora default,
delete the file and run the responsible step:

```bash
rm ~/.config/niri/config.kdl
sudo bash scripts/50-configs.sh
```

Files owned by omyfedora — `/etc/xdg/niri/config.kdl`, theme assets, wallpapers, helpers,
`90-greeter-sync.toml`, `91-widget-control-center.toml` and the palette — are updated with an
`.omyfedora-bak` backup. `settings.toml` and plugins are only installed when absent.

## Login screen (greetd + Noctalia Greeter)

`greetd` replaces Plasma Login Manager. **Noctalia Greeter** comes from the community **Terra**
repository; with `--no-greeter`, greetd uses its default text greeter and Noctalia remains the
session shell.

`90-greeter-sync.toml` enables **Auto-Sync**: changes to wallpaper, palette, theme and font are
copied to the login screen. The installer enables passwordless sync through a Polkit rule
restricted to the greeter action and triggers a **Sync Now** at the end. After logging in, you
can repeat it manually:

```bash
noctalia msg greeter-sync
```

If the wallpaper does not appear at login, check `/var/lib/noctalia-greeter/sync.toml` and the
session shell in `/etc/shells` (`pkexec` requires the shell to be listed). More details in
[Troubleshooting](solucao-de-problemas.en.md#wallpaper-does-not-appear-on-the-login-screen).

## Plasma shell removal

On a Fedora KDE base, the installer **schedules** the Plasma shell removal for the next boot,
before login, through `omyfedora-remove-plasma.service`. It does not happen in the live session
because the plasmalogin/plasma-* scriptlets touch systemd services and would kill the session
in the middle of the dnf transaction.

What goes away: `plasma-desktop`, `plasma-workspace`, `plasma-login-manager`, `plasma-setup`
and `plasma-welcome`. What stays: **all KDE apps** (Dolphin, Konsole, Kate/KWrite, Okular,
Gwenview, Spectacle, Dragon, Elisa, plasma-discover…) and the packages that keep KDE styling
and portals working (`plasma-integration`, `plasma-breeze`, `plasma-systemsettings`,
`polkit-kde`, `xdg-desktop-portal-kde`, `pam-kwallet`, `kde-gtk-config`, `konsole`).

To follow it:

```bash
systemctl status omyfedora-remove-plasma
journalctl -u omyfedora-remove-plasma -n 50
```

If removal fails (for example, no network at boot), the service stays enabled and tries again
on the next boot. With `--skip-remove`, the Plasma shell remains installed, but login already
goes to greetd/niri.

## Updates

omyfedora does not install automatic updates; `dnf-automatic` is disabled on purpose. Update
manually when you want:

```bash
sudo dnf upgrade --refresh
sudo reboot   # required for kernel, driver and initramfs
```

Re-running the installer is also safe and idempotent:

```bash
sudo ./install.sh
```

It reapplies whatever is missing, preserves your personal configs and updates the files owned
by the project (with backup). Zed and OpenCode update themselves through their official
installers; `lazydocker` can be reinstalled by the `20-stack.sh` step.

## Next steps

- [Troubleshooting](solucao-de-problemas.en.md) — if something does not work.
- [Architecture and steps](arquitetura.en.md) — to understand what each script does.
- [Credits](creditos.en.md) — the projects behind omyfedora.
