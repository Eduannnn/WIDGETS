# All widgets, one Quickshell instance

Start with:

```sh
quickshell --no-duplicate -p ~/.config/quickshell/WIDGETS
```

The launcher discovers every immediate subfolder with a `shell.qml` entry point.
Add a new widget as `WIDGETS/MyWidget/shell.qml`, then restart the launcher.
Helper QML files are not launched separately. One widget failing to load does not
stop the others; errors appear in the Quickshell log.

The ISLAND, P3R-CLOCK, CAVA, and CALENDAR folders here are links to the existing folders.
Their `shell.qml` files are links to their original entry files, so existing paths
and edits continue to work without separate copies.

For autostart, replace the individual widget services with one service
whose ExecStart uses the command above (with the executable's absolute path in
Nix). Stop/disable the old services when switching to avoid duplicate widgets.
The launcher's --no-duplicate flag prevents a second copy of this launcher;
it does not stop widgets launched separately by the old services.

To exclude a widget from the combined launcher, remove its folder link from
WIDGETS. This leaves the original widget folder untouched.

CALENDAR is an always-visible, transparent, click-through desktop timeline on each screen.
It follows today automatically and sits behind normal windows.

Source files and helper QML files inside linked widget folders are watched
explicitly; edits trigger a debounced reload of the combined shell.
