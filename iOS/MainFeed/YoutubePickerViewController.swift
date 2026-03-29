//
//  YoutubePickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-27.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol YoutubePickerDelegate: AnyObject {
	func youtubePickerDidSelectChannelName(_ picker: YoutubePickerViewController)
	func youtubePicker(_ picker: YoutubePickerViewController, didEnterChannelHandle handle: String)
	func youtubePicker(_ picker: YoutubePickerViewController, didSelectChannel source: YoutubeSource)
	func youtubePickerDidCancel(_ picker: YoutubePickerViewController)
}

final class YoutubePickerViewController: UIViewController {

	weak var delegate: YoutubePickerDelegate?

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<SourcePickerSection, SourcePickerItem>!
	private let searchController = UISearchController(searchResultsController: nil)
	private var findTask: Task<Void, Never>?
	private var currentFindItems: [SourcePickerItem] = []
	private var lastFindQuery: String = ""

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add YouTube Channel", comment: "Add YouTube Channel")
		view.backgroundColor = Assets.Colors.background
		//edgesForExtendedLayout = []

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		configureSearch()
		configureOpaqueNavigationBar()
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

	// MARK: - Configuration

	/// Forces an opaque nav bar at every scroll position. Must be called AFTER
	/// configureSearch() because setting navigationItem.searchController can
	/// reset scrollEdgeAppearance to nil (transparent).
	private func configureOpaqueNavigationBar() {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = Assets.Colors.foreground
		appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
		appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
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
		searchController.searchBar.autocorrectionType = .default
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
				cell.configure(name: NSLocalizedString("Add Channel", comment: "Add Channel"), imageURL: nil, isCustomEntry: true)
			case .youtubeSource(let source):
				cell.configure(name: source.name, imageURL: source.imageURL, imageURLLight: source.imageURLLight)
			case .findCandidate(let candidate):
				cell.configureFindCandidate(name: candidate.name, artworkURL: candidate.artworkUrl)
			case .findLoading:
				cell.configureFindLoading(sourceType: .youtube)
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

		let topSources = YoutubeSourcesManager.shared.youtubeSources.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
		let topNames = Set(topSources.map { $0.name.lowercased() })
		let librarySources = YoutubeSourcesManager.shared.youtubeLibrarySources
			.filter { !topNames.contains($0.name.lowercased()) }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		if query.isEmpty {
			if !topSources.isEmpty {
				let topPicks = SourcePickerSection.sources(NSLocalizedString("Free Picks", comment: "Free Picks"))
				snapshot.appendSections([topPicks])
				let items = topSources.map { SourcePickerItem.youtubeSource($0) }
				snapshot.appendItems(items, toSection: topPicks)
			}
			if !librarySources.isEmpty {
				snapshot.appendSections([.paidSources])
				let items = librarySources.map { SourcePickerItem.youtubeSource($0) }
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
			snapshot.appendItems(matches.map { SourcePickerItem.youtubeSource($0) }, toSection: section)
		}

		if !currentFindItems.isEmpty {
			snapshot.appendSections([.findResults])
			snapshot.appendItems(currentFindItems, toSection: .findResults)
		}

		dataSource.apply(snapshot, animatingDifferences: false)
	}

	// MARK: - Actions

	@objc private func cancelTapped() {
		delegate?.youtubePickerDidCancel(self)
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
		await FeedStatsManager.shared.fetchCredits()
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
			guard case .youtubeSource(let source) = item else {
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

extension YoutubePickerViewController: UICollectionViewDelegate {

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let item = dataSource.itemIdentifier(for: indexPath) else {
			return
		}

		switch item {
		case .youtubeSource(let source):
			delegate?.youtubePicker(self, didSelectChannel: source)
		case .findCandidate(let candidate):
			let source = YoutubeSource(name: candidate.name, author: candidate.author, url: "", imageURL: nil, imageURLLight: nil)
			delegate?.youtubePicker(self, didSelectChannel: source)
		default:
			break
		}
	}
}

// MARK: - UISearchResultsUpdating

extension YoutubePickerViewController: UISearchResultsUpdating {

	func updateSearchResults(for searchController: UISearchController) {
		let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

		guard query.count >= 3 else {
			clearFindResults()
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
				let result = await YoutubeSourcesManager.shared.findYoutube(name: query)
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

	private func computeLocalMatches(query: String) -> [YoutubeSource] {
		let topSources = YoutubeSourcesManager.shared.youtubeSources.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
		let topNames = Set(topSources.map { $0.name.lowercased() })
		let librarySources = YoutubeSourcesManager.shared.youtubeLibrarySources
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
