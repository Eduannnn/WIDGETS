// Dynamic-Island style media widget that lives in the MacBook notch.
// Run with:  quickshell -p island.qml

import QtQuick
import "."
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Io

ShellRoot {
    id: root

    // ---------- notch calibration ----------
    property real notchWidth: 280
    property real notchHeight: 38
    property bool debugNotch: false
    property string screenName: "eDP-1"

    // ---------- look & behaviour ----------
    property real   wingWidth: 20
    property real   uiScale: 0.58            // expanded player scale
    property real   expandedWidth: 688 * uiScale
    property real   expandedHeight: 334 * uiScale
    property real   compactWidth: Math.max(notchWidth + 80, expandedWidth * 0.94)
    property int    compactPadding: 14
    property real   compactHeight: notchHeight + 40 + compactPadding
    property real   collapsedRadius: 15
    property real   expandedRadius: 70 * uiScale
    property real   earRadius: 16  // the concave corners where the island meets the top of the screen
    property color  accent: "#49fffe"        // Persona cyan accent (used when the cover has no usable colour)
    property bool   tintFromCover: true      // progress bar + waveform take the cover art's main colour
    property color  dim: "#9aa0b4"           // Secondary text
    property string fontFamily: "sans-serif"
    property int    animMs: 280              // Snappy, fast open/close speed
    property int    pausedLingerMs: 12000
    property int    trackPeekMs: 3500
    property int    collapseDelayMs: 350

    // ---------- Cava Audio Integration ----------
    property int    barCount: 6
    property var    levels: []

    function cavaConfig() {
        return [
            "[general]",
            "bars = " + barCount,
            "framerate = 60",
            "autosens = 1",
            "sensitivity = 50",
            "",
            "[input]",
            "method = pipewire",
            "source = auto",
            "",
            "[output]",
            "method = raw",
            "raw_target = /dev/stdout",
            "data_format = ascii",
            "ascii_max_range = 100",
            "bar_delimiter = 59",
            "frame_delimiter = 10",
            "channels = mono",
            "mono_option = average",
            "",
            "[smoothing]",
            "monstercat = 0",
            "waves = 1",
            "noise_reduction = 0.77",
            "ignore = 3",
        ].join("\n");
    }

    Process {
        id: cava
        running: true
        command: ["sh", "-c",
            'cfg="${XDG_RUNTIME_DIR:-/tmp}/qs-notch-cava.conf"; printf "%s\\n" "$CAVA_CFG" > "$cfg"; exec cava -p "$cfg"']
        environment: ({ CAVA_CFG: root.cavaConfig() })

        stdout: SplitParser {
            onRead: data => {
                const parts = data.split(";");
                const out = [];
                for (let i = 0; i < parts.length; i++) {
                    if (parts[i] === "") continue;
                    const level = Number(parts[i]);
                    out.push(Number.isFinite(level) ? Math.max(0, Math.min(1, level / 100)) : 0);
                }
                root.levels = out;
            }
        }

        stderr: SplitParser {
            onRead: data => console.log("notch-cava says: " + data)
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 127) restartTimer.start();
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: cava.running = true
    }

    function pickPlayer() {
        const list = Mpris.players.values;
        let fallback = null;
        for (let i = 0; i < list.length; i++) {
            const p = list[i];
            if (p.playbackState === MprisPlaybackState.Playing) return p;
            if (fallback === null && p.trackTitle !== "") fallback = p;
        }
        return fallback;
    }

    function pickScreen() {
        const list = Quickshell.screens;
        for (let i = 0; i < list.length; i++)
            if (list[i].name === screenName) return list[i];
        return list.length > 0 ? list[0] : null;
    }

    function fmt(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        const m = Math.floor(sec / 60), s = sec % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // ---------- colour picked from the cover art ----------
    // Takes the pixels of a tiny copy of the cover and finds its most prominent *vivid* colour.
    // Dark and grey pixels (usually background) are ignored. The result is then lifted in
    // saturation and brightness so it still reads clearly on the black island.
    function dominantFromPixels(d) {
        const BINS = 24;
        const wt = [], sr = [], sg = [], sb = [];
        for (let i = 0; i < BINS; i++) { wt.push(0); sr.push(0); sg.push(0); sb.push(0); }
        let n = 0, total = 0;
        for (let i = 0; i + 3 < d.length; i += 4) {
            if (d[i + 3] < 128) continue;                       // see-through pixel
            n++;
            const r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255;
            const mx = Math.max(r, g, b), c = mx - Math.min(r, g, b);
            if (mx < 0.18 || c < 0.12) continue;                // near-black or grey
            let h;
            if (mx === r) h = ((g - b) / c + 6) % 6;
            else if (mx === g) h = (b - r) / c + 2;
            else h = (r - g) / c + 4;
            const bin = Math.min(BINS - 1, Math.floor(h / 6 * BINS));
            wt[bin] += c; sr[bin] += r * c; sg[bin] += g * c; sb[bin] += b * c;   // vivid pixels count more
            total += c;
        }
        if (n === 0) return null;
        if (total < 0.03 * n) return { h: 0, s: 0, v: 0.92 };   // black & white artwork -> soft white

        // the hue range (a bin plus its two neighbours) with the most weight wins
        let best = 0, bestScore = -1;
        for (let b = 0; b < BINS; b++) {
            const score = wt[(b + BINS - 1) % BINS] * 0.5 + wt[b] + wt[(b + 1) % BINS] * 0.5;
            if (score > bestScore) { bestScore = score; best = b; }
        }
        let R = 0, G = 0, B = 0, W = 0;
        for (let k = -1; k <= 1; k++) {
            const b = (best + k + BINS) % BINS;
            R += sr[b]; G += sg[b]; B += sb[b]; W += wt[b];
        }
        R /= W; G /= W; B /= W;

        const mx = Math.max(R, G, B), c = mx - Math.min(R, G, B);
        let h = 0;
        if (c > 0) {
            if (mx === R) h = ((G - B) / c + 6) % 6;
            else if (mx === G) h = (B - R) / c + 2;
            else h = (R - G) / c + 4;
            h /= 6;
        }
        return { h: h, s: Math.min(1, Math.max(0.45, c / mx)), v: Math.max(0.85, mx) };
    }

    // the colour actually used by the progress bar and waveform; it fades between songs
    QtObject {
        id: tint
        property bool has: false
        property color picked: "white"
        readonly property color target: (root.tintFromCover && has) ? picked : root.accent
        property color value: target
        Behavior on value { ColorAnimation { duration: 450 } }
    }

    readonly property var  player: pickPlayer()
    readonly property bool playing: player !== null && player.playbackState === MprisPlaybackState.Playing

    property bool shown: false
    property bool peek: false
    property bool hovering: false
    property bool hoverLatch: false
    property bool scrubbing: false
    readonly property bool expanded: shown && (hoverLatch || scrubbing)
    readonly property bool compact: shown && peek && !expanded

    onHoveringChanged: {
        if (hovering) { collapseTimer.stop(); hoverLatch = true; }
        else collapseTimer.restart();
    }

    onPlayingChanged: {
        if (playing) { shown = true; lingerTimer.stop(); }
        else if (shown) lingerTimer.restart();
    }

    // Debounce metadata updates so one track switch produces one peek.
    property bool trackWatchingReady: false
    property var lastPeekPlayer: null
    property var lastPeekTrack: null
    function scheduleTrackPeek() {
        if (trackWatchingReady) trackChangeTimer.restart();
    }
    Component.onCompleted: {
        rememberDuration();
        if (playing) shown = true;
        lastPeekPlayer = player;
        lastPeekTrack = player ? player.uniqueId : null;
        trackWatchingReady = true;
    }
    Timer {
        id: trackChangeTimer
        interval: 180
        onTriggered: {
            const p = root.player;
            if (!p || !p.trackTitle) return;
            if (root.lastPeekPlayer === p && root.lastPeekTrack === p.uniqueId) return;
            root.lastPeekPlayer = p;
            root.lastPeekTrack = p.uniqueId;
            root.shown = true;
            root.peek = true;
            peekTimer.restart();
            if (!root.playing) lingerTimer.restart();
        }
    }

    Timer { id: collapseTimer; interval: root.collapseDelayMs; onTriggered: root.hoverLatch = false }
    Timer {
        id: peekTimer
        interval: Math.max(root.trackPeekMs, compactView.textReadMs)
        onTriggered: root.peek = false
    }
    Timer {
        id: lingerTimer
        interval: root.pausedLingerMs
        onTriggered: { if (root.hoverLatch || root.scrubbing || root.peek) lingerTimer.restart(); else root.shown = false; }
    }

    // Keep the playback clock separate from the pointer's seek preview.
    // Temporary diagnostics: disable after the live seeking issue is resolved.
    property bool debugSeeking: false
    function logSeek(event) {
        if (!debugSeeking) return;
        const p = root.player;
        console.log("island-seek " + JSON.stringify({
            event: event, player: p ? p.identity : null,
            track: p ? p.uniqueId : null,
            position: p ? p.position : null, livePosition: livePos,
            length: p ? p.length : null, duration: root.mediaDuration,
            positionSupported: p ? p.positionSupported : false,
            lengthSupported: p ? p.lengthSupported : false,
            canSeek: p ? p.canSeek : false, scrubbing: scrubbing
        }));
    }
    Connections {
        target: root.player
        function onTrackTitleChanged() { root.scheduleTrackPeek(); }
        function onLengthChanged() { root.rememberDuration(); }
        function onLengthSupportedChanged() {
            root.rememberDuration();
            root.logSeek("length-support-changed");
        }
        function onPositionSupportedChanged() { root.logSeek("position-support-changed"); }
        function onCanSeekChanged() { root.logSeek("seek-support-changed"); }
    }
    Timer {
        id: seekDiagnosticTimer
        interval: 750
        onTriggered: root.logSeek("after-seek")
    }
    // Firefox can drop mpris:length after seeking, while the track stays the same.
    // Never use its unsupported length fallback (which is actually the position).
    property var durationPlayer: null
    property var durationTrack: null
    property real rememberedDuration: 0
    readonly property real mediaDuration: {
        const p = root.player;
        if (!p) return 0;
        if (p.lengthSupported && Number.isFinite(p.length) && p.length > 0) return p.length;
        return durationPlayer === p && durationTrack === p.uniqueId ? rememberedDuration : 0;
    }
    function rememberDuration() {
        const p = root.player;
        const key = p ? p.uniqueId : null;
        if (durationPlayer !== p || durationTrack !== key) {
            rememberedDuration = 0;
            durationPlayer = p;
            durationTrack = key;
        }
        if (p && p.lengthSupported && Number.isFinite(p.length) && p.length > 0)
            rememberedDuration = p.length;
    }

    property real livePos: 0
    readonly property var trackKey: player ? player.uniqueId : null
    onTrackKeyChanged: { resetProgress(); scheduleTrackPeek(); }
    onPlayerChanged: {
        resetProgress();
        logSeek("player-changed");
        scheduleTrackPeek();
        if (player === null) {
            shown = false;
            peek = false;
            peekTimer.stop();
            lingerTimer.stop();
        }
    }
    onExpandedChanged: { if (expanded) refreshPos(); }

    function resetProgress() {
        rememberDuration();
        scrubbing = false;
        livePos = 0;
        refreshPos();
    }

    function refreshPos() {
        const p = root.player;
        if (!p || !p.positionSupported) { root.livePos = 0; return; }
        p.positionChanged();
        const position = p.position;
        root.livePos = Number.isFinite(position) ? Math.max(0, position) : 0;
    }
    Timer {
        interval: 100
        repeat: true
        running: root.expanded && root.player !== null && !root.scrubbing
        onTriggered: root.refreshPos()
    }

    function seekTo(fraction) {
        const p = root.player;
        root.rememberDuration();
        const duration = root.mediaDuration;
        if (!p || !p.canSeek || duration <= 0 || !Number.isFinite(fraction)) return;
        // Stay just inside the track: a relative seek beyond its end can skip it.
        root.logSeek("before-seek");
        const target = Math.min(Math.max(0, duration - 0.01),
                                Math.max(0, Math.min(1, fraction)) * duration);
        if (p.positionSupported) p.position = target;
        else p.seek(target - p.position);
        root.livePos = target;
        root.logSeek("seek-requested");
        seekDiagnosticTimer.restart();
    }

    // ---------- components ----------
    component CoverArt: Item {
        id: art
        property string source: ""
        property real radius: 12

        Rectangle {
            anchors.fill: parent
            radius: art.radius
            color: "#1a1c2b"
            visible: img.status !== Image.Ready
            Text {
                anchors.centerIn: parent
                text: "♪"
                color: root.accent
                font.pixelSize: parent.height * 0.35
            }
        }
        Image {
            id: img
            anchors.fill: parent
            source: art.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 225
            sourceSize.height: 225
            visible: false
        }
        Rectangle {
            id: mask
            anchors.fill: parent
            radius: art.radius
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: img
            maskEnabled: true
            maskSource: mask
            visible: img.status === Image.Ready
        }
    }

    // Shared small waveform for the collapsed and track-change views.
    component MiniWaveform: Row {
        id: miniWaveform
        property bool active: false
        height: 22
        spacing: 3
        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                id: barRect
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: currentHeight
                radius: width / 2
                color: tint.value
                property real currentHeight: 5

                Timer {
                    interval: 16
                    running: miniWaveform.active
                    repeat: true
                    onTriggered: {
                        const rawLevel = root.levels[barRect.index] || 0;
                        const targetVal = root.playing ? 5 + rawLevel * 17 : 5;
                        const lerpFactor = targetVal > barRect.currentHeight ? 0.4 : 0.12;
                        barRect.currentHeight += (targetVal - barRect.currentHeight) * lerpFactor;
                    }
                }
            }
        }
    }

    component GlyphIcon: Canvas {
        id: ic
        property string kind: "play"        // play | pause | next | prev
        property color fg: "white"
        onKindChanged: requestPaint()
        onFgChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = fg;
            ctx.strokeStyle = fg;
            ctx.lineJoin = "round";
            const w = width, h = height;
            const lw = Math.min(w, h) * 0.13;      // stroking the same colour rounds the triangle corners
            const pad = lw / 2;
            ctx.lineWidth = lw;

            function poly(pts) {
                ctx.beginPath();
                ctx.moveTo(pts[0][0], pts[0][1]);
                for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
                ctx.closePath();
                ctx.fill();
                ctx.stroke();
            }

            if (kind === "play") {
                poly([[pad + w * 0.06, pad], [w - pad, h / 2], [pad + w * 0.06, h - pad]]);
            } else if (kind === "pause") {
                const bw = w * 0.38;
                ctx.beginPath();
                ctx.roundedRect(w * 0.05, 0, bw, h, bw * 0.3, bw * 0.3);
                ctx.roundedRect(w * 0.57, 0, bw, h, bw * 0.3, bw * 0.3);
                ctx.fill();
            } else if (kind === "next") {          // fast-forward: two right-pointing triangles
                poly([[pad, pad], [w * 0.5, h / 2], [pad, h - pad]]);
                poly([[w * 0.5, pad], [w - pad, h / 2], [w * 0.5, h - pad]]);
            } else {                               // rewind: two left-pointing triangles
                poly([[w * 0.5, pad], [pad, h / 2], [w * 0.5, h - pad]]);
                poly([[w - pad, pad], [w * 0.5, h / 2], [w - pad, h - pad]]);
            }
        }
    }

    component IconButton: Item {
        id: btn
        property string kind: "play"
        property color fg: "white"
        property bool usable: true
        signal activated()

        opacity: usable ? (ma.containsMouse ? 1 : 0.88) : 0.28
        Behavior on opacity { NumberAnimation { duration: 120 } }
        scale: ma.pressed && usable ? 0.86 : (ma.containsMouse && usable ? 1.12 : 1.0)
        Behavior on scale { NumberAnimation { duration: 90 } }

        GlyphIcon { anchors.fill: parent; kind: btn.kind; fg: btn.fg }
        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.margins: -10
            hoverEnabled: true
            cursorShape: btn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: { if (btn.usable) btn.activated(); }
        }
    }

    // ---------- window ----------
    PanelWindow {
        id: win
        screen: root.pickScreen()

        anchors { top: true }
        implicitWidth: Math.max(root.expandedWidth, root.compactWidth) + 2 * root.earRadius + 40
        implicitHeight: Math.max(root.expandedHeight, root.compactHeight) + 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        mask: Region {
            x: island.x
            y: island.y
            width: root.shown ? island.width : 0
            height: root.shown ? island.height : 0
        }

        Rectangle {
            visible: root.debugNotch
            z: 999
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: root.notchWidth
            height: root.notchHeight
            color: "#ff0033"
        }

        // Invisible 32x32 canvas that loads the cover art and hands its pixels to dominantFromPixels()
        Canvas {
            id: coverProbe
            width: 32
            height: 32
            opacity: 0.01
            z: -1
            renderTarget: Canvas.Image

            property string src: root.player ? root.player.trackArtUrl : ""
            property string previousSrc: ""
            Connections {
                target: root
                function onTintFromCoverChanged() { coverProbe.reload(); }
            }

            function reload() {
                tint.has = false;
                if (previousSrc !== "" && previousSrc !== src) unloadImage(previousSrc);
                previousSrc = src;
                if (src !== "" && root.tintFromCover) {
                    loadImage(src);
                    requestPaint();
                }
            }
            onSrcChanged: reload()
            Component.onCompleted: reload()
            onImageLoaded: requestPaint()

            onPaint: {
                if (!root.tintFromCover || src === "" || !isImageLoaded(src)) return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.drawImage(src, 0, 0, width, height);
                const dom = root.dominantFromPixels(ctx.getImageData(0, 0, width, height).data);
                if (dom) {
                    tint.picked = Qt.hsva(dom.h, dom.s, dom.v, 1);
                    tint.has = true;
                } else {
                    tint.has = false;
                }
            }
        }

        Item {
            id: island
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            opacity: root.shown ? 1 : 0

            width: root.expanded ? root.expandedWidth
                 : root.compact ? root.compactWidth
                 : (root.shown ? root.notchWidth + 2 * root.wingWidth : root.notchWidth)
            height: root.expanded ? root.expandedHeight : root.compact ? root.compactHeight : root.notchHeight

            // Use a subtler screen join while collapsed.
            property real ear: root.expanded ? root.earRadius : root.compact ? 8 : 6
            Behavior on ear { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }

            Behavior on width  { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            HoverHandler {
                onHoveredChanged: root.hovering = hovered
            }

            Rectangle {
                id: body
                property real r: root.expanded ? root.expandedRadius : root.compact ? 24 : root.collapsedRadius
                Behavior on r { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
                y: -r
                width: parent.width
                height: parent.height + r
                radius: r
                color: "black"
            }

            // left ear: a black corner piece with a quarter circle cut out, so the sides of the
            // island flare outward into the top edge of the screen
            Canvas {
                visible: island.ear > 0.5
                width: island.ear + 1
                height: island.ear
                x: -island.ear
                y: 0
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const e = width - 1;
                    ctx.fillStyle = "black";
                    ctx.beginPath();
                    ctx.moveTo(e + 1, 0);
                    ctx.lineTo(e + 1, e);
                    ctx.lineTo(e, e);
                    ctx.arc(0, e, e, 0, -Math.PI / 2, true);
                    ctx.closePath();
                    ctx.fill();
                }
            }
            // right ear: the mirror image
            Canvas {
                visible: island.ear > 0.5
                width: island.ear + 1
                height: island.ear
                x: island.width - 1
                y: 0
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const e = width - 1;
                    ctx.fillStyle = "black";
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(0, e);
                    ctx.lineTo(1, e);
                    ctx.arc(1 + e, e, e, Math.PI, 1.5 * Math.PI, false);
                    ctx.closePath();
                    ctx.fill();
                }
            }

            // everything inside the island is clipped to it while it grows and shrinks
            Item {
                anchors.fill: parent
                clip: true

                // ===== collapsed view =====
                Item {
                    id: collapsedView
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    width: root.notchWidth + 2 * root.wingWidth
                    height: root.notchHeight
                    opacity: root.expanded || root.compact ? 0 : 1
                    visible: opacity > 0.01
                    enabled: !root.expanded && !root.compact
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    CoverArt {
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.top: parent.top
                        anchors.topMargin: 4              
                        height: 26                        
                        width: 26
                        radius: 9
                        source: root.player ? root.player.trackArtUrl : ""
                    }

                    MiniWaveform {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        active: collapsedView.visible
                    }
                }

                // Compact track-change peek sits below the physical camera notch.
                Item {
                    id: compactView
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.compactWidth
                    height: root.compactHeight
                    opacity: root.compact ? 1 : 0
                    visible: opacity > 0.01
                    enabled: root.compact
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    // Leave time to read both ends of any overflowing metadata.
                    readonly property real textReadMs: Math.max(
                        compactTitle.overflow > 0 ? compactTitle.scrollDuration + 2 * compactTitle.readPauseMs : 0,
                        compactArtist.overflow > 0 ? compactArtist.scrollDuration + 2 * compactArtist.readPauseMs : 0)

                    CoverArt {
                        id: compactArt
                        x: root.compactPadding
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.compactPadding
                        width: 40
                        height: 40
                        radius: 11
                        source: root.player ? root.player.trackArtUrl : ""
                    }
                    RibbonText {
                        id: compactTitle
                        x: compactArt.x + compactArt.width + root.compactPadding
                        y: compactArt.y + 2
                        width: Math.max(0, compactWaveform.x - x - root.compactPadding)
                        text: root.player ? (root.player.trackTitle || root.player.identity) : ""
                        fontFamily: root.fontFamily
                        pixelSize: 14
                        active: root.compact
                        resetKey: root.trackKey
                    }
                    RibbonText {
                        id: compactArtist
                        x: compactTitle.x
                        y: compactArt.y + 23
                        width: compactTitle.width
                        text: root.player ? (root.player.trackArtist || root.player.trackAlbum || root.player.identity) : ""
                        fontFamily: root.fontFamily
                        pixelSize: 11.5
                        weight: Font.Normal
                        textColor: root.dim
                        pixelsPerSecond: 24
                        active: root.compact
                        resetKey: root.trackKey
                    }
                    MiniWaveform {
                        id: compactWaveform
                        anchors.right: parent.right
                        anchors.rightMargin: root.compactPadding
                        y: compactArt.y + compactArt.height / 2 - height / 2
                        active: compactView.visible
                    }
                }

                // ===== expanded view =====
                // Coordinates share a reference size of 688 x 334 and scale together.
                Item {
                    id: expandedView
                    property real k: root.uiScale
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    width: root.expandedWidth
                    height: root.expandedHeight
                    opacity: root.expanded ? 1 : 0
                    visible: opacity > 0.01
                    enabled: root.expanded
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    // cover art
                    CoverArt {
                        id: bigArt
                        x: 37 * expandedView.k
                        y: 37 * expandedView.k
                        width: 112 * expandedView.k
                        height: 112 * expandedView.k
                        radius: 22 * expandedView.k
                        source: root.player ? root.player.trackArtUrl : ""
                    }

                    Text {
                        x: 181 * expandedView.k
                        y: 43 * expandedView.k
                        width: 300 * expandedView.k
                        text: root.playing ? "NOW PLAYING" : "PAUSED"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: 14 * expandedView.k
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.5 * expandedView.k
                        elide: Text.ElideRight
                    }

                    // Track metadata stays clear of the playback status and waveform.
                    RibbonText {
                        id: trackTitle
                        x: 181 * expandedView.k
                        y: 78 * expandedView.k
                        width: 456 * expandedView.k
                        text: root.player ? (root.player.trackTitle || root.player.identity) : ""
                        fontFamily: root.fontFamily
                        pixelSize: 26 * expandedView.k
                        active: root.expanded
                        resetKey: root.trackKey
                    }
                    Text {
                        x: 181 * expandedView.k
                        y: 112 * expandedView.k
                        width: 456 * expandedView.k
                        text: root.player ? (root.player.trackArtist || root.player.trackAlbum || root.player.identity) : ""
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: 26 * expandedView.k
                        elide: Text.ElideRight
                    }

                    // level bars, top right, sitting above the title row so the title can use the full width
                    Row {
                        x: 637 * expandedView.k - width
                        y: 60 * expandedView.k - height / 2
                        height: 26 * expandedView.k
                        spacing: 5.5 * expandedView.k
                        Repeater {
                            model: root.barCount

                            Rectangle {
                                required property int index
                                id: barRect
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5 * expandedView.k
                                radius: width / 2
                                color: tint.value

                                property real currentHeight: 6 * expandedView.k

                                Timer {
                                    interval: 16
                                    running: expandedView.visible
                                    repeat: true
                                    onTriggered: {
                                        var rawLevel = root.levels[index] || 0.0;
                                        var targetVal = root.playing ? (6 * expandedView.k + rawLevel * 14 * expandedView.k) : 6 * expandedView.k;
                                        var lerpFactor = targetVal > barRect.currentHeight ? 0.4 : 0.12;
                                        barRect.currentHeight += (targetVal - barRect.currentHeight) * lerpFactor;
                                    }
                                }

                                height: currentHeight
                            }
                        }
                    }

                    // elapsed time, progress bar, time remaining
                    Item {
                        id: progress
                        x: 106 * expandedView.k
                        y: 175 * expandedView.k
                        width: 468 * expandedView.k
                        height: 24 * expandedView.k

                        // Read the player once in each binding: derived capability flags can
                        // briefly outlive their player during MPRIS service replacement.
                        readonly property real duration: root.mediaDuration
                        readonly property bool known: duration > 0
                        readonly property bool seekable: {
                            const p = root.player;
                            return p !== null && p.canSeek && duration > 0;
                        }
                        property real previewRatio: 0
                        readonly property real displayedPosition: root.scrubbing
                                                                 ? previewRatio * duration : root.livePos
                        readonly property real ratio: root.scrubbing ? previewRatio
                            : (duration > 0 ? Math.min(1, Math.max(0, root.livePos / duration)) : 0)

                        function preview(x) {
                            previewRatio = Math.max(0, Math.min(1, x / width));
                        }
                        onSeekableChanged: { if (!seekable) root.scrubbing = false; }

                        Rectangle {
                            id: track
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: (root.scrubbing || seekArea.containsMouse ? 14 : 9) * expandedView.k
                            radius: height / 2
                            color: "#303036"
                            Behavior on height { NumberAnimation { duration: 120 } }
                            Rectangle {
                                width: parent.width * progress.ratio
                                height: parent.height
                                radius: parent.radius
                                color: tint.value
                            }
                        }
                        Rectangle {
                            width: 18 * expandedView.k
                            height: width
                            radius: width / 2
                            x: Math.max(0, Math.min(progress.width - width, progress.width * progress.ratio - width / 2))
                            anchors.verticalCenter: parent.verticalCenter
                            color: "white"
                            opacity: progress.seekable && (root.scrubbing || seekArea.containsMouse) ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            anchors.topMargin: -6
                            anchors.bottomMargin: -6
                            hoverEnabled: true
                            enabled: progress.seekable
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            onPressed: mouse => {
                                progress.preview(mouse.x);
                                root.scrubbing = true;
                                root.logSeek("drag-start");
                            }
                            onPositionChanged: mouse => {
                                if (pressed && root.scrubbing) progress.preview(mouse.x);
                            }
                            onReleased: mouse => {
                                if (!root.scrubbing) return;
                                progress.preview(mouse.x);
                                root.seekTo(progress.previewRatio);
                                root.scrubbing = false;
                            }
                            onCanceled: {
                                root.logSeek("drag-canceled");
                                root.scrubbing = false;
                            }
                        }
                    }
                    Text {
                        x: 43 * expandedView.k
                        y: 176 * expandedView.k
                        text: root.player ? root.fmt(progress.displayedPosition) : ""
                        visible: progress.known
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: 20 * expandedView.k
                        font.weight: Font.DemiBold
                    }
                    Text {
                        x: 647 * expandedView.k - width
                        y: 176 * expandedView.k
                        text: root.player ? "-" + root.fmt(Math.max(0, progress.duration - progress.displayedPosition)) : ""
                        visible: progress.known
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: 20 * expandedView.k
                        font.weight: Font.DemiBold
                    }

                    // rewind  /  play-pause  /  fast-forward, centred on the panel
                    IconButton {
                        width: 51 * expandedView.k
                        height: 30 * expandedView.k
                        x: 231 * expandedView.k - width / 2
                        y: 270 * expandedView.k - height / 2
                        kind: "prev"
                        usable: root.player !== null && root.player.canGoPrevious
                        onActivated: root.player.previous()
                    }
                    IconButton {
                        width: 38 * expandedView.k
                        height: 46 * expandedView.k
                        x: 344 * expandedView.k - width / 2
                        y: 270 * expandedView.k - height / 2
                        kind: root.playing ? "pause" : "play"
                        usable: root.player !== null && root.player.canTogglePlaying
                        onActivated: root.player.togglePlaying()
                    }
                    IconButton {
                        width: 51 * expandedView.k
                        height: 30 * expandedView.k
                        x: 457 * expandedView.k - width / 2
                        y: 270 * expandedView.k - height / 2
                        kind: "next"
                        usable: root.player !== null && root.player.canGoNext
                        onActivated: root.player.next()
                    }
                }
            }
        }
    }
}
