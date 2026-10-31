// 지도 상태: 현재 위치(z16 월드 픽셀) · 축척 · 궤적 · 타일 캐시 · 운동 기록
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

class MapModel {
    const ZOOMS = [13, 14, 15, 16];
    var zi = 1;                 // 기본 z14(화면 폭 약 2.7km)
    var cx16 = 14303044;        // GPS 잡기 전 초기 화면 = 신풍역 근처(z16 월드 px)
    var cy16 = 6500868;
    var lat = 37.5d;
    var heading = null;         // 라디안, 북쪽 0
    var hasFix = false;
    var tiles = new TileCache();
    var trail = new Trail();
    var recorder = new Recorder();
    var timer = new Timer.Timer();

    function start() {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        timer.start(method(:onTick), 2000, true);
    }

    function stop() {
        timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onTick() as Void {
        tiles.pump();
        WatchUi.requestUpdate();
    }

    function zoom() {
        return ZOOMS[zi];
    }

    function zoomIn() {
        if (zi < ZOOMS.size() - 1) { zi++; }
    }

    function zoomOut() {
        if (zi > 0) { zi--; }
    }

    // 축척 z에서 1픽셀이 몇 m인지(256px 타일 기준 웹 메르카토르)
    function metersPerPx() {
        return 156543.03d * Math.cos(Math.toRadians(lat)) / (1 << zoom());
    }

    function onPosition(info as Position.Info) as Void {
        if (info.position == null) { return; }
        var deg = info.position.toDegrees();   // [lat, lon]
        lat = deg[0];
        var n = 16777216.0d;                   // 256 * 2^16
        var x = (deg[1] + 180.0d) / 360.0d * n;
        var latR = Math.toRadians(deg[0]);
        var y = (1.0d - Math.ln(Math.tan(latR) + 1.0d / Math.cos(latR)) / Math.PI) / 2.0d * n;
        cx16 = x.toNumber();
        cy16 = y.toNumber();
        heading = info.heading;
        hasFix = (info.accuracy != null) && (info.accuracy >= Position.QUALITY_POOR);
        if (hasFix) { trail.add(cx16, cy16); }
        WatchUi.requestUpdate();
    }
}
