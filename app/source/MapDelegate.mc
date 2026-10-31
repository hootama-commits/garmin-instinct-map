// 버튼: UP/DOWN=축척(지도) · START=기록 시작/정지 · BACK=지도↔데이터 · MENU(UP 길게)=저장/폐기/종목/종료
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

    function onPreviousPage() {
        if (view.page == 0) { model.zoomIn(); } else { view.page = 0; }
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() {
        if (view.page == 0) { model.zoomOut(); } else { view.page = 0; }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        model.recorder.toggle();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        view.page = (view.page == 0) ? 1 : 0;
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() {
        var menu = new WatchUi.Menu2({:title => "Mono Map"});
        if (model.recorder.session != null) {
            menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
            menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
        }
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
        if (id == :save) {
            model.recorder.save();
            System.exit();
        } else if (id == :discard) {
            model.recorder.discard();
            System.exit();
        } else if (id == :sport) {
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
