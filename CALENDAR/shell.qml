import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

ShellRoot {
    id: root
    // Temporary preview: set false to return to the real date.
    property bool debugDateCycle: false
    property int debugDayOffset: 0
    onDebugDateCycleChanged: { if (!debugDateCycle) debugDayOffset = 0; }
    Timer {
        interval: 10000
        repeat: true
        running: root.debugDateCycle
        onTriggered: root.debugDayOffset++
    }
    SystemClock { id: clock; precision: SystemClock.Seconds }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            CalendarView {
                anchors.fill: parent
                now: clock.date
                debugDayOffset: root.debugDayOffset
                displayFont: {
                    const installed = Qt.fontFamilies();
                    for (const name of ["Impact", "Anton", "Bebas Neue", "Oswald", "Archivo Black", "Arial Black"])
                        if (installed.indexOf(name) >= 0) return name;
                    return "sans-serif";
                }
            }
        }
    }
}
