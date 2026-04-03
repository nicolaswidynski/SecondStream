//
//  LeftSideMenuViewController.swift
//  NetNewsWire-iOS
//

import UIKit
import RSCore

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
		label.font = .systemFont(ofSize: 13)
		label.textColor = .secondaryLabel
		return label
	}()

	private lazy var creditsInfoButton: UIButton = {
		let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)
		let button = UIButton(type: .system)
		button.setImage(UIImage(systemName: "info.circle", withConfiguration: symbolConfig), for: .normal)
		button.tintColor = .secondaryLabel
		button.addAction(UIAction { [weak self] _ in
			Task { @MainActor [weak self] in await self?.handleCreditsInfo() }
		}, for: .touchUpInside)
		return button
	}()

	private lazy var creditsRowStack: UIStackView = {
		let stack = UIStackView(arrangedSubviews: [creditsLabel, creditsInfoButton])
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .horizontal
		stack.alignment = .top
		stack.spacing = 4
		return stack
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
		view.backgroundColor = Assets.Colors.background
		setupViews()
		updateCredits()

		NotificationCenter.default.addObserver(self, selector: #selector(creditsDidUpdate), name: .creditsDidUpdate, object: nil)

		let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftSwipe))
		swipeLeft.direction = .left
		view.addGestureRecognizer(swipeLeft)
	}

	private func setupViews() {
		// Add row items
		let items: [(icon: UIImage?, title: String, action: Selector)] = [
			(UIImage(systemName: "mic.fill"),       NSLocalizedString("Podcasts", comment: "Podcasts"), #selector(addPodcastTapped)),
			(UIImage(systemName: "play.rectangle"), NSLocalizedString("YouTube",  comment: "YouTube"),  #selector(addYoutubeTapped)),
			(UIImage(systemName: "newspaper"),      NSLocalizedString("News",     comment: "News"),     #selector(addNewsTapped)),
			(RSImage(named: "rss_thin-symbol") ?? UIImage(systemName: "dot.radiowaves.left.and.right"), NSLocalizedString("RSS", comment: "RSS"), #selector(addRSSTapped)),
		]

		for item in items {
			addStackView.addArrangedSubview(makeAddRow(icon: item.icon, title: item.title, action: item.action))
		}

		view.addSubview(titleLabel)
		view.addSubview(creditsRowStack)
		view.addSubview(addSectionLabel)
		view.addSubview(addStackView)
		view.addSubview(settingsButton)

		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),

			creditsRowStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			creditsRowStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
			creditsRowStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

			addSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			addSectionLabel.topAnchor.constraint(equalTo: creditsRowStack.bottomAnchor, constant: 32),

			addStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			addStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			addStackView.topAnchor.constraint(equalTo: addSectionLabel.bottomAnchor, constant: 8),

			settingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			settingsButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
			settingsButton.heightAnchor.constraint(equalToConstant: 50),
		])
	}

	private func makeAddRow(icon: UIImage?, title: String, action: Selector) -> UIControl {
		let row = UIControl()
		row.heightAnchor.constraint(equalToConstant: 40).isActive = true

		let iconView = UIImageView()
		iconView.image = icon
		iconView.contentMode = .center
		iconView.tintColor = .label
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true

		let label = UILabel()
		label.text = title
		label.font = .systemFont(ofSize: 16)
		label.textColor = .label
		label.translatesAutoresizingMaskIntoConstraints = false

		let stack = UIStackView(arrangedSubviews: [iconView, label])
		stack.axis = .horizontal
		stack.spacing = 12
		stack.alignment = .center
		stack.isUserInteractionEnabled = false
		stack.translatesAutoresizingMaskIntoConstraints = false

		row.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
			stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
			stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
		])

		row.addTarget(self, action: action, for: .touchUpInside)
		return row
	}

	// MARK: - Credits

	@objc private func creditsDidUpdate() {
		updateCredits()
	}

	private func updateCredits() {
		if let credits = FeedStatsManager.shared.cachedCredits {
			creditsLabel.text = "\(credits) remaining credits"
			creditsInfoButton.isHidden = false
		} else {
			creditsLabel.text = nil
			creditsInfoButton.isHidden = true
		}
	}

	@MainActor
	private func handleCreditsInfo() async {
		await FeedStatsManager.shared.reportUpdate()
		let credits = FeedStatsManager.shared.cachedCredits ?? 0
		let alert = UIAlertController(
			title: NSLocalizedString("Remaining Credits", comment: "Credits info title"),
			message: String(format: NSLocalizedString("You have %d remaining credits, please buy new ones or remove non-free Podcasts and YouTube Channels contents.", comment: "Credits info message"), credits),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
		present(alert, animated: true)
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
