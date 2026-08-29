import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import GoogleMaps
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    FirebaseApp.configure()

    provideGoogleMapsAPIKey()

    _ = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    if
      let url = AppLinks.shared.getLink(launchOptions: launchOptions),
      isLocalLinkDeepLink(url)
    {
      logDeepLink(
        callback: "didFinishLaunchingWithOptions",
        url: url,
        handled: true
      )
      AppLinks.shared.handleLink(url: url)
      return true
    }

    return true
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if
      userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL,
      isLocalLinkDeepLink(url)
    {
      logDeepLink(
        callback: "application_continueUserActivity",
        url: url,
        handled: true
      )
      AppLinks.shared.handleLink(url: url)
      return true
    }

    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if isLocalLinkDeepLink(url) {
      logDeepLink(
        callback: "application_openURL",
        url: url,
        handled: true
      )
      AppLinks.shared.handleLink(url: url)
      return true
    }

    return super.application(application, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(
      with: engineBridge.pluginRegistry
    )
  }

  private func provideGoogleMapsAPIKey() {
    if
      let apiKey = Bundle.main.object(
        forInfoDictionaryKey: "GoogleMapsAPIKey"
      ) as? String,
      !apiKey.isEmpty,
      !apiKey.contains("$(")
    {
      GMSServices.provideAPIKey(apiKey)
      return
    }

    guard
      let path = Bundle.main.path(
        forResource: "GoogleService-Info",
        ofType: "plist"
      ),
      let config = NSDictionary(contentsOfFile: path),
      let apiKey = config["API_KEY"] as? String,
      !apiKey.isEmpty
    else {
      print("Google Maps API key is missing. Map tiles will not load.")
      return
    }

    print("Using Firebase API_KEY for Google Maps. Prefer GoogleMapsAPIKey in Info.plist.")
    GMSServices.provideAPIKey(apiKey)
  }

  private func isLocalLinkDeepLink(_ url: URL) -> Bool {
    if url.scheme?.lowercased() == "locallink" {
      return isSupportedLocalLinkScheme(url.host)
    }

    guard
      let scheme = url.scheme?.lowercased(),
      let host = url.host?.lowercased()
    else {
      return false
    }

    return (scheme == "https" || scheme == "http")
      && host == "locallinkapp.co.uk"
      && isSupportedLocalLinkPath(url.path)
  }

  private func isSupportedLocalLinkPath(_ path: String) -> Bool {
    return path.hasPrefix("/community-help/")
      || path.hasPrefix("/opportunities/")
      || path.hasPrefix("/availability/")
      || path.hasPrefix("/businesses/")
      || path.hasPrefix("/services/")
  }

  private func isSupportedLocalLinkScheme(_ host: String?) -> Bool {
    switch host?.lowercased() {
    case "community-help", "opportunity", "availability", "business":
      return true
    default:
      return false
    }
  }

  private func logDeepLink(callback: String, url: URL, handled: Bool) {
    #if DEBUG
    print("LocalLink deep link \(callback): \(url.absoluteString), handled=\(handled)")
    #endif
  }
}
