import SafariServices
import UIKit

func prewarm(_ url: URL) {
  prewarmToken?.invalidate()
  prewarmToken = SFSafariViewController.prewarmConnections(to: [url])
}

func openInApp(_ url: URL) {
  guard ["http", "https"].contains(url.scheme) else {
    UIApplication.shared.open(url)
    return
  }
  let scene =
    UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
    as? UIWindowScene
  guard var top = scene?.keyWindow?.rootViewController else { return }
  while let presented = top.presentedViewController {
    top = presented
  }
  top.present(safariViewController(for: url), animated: true)
}

private var prewarmToken: SFSafariViewController.PrewarmingToken?

private var openedPages: [(url: URL, controller: SFSafariViewController)] = []
private let maxOpenedPages = 5

private func safariViewController(for url: URL) -> SFSafariViewController {
  if let index = openedPages.firstIndex(where: { $0.url == url }) {
    let page = openedPages.remove(at: index)
    openedPages.append(page)
    return page.controller
  }
  let controller = SFSafariViewController(url: url)
  openedPages.append((url, controller))
  if openedPages.count > maxOpenedPages {
    openedPages.removeFirst()
  }
  return controller
}
