import Cocoa
import Sparkle

extension SUAppcast {
    public func toDictionary() -> NSDictionary {
        let dict: NSDictionary = [
            "items": self.items.map({ item in
                return item.toDictionary()
            }),
        ]
        return dict;
    }
}

extension SUAppcastItem {
    
    
    public func toDictionary() -> NSDictionary {
        let dict: NSDictionary = [
            "versionString": self.versionString,
            "displayVersionString": self.displayVersionString,
            "fileURL": self.fileURL?.absoluteString ?? "",
            "contentLength": self.contentLength,
            "infoURL": self.infoURL?.absoluteString ?? "",
            "title":self.title ?? "",
            "dateString": self.dateString ?? "",
            "releaseNotesURL":self.releaseNotesURL?.absoluteString ?? "",
            "itemDescription":self.itemDescription ?? "",
            "itemDescriptionFormat": self.itemDescriptionFormat ?? "",
            "fullReleaseNotesURL": self.fullReleaseNotesURL ?? "",
            "minimumSystemVersion": self.minimumSystemVersion ?? "",
            "minimumOperatingSystemVersionIsOK": self.minimumOperatingSystemVersionIsOK,
            "maximumSystemVersion": self.maximumSystemVersion ?? "",
            "maximumOperatingSystemVersionIsOK": self.maximumOperatingSystemVersionIsOK,
            "channel": self.channel ?? "",
        ]
        return dict;
    }
}

public class AutoUpdater: NSObject, SPUUpdaterDelegate {
    var _userDriver: SPUStandardUserDriver?
    var _updater: SPUUpdater?
    var feedURL: URL?
    public var onEvent:((String, NSDictionary) -> Void)?
    private var didReportCancellation = false
    
    override init() {
        super.init()
        let hostBundle: Bundle = Bundle.main
        
        _userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        _updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: _userDriver!,
            delegate: self
        )
        _updater?.clearFeedURLFromUserDefaults()
    }
    
    public func feedURLString(for updater: SPUUpdater) -> String? {
        return feedURL?.absoluteString
    }

    public func setFeedURL(_ feedURL: URL?) throws {
        self.feedURL = feedURL
        try _updater?.start()
    }
    
    public func checkForUpdates() {
        _updater?.checkForUpdates()
    }
    
    public func checkForUpdatesInBackground() {
        _updater?.checkForUpdatesInBackground()
    }
    
    public func setScheduledCheckInterval(_ interval: Int) {
        _updater?.updateCheckInterval = TimeInterval(interval)
    }
    
    // SPUUpdaterDelegate

    public func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        didReportCancellation = false
    }
    
    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        // Sparkle also uses this callback for normal no-update and cancel outcomes.
        if error.domain == SUSparkleErrorDomain {
            if error.code == Int(SUError.noUpdateError.rawValue) {
                return
            }
            if error.code == Int(SUError.installationCanceledError.rawValue) {
                reportCancellation()
                return
            }
        }
        _emitEvent("error", Self.errorData(error))
    }
    
    public func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        let data: NSDictionary = [
            "appcast": appcast.toDictionary()
        ]
        _emitEvent("checking-for-update", data)
    }
    
    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let data: NSDictionary = [
            "appcastItem": item.toDictionary()
        ]
        _emitEvent("update-available", data)
    }
    
    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        _emitEvent("update-not-available", Self.errorData(error))
    }

    public func userDidCancelDownload(_ updater: SPUUpdater) {
        reportCancellation()
    }

    public func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                        forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip || (choice == .dismiss && state.stage != .installing) {
            reportCancellation()
        }
    }

    public func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                        error: Error?) {
        var data: NSDictionary = [:]
        if let error = error as NSError? {
            if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.installationCanceledError.rawValue) {
                reportCancellation()
            } else if error.domain != SUSparkleErrorDomain || error.code != Int(SUError.noUpdateError.rawValue) {
                data = Self.errorData(error)
            }
        }
        _emitEvent("update-cycle-finished", data)
    }
    
    public func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let data: NSDictionary = [
            "appcastItem": item.toDictionary()
        ]
        _emitEvent("update-downloaded", data)
    }
    
    public func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let data: NSDictionary = [
            "appcastItem": item.toDictionary()
        ]
        _emitEvent("before-quit-for-update", data)
        return true
    }
    
    public func _emitEvent(_ eventName: String, _ data: NSDictionary) {
        onEvent?(eventName, data)
    }

    private func reportCancellation() {
        guard !didReportCancellation else { return }
        didReportCancellation = true
        _emitEvent("update-cancelled", [:])
    }

    static func errorData(_ error: Error) -> NSDictionary {
        let error = error as NSError
        return [
            "error": error.localizedDescription,
            "errorCode": error.code,
            "errorDomain": error.domain,
        ]
    }
}
