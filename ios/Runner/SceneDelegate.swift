import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(
      scene,
      willConnectTo: session,
      options: connectionOptions
    )

    if let url = localLinkUrl(from: connectionOptions) {
      logDeepLink(
        callback: "scene_willConnectToSession",
        url: url,
        handled: true
      )
      AppLinks.shared.handleLink(url: url)
    }
  }

  override func scene(
    _ scene: UIScene,
    continue userActivity: NSUserActivity
  ) {
    if
      userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL,
      isLocalLinkDeepLink(url)
    {
      logDeepLink(callback: "scene_continueUserActivity", url: url, handled: true)
      AppLinks.shared.handleLink(url: url)
      return
    }

    super.scene(scene, continue: userActivity)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for context in URLContexts {
      if isLocalLinkDeepLink(context.url) {
        logDeepLink(callback: "scene_openURLContexts", url: context.url, handled: true)
        AppLinks.shared.handleLink(url: context.url)
        return
      }
    }

    super.scene(scene, openURLContexts: URLContexts)
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

  private func localLinkUrl(
    from connectionOptions: UIScene.ConnectionOptions
  ) -> URL? {
    for userActivity in connectionOptions.userActivities {
      if
        userActivity.activityType == NSUserActivityTypeBrowsingWeb,
        let url = userActivity.webpageURL,
        isLocalLinkDeepLink(url)
      {
        return url
      }
    }

    for context in connectionOptions.urlContexts {
      if isLocalLinkDeepLink(context.url) {
        return context.url
      }
    }

    return nil
  }

  private func logDeepLink(callback: String, url: URL, handled: Bool) {
    #if DEBUG
    print("LocalLink deep link \(callback): \(url.absoluteString), handled=\(handled)")
    #endif
  }
}
