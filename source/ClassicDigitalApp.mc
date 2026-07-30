import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Digital Classic - a rebuild of the fenix 5 Plus stock digital face
//! for the fenix 8 Solar / tactix 8 Solar 51mm (280x280 MIP).
class ClassicDigitalApp extends Application.AppBase {
    private var _view as ClassicDigitalView?;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
    }

    public function onStop(state as Dictionary?) as Void {
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new $.ClassicDigitalView();
        _view = view;

        // The delegate is what tells us if we blow the per-second power budget.
        if (WatchUi has :WatchFaceDelegate) {
            return [view, new $.ClassicDigitalDelegate(view)];
        }
        return [view];
    }

    public function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
