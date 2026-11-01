// 운동 기록: 시계 내장 기록기(FIT)로 저장 → Garmin Connect에 보통 운동처럼 올라감
import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;

class Recorder {
    const SPORTS = [Activity.SPORT_CYCLING, Activity.SPORT_RUNNING];
    const NAMES = ["Bike", "Run"];
    var si = 0;
    var session = null;

    function isBike() {
        return si == 0;
    }

    function sportName() {
        return NAMES[si];
    }

    function nextSport() {
        if (session == null) { si = (si + 1) % SPORTS.size(); }
    }

    function begin() {
        if (session == null) {
            session = ActivityRecording.createSession({:name => "MonoMap", :sport => SPORTS[si]});
        }
        session.start();
    }

    function pause() {
        if (session != null) { session.stop(); }
    }

    function lap() {
        if (session != null && session.isRecording()) { session.addLap(); }
    }

    function isRecording() {
        return session != null && session.isRecording();
    }

    function save() {
        if (session != null) {
            session.stop();
            session.save();
            session = null;
        }
    }

    function discard() {
        if (session != null) {
            session.stop();
            session.discard();
            session = null;
        }
    }
}
