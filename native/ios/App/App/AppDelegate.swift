import SwiftUI
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.tintColor = UIColor(red: 0.37, green: 0.22, blue: 0.48, alpha: 1)
        self.window = window
        self.window?.rootViewController = UIHostingController(rootView: StemacleRootView())
        self.window?.makeKeyAndVisible()
        return true
    }
}
