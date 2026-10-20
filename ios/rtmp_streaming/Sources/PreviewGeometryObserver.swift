import UIKit

/// Observe the Flutter host's actual scene, including split-view layout changes.
/// Window aspect ratio is layout information, not capture orientation.
@MainActor
final class PreviewGeometryObserver: UIViewController {
  var onGeometryChanged: (() -> Void)?

  override func loadView() {
    view = UIView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onGeometryChanged?()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    onGeometryChanged?()
  }

  override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
      self?.onGeometryChanged?()
    }
  }

  func attach(to host: UIViewController) {
    host.addChild(self)
    view.frame = host.view.bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.view.addSubview(view)
    didMove(toParent: host)
  }

  func detach() {
    onGeometryChanged = nil
    willMove(toParent: nil)
    view.removeFromSuperview()
    removeFromParent()
  }
}
