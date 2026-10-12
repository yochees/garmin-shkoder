import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// ---------------------------------------------------------------------------
// On-device settings.
//
// A sideloaded face - one copied straight into GARMIN/APPS rather than
// installed from the store - never appears in the Connect IQ phone app,
// because that list is built from the Garmin account's installed-app records
// and a sideloaded app has no such record. The phone settings screen is
// therefore unreachable, and AppBase.getSettingsView() is the only way in.
// ---------------------------------------------------------------------------

//! Quarter hours are all that real zones need: +5:45 Nepal, +8:45 Eucla,
//! -3:30 Newfoundland, +12:45 Chatham.
const OFFSET_STEPS = [0, 15, 30, 45];

//! TopField default, meaning "not chosen yet" - see topFieldProp().
const TOP_FIELD_UNSET = -1;

//! getSettingsView() must hand back a plain View, not a Menu2.
//!
//! Returning a Menu2 straight from getSettingsView() builds and runs in the
//! simulator, but the watch then offers no Customize entry at all. Garmin's own
//! Analog sample returns a View whose delegate opens the menu, and that is the
//! shape the firmware accepts - verified against the sample on this watch.
//!
//! The sample then waits for MENU, which is dead on a fenix 8: MENU is a long
//! press of UP and never reaches onMenu() inside a settings view. So the view
//! opens the menu itself as soon as it is shown, and the button handlers below
//! are only a fallback.
class SettingsLauncherView extends WatchUi.View {

    private var _opened as Boolean = false;

    public function initialize() {
        View.initialize();
    }

    //! Guarded, because popping the menu shows this view again and an
    //! unguarded push here would trap the user in a loop they cannot back out
    //! of.
    public function onShow() as Void {
        if (!_opened) {
            _opened = true;
            openSettingsMenu();
        }
    }

    public function onUpdate(dc as Dc) as Void {
        dc.clearClip();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2, dc.getHeight() / 2 - 30,
            Graphics.FONT_SMALL, "Press START\nfor settings",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}

//! Every route to the menu, because which button reaches a settings view
//! differs between devices: START/ENTER, MENU, and the raw key events.
class SettingsLauncherDelegate extends WatchUi.BehaviorDelegate {

    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onMenu() as Boolean {
        openSettingsMenu();
        return true;
    }

    public function onSelect() as Boolean {
        openSettingsMenu();
        return true;
    }

    public function onKey(event as WatchUi.KeyEvent) as Boolean {
        var key = event.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START ||
            key == WatchUi.KEY_MENU || key == WatchUi.KEY_DOWN) {
            openSettingsMenu();
            return true;
        }
        return false;
    }
}

function openSettingsMenu() as Void {
    var menu = new $.SettingsMenu();
    WatchUi.pushView(menu, new $.SettingsMenuDelegate(menu), WatchUi.SLIDE_IMMEDIATE);
}

//! Builds the root menu and keeps its sub-labels in step with the properties.
class SettingsMenu extends WatchUi.Menu2 {

    public function initialize() {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.AppName) as String});

        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SettTopField) as String,
            topFieldText(), :TopField, {}));

        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SettLeftField) as String,
            fieldText("LeftField", 1), :LeftField, {}));

        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SettRightField) as String,
            fieldText("RightField", 2), :RightField, {}));

        addItem(new WatchUi.ToggleMenuItem(
            WatchUi.loadResource(Rez.Strings.SettLeadingZero) as String, null,
            :LeadingZero, boolProp("LeadingZero", true), {}));

        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SettExtraZoneLabel) as String,
            labelText(), :ExtraZoneLabel, {}));

        addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.SettExtraZoneOffset) as String,
            offsetText(), :ExtraZoneOffset, {}));
    }

    //! Re-read one row's sub-label after its picker or submenu has written it.
    public function refresh(id as Symbol) as Void {
        var idx = findItemById(id);
        if (idx < 0) {
            return;
        }
        var item = getItem(idx);
        if (item == null) {
            return;
        }

        if (id == :ExtraZoneLabel) {
            item.setSubLabel(labelText());
        } else if (id == :ExtraZoneOffset) {
            item.setSubLabel(offsetText());
        } else if (id == :TopField) {
            item.setSubLabel(topFieldText());
        } else if (id == :LeftField) {
            item.setSubLabel(fieldText("LeftField", 1));
        } else if (id == :RightField) {
            item.setSubLabel(fieldText("RightField", 2));
        }
    }
}

// ---------------------------------------------------------------------------
// Root menu input
// ---------------------------------------------------------------------------

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as SettingsMenu;

    public function initialize(menu as SettingsMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    //! Backing out of the menu lands on the launcher view, which would leave
    //! the user staring at a hint screen, so take the launcher with it.
    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :LeadingZero) {
            // The toggle has already flipped itself; just persist it.
            saveProp("LeadingZero", (item as WatchUi.ToggleMenuItem).isEnabled());
            return;
        }

        if (id == :ExtraZoneLabel) {
            pushLabelEditor(_menu);
            return;
        }

        if (id == :ExtraZoneOffset) {
            pushOffsetPicker(_menu);
            return;
        }

        if (id == :TopField || id == :LeftField || id == :RightField) {
            var key = "RightField";
            var current = numberProp(key, 2);
            if (id == :TopField) {
                key = "TopField";
                current = topFieldProp();
            } else if (id == :LeftField) {
                key = "LeftField";
                current = numberProp(key, 1);
            }

            WatchUi.pushView(
                new $.ChoiceMenu(item.getLabel(), fieldChoices(), current),
                new $.ChoiceDelegate(_menu, id as Symbol, key),
                WatchUi.SLIDE_LEFT);
        }
    }
}

// ---------------------------------------------------------------------------
// Generic "pick one value" submenu, used for the complication fields and as
// the label fallback on any device without a TextPicker.
// ---------------------------------------------------------------------------

class ChoiceMenu extends WatchUi.Menu2 {

    //! `choices` is an array of [value, display text] pairs.
    public function initialize(title as String, choices as Array, current as Object) {
        Menu2.initialize({:title => title});
        for (var i = 0; i < choices.size(); i++) {
            var c = choices[i] as Array;
            var mark = c[0].equals(current) ? "> " : "";
            addItem(new WatchUi.MenuItem(mark + (c[1] as String), null, i, {}));
        }
    }
}

class ChoiceDelegate extends WatchUi.Menu2InputDelegate {

    private var _root as SettingsMenu;
    private var _id as Symbol;
    private var _key as String;
    private var _choices as Array;

    public function initialize(root as SettingsMenu, id as Symbol, key as String) {
        Menu2InputDelegate.initialize();
        _root = root;
        _id = id;
        _key = key;
        _choices = key.equals("ExtraZoneLabel") ? labelChoices() : fieldChoices();
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var choice = _choices[item.getId() as Number] as Array;
        saveProp(_key, choice[0]);
        _root.refresh(_id);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// ---------------------------------------------------------------------------
// Label - free text where the device allows it, presets where it does not
// ---------------------------------------------------------------------------

//! A list, not the TextPicker straight away.
//!
//! TextPicker greys out its save button on an empty field, so once a label
//! existed there was no way back to none - the only escape was typing a space
//! and knowing that it gets trimmed, which nobody should have to guess. The
//! list carries an explicit "(none)" row, and "Type..." for anything not in
//! the presets.
const LABEL_TYPE_ID = -1;

function pushLabelEditor(root as SettingsMenu) as Void {
    WatchUi.pushView(
        new $.LabelMenu(stringProp("ExtraZoneLabel", "")),
        new $.LabelMenuDelegate(root),
        WatchUi.SLIDE_LEFT);
}

class LabelMenu extends WatchUi.Menu2 {

    public function initialize(current as String) {
        Menu2.initialize({
            :title => WatchUi.loadResource(Rez.Strings.SettExtraZoneLabel) as String
        });

        var choices = labelChoices();
        for (var i = 0; i < choices.size(); i++) {
            var c = choices[i] as Array;
            var mark = (c[0] as String).equals(current) ? "> " : "";
            addItem(new WatchUi.MenuItem(mark + (c[1] as String), null, i, {}));
        }

        if (WatchUi has :TextPicker) {
            addItem(new WatchUi.MenuItem("Type...", null, LABEL_TYPE_ID, {}));
        }
    }
}

class LabelMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _root as SettingsMenu;

    public function initialize(root as SettingsMenu) {
        Menu2InputDelegate.initialize();
        _root = root;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Number;

        if (id == LABEL_TYPE_ID) {
            WatchUi.pushView(
                new WatchUi.TextPicker(stringProp("ExtraZoneLabel", "")),
                new $.LabelPickerDelegate(_root),
                WatchUi.SLIDE_LEFT);
            return;
        }

        var choice = labelChoices()[id] as Array;
        saveProp("ExtraZoneLabel", choice[0]);
        _root.refresh(:ExtraZoneLabel);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class LabelPickerDelegate extends WatchUi.TextPickerDelegate {

    private var _root as SettingsMenu;

    public function initialize(root as SettingsMenu) {
        TextPickerDelegate.initialize();
        _root = root;
    }

    //! Spaces are stripped, so a label of nothing but spaces clears it. That is
    //! the only way to end up with no label: the TextPicker will not confirm an
    //! empty string, so "type a space" is the escape hatch.
    public function onTextEntered(text as String, changed as Boolean) as Boolean {
        var label = trimSpaces(text);

        // The row is drawn beside the time in the complication font, so a long
        // label would push it wider than the face.
        if (label.length() > 6) {
            label = label.substring(0, 6) as String;
        }

        saveProp("ExtraZoneLabel", label);
        _root.refresh(:ExtraZoneLabel);
        return true;
    }
}

function trimSpaces(s as String) as String {
    var start = 0;
    var end = s.length();
    while (start < end && (s.substring(start, start + 1) as String).equals(" ")) {
        start += 1;
    }
    while (end > start && (s.substring(end - 1, end) as String).equals(" ")) {
        end -= 1;
    }
    return s.substring(start, end) as String;
}

// ---------------------------------------------------------------------------
// Offset - two columns, hours and quarter hours
// ---------------------------------------------------------------------------

function pushOffsetPicker(root as SettingsMenu) as Void {
    var hours = floatProp("ExtraZoneOffset", 0.0);
    var quarters = Math.round(hours.abs() * 4.0).toNumber();
    var defHour = quarters / 4;
    if (hours < 0) {
        defHour = -defHour;
    }

    WatchUi.pushView(
        new WatchUi.Picker({
            :title => new WatchUi.Text({
                :text => WatchUi.loadResource(Rez.Strings.SettExtraZoneOffset) as String,
                :color => Graphics.COLOR_WHITE,
                :font => Graphics.FONT_XTINY,
                :locX => WatchUi.LAYOUT_HALIGN_CENTER,
                :locY => WatchUi.LAYOUT_VALIGN_BOTTOM
            }),
            :pattern => [new $.HourFactory(), new $.MinuteFactory()],
            :defaults => [defHour + 12, quarters % 4]
        }),
        new $.OffsetPickerDelegate(root),
        WatchUi.SLIDE_LEFT);
}

class HourFactory extends WatchUi.PickerFactory {

    public function initialize() {
        PickerFactory.initialize();
    }

    public function getSize() as Number {
        return 27;                      // -12 .. +14
    }

    public function getValue(index as Number) as Object? {
        return index - 12;
    }

    public function getDrawable(index as Number, selected as Boolean) as WatchUi.Drawable? {
        var v = index - 12;
        return pickerText((v < 0) ? v.format("%d") : "+" + v.format("%d"), selected);
    }
}

class MinuteFactory extends WatchUi.PickerFactory {

    public function initialize() {
        PickerFactory.initialize();
    }

    public function getSize() as Number {
        return OFFSET_STEPS.size();
    }

    public function getValue(index as Number) as Object? {
        return OFFSET_STEPS[index];
    }

    public function getDrawable(index as Number, selected as Boolean) as WatchUi.Drawable? {
        return pickerText(":" + (OFFSET_STEPS[index] as Number).format("%02d"), selected);
    }
}

function pickerText(s as String, selected as Boolean) as WatchUi.Text {
    return new WatchUi.Text({
        :text => s,
        :color => selected ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY,
        :font => Graphics.FONT_NUMBER_MILD,
        :locX => WatchUi.LAYOUT_HALIGN_CENTER,
        :locY => WatchUi.LAYOUT_VALIGN_CENTER
    });
}

class OffsetPickerDelegate extends WatchUi.PickerDelegate {

    private var _root as SettingsMenu;

    public function initialize(root as SettingsMenu) {
        PickerDelegate.initialize();
        _root = root;
    }

    public function onAccept(values as Array) as Boolean {
        var h = values[0] as Number;
        var m = values[1] as Number;

        // The sign belongs to the whole offset, not to the hour alone, so
        // -3 with :30 has to come out as -3.5 rather than -2.5.
        var magnitude = h.abs() + m / 60.0;
        saveProp("ExtraZoneOffset", (h < 0) ? -magnitude : magnitude);

        _root.refresh(:ExtraZoneOffset);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    public function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ---------------------------------------------------------------------------
// Property access and display text
// ---------------------------------------------------------------------------

function saveProp(key as String, value as Object) as Void {
    Application.Properties.setValue(key, value);

    // Editing on the device does not raise onSettingsChanged() the way the
    // phone app does, so tell the face to re-read its properties.
    var app = Application.getApp();
    if (app != null) {
        app.onSettingsChanged();
    }
}

function boolProp(key as String, fallback as Boolean) as Boolean {
    try {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Boolean) {
            return v;
        }
    } catch (e) {
    }
    return fallback;
}

function numberProp(key as String, fallback as Number) as Number {
    try {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Number) {
            return v;
        }
    } catch (e) {
    }
    return fallback;
}

function floatProp(key as String, fallback as Float) as Float {
    try {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Number || v instanceof Lang.Float ||
            v instanceof Lang.Long || v instanceof Lang.Double) {
            return v.toFloat();
        }
    } catch (e) {
    }
    return fallback;
}

function stringProp(key as String, fallback as String) as String {
    try {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.String) {
            return v;
        }
    } catch (e) {
    }
    return fallback;
}

function labelText() as String {
    var s = stringProp("ExtraZoneLabel", "");
    return s.equals("") ? "(none)" : s;
}

//! "UTC+05:30" - the same shape the offset is typed in as.
function offsetText() as String {
    var hours = floatProp("ExtraZoneOffset", 0.0);
    var quarters = Math.round(hours.abs() * 4.0).toNumber();
    return "UTC" + ((hours < 0) ? "-" : "+") +
           (quarters / 4).format("%02d") + ":" +
           ((quarters % 4) * 15).format("%02d");
}

function fieldChoices() as Array {
    return [
        [0, WatchUi.loadResource(Rez.Strings.FieldOff) as String],
        [1, WatchUi.loadResource(Rez.Strings.FieldDate) as String],
        [2, WatchUi.loadResource(Rez.Strings.FieldSteps) as String],
        [3, WatchUi.loadResource(Rez.Strings.FieldBattery) as String],
        [4, WatchUi.loadResource(Rez.Strings.FieldCalories) as String],
        [5, WatchUi.loadResource(Rez.Strings.FieldDistance) as String],
        [6, WatchUi.loadResource(Rez.Strings.FieldNotifications) as String],
        [7, WatchUi.loadResource(Rez.Strings.FieldZone) as String],
        [8, WatchUi.loadResource(Rez.Strings.FieldHr) as String],
        [9, WatchUi.loadResource(Rez.Strings.FieldSolar) as String],
        [10, WatchUi.loadResource(Rez.Strings.FieldPressure) as String],
        [11, WatchUi.loadResource(Rez.Strings.FieldTemp) as String],
        [12, WatchUi.loadResource(Rez.Strings.FieldWatchTemp) as String]
    ];
}

//! The top row used to be a ShowExtraZone toggle rather than a field, so
//! TopField ships with a sentinel default of -1 meaning "never set". Read it
//! through here: the first read converts the old toggle and writes the answer
//! back, after which the sentinel is gone for good.
function topFieldProp() as Number {
    var v = numberProp("TopField", TOP_FIELD_UNSET);
    if (v != TOP_FIELD_UNSET) {
        return v;
    }

    var migrated = boolProp("ShowExtraZone", false) ? 7 : 0;
    Application.Properties.setValue("TopField", migrated);
    return migrated;
}

function labelChoices() as Array {
    return [
        ["", "(none)"], ["UTC", "UTC"], ["HOME", "HOME"], ["LON", "LON"],
        ["NY", "NY"], ["LA", "LA"], ["TOK", "TOK"], ["SYD", "SYD"]
    ];
}

function fieldText(key as String, fallback as Number) as String {
    return fieldName(numberProp(key, fallback));
}

function topFieldText() as String {
    return fieldName(topFieldProp());
}

function fieldName(value as Number) as String {
    var choices = fieldChoices();
    for (var i = 0; i < choices.size(); i++) {
        var c = choices[i] as Array;
        if ((c[0] as Number) == value) {
            return c[1] as String;
        }
    }
    return "?";
}
