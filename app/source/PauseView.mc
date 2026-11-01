// 일시정지 화면(계속·저장·폐기)과 폐기 확인 화면(취소·폐기) — 아이콘+글자, 원창·깎인 모서리를 피해 직접 그림
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class PauseView extends WatchUi.View {
    const ROW_X = 30;
    const ROW_W = 116;
    const ROW_H = 26;
    const ROW_Y0 = 66;       // 우상단 원창(y 0~62) 아래부터
    var model;
    var sel = 0;
    var mapView;
    var confirm;

    function initialize(m, mv, c) {
        View.initialize();
        model = m;
        mapView = mv;
        confirm = c;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();
        var info = Activity.getActivityInfo();
        mapView.drawCircle(dc, info);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        mapView.drawIcon(dc, confirm ? 4 : 2, 24, 32);
        dc.drawText(40, 28, Graphics.FONT_XTINY, confirm ? "SURE?" : "PAUSED", Graphics.TEXT_JUSTIFY_LEFT);
        var labels = confirm ? ["CANCEL", "DISCARD"] : ["RESUME", "SAVE", "DISCARD"];
        var kinds = confirm ? [0, 4] : [0, 3, 4];
        for (var i = 0; i < labels.size(); i++) {
            var y = ROW_Y0 + i * (ROW_H + 4);
            var on = (i == sel);
            dc.setColor(on ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.fillRoundedRectangle(ROW_X, y, ROW_W, ROW_H, 5);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(ROW_X, y, ROW_W, ROW_H, 5);
            dc.setPenWidth(1);
            dc.setColor(on ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            mapView.drawIcon(dc, kinds[i], ROW_X + 10, y + 8);
            dc.drawText(ROW_X + 30, y + 2, Graphics.FONT_XTINY, labels[i], Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}

class PauseDelegate extends WatchUi.BehaviorDelegate {
    var model;
    var pv;
    var cd;

    function initialize(m, p) {
        BehaviorDelegate.initialize();
        model = m;
        pv = p;
    }

    function onPreviousPage() {
        pv.sel = (pv.sel + 2) % 3;
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() {
        pv.sel = (pv.sel + 1) % 3;
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        if (pv.sel == 0) {
            resume();
        } else if (pv.sel == 1) {
            model.recorder.save();
            System.exit();
        } else {
            var cv = new PauseView(model, pv.mapView, true);
            cd = new ConfirmDelegate(model, cv);
            WatchUi.pushView(cv, cd, WatchUi.SLIDE_UP);
        }
        return true;
    }

    // BACK = 계속(가민 운동앱과 같음)
    function onBack() {
        resume();
        return true;
    }

    function resume() {
        model.recorder.begin();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ConfirmDelegate extends WatchUi.BehaviorDelegate {
    var model;
    var pv;

    function initialize(m, p) {
        BehaviorDelegate.initialize();
        model = m;
        pv = p;
    }

    function onPreviousPage() {
        pv.sel = (pv.sel + 1) % 2;
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() {
        return onPreviousPage();
    }

    function onSelect() {
        if (pv.sel == 1) {
            model.recorder.discard();
            System.exit();
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
