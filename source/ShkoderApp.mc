import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Shkoder - a rebuild of the fenix 5 Plus stock digital face
//! for the fenix 8 Solar / tactix 8 Solar 51mm (280x280 MIP).
class ShkoderApp extends Application.AppBase {
    private var _view as ShkoderView?;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
    }

    public function onStop(state as Dictionary?) as Void {
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new $.ShkoderView();
        _view = view;

        // The delegate is what tells us if we blow the per-second power budget.
        if (WatchUi has :WatchFaceDelegate) {
            return [view, new $.ShkoderDelegate(view)];
        }
        return [view];
    }

    //! Settings menu shown on the watch itself. Without this the face's
    //! settings are unreachable when it is sideloaded, because a sideloaded
    //! app never shows up in the Connect IQ phone app.
    public function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [new $.SettingsLauncherView(), new $.SettingsLauncherDelegate()];
    }

    public function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
