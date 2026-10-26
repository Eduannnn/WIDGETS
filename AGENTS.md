# Repository Guidelines

## Project Structure & Module Organization

This repository contains Qt Quick/QML desktop widgets for Quickshell on Wayland. The root `shell.qml` discovers immediate subdirectories containing a `shell.qml` entry point and watches QML sources for automatic reloads.

- `CALENDAR/`: `CalendarView.qml` draws the date timeline; `shell.qml` supplies clocks and screen windows.
- `P3R-CLOCK/`: `clock.qml` implements the clock and moon phase.
- `CAVA/`: `cava.qml` draws the audio visualizer using the external `cava` executable.
- `ISLAND/`: `island.qml` implements the media widget; `RibbonText.qml` is a helper component.
- `qmldir` files register reusable components. Some widget entry points are symlinks; preserve their targets.

There are no dedicated test or static asset directories. Most artwork is drawn with Canvas and QML primitives.

## Build, Test, and Development Commands

Run commands from this directory:

```sh
quickshell --no-duplicate -p .    # Launch all widgets
quickshell -p CALENDAR           # Preview the calendar
quickshell -p P3R-CLOCK/clock.qml # Preview the clock
quickshell -p CAVA/cava.qml      # Preview the visualizer
quickshell -p ISLAND/island.qml  # Preview the media widget
```

No separate build step is required. Use a Wayland session with Quickshell installed; audio visualizations also require `cava`. Stop a combined instance before previewing the same widget separately to avoid duplicates.

## Coding Style & Naming Conventions

Use four-space indentation, camelCase IDs, properties, and JavaScript functions, and PascalCase reusable component filenames. Follow the surrounding QML style; use semicolons in JavaScript blocks. Keep configurable dimensions, colors, and timings in properties. Request Canvas repaints when drawing inputs change. No repository formatter or lint configuration is present.

## Testing Guidelines

No automated test framework or coverage threshold is configured. Validate changed widgets by launching them and checking Quickshell logs for QML errors. Visually check scaling, clipping, animations, and relevant states such as moon phases, date transitions, hover behavior, and audio silence. Offscreen checks can exercise drawing code; verify final appearance in Wayland.

## Commit & Pull Request Guidelines

Git history is unavailable in this checkout, so no existing commit convention can be established. Use concise imperative subjects, such as `Add calendar moon boundary glow`. Keep changes focused. Pull requests should describe behavior changes, list validation performed, link relevant issues, and include screenshots for visual changes. Preserve existing `.qml.bak` snapshots unless updating them is explicitly requested.
