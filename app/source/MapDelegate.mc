// 버튼(가민 운동앱 방식): START/STOP=시작 · 기록 중 누르면 일시정지+메뉴(계속·저장·폐기)
// BACK(LAP)=기록 중 랩, 기록 전 종료 · UP/DOWN=화면 넘기기(지도 확대 단계 → 데이터) · MENU(UP 길게)=종목·종료
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class MapDelegate extends WatchUi.BehaviorDelegate {
    var model;
    var view;

    function initialize(m, v) {
        BehaviorDelegate.initialize();
        model = m;
        view = v;
    }

    // UP: 데이터 → 지도(가장 넓은 축척) → 확대
    function onPreviousPage() {
        if (view.page == 1) { view.page = 0; } else { model.zoomIn(); }
        WatchUi.requestUpdate();
        return true;
    }

    // DOWN: 축소 → 가장 넓은 축척에서 한 번 더 누르면 데이터
    function onNextPage() {
        if (view.page == 0) {
            if (model.zi > 0) { model.zoomOut(); } else { view.page = 1; }
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        var r = model.recorder;
        if (r.session == null) {
            r.begin();
        } else {
            r.pause();
            pushPauseMenu();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function pushPauseMenu() {
        var pv = new PauseView(model, view, false);
        WatchUi.pushView(pv, new PauseDelegate(model, pv), WatchUi.SLIDE_UP);
    }

    function onBack() {
        var r = model.recorder;
        if (r.session == null) {
            System.exit();
        } else if (r.isRecording()) {
            r.lap();
            WatchUi.requestUpdate();
        } else {
            pushPauseMenu();
        }
        return true;
    }

    function onMenu() {
        var menu = new WatchUi.Menu2({:title => "Mono Map"});
        menu.addItem(new WatchUi.MenuItem("Sport", model.recorder.sportName(), :sport, null));
        menu.addItem(new WatchUi.MenuItem("Exit", null, :exit, null));
        WatchUi.pushView(menu, new MapMenuDelegate(model), WatchUi.SLIDE_UP);
        return true;
    }
}

class MapMenuDelegate extends WatchUi.Menu2InputDelegate {
    var model;

    function initialize(m) {
        Menu2InputDelegate.initialize();
        model = m;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :sport) {
            model.recorder.nextSport();
            item.setSubLabel(model.recorder.sportName());
            WatchUi.requestUpdate();
        } else if (id == :exit) {
            if (model.recorder.session == null) {
                System.exit();
            } else {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
            }
        }
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
