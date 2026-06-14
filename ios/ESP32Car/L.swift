import Foundation

/// Typed accessors for localized strings. Text lives in Resources/<lang>.lproj/Localizable.strings.
enum L {
    private static func s(_ key: String, _ args: CVarArg...) -> String {
        let f = NSLocalizedString(key, comment: "")
        return args.isEmpty ? f : String(format: f, arguments: args)
    }
    static var connectTitle: String { s("connect.title") }
    static var connectBody: String { s("connect.body") }
    static var openSettings: String { s("common.openSettings") }
    static var close: String { s("common.close") }
    static var settingsTitle: String { s("settings.title") }
    static var settingsCalibration: String { s("settings.calibration") }
    static var calibTitle: String { s("calib.title") }
    static var calibForward: String { s("calib.forward") }
    static var calibBack: String { s("calib.back") }
    static var calibSpin: String { s("calib.spin") }
    static var calibAllSet: String { s("calib.allSet") }
    static var calibSave: String { s("calib.save") }
    static var calibSpinSub: String { s("calib.spinSub") }
    static var calibWhichDir2: String { s("calib.whichDir2") }
    static var calibDoneTitle: String { s("calib.doneTitle") }
    static var calibSaving: String { s("calib.saving") }
    static var calibSavingSub: String { s("calib.savingSub") }
    static var calibFailTitle: String { s("calib.failTitle") }
    static var calibFailSub: String { s("calib.failSub") }
    static var calibRetry: String { s("calib.retry") }
    static func calibWheel(_ w: String) -> String { s("calib.wheel", w) }
    static var driveSearching: String { s("drive.searching") }
    static var schemeArcade: String { s("scheme.arcade") }
    static var schemeTank: String { s("scheme.tank") }
    static func calibStep(_ n: Int) -> String { s("calib.step", n) }
    static var settingsFirmware: String { s("settings.firmware") }
    static var fwChecking: String { s("fw.checking") }
    static var fwUpToDate: String { s("fw.upToDate") }
    static var fwRecheck: String { s("fw.recheck") }
    static var fwAvailable: String { s("fw.available") }
    static var fwUpdate: String { s("fw.update") }
    static var fwDownloadTitle: String { s("fw.downloadTitle") }
    static var fwConnectTitle: String { s("fw.connectTitle") }
    static var fwConnectSub: String { s("fw.connectSub") }
    static var fwFlash: String { s("fw.flash") }
    static var fwUploadTitle: String { s("fw.uploadTitle") }
    static var fwRebootTitle: String { s("fw.rebootTitle") }
    static var fwRebootWait: String { s("fw.rebootWait") }
    static var fwDoneTitle: String { s("fw.doneTitle") }
    static var fwFailTitle: String { s("fw.failTitle") }
    static var fwFailSub: String { s("fw.failSub") }
    static var fwRetry: String { s("fw.retry") }
    static func fwCurrent(_ v: String) -> String { s("fw.current", v) }
    static func fwVersionLine(_ v: String) -> String { s("fw.versionLine", v) }
    static func fwTransition(_ a: String, _ b: String) -> String { s("fw.transition", a, b) }
    static func fwDoneSub(_ v: String) -> String { s("fw.doneSub", v) }
    static var driveConnected: String { s("drive.connected") }
    static var rampTitle: String { s("ramp.title") }
    static var rampHeadline: String { s("ramp.headline") }
    static var rampSub: String { s("ramp.sub") }
    static var rampValueOff: String { s("ramp.valueOff") }
    static func rampValue(_ ms: Int) -> String { s("ramp.value", ms) }
    static var trimTitle: String { s("trim.title") }
    static var trimSub: String { s("trim.sub") }
    static var trimCenter: String { s("trim.center") }
    static func trimLeft(_ p: Int) -> String { s("trim.left", p) }
    static func trimRight(_ p: Int) -> String { s("trim.right", p) }
    static var recoverTitle: String { s("recover.title") }
    static var recoverHeadline: String { s("recover.headline") }
    static var recoverEnable: String { s("recover.enable") }
    static var recoverWindow: String { s("recover.window") }
    static func recoverWindowValue(_ sec: Int) -> String { s("recover.windowValue", sec) }
    static var recoverSubOn: String { s("recover.subOn") }
    static var recoverSubOff: String { s("recover.subOff") }
    static func trickName(_ key: String) -> String { s(key) }
    static var tricksTitle: String { s("tricks.title") }
    static func trickSec(_ v: Double) -> String { s("tricks.sec", v) }
    static func trickMult(_ v: Double) -> String { s("tricks.mult", v) }
    static func driveWdtTrips(_ n: Int) -> String { s("drive.wdtTrips", n) }
    static var gateNoInternetTitle: String { s("gate.noInternetTitle") }
    static var gateNoInternetSub: String { s("gate.noInternetSub") }
    static var gateCheckFailedTitle: String { s("gate.checkFailedTitle") }
    static var gateCheckFailedSub: String { s("gate.checkFailedSub") }
    static var gateUpdateTitle: String { s("gate.updateTitle") }
    static var gateUpdateSub: String { s("gate.updateSub") }
    static func uptime(_ sec: Int) -> String {
        if sec < 60 { return s("uptime.sec", sec) }
        if sec < 3600 { return s("uptime.min", sec / 60) }
        if sec < 86400 { return s("uptime.hourMin", sec / 3600, (sec % 3600) / 60) }
        return s("uptime.day", sec / 86400)
    }
}
