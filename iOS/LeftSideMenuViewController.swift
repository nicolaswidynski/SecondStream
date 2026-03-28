//
//  LeftSideMenuViewController.swift
//  NetNewsWire-iOS
//

import UIKit

final class LeftSideMenuViewController: UIViewController {

	weak var coordinator: SceneCoordinator?

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.text = "Second Stream"
		label.font = .systemFont(ofSize: 22, weight: .bold)
		label.textColor = .label
		return label
	}()

	private lazy var settingsButton: UIButton = {
		var config = UIButton.Configuration.plain()
		config.image = UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
		config.title = NSLocalizedString("Settings", comment: "Settings")
		config.imagePlacement = .leading
		config.imagePadding = 12
		config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16)
		config.baseForegroundColor = .label
		config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
			var outgoing = incoming
			outgoing.font = UIFont.systemFont(ofSize: 16, weight: .medium)
			return outgoing
		}

		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.contentHorizontalAlignment = .leading
		button.addAction(UIAction { [weak self] _ in
			self?.settingsTapped()
		}, for: .touchUpInside)
		return button
	}()

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .systemBackground
		setupViews()

		let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftSwipe))
		swipeLeft.direction = .left
		view.addGestureRecognizer(swipeLeft)
	}

	private func setupViews() {
		view.addSubview(titleLabel)
		view.addSubview(settingsButton)

		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),

			settingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			settingsButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
			settingsButton.heightAnchor.constraint(equalToConstant: 50),
		])
	}

	@objc private func handleLeftSwipe() {
		coordinator?.hideLeftMenu()
	}

	private func settingsTapped() {
		coordinator?.hideLeftMenu { [weak self] in
			self?.coordinator?.showSettings()
		}
	}
}
