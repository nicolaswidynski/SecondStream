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

	private lazy var creditsLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .systemFont(ofSize: 13)
		label.textColor = .secondaryLabel
		return label
	}()

	private lazy var addSectionLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.text = NSLocalizedString("Add", comment: "Add section header")
		label.font = .systemFont(ofSize: 13, weight: .semibold)
		label.textColor = .secondaryLabel
		return label
	}()

	private lazy var addStackView: UIStackView = {
		let stack = UIStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .vertical
		stack.spacing = 0
		return stack
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
		updateCredits()

		NotificationCenter.default.addObserver(self, selector: #selector(creditsDidUpdate), name: .creditsDidUpdate, object: nil)

		let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftSwipe))
		swipeLeft.direction = .left
		view.addGestureRecognizer(swipeLeft)
	}

	private func setupViews() {
		// Add row items
		let items: [(icon: String, title: String, action: Selector)] = [
			("mic.fill",          NSLocalizedString("Podcasts", comment: "Podcasts"),  #selector(addPodcastTapped)),
			("play.rectangle",    NSLocalizedString("YouTube",  comment: "YouTube"),   #selector(addYoutubeTapped)),
			("newspaper",         NSLocalizedString("News",     comment: "News"),      #selector(addNewsTapped)),
			("dot.radiowaves.left.and.right", NSLocalizedString("RSS", comment: "RSS"), #selector(addRSSTapped)),
		]

		for item in items {
			addStackView.addArrangedSubview(makeAddRow(icon: item.icon, title: item.title, action: item.action))
		}

		view.addSubview(titleLabel)
		view.addSubview(creditsLabel)
		view.addSubview(addSectionLabel)
		view.addSubview(addStackView)
		view.addSubview(settingsButton)

		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),

			creditsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			creditsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			creditsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

			addSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			addSectionLabel.topAnchor.constraint(equalTo: creditsLabel.bottomAnchor, constant: 32),

			addStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			addStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			addStackView.topAnchor.constraint(equalTo: addSectionLabel.bottomAnchor, constant: 8),

			settingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			settingsButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
			settingsButton.heightAnchor.constraint(equalToConstant: 50),
		])
	}

	private func makeAddRow(icon: String, title: String, action: Selector) -> UIButton {
		var config = UIButton.Configuration.plain()
		config.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
		config.title = title
		config.imagePlacement = .leading
		config.imagePadding = 12
		config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16)
		config.baseForegroundColor = .label
		config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
			var outgoing = incoming
			outgoing.font = UIFont.systemFont(ofSize: 16)
			return outgoing
		}

		let button = UIButton(configuration: config)
		button.contentHorizontalAlignment = .leading
		button.heightAnchor.constraint(equalToConstant: 50).isActive = true
		button.addTarget(self, action: action, for: .touchUpInside)
		return button
	}

	// MARK: - Credits

	@objc private func creditsDidUpdate() {
		updateCredits()
	}

	private func updateCredits() {
		if let credits = FeedStatsManager.shared.cachedCredits {
			creditsLabel.text = "\(credits) credits remaining"
		} else {
			creditsLabel.text = nil
		}
	}

	// MARK: - Actions

	@objc private func addPodcastTapped() {
		coordinator?.hideLeftMenu { [weak self] in
			self?.coordinator?.showPodcastPicker()
		}
	}

	@objc private func addYoutubeTapped() {
		coordinator?.hideLeftMenu { [weak self] in
			self?.coordinator?.showYoutubePicker()
		}
	}

	@objc private func addNewsTapped() {
		coordinator?.hideLeftMenu { [weak self] in
			self?.coordinator?.showNewsPicker()
		}
	}

	@objc private func addRSSTapped() {
		coordinator?.hideLeftMenu { [weak self] in
			self?.coordinator?.showRSSPicker()
		}
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
