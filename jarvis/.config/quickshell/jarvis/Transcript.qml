// Transcript.qml — muestra la transcripción y la respuesta con fade.

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    property string transcript: ""
    property string response: ""
    property string state: "idle"
    spacing: 2

    Text {
        Layout.fillWidth: true
        visible: root.transcript !== ""
        text: "“" + root.transcript + "”"
        color: "#b8c2cc"
        font.family: "Inter"
        font.pixelSize: 13
        font.italic: true
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 1
        opacity: 0.9
    }

    Text {
        Layout.fillWidth: true
        Layout.fillHeight: true
        text: root.response || (root.state === "thinking" ? "Pensando…" : "")
        color: "#eaf6ff"
        font.family: "Inter"
        font.pixelSize: 15
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 3
        opacity: root.response ? 1.0 : 0.6

        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
}
