//
//  GameViewController.swift
//  Auries
//

import UIKit
import SpriteKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let skView = self.view as? SKView else { return }

        // Fixed, non-zero size so the scene can never collapse to nothing.
        let scene = AurieDemoScene(size: CGSize(width: 400, height: 800))
        scene.scaleMode = .aspectFill
        skView.presentScene(scene)

        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true

        // Step-1 scaffold check: prove the bundled content loaded.
        let label = UILabel()
        label.text = "content ok · \(ContentService.loadedSummary)"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        skView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: skView.centerXAnchor),
            label.topAnchor.constraint(equalTo: skView.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
