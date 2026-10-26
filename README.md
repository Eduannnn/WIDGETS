# Quickshell Widgets

A collection of Qt Quick/QML desktop widgets for Linux and Wayland, featuring Persona 3 inspired visuals, animated audio bars, and a notch-style media player. Run all four widgets through one Quickshell instance, or launch them individually.

## Included widgets

| Widget | Description | Main source |
| --- | --- | --- |
| **P3R Clock** | Top-right clock with a hover-to-show date, weekday/weekend banner, animated waves, time-of-day label, and glowing moon glyph. | [`P3R-CLOCK/clock.qml`](P3R-CLOCK/clock.qml) |
| **Calendar** | Transparent, click-through desktop timeline on every screen, with an animated date transition and highlighted moon glyph for the active day. | [`CALENDAR/CalendarView.qml`](CALENDAR/CalendarView.qml) |
| **CAVA** | Full-width audio visualizer along the bottom of the screen, with configurable colors and a fade when audio goes silent. | [`CAVA/cava.qml`](CAVA/cava.qml) |
| **Island** | Notch-style media widget with album artwork, track information, playback controls, seeking, and an audio visualization. | [`ISLAND/island.qml`](ISLAND/island.qml) |

The moon glyphs follow a **visual cycle over each local day**: new at midnight and full at noon. They do not represent astronomical moon phases.

## Requirements

- A Linux Wayland session with a compositor supporting the layer-shell protocol.
- **Quickshell**, including its Qt Quick, Wayland, I/O, and MPRIS modules and Qt Quick Effects support.
- **CAVA**, installed as `cava` on your `PATH`, for the bottom visualizer and Island's audio bars.
- An audio backend supported by your CAVA installation. Both audio widgets default to **PipeWire**.
- An **MPRIS-compatible media player** for Island's track information and controls.
- **Git** to clone the repository, plus standard shell tools including `find` and `readlink`.

The clock and calendar look for Impact, Anton, Bebas Neue, Oswald, Archivo Black, and Arial Black. Install a preferred font for the intended appearance; the calendar falls back to sans-serif.

## Installation

Install Quickshell and CAVA using your distribution's package manager or their upstream installation instructions. No compilation or additional build step is needed for these QML files.

Clone the repository into your Quickshell configuration directory:

```sh
mkdir -p ~/.config/quickshell
git clone https://github.com/ForSaleDev/WIDGETS.git ~/.config/quickshell/WIDGETS
```

Start all widgets:

```sh
quickshell --no-duplicate -p ~/.config/quickshell/WIDGETS
```

Keep the terminal open while checking the initial setup; widget loading errors appear in the output.

### Run a single widget

From the repository directory:

```sh
quickshell -p P3R-CLOCK/clock.qml
quickshell -p CALENDAR
quickshell -p CAVA/cava.qml
quickshell -p ISLAND/island.qml
```

Run only the command for the widget you want. Stop the combined launcher before launching the same widgets separately to avoid overlapping instances.

### Start automatically

Add the combined launch command to your compositor's startup configuration or your desktop's autostart setup. Use absolute paths if your startup mechanism does not expand `~` or resolve `quickshell` through `PATH`.

If replacing individual widget services, disable those services first. `--no-duplicate` prevents another instance of this combined configuration; it does not stop widgets started separately.

## Widget configuration

Settings are QML properties inside each widget's source file. Edit the values directly and save. The combined launcher watches QML sources and helper files and reloads automatically after a short delay. Restart it after adding or disabling widgets.

### P3R Clock

Edit [`P3R-CLOCK/clock.qml`](P3R-CLOCK/clock.qml):

- `anchors` and `margins`: screen placement and distance from the edges.
- `horizontalScale` and `topPad`: proportions and space above the lettering.
- `fontChoices`: preferred display fonts, in priority order.
- `accentCyan`, `moonYellow`, and `ink`: accent, moon, and shadow colors.
- `animateWaves`: enable or freeze the background animation.
- `labelHeight`, `labelBaseline`, and `labelGap`: banner typography.

Hover over the widget to show the date instead of the digital clock.

### Calendar

Edit [`CALENDAR/CalendarView.qml`](CALENDAR/CalendarView.qml) for `moonColor` and `transitionMs` (the date scroll duration in milliseconds). Its layout scales from a 1440 × 900 reference stage to fit each screen.

Edit [`CALENDAR/shell.qml`](CALENDAR/shell.qml) to change the font preference list or date-preview settings. Keep `debugDateCycle: false` and `debugDayOffset: 0` for normal use. Setting `debugDateCycle` to `true` advances the preview date every ten seconds.

### CAVA visualizer

Edit [`CAVA/cava.qml`](CAVA/cava.qml):

- `bars`, `barGap`, `maxHeight`, and `topRadius`: bar count and shape. Odd bar counts are rounded up to an even number.
- `sensitivity` and `curve`: response to audio levels.
- `barTop`, `barBottom`, and `barOpacity`: appearance.
- `silenceThreshold`, `silenceHoldMs`, and `fadeMs`: silence detection and fading.
- `inputMethod`: audio backend, such as `"pipewire"`, `"pulse"`, or `"alsa"`, depending on your CAVA build.

### Island media widget

Edit [`ISLAND/island.qml`](ISLAND/island.qml):

- `screenName`: target output, initially `"eDP-1"`. The first available screen is used if no output matches.
- `notchWidth`, `notchHeight`, and `wingWidth`: fit around your screen's notch or desired top-center area.
- `debugNotch`: show a calibration rectangle while adjusting placement.
- `uiScale`, `animMs`, and `collapseDelayMs`: size and animation timing.
- `accent`, `tintFromCover`, and `fontFamily`: appearance and artwork-based coloring.
- `barCount`: audio bar count. Change the audio backend inside `cavaConfig()` if needed; Island has its own CAVA configuration.

Play media in an MPRIS-compatible application, then hover over Island to expand it. Available controls and seeking depend on what the player supports.

Both audio widgets generate their CAVA configuration at runtime; there is no separate CAVA configuration file to install.

## Enable, disable, or add widgets

The root [`shell.qml`](shell.qml) loads every immediate subdirectory containing a `shell.qml` entry point. Helper components are not launched independently, and a widget loading error is logged without preventing the others from loading.

To disable a widget without deleting its source, rename its entry point and restart the launcher:

```sh
mv CAVA/shell.qml CAVA/shell.qml.disabled
```

To enable it again:

```sh
mv CAVA/shell.qml.disabled CAVA/shell.qml
```

Some entry points are relative symlinks to the widget's main QML file. Preserve those links and their targets when moving or copying files.

To add a widget, create `MyWidget/shell.qml` inside this repository and restart the launcher. Existing `.qml.bak` files are source snapshots and are not loaded as widgets.

## Troubleshooting

- **Nothing appears:** run the launcher from a terminal and check for missing QML modules or layer-shell support. These widgets are intended for Wayland.
- **Duplicate widgets:** stop older individual launches or autostart services, then start the combined launcher once.
- **No audio bars:** confirm `cava` is on `PATH`, play audio, and check that each widget's configured audio backend matches your setup.
- **Island has no track information:** use a player with MPRIS support. Enable its media integration if required.
- **Island appears on the wrong screen:** set `screenName` to your output's name and adjust the notch dimensions.
- **Text is clipped or looks different:** install a preferred display font, then adjust the relevant font and layout properties.

## Contributing

Keep changes focused on the affected widget. Run it locally, check the logs for QML errors, and include screenshots for visual changes. See [`AGENTS.md`](AGENTS.md) for the repository's contributor guidelines.

## AI disclosure

AI was used to add comments to all files.
