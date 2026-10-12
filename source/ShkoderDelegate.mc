import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Receives the power-budget verdict for onPartialUpdate(). If the once-per-second
//! second marker ever costs more than the device allows, we permanently fall back
//! to minute-only updates instead of being killed by the system.
class ShkoderDelegate extends WatchUi.WatchFaceDelegate {
    private var _view as ShkoderView;

    public function initialize(view as ShkoderView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    public function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Partial update average time: " + powerInfo.executionTimeAverage);
        System.println("Partial update limit:        " + powerInfo.executionTimeLimit);
        _view.disablePartialUpdates();
    }
}
