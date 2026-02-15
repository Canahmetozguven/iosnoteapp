import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Forward to the download manager so it can call back when all events are delivered.
        ModelDownloadManager.shared.backgroundSessionCompletionHandler = completionHandler
    }
}

