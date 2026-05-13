// Waveform.qml — 32 barras animadas según RMS.
// No es FFT real (es un VU meter estilizado), pero el efecto visual basta.

import QtQuick

Canvas {
    id: root
    property bool active: false
    property real rms: 0.0
    property int bars: 32
    property color color: "#6cdcf3"

    // Cada barra mantiene su propio nivel, decae suave hacia rms.
    property var levels: []

    Component.onCompleted: {
        levels = new Array(bars).fill(0);
    }

    Timer {
        interval: 50
        running: root.active
        repeat: true
        onTriggered: {
            if (!root.levels || root.levels.length !== root.bars) {
                root.levels = new Array(root.bars).fill(0);
            }
            for (let i = 0; i < root.bars; i++) {
                // Pico aleatorio modulado por rms global
                const target = Math.min(1.0, root.rms * 8 * (0.4 + Math.random() * 0.8));
                root.levels[i] = root.levels[i] * 0.6 + target * 0.4;
            }
            root.requestPaint();
        }
    }

    Timer {
        interval: 100
        running: !root.active
        repeat: true
        onTriggered: {
            // Decae a cero cuando no está activo
            let any = false;
            for (let i = 0; i < root.bars; i++) {
                root.levels[i] *= 0.85;
                if (root.levels[i] > 0.01) any = true;
            }
            root.requestPaint();
            if (!any) running = false;
        }
    }

    onActiveChanged: {
        if (active) requestPaint();
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width;
        const h = height;
        const gap = 3;
        const bw = (w - (bars + 1) * gap) / bars;
        ctx.fillStyle = root.color;
        for (let i = 0; i < bars; i++) {
            const lvl = Math.max(0.04, root.levels[i] || 0);
            const bh = lvl * h;
            const x = gap + i * (bw + gap);
            const y = (h - bh) / 2;
            ctx.fillRect(x, y, bw, bh);
        }
    }
}
