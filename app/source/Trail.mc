// 이동 궤적: z16 월드 픽셀 정수 링 버퍼(약 15m 간격 · 최대 400점 ≈ 6km)
import Toybox.Graphics;
import Toybox.Lang;

class Trail {
    const CAP = 400;
    const MIN_STEP = 8;   // z16 px, 신풍역 위도에서 약 15m
    var xs = new [CAP];
    var ys = new [CAP];
    var n = 0;
    var head = 0;
    var lastX = null;
    var lastY = null;

    function add(x, y) {
        if (lastX != null && (x - lastX).abs() < MIN_STEP && (y - lastY).abs() < MIN_STEP) { return; }
        xs[head] = x;
        ys[head] = y;
        head = (head + 1) % CAP;
        if (n < CAP) { n++; }
        lastX = x;
        lastY = y;
    }

    function draw(dc, shift, ox, oy, w, h) {
        if (n < 2) { return; }
        var start = (head - n + CAP) % CAP;
        var px = null;
        var py = null;
        for (var i = 0; i < n; i++) {
            var k = (start + i) % CAP;
            var sx = (xs[k] >> shift) - ox;
            var sy = (ys[k] >> shift) - oy;
            if (px != null) {
                var inside = (sx >= -2 && sx < w + 2 && sy >= -2 && sy < h + 2) ||
                             (px >= -2 && px < w + 2 && py >= -2 && py < h + 2);
                if (inside) { dc.drawLine(px, py, sx, sy); }
            }
            px = sx;
            py = sy;
        }
    }
}
