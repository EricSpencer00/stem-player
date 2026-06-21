import SwiftUI
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        configureSystemBarAppearance()
        // Keep in sync with StemacleDesign.paper
        let paper = UIColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = paper
        window.tintColor = UIColor(red: 0.37, green: 0.22, blue: 0.48, alpha: 1)
        let rootViewController = UIHostingController(rootView: StemacleRootView())
        rootViewController.view.backgroundColor = paper
        self.window = window
        self.window?.rootViewController = rootViewController
        self.window?.makeKeyAndVisible()
        return true
    }

    private func configureSystemBarAppearance() {
        let paper = UIColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1)
        let ink = UIColor(red: 0.15, green: 0.12, blue: 0.15, alpha: 1)
        let track = UIColor(red: 0.72, green: 0.66, blue: 0.56, alpha: 0.66)
        let muted = UIColor(red: 0.46, green: 0.41, blue: 0.39, alpha: 1)
        let purple = UIColor(red: 0.29, green: 0.15, blue: 0.35, alpha: 1)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = paper
        navigation.shadowColor = track
        navigation.titleTextAttributes = [.foregroundColor: ink]
        navigation.largeTitleTextAttributes = [.foregroundColor: ink]
        UINavigationBar.appearance().tintColor = purple
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = paper
        tabs.backgroundEffect = nil
        tabs.shadowColor = track
        [
            tabs.stackedLayoutAppearance,
            tabs.inlineLayoutAppearance,
            tabs.compactInlineLayoutAppearance,
        ].forEach { item in
            item.normal.iconColor = muted
            item.normal.titleTextAttributes = [.foregroundColor: muted]
            item.selected.iconColor = purple
            item.selected.titleTextAttributes = [.foregroundColor: purple]
        }
        UITabBar.appearance().isTranslucent = false
        UITabBar.appearance().barTintColor = paper
        UITabBar.appearance().backgroundColor = paper
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().tintColor = purple
        UITabBar.appearance().unselectedItemTintColor = muted
    }
}

