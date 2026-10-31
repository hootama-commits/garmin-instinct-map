// 타일 캐시: 폰(Garmin Connect) 경유로 1비트 PNG 타일을 받아 LRU로 보관
// 동시 요청 1건 · 화면 중심에서 가까운 타일 먼저 · 404(빈 땅)는 15분간 재요청 안 함
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class TileCache {
    const BASE = "https://hootama-commits.github.io/garmin-instinct-map/t/";
    const CAP = 12;
    var bitmaps = {};        // key -> BitmapResource
    var order = [];          // LRU, 오래된 것이 앞
    var missing = {};        // key -> 실패 시각(초)
    var pending = null;      // 요청 중인 key
    var wanted = [];         // 이번 프레임에 필요한 [z, x, y, key, dist]
    var backoffUntil = 0;
    var lastCode = 0;
    var fetched = 0;

    function beginFrame() {
        wanted = [];
    }

    function get(z, x, y, dist) {
        var key = "" + z + "/" + x + "/" + y;
        var bmp = bitmaps.get(key);
        if (bmp != null) {
            touch(key);
            return bmp;
        }
        var m = missing.get(key);
        if (m != null) {
            if (Time.now().value() - m < 900) { return null; }
            missing.remove(key);
        }
        if (pending == null || !pending.equals(key)) {
            wanted.add([z, x, y, key, dist]);
        }
        return null;
    }

    function pump() {
        if (pending != null || wanted.size() == 0) { return; }
        var now = Time.now().value();
        if (now < backoffUntil) { return; }
        if (!System.getDeviceSettings().phoneConnected) {
            backoffUntil = now + 10;
            return;
        }
        var best = 0;
        for (var i = 1; i < wanted.size(); i++) {
            if (wanted[i][4] < wanted[best][4]) { best = i; }
        }
        var w = wanted[best];
        wanted = [];
        pending = w[3];
        var url = BASE + w[0] + "/" + w[1] + "/" + w[2] + ".png";
        Communications.makeImageRequest(url, null,
            {:dithering => Communications.IMAGE_DITHERING_NONE,
             :palette => [Graphics.COLOR_BLACK, Graphics.COLOR_WHITE]},
            method(:onImage));
    }

    function onImage(code as Number, data) as Void {
        var key = pending;
        pending = null;
        lastCode = code;
        if (key == null) { return; }
        if (code == 200 && data != null) {
            put(key, data);
            fetched++;
        } else {
            missing.put(key, Time.now().value());
            if (code != 404) { backoffUntil = Time.now().value() + 15; }
            if (missing.size() > 300) { missing = {}; }
        }
        WatchUi.requestUpdate();
    }

    function put(key, bmp) {
        while (order.size() >= CAP) {
            var old = order[0];
            removeKey(old);
            bitmaps.remove(old);
        }
        bitmaps.put(key, bmp);
        order.add(key);
    }

    function touch(key) {
        removeKey(key);
        order.add(key);
    }

    function removeKey(key) {
        for (var i = 0; i < order.size(); i++) {
            if (order[i].equals(key)) {
                order = order.slice(0, i).addAll(order.slice(i + 1, null));
                return;
            }
        }
    }
}
