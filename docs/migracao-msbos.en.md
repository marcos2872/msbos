# Migration to msbos

This document is for systems still named **omyfedora** or **MyOS** that should
become **msbos** without reinstalling Fedora.

## What happens

`install.sh` now has two migration steps:

- `scripts/00-migrate-names.sh` — runs before everything. It disables old units
  (without stopping the session), moves state and settings that the installer
  does not overwrite, and fixes paths in user files. Nothing is deleted.
- `scripts/99-cleanup-legacy.sh` — runs at the end, after the new files exist.
  It removes old binaries, units, policies, the Plymouth theme and directories.
  Backups are moved to `/var/backups/msbos-migration/legacy-*` or
  `~/.local/state/msbos/migration-backups/legacy-*`.

On a fresh installation both steps are no-ops.

## How to migrate

```bash
# 1. simulate and read the output
./install.sh --dry-run

# 2. apply; --yes authorizes removing the old artifacts
sudo ./install.sh --yes

# 3. reboot so greetd, Plymouth and the units take effect
sudo reboot

# 4. check
msbos-doctor --strict
```

Without `--yes`, the new installation is applied but old-name cleanup stays
pending; run it again with `--yes` to finish.

## What is preserved

- `/etc/msbos/allowed-units.list` and `protected.list`;
- `/var/log/msbos/actions.log` (the old trail is appended);
- wallpapers in `~/.config/msbos-walls/` and `/usr/share/msbos-walls/`;
- `~/.config/niri/config.kdl`, `~/.config/noctalia/config.toml` and
  `~/.local/state/noctalia/settings.toml` (paths are fixed, customizations stay);
- `~/.agents/skills/msbos/references/local.md` and the
  `~/.local/state/msbos/agent-changes.log` history;
- existing backups, archived in the migration directory.

## Rollback

Before migrating, take a system snapshot (btrfs/snapper) or copy `/etc`,
`/usr/local`, `/usr/share/omyfedora*` and the user settings. The migration logs
every move; to roll back, restore the snapshot or the backups. If you need the
old code, use tag `v0.2.0` in a separate clone.

## AI Chat plugin

The `omyfedora/ai-chat` plugin is a separate project
(`marcos2872/omyfedora-ai-chat`). It may still show the old name until it is
renamed and released; that does not affect the system or the privileged helper.
