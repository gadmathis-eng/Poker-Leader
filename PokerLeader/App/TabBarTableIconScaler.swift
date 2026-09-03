import SwiftUI
import UIKit

private struct TabBarTableIconScaler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scaleTableIconIfNeeded()
        }

        private func scaleTableIconIfNeeded() {
            guard let items = tabBarController?.tabBar.items, items.count >= 3 else { return }
            let item = items[2]
            guard item.title == "Table" else { return }
            guard item.image?.size.width ?? 0 < 34 else { return }

            guard let base = UIImage(named: "PokerTableIcon")?.withRenderingMode(.alwaysTemplate) else { return }
            let scale: CGFloat = 1.12
            let newSize = CGSize(width: base.size.width * scale, height: base.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let scaled = renderer.image { _ in
                base.draw(in: CGRect(origin: .zero, size: newSize))
            }
            item.image = scaled
            item.selectedImage = scaled
        }
    }
}

extension View {
    func scaleTableTabIcon() -> some View {
        background(TabBarTableIconScaler())
    }
}
