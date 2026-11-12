import  Flutter
import UIKit
import GoogleMaps

// UIScene lifecycle (Info.plist UIApplicationSceneManifest → FlutterSceneDelegate).
// iOS 27 refuses to launch an app built with the iOS 27 SDK that has not
// adopted scenes. With scenes, the Flutter engine is created implicitly by the
// storyboard's FlutterViewController, so plugins are registered when that
// engine exists rather than in didFinishLaunching.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialise the Google Maps SDK for the embedded map picker. The key is
    // injected at build time via the GMSApiKey Info.plist entry (fed from
    // Secrets.xcconfig / CI), so no secret is hardcoded here.
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsApiKey.isEmpty,
       mapsApiKey != "$(GOOGLE_MAPS_IOS_API_KEY)" {
      GMSServices.provideAPIKey(mapsApiKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
