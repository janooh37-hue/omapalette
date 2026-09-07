# Omapalette

**Point it at your wallpaper collection and watch it dress your desktop.**

Omapalette is an Omarchy bar widget that turns theme switching into a colour
decision. It reads the palette of every wallpaper you own, and every theme card
in its popup shows you the wallpaper that switching will actually apply — the
one that already speaks that theme's colours. Click a colour instead of a theme
and it generates a brand new theme out of it.

In the bar it stays quiet: the active theme's palette as small circles that
morph into one continuous capsule on hover, and crossfade in place when the
theme changes.

![Omapalette popup over the Omarchy bar](docs/screenshot.png)

![Omapalette on the desktop](docs/screenshot-desktop.jpg)

## Install

```bash
omarchy plugin add https://github.com/janooh37-hue/omapalette --enable
```

`--enable` adds `{ "id": "omapalette" }` to the `right` section of the bar in
`~/.config/omarchy/shell.json`. To place it yourself instead:

```bash
omarchy plugin add https://github.com/janooh37-hue/omapalette
omarchy plugin enable omapalette --section right
```

The shell hot-reloads; the widget appears without a restart. Build the wallpaper
palette index once (about 25s for ~1000 wallpapers, then cached):

```bash
~/.config/omarchy/plugins/omapalette/bin/omapalette index --rebuild
```

## Removal

```bash
omarchy plugin remove omapalette
rm -rf ~/.cache/omapalette
```

`omarchy plugin remove` deletes the plugin directory and drops the widget from
`shell.json`. The second command clears the wallpaper palette cache. Themes and
wallpapers the plugin applied stay as they are; the background symlinks it wrote
live in `~/.config/omarchy/backgrounds/<theme>/omapalette-*` and can be deleted
with `rm ~/.config/omarchy/backgrounds/*/omapalette-*`.

## Requirements

| Dependency | Why | Where it comes from |
|---|---|---|
| Omarchy 4 (Quattro) shell | plugin host | ships with Omarchy |
| `aether` | palette extraction and theme generation | Arch package `aether` (install it with your package manager) |
| `python3` ≥ 3.11 | `bin/omapalette` engine (`tomllib`) | ships with Arch |

The plugin never installs anything itself; install `aether` yourself before
enabling the widget.

Nothing is downloaded at runtime. `bin/omapalette` only reads theme `colors.toml`
files and your wallpapers, and shells out to `aether`, `omarchy-theme-set`,
`omarchy-theme-bg-set` and `omarchy-theme-bg-current` with argument lists (no
shell interpolation).

## Layout

```
manifest.json      bar-widget plugin manifest (id: omapalette)
Palette.qml        widget + popup (root type: qs.Ui.Panel)
PaletteDots.qml    the morphing circle row
PaletteData.js     colors.toml parsing + label helpers
bin/omapalette     palette engine (index / map / match / apply)
```

## Interactions

Bar widget:

| Input | Action |
|---|---|
| hover | morph circles → capsule, tooltip `<theme> — <wallpaper>` |
| left click | open the theme popup |
| right click | next palette-matched wallpaper |
| middle click | random palette-matched wallpaper |
| scroll | next / previous matched wallpaper |

Popup:

| Input | Action |
|---|---|
| click a theme card | apply that theme + its best matched wallpaper |
| right click the current card | next matched wallpaper |
| click a colour in the header row | generate a whole new theme from that colour (aether) |
| arrows / hjkl | move the card cursor |
| enter / space | apply the selected theme |
| `w` / `b` | next / previous matched wallpaper |
| `r` | rebuild the wallpaper palette index |
| esc | close |

IPC (`omarchy-shell omapalette <method> [arg]`):
`open`, `close`, `toggle`, `apply <theme>`, `wallpaper <best|next|prev|random>`,
`generate <#hex>`, `reindex`, `morph`.

## How matching works

`bin/omapalette` asks `aether --extract-palette --json` for each wallpaper in
`~/Pictures/wallpapers/active_theme` (override with `OMAPALETTE_WALLPAPERS`)
and caches the 16-colour result in `~/.cache/omapalette/index.json`, keyed by
mtime+size. Cold indexing of ~1000 wallpapers takes ~25s at 16 jobs; warm runs
are ~0.1s.

A wallpaper's cost against a theme is computed in OKLab:

- **accent cost** — mean over the theme's `red green yellow blue magenta cyan`
  of the distance to the nearest wallpaper accent slot (lightness weighted 1.6,
  because hue mismatch reads louder than lightness mismatch),
- **background cost** — theme `background` vs the wallpaper's background slot
  (weight 0.75),
- **saturation agreement** — |mean theme chroma − mean wallpaper chroma|
  (weight 1.5), which stops a grey wallpaper from winning a vivid theme just by
  being "not far" from every accent,
- **mode penalty** — 0.35 when a dark theme meets a light wallpaper or vice
  versa.

The per-theme top 12 is cached in `~/.cache/omapalette/map.json` and
invalidated by an index signature, so the popup can show previews instantly.

## Legibility rules

A theme palette is authored against *its own* background, so anything painted on
a different surface has to be re-checked or it renders invisible. Helpers live in
`PaletteData.js` (`contrast`, `legible`, `visible`) and are WCAG
relative-luminance based; fixes are hue-preserving (the colour is mixed toward
white/black only until it clears the ratio).

| Surface | Painted with | Minimum |
|---|---|---|
| card band (solid theme background) | theme `foreground` | 4.5 |
| card border / current marker | theme `accent` | 2.2 |
| card + header + bar swatches | palette colours | 1.9 (seen, not read) |
| popup title | `Color.popups.text` | 4.5 |
| popup captions | `Color.muted` | 3.0 |

Theme cards keep the wallpaper preview in the top band only. Text never sits on
a photo — a light theme over a bright wallpaper used to render its label at
1.0:1.

## What applying a theme does

`omapalette apply <slug>`:

1. symlinks the top 12 matches into `~/.config/omarchy/backgrounds/<slug>/` as
   `omapalette-NN.<ext>` (replacing the previous `omapalette-*` links), so omarchy's
   own `omarchy-theme-bg-next` and background switcher cycle inside the matched
   set;
2. runs `omarchy-theme-set <slug>` with `OMARCHY_THEME_SKIP_BACKGROUND=1`, so
   the palette hot-swaps without omarchy choosing its own background;
3. runs `omarchy-theme-bg-set <match>` for the crossfade.

`omapalette from-color '#rrggbb'` instead finds the wallpaper that carries that
colour most convincingly and hands it to `aether --generate`, which builds and
applies a fresh theme from it.

Every one of these actions is user-initiated (click, key, or IPC call). The
plugin writes nothing on load beyond its own cache under
`~/.cache/omapalette/`.

## CLI

```
omapalette themes                  # installed themes + swatches (JSON)
omapalette current                 # active theme + swatches (JSON)
omapalette index [--rebuild]       # refresh the wallpaper palette cache
omapalette map [--refresh]         # per-theme matched wallpapers (JSON)
omapalette match --theme gruvbox -n 5
omapalette match --color '#d3869b' -n 5
omapalette apply gruvbox [--pick best|next|prev|random] [--keep-wallpaper]
omapalette wallpaper [theme] [--pick next]
omapalette from-color '#d3869b' [--light] [--mode <aether-extract-mode>]
```

## Settings

Inline keys on the `shell.json` layout entry:

```json
{ "id": "omapalette", "dots": 6, "dotSize": 7, "columns": 3, "rows": 4, "autoIndex": true }
```

`dots` swatch count (2-8) · `dotSize` circle diameter before text scaling ·
`columns`/`rows` popup grid · `autoIndex` refresh the wallpaper cache ~8s after
login.

## License

[MIT](LICENSE)
