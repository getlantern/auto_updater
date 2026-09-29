import Cocoa
import Sparkle

final class DeliveryDriver: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    let feed: String
    let expectFailure: Bool
    var reachedHandoff = false

    init(feed: String, expectFailure: Bool) {
        self.feed = feed
        self.expectFailure = expectFailure
        super.init()
    }

    func finish(_ success: Bool, _ message: String) {
        print(message)
        exit(success ? 0 : 1)
    }

    func feedURLString(for updater: SPUUpdater) -> String? { feed }
    func show(_ request: SPUUpdatePermissionRequest,
                                    reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateInFocus() {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        finish(false, "Release notes failed: \(error)")
    }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        finish(false, "No update: \(error)")
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let native = error as NSError
        var cause: NSError? = native
        var signatureFailure = false
        while let current = cause {
            signatureFailure = signatureFailure || (current.domain == SUSparkleErrorDomain
                && (current.code == Int(SUError.signatureError.rawValue)
                    || current.code == Int(SUError.validationError.rawValue)))
            cause = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        finish(expectFailure && signatureFailure, "Updater error: \(native)")
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Cancel before installation; this fixture only proves delivery and validation.
        reachedHandoff = true
        reply(.skip)
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        if reachedHandoff {
            finish(!expectFailure, "Verified update reached install handoff and was cancelled")
        }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        finish(false, "Unexpected installation")
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        finish(false, "Unexpected installation")
    }
    func dismissUpdateInstallation() {}
}

@main
struct DeliveryTest {
    static func main() throws {
        _ = NSApplication.shared
        let driver = DeliveryDriver(feed: CommandLine.arguments[1],
                                    expectFailure: CommandLine.arguments[2] == "invalid")
        driver.updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                    userDriver: driver, delegate: driver)
        driver.updater.clearFeedURLFromUserDefaults()
        try driver.updater.start()
        driver.updater.checkForUpdates()
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            driver.finish(false, "Native update timed out")
        }
        withExtendedLifetime(driver) { NSApplication.shared.run() }
    }
}
