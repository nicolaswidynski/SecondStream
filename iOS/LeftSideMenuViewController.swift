//
//  LeftSideMenuViewController.swift
//  NetNewsWire-iOS
//

import UIKit
import SwiftUI
import RSCore

// MARK: - Container

final class LeftSideMenuViewController: UIViewController {

	weak var coordinator: SceneCoordinator? {
		didSet { contentVC.coordinator = coordinator }
	}

	private let contentVC = LeftSideMenuContentViewController()

	private lazy var menuNavController: UINavigationController = {
		let nav = UINavigationController(rootViewController: contentVC)
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = Assets.Colors.SettingsNavBarColor
		appearance.shadowColor = Assets.Colors.separator
		nav.navigationBar.standardAppearance = appearance
		nav.navigationBar.scrollEdgeAppearance = appearance
		nav.navigationBar.compactAppearance = appearance
		nav.navigationBar.tintColor = Assets.Colors.primaryAccent
		return nav
	}()

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.SettingsContentBgColor
		contentVC.coordinator = coordinator

		addChild(menuNavController)
		menuNavController.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(menuNavController.view)
		NSLayoutConstraint.activate([
			menuNavController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			menuNavController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			menuNavController.view.topAnchor.constraint(equalTo: view.topAnchor),
			menuNavController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
		menuNavController.didMove(toParent: self)
		menuNavController.delegate = self

		let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftSwipe))
		swipeLeft.direction = .left
		view.addGestureRecognizer(swipeLeft)
	}

	/// Called by RootSplitViewController when the drawer is closed so the next open starts fresh.
	func resetNavigation() {
		menuNavController.popToRootViewController(animated: false)
	}

	@objc private func handleLeftSwipe() {
		coordinator?.hideLeftMenu()
	}
}

extension LeftSideMenuViewController: UINavigationControllerDelegate {
	func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
		let isRoot = viewController is LeftSideMenuContentViewController
		navigationController.setNavigationBarHidden(isRoot, animated: animated)
	}
}

// MARK: - Content

private final class LeftSideMenuContentViewController: UIViewController {

	weak var coordinator: SceneCoordinator?

	// MARK: - Title

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
		var config = UIButton.Configuration.plain()
		let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)
		config.image = UIImage(systemName: "info.circle", withConfiguration: symbolConfig)
		config.contentInsets = .zero
		config.baseForegroundColor = .secondaryLabel
		let button = UIButton(configuration: config)
		button.addAction(UIAction { [weak self] _ in
			Task { @MainActor [weak self] in await self?.handleCreditsInfo() }
		}, for: .touchUpInside)
		return button
	}()

	private lazy var creditsRowStack: UIStackView = {
		let stack = UIStackView(arrangedSubviews: [creditsLabel, creditsInfoButton])
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .horizontal
		stack.alignment = .center
		stack.spacing = 4
		creditsLabel.setContentHuggingPriority(.required, for: .horizontal)
		creditsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
		return stack
	}()

	// MARK: - Scroll content

	private lazy var scrollView: UIScrollView = {
		let sv = UIScrollView()
		sv.translatesAutoresizingMaskIntoConstraints = false
		sv.alwaysBounceVertical = true
		sv.showsHorizontalScrollIndicator = false
		return sv
	}()

	private lazy var contentStack: UIStackView = {
		let stack = UIStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .vertical
		stack.spacing = 0
		return stack
	}()

	// MARK: - Add section

	private lazy var addSectionLabel: UIView = makeSectionLabel(NSLocalizedString("Add", comment: "Add section header"))

	private lazy var addStackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.spacing = 0
		return stack
	}()

	// MARK: - Settings section

	private lazy var settingsSectionLabel: UIView = makeSectionLabel(NSLocalizedString("Settings", comment: "Settings section header"))

	private lazy var settingsStackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.spacing = 0
		return stack
	}()

	// MARK: - Build label (bottom, fixed)

	private lazy var buildLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.text = "\(Bundle.main.appName) \(Bundle.main.versionNumber) (Build \(Bundle.main.buildNumber))"
		label.font = .systemFont(ofSize: 11)
		label.textColor = .tertiaryLabel
		label.textAlignment = .center
		label.isUserInteractionEnabled = true
		return label
	}()

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.SettingsContentBgColor
		setupViews()
		NotificationCenter.default.addObserver(self, selector: #selector(creditsDidUpdate), name: .creditsDidUpdate, object: nil)

		let tripleTap = UITapGestureRecognizer(target: self, action: #selector(buildLabelTripleTapped))
		tripleTap.numberOfTapsRequired = 3
		buildLabel.addGestureRecognizer(tripleTap)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateCredits()
	}

	private func setupViews() {
		// Add section rows
		let addItems: [(icon: UIImage?, title: String, action: Selector)] = [
			(RSImage(named: "podcast_thin-symbol") ?? UIImage(systemName: "mic.fill"), NSLocalizedString("Podcasts", comment: "Podcasts"), #selector(addPodcastTapped)),
			(UIImage(systemName: "play.rectangle"), NSLocalizedString("YouTube",  comment: "YouTube"),  #selector(addYoutubeTapped)),
			(UIImage(systemName: "newspaper"),      NSLocalizedString("News",     comment: "News"),     #selector(addNewsTapped)),
			(RSImage(named: "rss_thin-symbol") ?? UIImage(systemName: "dot.radiowaves.left.and.right"), NSLocalizedString("RSS", comment: "RSS"), #selector(addRSSTapped)),
		]
		for item in addItems {
			addStackView.addArrangedSubview(makeMenuRow(icon: item.icon, title: item.title, action: item.action))
		}

		// Settings section rows
		for item in SettingsSidebarItem.allCases {
			if item == .about {
				settingsStackView.addArrangedSubview(makeMenuRow(
					icon: UIImage(systemName: "ladybug"),
					title: NSLocalizedString("Report a Bug", comment: "Report a Bug"),
					action: #selector(reportBugTapped)
				))
			}
			settingsStackView.addArrangedSubview(makeSettingsRow(for: item))
		}

		// Assemble content stack
		contentStack.addArrangedSubview(makePadding(height: 14))
		contentStack.addArrangedSubview(titleLabel)
		contentStack.addArrangedSubview(makePadding(height: 4))
		contentStack.addArrangedSubview(creditsRowStack)
		contentStack.addArrangedSubview(makePadding(height: 12))
		contentStack.addArrangedSubview(makeSeparator())
		contentStack.addArrangedSubview(makePadding(height: 8))
		contentStack.addArrangedSubview(addSectionLabel)
		contentStack.addArrangedSubview(makePadding(height: 6))
		contentStack.addArrangedSubview(addStackView)
		contentStack.addArrangedSubview(makePadding(height: 14))
		contentStack.addArrangedSubview(settingsSectionLabel)
		contentStack.addArrangedSubview(makePadding(height: 6))
		contentStack.addArrangedSubview(settingsStackView)
		contentStack.addArrangedSubview(makePadding(height: 10))

		// Scroll view
		scrollView.addSubview(contentStack)
		view.addSubview(scrollView)
		view.addSubview(buildLabel)

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: buildLabel.topAnchor, constant: -8),

			contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
			contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
			contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

			titleLabel.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 20),
			titleLabel.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -16),

			creditsRowStack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 20),
			creditsRowStack.trailingAnchor.constraint(lessThanOrEqualTo: contentStack.trailingAnchor, constant: -16),

			buildLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
			buildLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			buildLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
		])
	}

	// MARK: - Row builders

	private func makeMenuRow(icon: UIImage?, title: String, action: Selector) -> UIControl {
		let row = UIControl()
		row.heightAnchor.constraint(equalToConstant: 44).isActive = true

		let iconView = UIImageView()
		iconView.image = icon
		iconView.contentMode = .center
		iconView.tintColor = Assets.Colors.primaryAccent
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true

		let label = UILabel()
		label.text = title
		label.font = .systemFont(ofSize: 16)
		label.textColor = .label
		label.translatesAutoresizingMaskIntoConstraints = false

		let stack = UIStackView(arrangedSubviews: [iconView, label])
		stack.axis = .horizontal
		stack.spacing = 14
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

	private func makeSettingsRow(for item: SettingsSidebarItem) -> UIControl {
		let row = UIControl()
		row.heightAnchor.constraint(equalToConstant: 44).isActive = true

		let tintColor: UIColor = item.isDestructive ? .systemRed : Assets.Colors.primaryAccent

		let iconView = UIImageView()
		iconView.image = item.icon
		iconView.contentMode = .scaleAspectFit
		iconView.tintColor = tintColor
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
		iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true

		let label = UILabel()
		label.text = item.title
		label.font = .systemFont(ofSize: 16)
		label.textColor = item.isDestructive ? .systemRed : .label

		let rightView: UIView?
		if item.showsChevron {
			let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
			chevron.contentMode = .scaleAspectFit
			chevron.tintColor = .tertiaryLabel
			chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
			chevron.translatesAutoresizingMaskIntoConstraints = false
			chevron.widthAnchor.constraint(equalToConstant: 12).isActive = true
			rightView = chevron
		} else {
			rightView = nil
		}

		var arranged: [UIView] = [iconView, label]
		if let rv = rightView {
			let spacer = UIView()
			spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
			arranged += [spacer, rv]
		}

		let stack = UIStackView(arrangedSubviews: arranged)
		stack.axis = .horizontal
		stack.spacing = 14
		stack.alignment = .center
		stack.isUserInteractionEnabled = false
		stack.translatesAutoresizingMaskIntoConstraints = false

		row.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
			stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
			stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
		])

		row.tag = SettingsSidebarItem.allCases.firstIndex(of: item) ?? 0
		row.addTarget(self, action: #selector(settingsRowTapped(_:)), for: .touchUpInside)
		return row
	}

	private func makeSectionLabel(_ text: String) -> UIView {
		let label = UILabel()
		label.text = text
		label.font = .systemFont(ofSize: 13, weight: .semibold)
		label.textColor = .secondaryLabel

		let wrapper = UIView()
		label.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
			label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
			label.topAnchor.constraint(equalTo: wrapper.topAnchor),
			label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
		])
		return wrapper
	}

	private func makeSeparator() -> UIView {
		let sep = UIView()
		sep.backgroundColor = .separator
		sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
		return sep
	}

	private func makePadding(height: CGFloat) -> UIView {
		let v = UIView()
		v.heightAnchor.constraint(equalToConstant: height).isActive = true
		return v
	}

	// MARK: - Credits

	@objc private func creditsDidUpdate() {
		updateCredits()
	}

	private func updateCredits() {
		guard let credits = FeedStatsManager.shared.cachedCredits else {
			creditsRowStack.isHidden = true
			return
		}
		creditsRowStack.isHidden = false
		creditsLabel.text = "\(credits) remaining credits"
		creditsInfoButton.isHidden = false
	}

	@MainActor
	private func handleCreditsInfo() async {
		await FeedStatsManager.shared.reportUpdate()
		presentPaidFeedsAlert()
	}

	@MainActor
	private func presentPaidFeedsAlert() {
		let credits = FeedStatsManager.shared.cachedCredits ?? 0
		let paid = FeedStatsManager.shared.paidFeeds()

		var message = String(format: NSLocalizedString("You have %d remaining credits.", comment: "Credits info message"), credits)
		if !paid.isEmpty {
			message += "\n\n" + NSLocalizedString("The following feeds use paid credits. Remove any you no longer need:", comment: "Paid feeds list intro")
		}

		let alert = UIAlertController(
			title: NSLocalizedString("Remaining Credits", comment: "Credits info title"),
			message: message,
			preferredStyle: .alert
		)

		for feed in paid {
			let name = feed.nameForDisplay
			alert.addAction(UIAlertAction(title: String(format: NSLocalizedString("Remove \"%@\"", comment: "Remove paid feed action"), name), style: .destructive) { [weak self] _ in
				guard let account = feed.account else { return }
				FeedStatsManager.shared.queueDelete(
					type: feed.feedCategory,
					name: feed.nameForDisplay,
					author: feed.authors?.first?.name
				)
				account.removeFeed(feed, from: account) { [weak self] _ in
					Task { @MainActor [weak self] in
						await FeedStatsManager.shared.waitForNextCreditsUpdate()
						self?.presentPaidFeedsAlert()
					}
				}
			})
		}

		alert.addAction(UIAlertAction(title: NSLocalizedString("Done", comment: "Done"), style: .cancel))
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

	@objc private func settingsRowTapped(_ sender: UIControl) {
		let item = SettingsSidebarItem.allCases[sender.tag]
		switch item {
		case .logOut, .deleteAccount:
			// These show alerts — keep them going through the coordinator
			coordinator?.showSidebarSettingsItem(item)
		default:
			navigationController?.pushViewController(makeSettingsVC(for: item), animated: true)
		}
	}

	private func makeSettingsVC(for item: SettingsSidebarItem) -> UIViewController {
		switch item {
		case .notifications:
			return NotificationsSettingsViewController()
		case .appearance:
			return AppearanceSettingsViewController()
		case .faceID:
			return FaceIDSettingsViewController()
		case .obsidian:
			return ObsidianSettingsViewController()
		case .donation:
			let vc = UIHostingController(rootView: DonationView())
			vc.view.backgroundColor = Assets.Colors.SettingsContentBgColor
			return vc
		case .about:
			let vc = UIHostingController(rootView: AboutWPodView())
			vc.view.backgroundColor = Assets.Colors.SettingsContentBgColor
			return vc
		case .logOut, .deleteAccount:
			return UIViewController()
		}
	}

	@objc private func reportBugTapped() {
		let bugVC = BugReportSheetViewController()
		bugVC.onSubmit = { [weak self] text in
			Task { await self?.sendBugReport(text) }
		}
		let nav = UINavigationController(rootViewController: bugVC)
		if let sheet = nav.sheetPresentationController {
			sheet.detents = [.large()]
			sheet.prefersGrabberVisible = true
		}
		present(nav, animated: true)
	}

	private func sendBugReport(_ bug: String) async {
		guard let appleUserID = AuthManager.shared.appleUserID, !appleUserID.isEmpty else { return }
		let body: [String: Any] = [
			"apple_user_id": appleUserID,
			"request_id": UUID().uuidString,
			"bug": bug
		]
		guard let (data, statusCode) = try? await SecondStreamAPIClient.shared.post(to: .reportBug, body: body),
			  statusCode == 200 else { return }
		let message: String
		if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let serverMessage = json["message"] as? String {
			message = serverMessage
		} else {
			return
		}
		let confirmation = UIAlertController(title: nil, message: message, preferredStyle: .alert)
		confirmation.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
		var presenter: UIViewController = self
		while let p = presenter.presentedViewController { presenter = p }
		presenter.present(confirmation, animated: true)
	}

	@objc private func buildLabelTripleTapped() {
		coordinator?.hideLeftMenu { [weak self] in
			self?.coordinator?.showSettings(devOptionsUnlocked: true)
		}
	}
}

// MARK: - BugReportSheetViewController

private final class BugReportSheetViewController: UIViewController {

	var onSubmit: ((String) -> Void)?

	private let textView = UITextView()
	private let placeholderLabel = UILabel()

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .systemBackground

		navigationItem.title = NSLocalizedString("Report a Bug", comment: "Report a Bug")
		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)
		navigationItem.rightBarButtonItem = UIBarButtonItem(
			title: NSLocalizedString("Send", comment: "Send bug report"),
			style: .prominent,
			target: self,
			action: #selector(sendTapped)
		)
		navigationItem.rightBarButtonItem?.isEnabled = false

		setupTextView()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		textView.becomeFirstResponder()
	}

	private func setupTextView() {
		// Placeholder
		placeholderLabel.text = NSLocalizedString("Describe the issue you encountered.", comment: "Bug report prompt")
		placeholderLabel.font = .preferredFont(forTextStyle: .body)
		placeholderLabel.textColor = .placeholderText
		placeholderLabel.numberOfLines = 0
		placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

		// Text view
		textView.font = .preferredFont(forTextStyle: .body)
		textView.autocapitalizationType = .sentences
		textView.backgroundColor = .clear
		textView.delegate = self
		textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
		textView.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(textView)
		textView.addSubview(placeholderLabel)

		NSLayoutConstraint.activate([
			textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

			placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top),
			placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.left + 5),
			placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -(textView.textContainerInset.right + 5)),
		])
	}

	@objc private func cancelTapped() {
		dismiss(animated: true)
	}

	@objc private func sendTapped() {
		let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return }
		dismiss(animated: true) { [weak self] in
			self?.onSubmit?(text)
		}
	}
}

extension BugReportSheetViewController: UITextViewDelegate {
	func textViewDidChange(_ textView: UITextView) {
		let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		placeholderLabel.isHidden = hasText
		navigationItem.rightBarButtonItem?.isEnabled = hasText
	}
}
