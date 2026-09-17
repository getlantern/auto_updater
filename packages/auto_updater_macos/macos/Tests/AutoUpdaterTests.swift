import Cocoa
import Sparkle
import XCTest

final class AutoUpdaterTests: XCTestCase {
    private var delegate: AutoUpdater!
    private var updater: SPUUpdater!
    private var events: [(String, NSDictionary)] = []

    override func setUp() {
        delegate = AutoUpdater()
        updater = delegate._updater!
        events = []
        delegate.onEvent = { [weak self] type, data in
            self?.events.append((type, data))
        }
    }

    func testNoUpdateIsNotAFailure() {
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))
        delegate.updaterDidNotFindUpdate(updater, error: error)
        delegate.updater(updater, didAbortWithError: error)
        delegate.updater(updater, didFinishUpdateCycleFor: .updates, error: error)
        XCTAssertEqual(events.map { $0.0 }, ["update-not-available", "update-cycle-finished"])
        XCTAssertEqual(events[0].1["errorCode"] as? Int, error.code)
        XCTAssertNil(events[1].1["error"])
    }

    func testFailurePreservesCodeAndDomain() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                            userInfo: [NSLocalizedDescriptionKey: "Network unavailable"])
        delegate.updater(updater, didAbortWithError: error)
        delegate.updater(updater, didFinishUpdateCycleFor: .updates, error: error)
        XCTAssertEqual(events.map { $0.0 }, ["error", "update-cycle-finished"])
        for (_, data) in events {
            XCTAssertEqual(data["error"] as? String, "Network unavailable")
            XCTAssertEqual(data["errorCode"] as? Int, error.code)
            XCTAssertEqual(data["errorDomain"] as? String, NSURLErrorDomain)
        }
    }

    func testNoUpdateCodeInAnotherDomainIsStillAFailure() {
        let error = NSError(domain: "OtherUpdater", code: Int(SUError.noUpdateError.rawValue))
        delegate.updater(updater, didAbortWithError: error)
        delegate.updater(updater, didFinishUpdateCycleFor: .updates, error: error)
        XCTAssertEqual(events.map { $0.0 }, ["error", "update-cycle-finished"])
        XCTAssertNotNil(events[1].1["error"])
    }

    func testCancellationIsReportedOncePerCycle() throws {
        let error = NSError(domain: SUSparkleErrorDomain,
                            code: Int(SUError.installationCanceledError.rawValue))
        try delegate.updater(updater, mayPerform: .updates)
        delegate.userDidCancelDownload(updater)
        delegate.updater(updater, didAbortWithError: error)
        delegate.updater(updater, didFinishUpdateCycleFor: .updates, error: error)
        XCTAssertEqual(events.map { $0.0 }, ["update-cancelled", "update-cycle-finished"])
        XCTAssertNil(events[1].1["error"])

        try delegate.updater(updater, mayPerform: .updates)
        delegate.userDidCancelDownload(updater)
        delegate.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
        XCTAssertEqual(events.map { $0.0 }, ["update-cancelled", "update-cycle-finished",
                                            "update-cancelled", "update-cycle-finished"])
    }

    func testNormalCompletionHasNoError() {
        delegate.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
        XCTAssertEqual(events.map { $0.0 }, ["update-cycle-finished"])
        XCTAssertEqual(events[0].1.count, 0)
    }

    func testLifecycleMethodsMatchSparkleDelegateSelectors() {
        XCTAssertTrue(delegate.responds(to: #selector(SPUUpdaterDelegate.updater(_:mayPerform:))))
        XCTAssertTrue(delegate.responds(to: #selector(SPUUpdaterDelegate.updater(_:userDidMake:forUpdate:state:))))
        XCTAssertTrue(delegate.responds(to: #selector(SPUUpdaterDelegate.userDidCancelDownload(_:))))
        XCTAssertTrue(delegate.responds(to: #selector(SPUUpdaterDelegate.updater(_:didFinishUpdateCycleFor:error:))))
    }

    func testInitializationFailureIsReturnedToTheCaller() {
        // This command-line test host has no app bundle metadata for Sparkle.
        XCTAssertThrowsError(try delegate.setFeedURL(URL(string: "https://example.com/appcast.xml"))) { error in
            XCTAssertEqual((error as NSError).domain, SUSparkleErrorDomain)
        }
    }
}

@main
struct TestRunner {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: AutoUpdaterTests.self)
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0 else { exit(1) }
        exit(result.hasSucceeded ? 0 : 1)
    }
}
