//
//  PodcastPickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-23.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit
import os.log

@MainActor protocol PodcastPickerDelegate: AnyObject {
	func podcastPickerDidSelectPodcastName(_ picker: PodcastPickerViewController)
	func podcastPicker(_ picker: PodcastPickerViewController, didEnterPodcastName name: String)
	func podcastPicker(_ picker: PodcastPickerViewController, didSelectPodcast source: PodcastSource)
	func podcastPickerDidCancel(_ picker: PodcastPickerViewController)
}

final class PodcastPickerViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PodcastPicker")

	weak var delegate: PodcastPickerDelegate?

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<SourcePickerSection, SourcePickerItem>!
	private let searchController = UISearchController(searchResultsController: nil)
	private var findTask: Task<Void, Never>?
	private var currentFindItems: [SourcePickerItem] = []
	private var lastFindQuery: String = ""
	/// Set on touch-down (shouldHighlightItemAt) so we can skip clearFindResults while a finger
	/// is on a cell — the keyboard-dismiss gesture fires on touch-up and would otherwise wipe
	/// currentFindItems before didSelectItemAt gets a chance to fire.
	private var isHighlightingItem = false
	/// Item captured at touch-down in case the snapshot is reapplied before didSelectItemAt.
	private var highlightedSelection: SourcePickerItem?

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add Podcast", comment: "Add Podcast")
		view.backgroundColor = Assets.Colors.background

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		configureSearch()
		configureCollectionView()
		configureDataSource()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sourceImageDidBecomeAvailable(_:)),
			name: .sourceImageDidBecomeAvailable,
			object: SourceImageCache.shared
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(creditsDidUpdate),
			name: .creditsDidUpdate,
			object: nil
		)

		applySnapshot()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		configureOpaqueNavigationBar()
	}

	// MARK: - Configuration

	/// Forces an opaque nav bar at every scroll position. Called from viewWillAppear
	/// so traitCollection is resolved against the live window (not the pre-presentation default).
	/// Must be set up after configureSearch() since setting navigationItem.searchController
	/// can reset scrollEdgeAppearance to nil (transparent).
	private func configureOpaqueNavigationBar() {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = Assets.Colors.pickerNavBar.resolvedColor(with: traitCollection)
		let textColor = UIColor.label.resolvedColor(with: traitCollection)
		appearance.titleTextAttributes = [.foregroundColor: textColor]
		appearance.largeTitleTextAttributes = [.foregroundColor: textColor]
		navigationItem.standardAppearance = appearance
		navigationItem.scrollEdgeAppearance = appearance
		navigationItem.compactAppearance = appearance
		navigationItem.compactScrollEdgeAppearance = appearance
	}

	private func configureSearch() {
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchResultsUpdater = self
		searchController.searchBar.placeholder = NSLocalizedString("Search or add", comment: "Search or add")
		searchController.searchBar.autocapitalizationType = .words
		searchController.searchBar.searchBarStyle = .minimal
		navigationItem.searchController = searchController
		navigationItem.hidesSearchBarWhenScrolling = false
		definesPresentationContext = true
	}

	private func configureCollectionView() {
		let layout = createLayout()
		collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
		collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		collectionView.backgroundColor = Assets.Colors.background
		collectionView.delegate = self
		collectionView.register(SourcePickerCell.self, forCellWithReuseIdentifier: SourcePickerCell.reuseIdentifier)
		collectionView.register(
			SourcePickerHeaderView.self,
			forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
			withReuseIdentifier: SourcePickerHeaderView.reuseIdentifier
		)
		view.addSubview(collectionView)
	}

	private func createLayout() -> UICollectionViewCompositionalLayout {
		let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
			let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / 3.0), heightDimension: .estimated(120))
			let item = NSCollectionLayoutItem(layoutSize: itemSize)

			let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(120))
			let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

			let section = NSCollectionLayoutSection(group: group)
			section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 16, trailing: 8)

			let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(32))
			let header = NSCollectionLayoutBoundarySupplementaryItem(
				layoutSize: headerSize,
				elementKind: UICollectionView.elementKindSectionHeader,
				alignment: .top
			)
			section.boundarySupplementaryItems = [header]

			return section
		}
		return layout
	}

	private func configureDataSource() {
		dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
			guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SourcePickerCell.reuseIdentifier, for: indexPath) as? SourcePickerCell else {
				fatalError("Cannot dequeue SourcePickerCell")
			}

			switch item {
			case .customEntryName:
				cell.configure(name: NSLocalizedString("Add Podcast", comment: "Add Podcast"), imageURL: nil, isCustomEntry: true)
			case .podcastSource(let source):
				cell.configure(name: source.name, imageURL: source.imageURL, imageURLLight: source.imageURLLight)
			case .findCandidate(let candidate):
				cell.configureFindCandidate(name: candidate.name, artworkURL: candidate.artworkUrl)
			case .findLoading:
				cell.configureFindLoading(sourceType: .podcast)
			default:
				break
			}

			return cell
		}

		dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
			guard let self, let header = collectionView.dequeueReusableSupplementaryView(
				ofKind: kind,
				withReuseIdentifier: SourcePickerHeaderView.reuseIdentifier,
				for: indexPath
			) as? SourcePickerHeaderView else {
				fatalError("Cannot dequeue SourcePickerHeaderView")
			}

			let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
			switch section {
			case .customEntry:
				header.configure(title: "")
			case .sources(let title):
				header.configure(title: title)
			case .paidSources:
				let credits = FeedStatsManager.shared.cachedCredits ?? 0
				header.configure(
					title: "\(credits) remaining credits",
					showsInfoButton: true,
					onInfoTapped: { [weak self] in Task { await self?.handleCreditsInfo() } }
				)
			case .findResults:
				header.configure(title: NSLocalizedString("Search Results", comment: "Remote search results section"))
			}

			return header
		}
	}

	// MARK: - Snapshot

	private func applySnapshot() {
		let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		var snapshot = NSDiffableDataSourceSnapshot<SourcePickerSection, SourcePickerItem>()

		let topSources = PodcastSourcesManager.shared.podcastSources.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
		let topNames = Set(topSources.map { $0.name.lowercased() })
		let librarySources = PodcastSourcesManager.shared.podcastLibrarySources
			.filter { !topNames.contains($0.name.lowercased()) }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		if query.isEmpty {
			if !topSources.isEmpty {
				let topPicks = SourcePickerSection.sources(NSLocalizedString("Free Picks", comment: "Free Picks"))
				snapshot.appendSections([topPicks])
				let items = topSources.map { SourcePickerItem.podcastSource($0) }
				snapshot.appendItems(items, toSection: topPicks)
			}
			if !librarySources.isEmpty {
				snapshot.appendSections([.paidSources])
				let items = librarySources.map { SourcePickerItem.podcastSource($0) }
				snapshot.appendItems(items, toSection: .paidSources)
			}
		} else {
			let allSources = topSources + librarySources
			let matches = allSources.filter { source in
				source.name.localizedCaseInsensitiveContains(query) ||
				(source.author?.localizedCaseInsensitiveContains(query) ?? false)
			}
			let section = SourcePickerSection.sources(NSLocalizedString("Matches", comment: "Search matches"))
			snapshot.appendSections([section])
			snapshot.appendItems(matches.map { SourcePickerItem.podcastSource($0) }, toSection: section)
		}

		if !currentFindItems.isEmpty {
			snapshot.appendSections([.findResults])
			snapshot.appendItems(currentFindItems, toSection: .findResults)
		}

		dataSource.apply(snapshot, animatingDifferences: false)
	}

	// MARK: - Actions

	@objc private func cancelTapped() {
		delegate?.podcastPickerDidCancel(self)
	}

	@objc private func creditsDidUpdate() {
		var snapshot = dataSource.snapshot()
		guard snapshot.sectionIdentifiers.contains(.paidSources) else {
			return
		}
		snapshot.reloadSections([.paidSources])
		dataSource.apply(snapshot, animatingDifferences: false)
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

	@objc private func sourceImageDidBecomeAvailable(_ notification: Notification) {
		guard let url = notification.userInfo?["url"] as? String else {
			return
		}

		reloadItemsIfNeeded(forImageURL: url)

		for cell in collectionView.visibleCells {
			(cell as? SourcePickerCell)?.updateImageIfNeeded(for: url)
		}
	}

	private func reloadItemsIfNeeded(forImageURL url: String) {
		var snapshot = dataSource.snapshot()
		let matchingItems = snapshot.itemIdentifiers.filter { item in
			guard case .podcastSource(let source) = item else {
				return false
			}
			return source.imageURL == url
		}
		guard !matchingItems.isEmpty else {
			return
		}
		snapshot.reloadItems(matchingItems)
		dataSource.apply(snapshot, animatingDifferences: false)
	}
}

// MARK: - UICollectionViewDelegate

extension PodcastPickerViewController: UICollectionViewDelegate {

	func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
		highlightedSelection = dataSource.itemIdentifier(for: indexPath)
		isHighlightingItem = true
		Self.logger.debug("shouldHighlight[\(indexPath.section),\(indexPath.item)] item=\(String(describing: self.highlightedSelection), privacy: .public) isHighlighting=true")
		return true
	}

	func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
		Self.logger.debug("didUnhighlight[\(indexPath.section),\(indexPath.item)] isHighlighting→false")
		isHighlightingItem = false
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let fromDS = dataSource.itemIdentifier(for: indexPath)
		let item = fromDS ?? highlightedSelection
		Self.logger.debug("didSelect[\(indexPath.section),\(indexPath.item)] fromDS=\(String(describing: fromDS), privacy: .public) fallback=\(String(describing: self.highlightedSelection), privacy: .public) resolved=\(String(describing: item), privacy: .public)")
		highlightedSelection = nil
		isHighlightingItem = false
		guard let item else { return }

		switch item {
		case .podcastSource(let source):
			delegate?.podcastPicker(self, didSelectPodcast: source)
		case .findCandidate(let candidate):
			let source = PodcastSource(name: candidate.name, author: candidate.author, url: "", imageURL: nil)
			delegate?.podcastPicker(self, didSelectPodcast: source)
		default:
			break
		}
	}
}

// MARK: - UISearchResultsUpdating

extension PodcastPickerViewController: UISearchResultsUpdating {

	func updateSearchResults(for searchController: UISearchController) {
		let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

		guard query.count >= 3 else {
			Self.logger.debug("updateSearchResults: query<3 (\"\(query, privacy: .public)\") isHighlighting=\(self.isHighlightingItem) currentFindItems=\(self.currentFindItems.count)")
			if !isHighlightingItem { clearFindResults() } else { Self.logger.debug("updateSearchResults: skipping clearFindResults — finger still down") }
			applySnapshot()
			return
		}

		let localMatches = computeLocalMatches(query: query)
		if localMatches.count <= 6 && query != lastFindQuery {
			lastFindQuery = query
			currentFindItems = [.findLoading]
			applySnapshot()
			findTask?.cancel()
			findTask = Task {
				try? await Task.sleep(for: .milliseconds(500))
				guard !Task.isCancelled else { return }
				let result = await PodcastSourcesManager.shared.findPodcast(name: query)
				guard !Task.isCancelled else { return }
				if case .success(let candidates) = result, !candidates.isEmpty {
					currentFindItems = candidates.map { .findCandidate($0) }
				} else {
					currentFindItems = []
				}
				applySnapshot()
			}
		} else {
			applySnapshot()
		}
	}

	private func computeLocalMatches(query: String) -> [PodcastSource] {
		let topSources = PodcastSourcesManager.shared.podcastSources.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
		let topNames = Set(topSources.map { $0.name.lowercased() })
		let librarySources = PodcastSourcesManager.shared.podcastLibrarySources
			.filter { !topNames.contains($0.name.lowercased()) }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		return (topSources + librarySources).filter {
			$0.name.localizedCaseInsensitiveContains(query) ||
			($0.author?.localizedCaseInsensitiveContains(query) ?? false)
		}
	}

	private func clearFindResults() {
		findTask?.cancel()
		currentFindItems = []
		lastFindQuery = ""
	}
}
