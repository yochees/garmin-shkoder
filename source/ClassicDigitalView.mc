import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// ---------------------------------------------------------------------------
// Layout constants. Everything that controls the look lives here - tune these
// in the simulator, they are all in pixels on the 280x280 screen. onLayout()
// scales them about the screen centre for other sizes (see scaleY()), so on
// 280x280 they are used exactly as written.
// ---------------------------------------------------------------------------

const TIME_Y = 140;         // vertical centre of the big time block
const MAX_TIME_W = 264;     // step the font down if the time is wider than this

// Vector face for the clock. Measured digit advances on this device at size
// 100, as "1" / "8":
//   PridiSemiBoldGarmin   28 / 38   <- the only proportional one, but quirky
//   NotoSansSCMedium      39 / 39
//   BionicSemiBold        41 / 41   <- what FONT_NUMBER_* is built from
//   RobotoCondensedBold   43 / 43
//   NanumGothicExtraBold  53 / 53   <- the fattest
// Every plain sans on the device is tabular, so "1" sits in a cell as wide as
// "8". TRIM_ONE claws that cell back to fake proportional spacing.
// Set TIME_VECTOR to false to go back to the bitmap FONT_NUMBER_THAI_HOT.
const TIME_VECTOR = true;
// Faces in order of preference - getVectorFont() takes the first one the
// device has. Only fenix 8 Solar and Enduro 3 carry BionicSemiBold; most
// other vector devices have BionicBold. RobotoCondensedBold is the last
// vector option before the bitmap fonts.
const TIME_FACE = ["BionicSemiBold", "BionicBold", "RobotoCondensedBold"];
const TIME_SIZE = 148;      // requested pixel height; shrinks to fit if needed
const TRIM_ONE = 0.28;      // fraction of the "1" cell to claw back (see below)

// The two rows are mirrored about the digits, but not about TIME_Y: VCENTER
// centres the font's whole box, and the digits use none of the descender space
// at the bottom of it, so their ink sits ~4px higher than the value asked for.
// Measured on device at TIME_SIZE 148, the ink runs 99..174 - centre 136. Both
// rows hang off that instead, which is what makes the two gaps come out equal.
const TIME_INK_Y = 137;     // optical centre of the digit ink
const ROW_GAP = 68;         // ink centre to the centre of each row

const FIELD_Y = TIME_INK_Y + ROW_GAP;   // complication row, below the time
const FIELD_GAP = 10;       // padding either side of the "|" separator
const FIELD_COLOR = Graphics.COLOR_LT_GRAY;

// Single complication above the time, in the same font and colour as the row
// below it. Any of the field types, including the extra time zone.
//
// TOP_LIFT breaks the mirror on purpose: the row below carries the date, which
// is wider and heavier, so hanging the top row at the same distance makes it
// look low. Lifting it a few pixels evens out what the eye sees rather than
// what the ruler says. Set it to 0 for a true mirror.
const TOP_LIFT = 4;
const TOP_Y = TIME_INK_Y - ROW_GAP - TOP_LIFT;  // top field row, above the time

// Complications use the same vector face as the clock, so the whole face is
// one family. The alternative is the bitmap FONT_TINY (RobotoCondensed-Bold,
// 26px, sizes 19 XTINY / 26 TINY / 29 SMALL / 33 MEDIUM) - crisper, being
// hand-tuned rather than rasterised, but a different family; set FIELD_VECTOR
// to false for it. There is no Bionic bitmap at this size: the nearest is
// FONT_NUMBER_MILD at 48px, far too big, and it carries no letters.
//
// FIELD_SIZE is em, not cap height: 37 measures the same 18.5px of digit ink
// as FONT_TINY did, and 32 - what this uses - about 16px.
const FIELD_VECTOR = true;
const FIELD_FACE = ["BionicSemiBold", "BionicBold", "BionicMedium", "RobotoCondensedBold"];
const FIELD_SIZE = 32;

const MARK_RADIUS = 133;    // radius of the marker centre
const MARK_W = 3;           // tangential width
const MARK_LEN = 6;         // radial length (2:1 against the width)

const REF_SIZE = 280;       // screen width the constants above are tuned on

//! Set to -1 to show the real step count.
const MOCK_STEPS = -1;

enum FieldType {
    FIELD_OFF = 0,
    FIELD_DATE = 1,
    FIELD_STEPS = 2,
    FIELD_BATTERY = 3,
    FIELD_CALORIES = 4,
    FIELD_DISTANCE = 5,
    FIELD_NOTIFICATIONS = 6,
    FIELD_ZONE = 7,
    FIELD_HR = 8,
    FIELD_SOLAR = 9,
    FIELD_PRESSURE = 10,
    FIELD_TEMP = 11,
    FIELD_WATCH_TEMP = 12
}

//! Big centred time, two minimalist complications below it, and a single
//! second marker sweeping the rim, kept alive by onPartialUpdate().
class ClassicDigitalView extends WatchUi.WatchFace {

    private var _cx as Number = 140;
    private var _cy as Number = 140;

    // Layout constants scaled to this screen in onLayout().
    private var _scale as Float = 1.0;
    private var _timeY as Number = TIME_Y;
    private var _topY as Number = TOP_Y;
    private var _fieldY as Number = FIELD_Y;
    private var _fieldGap as Number = FIELD_GAP;
    private var _markRadius as Float = MARK_RADIUS.toFloat();
    private var _markW as Float = MARK_W.toFloat();
    private var _markLen as Float = MARK_LEN.toFloat();

    private var _isAwake as Boolean = true;
    private var _partialUpdatesAllowed as Boolean = false;
    private var _prevSec as Number = -1;

    private var _timeFont as FontType = Graphics.FONT_NUMBER_THAI_HOT;
    private var _fieldFont as FontType = Graphics.FONT_TINY;

    //! Holds the static face (time + complications) so a partial update can
    //! restore whatever the marker was covering instead of blanking it.
    private var _buffer as BufferedBitmap?;

    // Trig for the 60 marker positions, computed once.
    private var _sinT as Array<Float>;
    private var _cosT as Array<Float>;

    // Settings
    private var _leadingZero as Boolean = true;
    private var _topField as Number = FIELD_OFF;
    private var _leftField as Number = FIELD_DATE;
    private var _rightField as Number = FIELD_STEPS;
    private var _extraZoneOffset as Number = 0;   // seconds ahead of UTC
    private var _extraZoneLabel as String = "";

    public function initialize() {
        WatchFace.initialize();

        var sinT = new Array<Float>[60];
        var cosT = new Array<Float>[60];
        for (var s = 0; s < 60; s++) {
            var a = s * 6.0 * Math.PI / 180.0;
            sinT[s] = Math.sin(a).toFloat();
            cosT[s] = Math.cos(a).toFloat();
        }
        _sinT = sinT;
        _cosT = cosT;

        // On this device (MIP) this is true; on AMOLED siblings it is not,
        // and the face degrades to minute-only updates on its own.
        _partialUpdatesAllowed = (WatchUi.WatchFace has :onPartialUpdate);

        loadSettings();
    }

    public function onLayout(dc as Dc) as Void {
        _cx = dc.getWidth() / 2;
        _cy = dc.getHeight() / 2;

        _scale = dc.getWidth().toFloat() / REF_SIZE;
        _timeY = scaleY(TIME_Y);
        _topY = scaleY(TOP_Y);
        _fieldY = scaleY(FIELD_Y);
        _fieldGap = scaled(FIELD_GAP);
        _markRadius = MARK_RADIUS * _scale;
        _markW = MARK_W * _scale;
        _markLen = MARK_LEN * _scale;

        _timeFont = pickTimeFont(dc);
        _fieldFont = pickFieldFont();

        // Comes out of the 1 MB graphics pool, not the 128 kB app budget.
        if (Graphics has :createBufferedBitmap) {
            var ref = Graphics.createBufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            });
            _buffer = ref.get() as BufferedBitmap?;
        }
    }

    //! A length from the 280x280 layout, scaled to this screen.
    private function scaled(v as Number) as Number {
        return Math.round(v * _scale).toNumber();
    }

    //! A y position from the 280x280 layout, measured from the centre so the
    //! face stays centred on screens of other sizes.
    private function scaleY(y as Number) as Number {
        return _cy + scaled(y - REF_SIZE / 2);
    }

    //! Prefer the vector face at the largest size that still fits four wide
    //! digits, falling back to the built-in bitmap numerals.
    private function pickTimeFont(dc as Dc) as FontType {
        if (TIME_VECTOR && (Graphics has :getVectorFont)) {
            var size = scaled(TIME_SIZE);
            while (size >= 60) {
                var vf = Graphics.getVectorFont({:face => TIME_FACE, :size => size});
                if (vf != null && dc.getTextWidthInPixels("8888", vf) <= scaled(MAX_TIME_W)) {
                    return vf;
                }
                size -= 4;
            }
        }

        var candidates = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM
        ];
        for (var i = 0; i < candidates.size(); i++) {
            var f = candidates[i] as FontDefinition;
            if (dc.getTextWidthInPixels("8888", f) <= scaled(MAX_TIME_W)) {
                return f;
            }
        }
        return Graphics.FONT_NUMBER_MEDIUM;
    }

    private function pickFieldFont() as FontType {
        if (FIELD_VECTOR && (Graphics has :getVectorFont)) {
            var vf = Graphics.getVectorFont({:face => FIELD_FACE, :size => scaled(FIELD_SIZE)});
            if (vf != null) {
                return vf;
            }
        }
        return Graphics.FONT_TINY;
    }

    // -----------------------------------------------------------------------
    // Settings
    // -----------------------------------------------------------------------

    public function loadSettings() as Void {
        _leadingZero = boolSetting("LeadingZero", true);
        _topField = $.topFieldProp();
        _leftField = numberSetting("LeftField", FIELD_DATE);
        _rightField = numberSetting("RightField", FIELD_STEPS);

        // Hours from UTC, clamped to the real range and snapped to the quarter
        // hour so that 5.5 (India) and 5.75 (Nepal) land exactly.
        var hours = floatSetting("ExtraZoneOffset", 0.0);
        if (hours < -12.0) {
            hours = -12.0;
        } else if (hours > 14.0) {
            hours = 14.0;
        }
        _extraZoneOffset = Math.round(hours * 4.0).toNumber() * 900;

        // Trimmed here as well as on the way in, so a label of spaces stored by
        // an older build cannot shove the row off centre with leading padding.
        _extraZoneLabel = $.trimSpaces(stringSetting("ExtraZoneLabel", ""));
    }

    //! Settings editors hand a numeric property back as a Number, a Float or a
    //! Double depending on what was typed, so accept any of them.
    private function floatSetting(key as String, fallback as Float) as Float {
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

    private function stringSetting(key as String, fallback as String) as String {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Lang.String) {
                return v;
            }
        } catch (e) {
        }
        return fallback;
    }

    private function numberSetting(key as String, fallback as Number) as Number {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Lang.Number) {
                return v;
            }
            if (v instanceof Lang.Float) {
                return v.toNumber();
            }
        } catch (e) {
            // property missing on first run - fall through
        }
        return fallback;
    }

    private function boolSetting(key as String, fallback as Boolean) as Boolean {
        try {
            var v = Application.Properties.getValue(key);
            if (v instanceof Lang.Boolean) {
                return v;
            }
        } catch (e) {
        }
        return fallback;
    }

    // -----------------------------------------------------------------------
    // Full redraw - runs once a minute, plus on wake and on settings changes
    // -----------------------------------------------------------------------

    public function onUpdate(dc as Dc) as Void {
        dc.clearClip();

        var buf = _buffer;
        var target = (buf != null) ? buf.getDc() : dc;

        target.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        target.clear();
        drawTime(target);
        drawFields(target);
        drawTopField(target);

        if (buf != null) {
            dc.drawBitmap(0, 0, buf);
        }

        var sec = System.getClockTime().sec;
        // Only show a second marker if it will actually keep moving.
        if (_isAwake || _partialUpdatesAllowed) {
            drawSecondMarks(dc, sec);
        }
        _prevSec = sec;
    }

    //! One string, no colon, no manual tracking - the font's own metrics decide
    //! the spacing, which is what keeps "1422" and "1500" optically consistent.
    private function drawTime(dc as Dc) as Void {
        // Always 24 hour, regardless of the system setting.
        var clock = System.getClockTime();
        var hourStr = _leadingZero ? clock.hour.format("%02d") : clock.hour.format("%d");
        var digits = hourStr + clock.min.format("%02d");
        var count = digits.length();

        // Advance each digit by its own trimmed cell rather than the font's
        // tabular one, so a "1" no longer leaves a hole beside it.
        var cells = new Array<Number>[count];
        var total = 0;
        for (var i = 0; i < count; i++) {
            var w = dc.getTextWidthInPixels(glyphAt(digits, i), _timeFont);
            cells[i] = glyphAt(digits, i).equals("1") ? w - (w * TRIM_ONE).toNumber() : w;
            total += cells[i];
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var just = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = _cx - total / 2;

        for (var i = 0; i < count; i++) {
            var g = glyphAt(digits, i);
            var full = dc.getTextWidthInPixels(g, _timeFont);
            // Keep the ink centred inside the narrowed cell.
            dc.drawText(x - (full - cells[i]) / 2, _timeY, _timeFont, g, just);
            x += cells[i];
        }
    }

    private function glyphAt(s as String, i as Number) as String {
        var g = s.substring(i, i + 1);
        return (g == null) ? "" : g;
    }

    // -----------------------------------------------------------------------
    // Top row - one field above the time, mirroring the complication row
    // -----------------------------------------------------------------------

    //! Centred rather than split in two: it is usually the extra time zone,
    //! which is wide, and a lone value reads better without a separator.
    private function drawTopField(dc as Dc) as Void {
        var text = fieldText(_topField);
        if (text == null) {
            return;
        }

        dc.setColor(FIELD_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            _cx, _topY, _fieldFont, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Unlike the big time this keeps its colon: at complication size four bare
    //! digits are hard to read, and the main time has no colon to clash with.
    //! 24 hour throughout, like drawTime().
    private function zoneText() as String {
        // The zone's wall clock is UTC shifted by a fixed offset, so read the
        // shifted moment back as UTC rather than as device local time.
        var moment = Time.now().add(new Time.Duration(_extraZoneOffset));
        var t = Gregorian.utcInfo(moment, Time.FORMAT_SHORT);

        var text = t.hour.format("%02d") + ":" + t.min.format("%02d");
        if (!_extraZoneLabel.equals("")) {
            text = _extraZoneLabel + " " + text;
        }
        return text;
    }

    // -----------------------------------------------------------------------
    // Complication row - numbers only, separated by a dim pipe
    // -----------------------------------------------------------------------

    private function drawFields(dc as Dc) as Void {
        var lTxt = fieldText(_leftField);
        var rTxt = fieldText(_rightField);

        var lw = (lTxt == null) ? 0 : dc.getTextWidthInPixels(lTxt, _fieldFont);
        var rw = (rTxt == null) ? 0 : dc.getTextWidthInPixels(rTxt, _fieldFont);
        var both = (lTxt != null) && (rTxt != null);
        var sw = both ? dc.getTextWidthInPixels("|", _fieldFont) : 0;

        var total = lw + rw;
        if (both) {
            total += _fieldGap * 2 + sw;
        }

        var just = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var x = _cx - total / 2;

        dc.setColor(FIELD_COLOR, Graphics.COLOR_TRANSPARENT);
        if (lTxt != null) {
            dc.drawText(x, _fieldY, _fieldFont, lTxt, just);
            x += lw;
        }

        if (both) {
            x += _fieldGap;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, _fieldY, _fieldFont, "|", just);
            x += sw + _fieldGap;
            dc.setColor(FIELD_COLOR, Graphics.COLOR_TRANSPARENT);
        }

        if (rTxt != null) {
            dc.drawText(x, _fieldY, _fieldFont, rTxt, just);
        }
    }

    private function fieldText(field as Number) as String? {
        switch (field) {
            case FIELD_DATE: {
                var d = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
                return Lang.format("$1$ $2$", [d.day_of_week, d.day.format("%d")]);
            }

            case FIELD_STEPS: {
                if (MOCK_STEPS >= 0) {
                    return MOCK_STEPS.format("%d");
                }
                var steps = ActivityMonitor.getInfo().steps;
                return (steps == null) ? "--" : steps.format("%d");
            }

            case FIELD_BATTERY: {
                return System.getSystemStats().battery.toNumber().format("%d") + "%";
            }

            case FIELD_CALORIES: {
                var cal = ActivityMonitor.getInfo().calories;
                return (cal == null) ? "--" : cal.format("%d");
            }

            case FIELD_DISTANCE: {
                var cm = ActivityMonitor.getInfo().distance;
                if (cm == null) {
                    return "--";
                }
                if (System.getDeviceSettings().distanceUnits == System.UNIT_METRIC) {
                    return (cm / 100000.0).format("%.1f") + "km";
                }
                return (cm / 160934.4).format("%.1f") + "mi";
            }

            case FIELD_NOTIFICATIONS: {
                var n = System.getDeviceSettings().notificationCount;
                return (n == null) ? "0" : n.format("%d");
            }

            case FIELD_ZONE: {
                return zoneText();
            }

            //! Activity first: in a watch face it carries the last reading the
            //! optical sensor took, which in low-power mode is a minute old at
            //! worst. The history is only there for the gap right after a
            //! reload, when Activity has nothing yet.
            case FIELD_HR: {
                var hr = null;
                var act = Activity.getActivityInfo();
                if (act != null) {
                    hr = act.currentHeartRate;
                }
                if (hr == null && (ActivityMonitor has :getHeartRateHistory)) {
                    var it = ActivityMonitor.getHeartRateHistory(1, true);
                    var s = (it == null) ? null : it.next();
                    if (s != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                        hr = s.heartRate;
                    }
                }
                return (hr == null) ? "--" : hr.format("%d");
            }

            //! Percent, not the lux hours the solar glance shows - Connect IQ
            //! exposes only this instantaneous figure, so the two will not
            //! agree and are not meant to.
            case FIELD_SOLAR: {
                var stats = System.getSystemStats();
                if (!(stats has :solarIntensity)) {
                    return "--";
                }
                var si = stats.solarIntensity;
                return (si == null) ? "--" : si.format("%d") + "%";
            }

            case FIELD_PRESSURE: {
                var pa = null;
                var act = Activity.getActivityInfo();
                if (act != null && (act has :ambientPressure)) {
                    pa = act.ambientPressure;
                }
                if (pa == null) {
                    pa = newestSample(:getPressureHistory);
                }
                // Pascals in, millibars out - the unit every altimeter watch
                // states pressure in.
                return (pa == null) ? "--" : (pa / 100.0).format("%.0f") + "mb";
            }

            case FIELD_TEMP: {
                if (!(Toybox has :Weather)) {
                    return "--";
                }
                var cc = Weather.getCurrentConditions();
                if (cc == null || cc.temperature == null) {
                    return "--";
                }
                return tempText(cc.temperature);
            }

            case FIELD_WATCH_TEMP: {
                var c = newestSample(:getTemperatureHistory);
                return (c == null) ? "--" : tempText(c);
            }
        }
        return null;
    }

    //! Newest reading from one of the SensorHistory series, or null if the
    //! device has no such sensor and on the older firmware that has no
    //! SensorHistory at all.
    private function newestSample(which as Symbol) as Numeric? {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has which)) {
            return null;
        }

        var it = (which == :getPressureHistory)
            ? SensorHistory.getPressureHistory({})
            : SensorHistory.getTemperatureHistory({});

        // Empty on a watch that has not logged a sample yet - a fresh reboot,
        // or a series the device does not keep at all.
        var s = it.next();
        return (s == null) ? null : s.data;
    }

    //! Celsius in - both sources report it - converted to whatever the watch
    //! is set to. Rounded rather than truncated, so -0.4 does not read as 0
    //! while -0.6 reads as -1.
    private function tempText(celsius as Numeric) as String {
        var v = celsius;
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            v = celsius * 9.0 / 5.0 + 32.0;
        }
        return Math.round(v).toNumber().format("%d") + "°";
    }

    // -----------------------------------------------------------------------
    // The moving second marker: a single mark, twice as long radially as it
    // is wide, so it stays radial at every position on the rim.
    // -----------------------------------------------------------------------

    //! Four corners of the marker, built from the radial and tangential unit
    //! vectors at second s.
    private function markCorners(s as Number) as Array<[Numeric, Numeric]> {
        var ux = _sinT[s];          // radial, pointing outwards
        var uy = -_cosT[s];
        var vx = _cosT[s];          // tangential
        var vy = _sinT[s];

        var cxp = _cx + _markRadius * ux;
        var cyp = _cy + _markRadius * uy;

        var hl = _markLen / 2.0;
        var hw = _markW / 2.0;

        return [
            [(cxp - hl * ux - hw * vx).toNumber(), (cyp - hl * uy - hw * vy).toNumber()],
            [(cxp + hl * ux - hw * vx).toNumber(), (cyp + hl * uy - hw * vy).toNumber()],
            [(cxp + hl * ux + hw * vx).toNumber(), (cyp + hl * uy + hw * vy).toNumber()],
            [(cxp - hl * ux + hw * vx).toNumber(), (cyp - hl * uy + hw * vy).toNumber()]
        ];
    }

    private function drawSecondMarks(dc as Dc, s as Number) as Void {
        dc.setColor(FIELD_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(markCorners(s));
    }

    //! Bounding box of the marker at second s.
    private function marksBox(s as Number) as Array<Number> {
        var pts = markCorners(s);
        var x0 = pts[0][0];
        var y0 = pts[0][1];
        var x1 = x0;
        var y1 = y0;

        for (var i = 1; i < pts.size(); i++) {
            var p = pts[i];
            if (p[0] < x0) { x0 = p[0]; }
            if (p[1] < y0) { y0 = p[1]; }
            if (p[0] > x1) { x1 = p[0]; }
            if (p[1] > y1) { y1 = p[1]; }
        }

        var pad = 2;
        x0 -= pad;
        y0 -= pad;
        x1 += pad;
        y1 += pad;

        if (x0 < 0) { x0 = 0; }
        if (y0 < 0) { y0 = 0; }
        if (x1 > _cx * 2 - 1) { x1 = _cx * 2 - 1; }
        if (y1 > _cy * 2 - 1) { y1 = _cy * 2 - 1; }

        return [x0, y0, x1 - x0 + 1, y1 - y0 + 1];
    }

    //! Repaint just the box around one second position by blitting the static
    //! face back, so the marker can pass over the digits without eating them.
    private function repaintSecond(dc as Dc, s as Number, highlight as Boolean) as Void {
        var box = marksBox(s);
        dc.setClip(box[0], box[1], box[2], box[3]);

        var buf = _buffer;
        if (buf != null) {
            dc.drawBitmap(0, 0, buf);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
        }

        if (highlight) {
            drawSecondMarks(dc, s);
        }
        dc.clearClip();
    }

    //! Called once a second in low-power mode. Keep this cheap - the device
    //! measures how long it takes and will cut us off if we overspend.
    public function onPartialUpdate(dc as Dc) as Void {
        if (!_partialUpdatesAllowed) {
            return;
        }

        var sec = System.getClockTime().sec;
        if (sec == _prevSec) {
            return;
        }

        if (_prevSec >= 0) {
            repaintSecond(dc, _prevSec, false);
        }
        repaintSecond(dc, sec, true);
        _prevSec = sec;
    }

    // -----------------------------------------------------------------------

    public function onExitSleep() as Void {
        _isAwake = true;
    }

    public function onEnterSleep() as Void {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    public function disablePartialUpdates() as Void {
        _partialUpdatesAllowed = false;
        WatchUi.requestUpdate();
    }
}
