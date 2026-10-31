// 인스팅트2 흑백 지도 — 앱 진입점
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MapApp extends Application.AppBase {
    var model;

    function initialize() {
        AppBase.initialize();
        model = new MapModel();
    }

    function onStart(state) {
        model.start();
    }

    function onStop(state) {
        model.stop();
    }

    function getInitialView() {
        var view = new MapView(model);
        return [view, new MapDelegate(model, view)];
    }
}
