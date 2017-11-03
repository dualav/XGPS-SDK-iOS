//
//  AppDelegate.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var xGpsManager: XGPSManager = XGPSManager()
    var reservedViewController:UIViewController! = nil

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        initializeUserDefault()
        loadingCustomLayouts()
        return true
    }
    
    func loadingCustomLayouts() {
        if let model = xGpsManager.currentModel {
            if (model.contains(XGPSManager.XGPS150)) {
                // if you use xgps150, you couldn't use trip mode.
                if let tabController = self.window?.rootViewController?.childViewControllers[0] as? UITabBarController, var viewControllers = tabController.viewControllers {
                    if reservedViewController == nil {
                        reservedViewController = viewControllers[1]
                        viewControllers.remove(at: 1)
                    }
                    tabController.viewControllers = viewControllers
                    tabController.removeFromParentViewController()
                    self.window?.rootViewController?.addChildViewController(tabController)
                    // further operations to make your root controller visible....
                }
                else {
                    print("tabController is nil")
                }
            }
            else if model.contains(XGPSManager.XGPS160) && reservedViewController != nil {
                if let tabController = self.window?.rootViewController?.childViewControllers[0] as? UITabBarController, var viewControllers = tabController.viewControllers {
                    viewControllers.insert(reservedViewController, at: 1)
                    reservedViewController = nil
                    tabController.viewControllers = viewControllers
                    tabController.removeFromParentViewController()
                    self.window?.rootViewController?.addChildViewController(tabController)
//                    self.window?.rootViewController = tabController
                    // further operations to make your root controller visible....
                }
            }
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        print("applicationDidEnterBackground")
//        xGpsManager.puck?.puck_applicationDidEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        print("applicationWillEnterForeground")
//        xGpsManager.puck?.puck_applicationWillEnterForeground()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        print("applicationDidBecomeActive")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        print("applicationWillTerminate")
    }

    class func getDelegate() -> AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }
    
    func initializeUserDefault() {
        if UserDefaults.standard.string(forKey: "speed_preference") == nil {
            UserDefaults.standard.set(Constants.speedUnits[2], forKey: "speed_preference")
        }
        if UserDefaults.standard.string(forKey: "altitude_preference") == nil {
            UserDefaults.standard.set(Constants.altitudeUnits[1], forKey: "altitude_preference")
        }
        if UserDefaults.standard.string(forKey: "position_preference") == nil {
            UserDefaults.standard.set(Constants.positionUnits[2], forKey: "position_preference")
        }
        if UserDefaults.standard.string(forKey: "record_rate_preference") == nil {
            UserDefaults.standard.set(Constants.recordingRates[2], forKey: "record_rate_preference")
        }
        if UserDefaults.standard.string(forKey: "update_rate_preference") == nil {
            UserDefaults.standard.set(Constants.updateRates[0], forKey: "update_rate_preference")
        }
    }
}

