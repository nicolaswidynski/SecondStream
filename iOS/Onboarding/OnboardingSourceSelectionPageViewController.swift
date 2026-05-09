//
//  OnboardingSourceSelectionPageViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import Account
import RSCore

/// Page 2 of onboarding: horizontal-scrolling source strips for Podcasts, YouTube, and Topics.
///
/// The Continue button stays disabled until the user selects at least one source.
/// Sources are loaded by the parent `OnboardingViewController` (via `reloadSources()`)
/// after `SourcesRefreshManager.shared.forceRefreshAndWait()` completes.
@MainActor final class OnboardingSourceSelectionPageViewController: UIViewController {

	var onContinue: (([DiscoverSourceItem]) -> Void)?

	// MARK: - State

	private var selectedSources: [DiscoverSourceItem] = []

	// MARK: - Views

	private let scrollView: UIScrollView = {
		let sv = UIScrollView()
		sv.showsVerticalScrollIndicator = false
		sv.delaysContentTouches = false
		sv.translatesAutoresizingMaskIntoConstraints = false
		return sv
	}()

	private let contentStack: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.spacing = 24
		stack.alignment = .fill
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	private let loadingIndicator: UIActivityIndicatorView = {
		let iv = UIActivityIndicatorView(style: .large)
		iv.hidesWhenStopped = true
		iv.translatesAutoresizingMaskIntoConstraints = false
		return iv
	}()

	private lazy var continueButton: UIButton = {
		var config = UIButton.Configuration.filled()
		config.title = "Continue"
		config.cornerStyle = .medium
		config.baseBackgroundColor = Assets.Colors.primaryAccent
		config.baseForegroundColor = .white
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.isEnabled = false
		button.alpha = 0.5
		button.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
		return button
	}()

	// Source strips — populated by reloadSources()
	private let podcastStrip = OnboardingSourceStripView(title: "Podcasts")
	private let youtubeStrip = OnboardingSourceStripView(title: "YouTube")
	private let topicsStrip = OnboardingSourceStripView(title: "Topics")

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background

		let titleLabel = UILabel()
		titleLabel.text = "Let's Get Started"
		titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
		titleLabel.textAlignment = .center

		let subtitleLabel = UILabel()
		subtitleLabel.text = "Pick what you want to follow. You can always add more later."
		subtitleLabel.font = .systemFont(ofSize: 15)
		subtitleLabel.textColor = .secondaryLabel
		subtitleLabel.textAlignment = .center
		subtitleLabel.numberOfLines = 0

		contentStack.addArrangedSubview(titleLabel)
		contentStack.setCustomSpacing(8, after: titleLabel)
		contentStack.addArrangedSubview(subtitleLabel)
		contentStack.addArrangedSubview(podcastStrip)
		contentStack.addArrangedSubview(youtubeStrip)
		contentStack.addArrangedSubview(topicsStrip)

		scrollView.addSubview(contentStack)
		view.addSubview(scrollView)
		view.addSubview(loadingIndicator)
		view.addSubview(continueButton)

		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -16),

			contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 40),
			contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
			contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
			contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
			contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

			loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

			continueButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			continueButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
			continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -52),
			continueButton.heightAnchor.constraint(equalToConstant: 50)
		])

		for strip in [podcastStrip, youtubeStrip, topicsStrip] {
			strip.onSelectionChanged = { [weak self] source, selected in
				self?.handleSelectionChange(source: source, selected: selected)
			}
		}

		// Show spinner until reloadSources() is called
		if MediaSourcesManager.podcast.topSources.isEmpty {
			contentStack.isHidden = true
			loadingIndicator.startAnimating()
		} else {
			reloadSources()
		}
	}

	// MARK: - API

	/// Called by `OnboardingViewController` once `SourcesRefreshManager.forceRefreshAndWait()` resolves.
	func reloadSources() {
		loadingIndicator.stopAnimating()
		contentStack.isHidden = false

		let podcasts = MediaSourcesManager.podcast.topSources.map {
			DiscoverSourceItem(name: $0.name, author: $0.author, url: $0.url, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight, category: .podcast)
		}
		let youtubes = MediaSourcesManager.youtube.topSources.map {
			DiscoverSourceItem(name: $0.name, author: $0.author, url: $0.url, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight, category: .youtube)
		}
		let topics = NewsSourcesManager.shared.newsSources.map {
			DiscoverSourceItem(name: $0.name, author: $0.author, url: $0.url, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight, category: .news)
		}

		podcastStrip.configure(with: podcasts)
		youtubeStrip.configure(with: youtubes)
		topicsStrip.configure(with: topics)
	}

	// MARK: - Private

	private func handleSelectionChange(source: DiscoverSourceItem, selected: Bool) {
		if selected {
			selectedSources.append(source)
		} else {
			selectedSources.removeAll { $0.name == source.name }
		}
		let hasSelection = !selectedSources.isEmpty
		continueButton.isEnabled = hasSelection
		UIView.animate(withDuration: 0.2, delay: 0, options: .allowUserInteraction) {
			self.continueButton.alpha = hasSelection ? 1.0 : 0.5
		}
	}

	@objc private func continueTapped() {
		onContinue?(selectedSources)
	}
}

// MARK: - OnboardingSourceStripView

/// A labeled horizontal-scrolling row of tappable source icons, styled like the main-feed strip.
@MainActor final class OnboardingSourceStripView: UIView {

	var onSelectionChanged: ((DiscoverSourceItem, Bool) -> Void)?

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.font = UIFont.preferredFont(forTextStyle: .title3).bold()
		label.textColor = .label
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let backgroundView: UIView = {
		let view = UIView()
		view.layer.cornerRadius = 20
		view.clipsToBounds = true
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}()

	private let scrollView: IconScrollView = {
		let sv = IconScrollView()
		sv.showsHorizontalScrollIndicator = false
		sv.showsVerticalScrollIndicator = false
		sv.alwaysBounceVertical = false
		sv.isDirectionalLockEnabled = true
		sv.clipsToBounds = false
		sv.delaysContentTouches = false
		sv.translatesAutoresizingMaskIntoConstraints = false
		return sv
	}()

	private let stackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .horizontal
		stack.spacing = 10
		stack.alignment = .center
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	private var items: [(source: DiscoverSourceItem, view: OnboardingSourceIconView)] = []
	private var selectedNames = Set<String>()

	// MARK: - Init

	init(title: String) {
		super.init(frame: .zero)
		titleLabel.text = title
		backgroundView.backgroundColor = Assets.Colors.foreground
		translatesAutoresizingMaskIntoConstraints = false
		setup()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	// MARK: - Layout

	private func setup() {
		scrollView.contentInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

		addSubview(titleLabel)
		addSubview(backgroundView)
		backgroundView.addSubview(scrollView)
		scrollView.addSubview(stackView)

		NSLayoutConstraint.activate([
			titleLabel.topAnchor.constraint(equalTo: topAnchor),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

			backgroundView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
			backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
			backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
			backgroundView.heightAnchor.constraint(equalToConstant: 108),
			backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

			scrollView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 8),
			scrollView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -8),
			scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
			scrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),

			stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			stackView.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
			stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
		])
	}

	// MARK: - API

	func configure(with sources: [DiscoverSourceItem]) {
		NotificationCenter.default.removeObserver(self, name: .sourceImageDidBecomeAvailable, object: nil)
		items = []
		selectedNames = []
		stackView.arrangedSubviews.forEach {
			stackView.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}

		for source in sources {
			let iconView = OnboardingSourceIconView()
			iconView.translatesAutoresizingMaskIntoConstraints = false
			iconView.setImage(iconImage(for: source))
			iconView.setName(source.name)
			iconView.accessibilityLabel = source.name
			iconView.onTap = { [weak self, weak iconView] in
				guard let self, let iconView else { return }
				self.iconTapped(iconView)
			}
			NSLayoutConstraint.activate([
				iconView.widthAnchor.constraint(equalToConstant: 71)
			])
			stackView.addArrangedSubview(iconView)
			items.append((source: source, view: iconView))
		}

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sourceImageAvailable(_:)),
			name: .sourceImageDidBecomeAvailable,
			object: nil
		)
	}

	// MARK: - Actions

	private func iconTapped(_ sender: OnboardingSourceIconView) {
		guard let (source, _) = items.first(where: { $0.view === sender }) else { return }
		let alreadySelected = selectedNames.contains(source.name)
		let isNowSelected = !alreadySelected
		if isNowSelected {
			selectedNames.insert(source.name)
		} else {
			selectedNames.remove(source.name)
		}
		sender.setSelected(isNowSelected, animated: true)
		onSelectionChanged?(source, isNowSelected)
	}

	@objc private func sourceImageAvailable(_ notification: Notification) {
		guard let url = notification.userInfo?["url"] as? String else { return }
		for (source, iconView) in items where source.imageURL == url || source.imageURLLight == url {
			iconView.setImage(iconImage(for: source))
		}
	}

	// MARK: - Image resolution

	private func iconImage(for source: DiscoverSourceItem) -> UIImage {
		if let darkURL = source.imageURL {
			let lightURL = source.imageURLLight
			if let image = SourceImageCache.shared.adaptiveImage(darkURL: darkURL, lightURL: lightURL) {
				return image
			}
			// Kick off async download; notification will update the view when ready.
			_ = SourceImageCache.shared.image(for: darkURL)
		}

		let config = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
		let fallback: UIImage?
		switch source.category {
		case .podcast:
			fallback = RSImage(named: "podcast_thin-symbol")?.applyingSymbolConfiguration(config)
				?? UIImage(systemName: "mic.fill", withConfiguration: config)
		case .youtube:
			fallback = UIImage(systemName: "play.rectangle", withConfiguration: config)
		case .news:
			fallback = UIImage(systemName: "newspaper", withConfiguration: config)
		case .rss:
			fallback = RSImage(named: "rss_thin-symbol")?.applyingSymbolConfiguration(config)
				?? UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config)
		}
		return (fallback ?? Assets.Images.nnwFeedIcon).withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
	}
}

// MARK: - OnboardingSourceIconView

/// A single tappable source icon with a name label and a thick blue selection ring.
@MainActor final class OnboardingSourceIconView: UIControl {

	/// Called when the user taps the icon. Set by the strip view.
	var onTap: (() -> Void)?


	private let iconImageView: UIImageView = {
		let iv = UIImageView()
		iv.translatesAutoresizingMaskIntoConstraints = false
		iv.contentMode = .scaleAspectFill
		iv.backgroundColor = Assets.Colors.foreground
		iv.layer.cornerRadius = 12
		iv.clipsToBounds = true
		return iv
	}()

	/// Sits behind the icon and provides the blue border when selected.
	private let selectionRing: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.layer.cornerRadius = 15
		view.layer.borderWidth = 3
		view.layer.borderColor = Assets.Colors.primaryAccent.cgColor
		view.isUserInteractionEnabled = false
		view.alpha = 0
		return view
	}()

	private let nameLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .systemFont(ofSize: 10, weight: .medium)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.numberOfLines = 1
		label.lineBreakMode = .byTruncatingTail
		return label
	}()

	// MARK: - Init

	override init(frame: CGRect) {
		super.init(frame: frame)

		let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
		tap.cancelsTouchesInView = false
		addGestureRecognizer(tap)

		addSubview(selectionRing)
		addSubview(iconImageView)
		addSubview(nameLabel)

		NSLayoutConstraint.activate([
			selectionRing.centerXAnchor.constraint(equalTo: centerXAnchor),
			selectionRing.topAnchor.constraint(equalTo: topAnchor),
			selectionRing.widthAnchor.constraint(equalToConstant: 74),
			selectionRing.heightAnchor.constraint(equalToConstant: 74),

			iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
			iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
			iconImageView.widthAnchor.constraint(equalToConstant: 67),
			iconImageView.heightAnchor.constraint(equalToConstant: 67),

			nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 5),
			nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
			nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
			nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	// MARK: - Actions

	@objc private func handleTap() {
		onTap?()
	}

	// MARK: - API

	func setImage(_ image: UIImage?) {
		iconImageView.image = image
	}

	func setName(_ name: String) {
		nameLabel.text = name
	}

	func setSelected(_ selected: Bool, animated: Bool) {
		let targetAlpha: CGFloat = selected ? 1 : 0
		let targetScale: CGFloat = selected ? 1.06 : 1.0
		let scaleTransform = CGAffineTransform(scaleX: targetScale, y: targetScale)
		if animated {
			UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
				self.selectionRing.alpha = targetAlpha
				self.iconImageView.transform = scaleTransform
				self.selectionRing.transform = scaleTransform
			}
		} else {
			selectionRing.alpha = targetAlpha
			iconImageView.transform = scaleTransform
			selectionRing.transform = scaleTransform
		}
	}

	// MARK: - Highlight

	override var isHighlighted: Bool {
		didSet {
			UIView.animate(withDuration: 0.1, delay: 0, options: .allowUserInteraction) {
				self.iconImageView.alpha = self.isHighlighted ? 0.65 : 1.0
			}
		}
	}
}

// MARK: - IconScrollView

private final class IconScrollView: UIScrollView {
	override func touchesShouldCancel(in view: UIView) -> Bool {
		view is UIControl ? true : super.touchesShouldCancel(in: view)
	}
}
