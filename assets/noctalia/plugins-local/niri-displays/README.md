# Niri Displays

Inspect connected outputs and change display settings directly from Noctalia. The plugin uses Niri's IPC to expose per-output enable/disable, resolution, refresh-rate, scale, rotation (transform), position, and focused-output state. Changes apply immediately and can be persisted to Niri's config so they survive a restart.

## Plugin

| Field | Value |
| --- | --- |
| ID | `raycursive/niri-displays` |
| Entries | Bar widget: `bar`; panel: `panel`; service: `displays` |

## Requirements

- Noctalia plugin API 9 or newer (used for closure-backed display controls).
- The `niri` executable on `PATH`, with a running Niri session and `NIRI_SOCKET` available to Noctalia.
- A Niri version that supports the `niri msg output` IPC commands.

## Usage

Enable `raycursive/niri-displays` in **Settings → Plugins**, then add the `bar` entry from **Settings → Bar → Widgets**. The `displays` service starts automatically, watches Noctalia's output-change hook, and uses slow polling as a recovery fallback.

Click the bar widget to open the `panel` entry. Each connected output shows its connector, make/model, focused state, current mode, refresh rate, scale, rotation, and position. Select a mode, refresh rate, or rotation reported by Niri, adjust the position, or drag the scale slider, to apply a temporary change. Press **Persist** in the footer to write the current state of every connected output to Niri's configuration and reload it.

The **Enabled** toggle at the top of each card runs `niri msg output <port> on` or `off`. A disabled output stays listed with its controls greyed out, so it can be switched back on at any time. The last enabled output is protected: its toggle is locked and labelled "Only display" so a session can never be left without a screen.

## Persistence

**Persist** writes the current state of all connected outputs to `~/.config/niri/msbos-displays.kdl` and ensures the main `config.kdl` ends with:

```kdl
include "msbos-displays.kdl"
```

Niri includes are positional, so the managed block only overrides the keys it defines (mode, scale, transform, position, or `off`) and leaves the rest of your output config — including per-output `layout` blocks — untouched. The setting survives a restart or config reload.

Before reloading, the service runs `niri validate -c ~/.config/niri/config.kdl`; if validation fails, both files are restored to their previous contents. On the first write, the original `config.kdl` is kept as `config.kdl.msbos-bak`. Requires Niri 25.11 or newer for `include` support.

Open the panel without the bar widget with:

```sh
noctalia msg panel-toggle raycursive/niri-displays:panel
```

### Scale presets

Each `scale_presets` item uses one of these forms:

```text
WIDTHxHEIGHT=SCALE
PORT:WIDTHxHEIGHT=SCALE
```

For example:

```text
3840x2160=1.5
2560x1440=1
DP-3:1920x1080=1.25
```

A port-specific preset wins over a global preset for the same resolution. At the same specificity, the last valid matching item wins. Presets match the resolution exactly and are applied after a resolution change, including changes detected outside the panel; refresh-rate-only changes do not reapply them.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `scale_presets` | `string_list` | empty | Global or per-connector `resolution=scale` mappings applied after matching resolution changes. |
| `refresh_interval` | `int` | `30` seconds | Recovery polling interval, limited to 5–300 seconds; normal output updates are event-driven. |
| `glyph` | `glyph` | `device-desktop` | Glyph used by this bar-widget instance. |
| `show_resolution` | `bool` | `true` | Shows the focused connector and resolution beside the bar glyph; disable for icon-only display. |

## IPC

The `displays` service accepts these events:

```sh
# Query Niri for a fresh output snapshot.
noctalia msg plugin raycursive/niri-displays:displays all refresh

# Write the current output state to Niri's config and reload it.
noctalia msg plugin raycursive/niri-displays:displays all persist

# Write the normalized output snapshot to the Noctalia log.
noctalia msg plugin raycursive/niri-displays:displays all dump
```

## Notes

- Discovery spawns `niri msg --json outputs` and `niri msg --json focused-output`. Changes spawn `niri msg output <connector> mode ...`, `niri msg output <connector> scale ...`, `niri msg output <connector> transform ...`, or `niri msg output <connector> position ...`.
- Niri intentionally does not persist these IPC changes to `config.kdl`; use **Persist** to write them to the managed include file.
- A matching scale preset can change output scale automatically when the service starts, reloads, detects a resolution change, or receives a settings change.
- Apart from the managed Niri file written by **Persist**, the plugin does not write files or make network requests. Command errors are shown without discarding the last successful in-memory output snapshot.
