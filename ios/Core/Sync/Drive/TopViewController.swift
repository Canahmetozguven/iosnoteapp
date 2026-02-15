import UIKit

enum TopViewController {
    static func current() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.compactMap { $0 as? UIWindowScene }.first
        let root = windowScene?.keyWindow?.rootViewController
        return top(from: root)
    }

    private static func top(from vc: UIViewController?) -> UIViewController? {
        if let nav = vc as? UINavigationController {
            return top(from: nav.visibleViewController)
        }
        if let tab = vc as? UITabBarController {
            return top(from: tab.selectedViewController)
        }
        if let presented = vc?.presentedViewController {
            return top(from: presented)
        }
        return vc
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow }
    }
}

