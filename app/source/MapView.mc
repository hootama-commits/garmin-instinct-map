// 화면: 0=지도(북쪽 고정, 중앙=현재 위치) · 1=데이터(시간·거리·페이스·심박)
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.UserProfile;
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
                var ops = model.tiles.get(z, tx, ty, dx * dx + dy * dy);
                if (ops != null) { drawOps(dc, ops, sx, sy); }
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

    // 타일 그리기: 코드 1~3 실선(펜 굵기) · 4 점선 · 10+r 고리 · 20+r 원판. 점 = (x+8)*256 + (y+8)
    function drawOps(dc, ops, sx, sy) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < ops.size(); i++) {
            var op = ops[i];
            var c = op[0];
            var n = op.size();
            if (c <= 3) {
                dc.setPenWidth(c);
                var p = op[1];
                var px = (p >> 8) - 8 + sx;
                var py = (p & 255) - 8 + sy;
                for (var j = 2; j < n; j++) {
                    var q = op[j];
                    var qx = (q >> 8) - 8 + sx;
                    var qy = (q & 255) - 8 + sy;
                    dc.drawLine(px, py, qx, qy);
                    px = qx;
                    py = qy;
                }
            } else if (c == 4) {
                dc.setPenWidth(1);
                for (var j = 1; j < n; j++) {
                    dc.drawPoint((op[j] >> 8) - 8 + sx, (op[j] & 255) - 8 + sy);
                }
            } else {
                var r = c % 10;
                var x = (op[1] >> 8) - 8 + sx;
                var y = (op[1] & 255) - 8 + sy;
                if (c >= 20) {
                    dc.fillCircle(x, y, r);
                } else {
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(x, y, r);
                    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(1);
                    dc.drawCircle(x, y, r);
                }
            }
        }
        dc.setPenWidth(1);
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
        var y = 42;
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

    // 속도 문자열: 자전거=km/h 한 자리, 러닝=분:초/km
    function fmtSpd(spd) {
        if (model.recorder.isBike()) { return (spd * 3.6).format("%.1f"); }
        if (spd > 0.4) {
            var spk = (1000.0 / spd).toNumber();
            return (spk / 60).format("%d") + ":" + (spk % 60).format("%02d");
        }
        return "--:--";
    }

    // 심박 존(0=존 아래, 1~5, -1=정보 없음) — 기기 사용자 프로필의 존 경계 사용
    function hrZone(hr) {
        if (hr == null) { return -1; }
        var sp = model.recorder.isBike() ? UserProfile.HR_ZONE_SPORT_BIKING : UserProfile.HR_ZONE_SPORT_RUNNING;
        var zones = UserProfile.getHeartRateZones(sp);
        if (zones == null) { return -1; }
        var z = 0;
        for (var i = 0; i < 5 && i < zones.size(); i++) {
            if (hr >= zones[i]) { z = i + 1; }
        }
        return z;
    }

    function zoneText(hr) {
        var z = hrZone(hr);
        if (hr == null || z < 0) { return "Z-"; }
        return "Z" + z + " " + hr;
    }

    // 우상단 원창: 심박 존·심박 / 현재 속도 / 평균 속도
    function drawCircle(dc, info) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(SUB_CX, SUB_CY, 31);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var spd = (info != null && info.currentSpeed != null) ? info.currentSpeed : 0.0;
        var avg = (info != null && info.averageSpeed != null) ? info.averageSpeed : 0.0;
        var hr = (info != null) ? info.currentHeartRate : null;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.drawText(SUB_CX, SUB_CY - 19, Graphics.FONT_XTINY, zoneText(hr), c);
        dc.drawText(SUB_CX, SUB_CY - 1, Graphics.FONT_SMALL, fmtSpd(spd), c);
        dc.drawText(SUB_CX, SUB_CY + 19, Graphics.FONT_XTINY, "av " + fmtSpd(avg), c);
    }

    // 상태 표시(아이콘+글자): START(▶) · REC(●) · PAUSE(❚❚) — 화면 아래 가운데
    function drawState(dc, cx, y) {
        var r = model.recorder;
        var label = "START";
        var kind = 0;
        if (r.session != null) {
            if (r.isRecording()) { label = "REC"; kind = 1; } else { label = "PAUSE"; kind = 2; }
        }
        var tw = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY);
        var total = 10 + 5 + tw;
        var x0 = cx - total / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x0 - 4, y - 2, total + 8, 18);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        drawIcon(dc, kind, x0, y + 2);
        dc.drawText(x0 + 15, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // 10×10 아이콘: 0=재생 1=기록 점 2=일시정지 3=정지(네모) 4=폐기(X)
    function drawIcon(dc, kind, x, y) {
        if (kind == 0) {
            dc.fillPolygon([[x, y], [x, y + 10], [x + 9, y + 5]]);
        } else if (kind == 1) {
            dc.fillCircle(x + 5, y + 5, 5);
        } else if (kind == 2) {
            dc.fillRectangle(x, y, 3, 10);
            dc.fillRectangle(x + 6, y, 3, 10);
        } else if (kind == 3) {
            dc.fillRectangle(x, y, 10, 10);
        } else {
            dc.setPenWidth(2);
            dc.drawLine(x, y, x + 9, y + 9);
            dc.drawLine(x, y + 9, x + 9, y);
            dc.setPenWidth(1);
        }
    }

    function drawStatus(dc, w, h, z) {
        var info = Activity.getActivityInfo();
        drawCircle(dc, info);
        var msg = null;
        if (!System.getDeviceSettings().phoneConnected) {
            msg = "NO PHONE";
        } else if (!model.hasFix) {
            msg = "GPS...";
        }
        if (msg == null && model.recorder.session != null && info != null && info.timerTime != null) {
            var t = info.timerTime / 1000;
            msg = (t / 3600).format("%d") + ":" + ((t % 3600) / 60).format("%02d") + ":" + (t % 60).format("%02d");
        }
        if (msg != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(w / 2 - 34, 2, 68, 16);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 10, Graphics.FONT_XTINY, msg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        drawState(dc, w / 2, 148);
    }

    function drawData(dc) {
        var info = Activity.getActivityInfo();
        var t = 0;
        var dist = 0.0;
        var hr = null;
        if (info != null) {
            if (info.timerTime != null) { t = info.timerTime / 1000; }
            if (info.elapsedDistance != null) { dist = info.elapsedDistance; }
            hr = info.currentHeartRate;
        }
        var timeStr = (t / 3600).format("%d") + ":" + ((t % 3600) / 60).format("%02d") + ":" + (t % 60).format("%02d");
        var rows = [["TIME", timeStr], ["KM", (dist / 1000).format("%.2f")], ["HR", (hr == null) ? "--" : "" + hr]];
        var y = 10;
        for (var i = 0; i < rows.size(); i++) {
            dc.drawText(32, y, Graphics.FONT_XTINY, rows[i][0], Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(30, y + 15, Graphics.FONT_MEDIUM, rows[i][1], Graphics.TEXT_JUSTIFY_LEFT);
            y += 45;
            if (i < 2) {
                dc.setPenWidth(1);
                dc.drawLine(30, y - 4, (i == 0) ? 104 : 146, y - 4);
            }
        }
        drawCircle(dc, info);
        drawState(dc, dc.getWidth() / 2, 148);
    }
}
