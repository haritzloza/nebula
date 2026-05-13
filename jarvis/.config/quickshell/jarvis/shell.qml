// shell.qml — entry point del HUD de Jarvis.
//
// Lee estado y config del socket UNIX (line-JSON) emitido por jarvis-daemon.
// Según `config.theme` ("minimal" o "stark") muestra un PanelWindow u otro:
//
//   minimal → MinimalHud.qml: card abajo-centro con orb pequeño y texto inline.
//   stark   → StarkHud.qml:   overlay fullscreen, orb azul Stark grande centrado.
//
// Solo uno de los dos está visible a la vez. La elección se hace por
// `WindowLifecycle`: si no es el tema activo, el window queda invisible y
// sin coste de render.

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // Estado reactivo recibido del daemon
    property string state: "idle"
    property real rms: 0.0
    property string transcript: ""
    property string response: ""
    property bool muted: false
    property string lastError: ""

    // Config recibida en el snapshot inicial del socket
    property string theme: "minimal"
    property bool alwaysVisible: false

    // ─── Socket UNIX → estado ─────────────────────────────────────
    Socket {
        id: sock
        path: Qt.resolvedUrl(Quickshell.env("XDG_RUNTIME_DIR") + "/jarvis.sock")
        connected: true

        onConnectionStateChanged: {
            if (connectionState === Socket.Disconnected) {
                reconnectTimer.start();
            }
        }

        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => root._onLine(data)
        }
    }

    Timer {
        id: reconnectTimer
        interval: 2000
        repeat: false
        onTriggered: sock.connected = true
    }

    function _onLine(line: string): void {
        try {
            const j = JSON.parse(line);
            if (j.config) {
                if (j.config.theme) root.theme = j.config.theme;
                if (j.config.always_visible !== undefined) root.alwaysVisible = j.config.always_visible;
            }
            if (j.state !== undefined) root.state = j.state;
            if (j.rms !== undefined) root.rms = j.rms;
            if (j.transcript !== undefined) root.transcript = j.transcript;
            if (j.response !== undefined) root.response = j.response;
            if (j.error !== undefined) root.lastError = j.error;
            root.muted = (j.state === "muted");
        } catch (e) {
            console.warn("jarvis: bad line", line);
        }
    }

    // ─── HUD minimal (card abajo-centro) ─────────────────────────
    Loader {
        active: root.theme === "minimal"
        sourceComponent: MinimalHud {
            state: root.state
            rms: root.rms
            transcript: root.transcript
            response: root.response
            muted: root.muted
            lastError: root.lastError
            alwaysVisible: root.alwaysVisible
        }
    }

    // ─── HUD stark (fullscreen overlay) ──────────────────────────
    Loader {
        active: root.theme === "stark"
        sourceComponent: StarkHud {
            state: root.state
            rms: root.rms
            transcript: root.transcript
            response: root.response
            muted: root.muted
            alwaysVisible: root.alwaysVisible
        }
    }
}
