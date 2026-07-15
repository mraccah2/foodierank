import  Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
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
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
