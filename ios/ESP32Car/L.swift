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
    static var later: String { s("common.later") }
    static var settingsTitle: String { s("settings.title") }
    static var settingsCalibration: String { s("settings.calibration") }
    static var calibTitle: String { s("calib.title") }
    static var calibForward: String { s("calib.forward") }
    static var calibBack: String { s("calib.back") }
    static var calibSpin: String { s("calib.spin") }
    static var calibAllSet: String { s("calib.allSet") }
    static var calibSave: String { s("calib.save") }
    static var calibSaveFailed: String { s("calib.saveFailed") }
    static var driveSearching: String { s("drive.searching") }
    static var driveCalibratedYes: String { s("drive.calibratedYes") }
    static var driveCalibratedNo: String { s("drive.calibratedNo") }
    static var sideLeft: String { s("drive.sideLeft") }
    static var sideRight: String { s("drive.sideRight") }
    static var schemeArcade: String { s("scheme.arcade") }
    static var schemeTank: String { s("scheme.tank") }
    static func calibStep(_ n: Int) -> String { s("calib.step", n) }
    static func calibWhichDir(_ wheel: String) -> String { s("calib.whichDir", wheel) }
    static func calibSpinPrompt(_ n: Int) -> String { s("calib.spinPrompt", n) }
    static var settingsFirmware: String { s("settings.firmware") }
    static var fwUpToDate: String { s("fw.upToDate") }
    static var fwConnectCar: String { s("fw.connectCar") }
    static var fwFlash: String { s("fw.flash") }
    static var fwRebooting: String { s("fw.rebooting") }
    static var fwFailed: String { s("fw.failed") }
    static var fwDone: String { s("fw.done") }
    static var fwChecking: String { s("fw.checking") }
    static var fwRecheck: String { s("fw.recheck") }
    static var fwUpdate: String { s("fw.update") }
    static var fwDownloadingGh: String { s("fw.downloadingGh") }
    static var fwRebootWait: String { s("fw.rebootWait") }
    static var fwRetry: String { s("fw.retry") }
    static func fwCurrent(_ v: String) -> String { s("fw.current", v) }
    static func fwLatest(_ v: String) -> String { s("fw.latest", v) }
    static func fwDownloaded(_ v: String) -> String { s("fw.downloaded", v) }
    static func fwUploadingTag(_ v: String) -> String { s("fw.uploadingTag", v) }
    static func fwVersion(_ v: String) -> String { s("fw.version", v) }
    static func driveConnected(_ ms: Int) -> String { s("drive.connected", ms) }
    static func uptime(_ sec: Int) -> String {
        if sec < 60 { return s("uptime.sec", sec) }
        if sec < 3600 { return s("uptime.min", sec / 60) }
        if sec < 86400 { return s("uptime.hourMin", sec / 3600, (sec % 3600) / 60) }
        return s("uptime.day", sec / 86400)
    }
}
