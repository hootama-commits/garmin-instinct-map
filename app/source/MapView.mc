// 화면: 0=지도(북쪽 고정, 중앙=현재 위치) · 1=데이터(시간·거리·페이스·심박)
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

class MapView extends WatchUi.View {
    const TILE = 128;
    const SUB_CX = 144;   // 우상단 원창 중심 — 기기 정의 subscreen(113,0 · 62×62)에서 계산
    const SUB_CY = 31;
    var model;
    var page = 0;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();
        if (page == 0) {
            drawMap(dc);
        } else {
            drawData(dc);
        }
    }

    function drawMap(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var z = model.zoom();
        var shift = 16 - z;
        var ox = (model.cx16 >> shift) - w / 2;   // 화면 좌상단의 월드 px
        var oy = (model.cy16 >> shift) - h / 2;
        var tx1 = (ox + w - 1) / TILE;
        var ty1 = (oy + h - 1) / TILE;
        model.tiles.beginFrame();
        for (var tx = ox / TILE; tx <= tx1; tx++) {
            for (var ty = oy / TILE; ty <= ty1; ty++) {
                var sx = tx * TILE - ox;
                var sy = ty * TILE - oy;
                var dx = sx + TILE / 2 - w / 2;
                var dy = sy + TILE / 2 - h / 2;
                var bmp = model.tiles.get(z, tx, ty, dx * dx + dy * dy);
                if (bmp != null) { dc.drawBitmap(sx, sy, bmp); }
            }
        }
        model.tiles.pump();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        model.trail.draw(dc, shift, ox, oy, w, h);
        drawMarker(dc, w / 2, h / 2);
        drawScale(dc, h, z);
        drawStatus(dc, w, h, z);
    }

    // 현재 위치: 진행 방향 삼각형(흰 테두리) · 방향 없으면 원
    function drawMarker(dc, cx, cy) {
        var hd = model.heading;
        if (model.hasFix && hd != null) {
            var s = Math.sin(hd);
            var c = Math.cos(hd);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(arrow(cx, cy, s, c, 12, 8));
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(arrow(cx, cy, s, c, 9, 5));
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 7);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawCircle(cx, cy, 6);
            dc.fillCircle(cx, cy, 2);
        }
    }

    // 마커 좌표계(앞=-y)를 진행 방향으로 회전: x' = x cos - y sin, y' = x sin + y cos
    function arrow(cx, cy, s, c, len, half) {
        var pts = [[0, -len], [half, half], [0, half / 2], [-half, half]];
        var out = new [pts.size()];
        for (var i = 0; i < pts.size(); i++) {
            var x = pts[i][0];
            var y = pts[i][1];
            out[i] = [cx + (x * c - y * s).toNumber(), cy + (x * s + y * c).toNumber()];
        }
        return out;
    }

    function drawScale(dc, h, z) {
        var mpp = model.metersPerPx();
        var opts = [50, 100, 200, 500, 1000, 2000, 5000];
        var m = 50;
        var px = 10;
        for (var i = 0; i < opts.size(); i++) {
            var p = opts[i] / mpp;
            if (p <= 70) {
                m = opts[i];
                px = p.toNumber();
            }
        }
        var x = 30;
        var y = h - 16;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 3, y - 15, px + 6, 20);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x, y, x + px, y);
        dc.drawLine(x, y - 4, x, y + 1);
        dc.drawLine(x + px, y - 4, x + px, y + 1);
        var label = (m >= 1000) ? ("" + (m / 1000) + "km") : ("" + m + "m");
        dc.drawText(x, y - 17, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function drawStatus(dc, w, h, z) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(SUB_CX, SUB_CY, Graphics.FONT_TINY, "z" + z, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var msg = null;
        var phone = System.getDeviceSettings().phoneConnected;
        if (!phone) {
            msg = "NO PHONE";
        } else if (!model.hasFix) {
            msg = "GPS...";
        }
        if (msg != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(w / 2 - 34, 2, 68, 16);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 10, Graphics.FONT_XTINY, msg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var cs = model.tiles.codes;
        dc.drawText(30, h - 70, Graphics.FONT_XTINY, "t" + model.tiles.fetched + " n" + model.tiles.tries, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(30, h - 58, Graphics.FONT_XTINY, "P" + cs[0] + " R" + cs[1], Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(30, h - 46, Graphics.FONT_XTINY, "W" + cs[2] + " J" + cs[3], Graphics.TEXT_JUSTIFY_LEFT);
        if (model.recorder.session != null) {
            var mark = model.recorder.isRecording() ? "REC" : "PAUSE";
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(w - 76, h - 22, 46, 16);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - 53, h - 14, Graphics.FONT_XTINY, mark, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function drawData(dc) {
        var w = dc.getWidth();
        var info = Activity.getActivityInfo();
        var t = 0;
        var dist = 0.0;
        var spd = 0.0;
        var hr = null;
        if (info != null) {
            if (info.timerTime != null) { t = info.timerTime / 1000; }
            if (info.elapsedDistance != null) { dist = info.elapsedDistance; }
            if (info.currentSpeed != null) { spd = info.currentSpeed; }
            hr = info.currentHeartRate;
        }
        var paceLabel = "PACE";
        var pace = "--:--";
        if (model.recorder.isBike()) {
            paceLabel = "KM/H";
            pace = (spd * 3.6).format("%.1f");
        } else if (spd > 0.4) {
            var spk = (1000.0 / spd).toNumber();
            pace = (spk / 60).format("%d") + ":" + (spk % 60).format("%02d");
        }
        var timeStr = (t / 3600).format("%d") + ":" + ((t % 3600) / 60).format("%02d") + ":" + (t % 60).format("%02d");
        var rows = [["TIME", timeStr], ["KM", (dist / 1000).format("%.2f")], [paceLabel, pace], ["HR", (hr == null) ? "--" : "" + hr]];
        var y = 14;
        for (var i = 0; i < rows.size(); i++) {
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, rows[i][0], Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, y + 12, Graphics.FONT_MEDIUM, rows[i][1], Graphics.TEXT_JUSTIFY_CENTER);
            y += 38;
        }
        var st = System.getSystemStats();
        dc.drawText(w / 2, dc.getHeight() - 14, Graphics.FONT_XTINY,
            "mem " + (st.usedMemory / 1024) + "/" + (st.totalMemory / 1024) + "k t" + model.tiles.fetched + " c" + model.tiles.lastCode,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
