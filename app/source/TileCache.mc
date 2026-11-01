// 타일 캐시: 폰(Garmin Connect) 경유 일반 웹 요청(JSON)으로 선 좌표 타일을 받아 LRU로 보관
// 이 폰·시계 조합은 이미지 요청이 -300으로 막혀 있어 JSON 방식을 쓴다.
// 동시 요청 1건 · 화면 중심에서 가까운 타일 먼저 · 404(빈 땅)는 15분간 재요청 안 함
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class TileCache {
    const PAGES = "https://hootama-commits.github.io/garmin-instinct-map/v/";   // 수도권(13~16)
    const R2 = "https://pub-b8b5b0f139db47ff9052de7f0563f6cc.r2.dev/v/";        // 전국(13~15)
    const CAP_W = 14274614;   // 수도권 상자(z16 월드 px) — areas.py의 capital과 같음
    const CAP_E = 14349180;
    const CAP_N = 6453674;
    const CAP_S = 6536028;
    const CAP = 10;
    var tiles = {};          // key -> 그리기 목록 [[코드, 점, 점...], ...]
    var order = [];          // LRU, 오래된 것이 앞
    var missing = {};        // key -> 실패 시각(초)
    var pending = null;      // 요청 중인 key
    var wanted = [];         // 이번 프레임에 필요한 [z, x, y, key, dist]
    var backoffUntil = 0;
    var lastCode = 0;
    var fetched = 0;
    var tries = 0;

    function beginFrame() {
        wanted = [];
    }

    // 타일 중심이 수도권 상자 안인지
    function inCapital(z, x, y) {
        var s = 16 - z;
        var cx = ((x * 128 + 64) << s);
        var cy = ((y * 128 + 64) << s);
        return cx >= CAP_W && cx <= CAP_E && cy >= CAP_N && cy <= CAP_S;
    }

    function get(z, x, y, dist) {
        if (z == 16 && !inCapital(z, x, y)) { return null; }   // 전국 타일은 15까지
        var key = "" + z + "/" + x + "/" + y;
        var ops = tiles.get(key);
        if (ops != null) {
            touch(key);
            return ops;
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
        tries++;
        var base = inCapital(w[0], w[1], w[2]) ? PAGES : R2;
        var url = base + w[0] + "/" + w[1] + "/" + w[2] + ".json";
        Communications.makeWebRequest(url, null,
            {:method => Communications.HTTP_REQUEST_METHOD_GET,
             :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON},
            method(:onTile));
    }

    function onTile(code as Number, data) as Void {
        var key = pending;
        pending = null;
        lastCode = code;
        if (key == null) { return; }
        if (code == 200 && data instanceof Dictionary && data.get("a") != null) {
            put(key, data.get("a"));
            fetched++;
        } else {
            missing.put(key, Time.now().value());
            if (code != 404) { backoffUntil = Time.now().value() + 15; }
            if (missing.size() > 300) { missing = {}; }
        }
        WatchUi.requestUpdate();
    }

    function put(key, ops) {
        while (order.size() >= CAP) {
            var old = order[0];
            removeKey(old);
            tiles.remove(old);
        }
        tiles.put(key, ops);
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
