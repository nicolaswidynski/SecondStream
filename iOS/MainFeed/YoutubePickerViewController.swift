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

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add YouTube Channel", comment: "Add YouTube Channel")
		view.backgroundColor = .systemGroupedBackground

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

		applySnapshot()
	}

	// MARK: - Configuration

	private func configureSearch() {
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchResultsUpdater = self
		searchController.searchBar.delegate = self
		searchController.searchBar.placeholder = NSLocalizedString("Search or add", comment: "Search or add")
		searchController.searchBar.autocapitalizationType = .none
		searchController.searchBar.autocorrectionType = .no
		searchController.searchBar.searchBarStyle = .minimal
		searchController.searchBar.showsBookmarkButton = true
		searchController.searchBar.setImage(UIImage(systemName: "plus.circle"), for: .bookmark, state: .normal)
		navigationItem.searchController = searchController
		navigationItem.hidesSearchBarWhenScrolling = false
		definesPresentationContext = true
	}

	private func configureCollectionView() {
		let layout = createLayout()
		collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
		collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		collectionView.backgroundColor = .systemGroupedBackground
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
				cell.configure(name: source.name, imageURL: source.imageURL)
			default:
				break
			}

			return cell
		}

		dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
			guard let header = collectionView.dequeueReusableSupplementaryView(
				ofKind: kind,
				withReuseIdentifier: SourcePickerHeaderView.reuseIdentifier,
				for: indexPath
			) as? SourcePickerHeaderView else {
				fatalError("Cannot dequeue SourcePickerHeaderView")
			}

			let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
			switch section {
			case .customEntry:
				header.configure(letter: "")
			case .sources(let title):
				header.configure(letter: title)
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
				let otherSection = SourcePickerSection.sources(NSLocalizedString("Popular Picks (with credits)", comment: "Popular Picks (with credits)"))
				snapshot.appendSections([otherSection])
				let items = librarySources.map { SourcePickerItem.youtubeSource($0) }
				snapshot.appendItems(items, toSection: otherSection)
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

		dataSource.apply(snapshot, animatingDifferences: false)
	}

	// MARK: - Actions

	@objc private func cancelTapped() {
		delegate?.youtubePickerDidCancel(self)
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
		default:
			break
		}
	}
}

// MARK: - UISearchResultsUpdating

extension YoutubePickerViewController: UISearchResultsUpdating {

	func updateSearchResults(for searchController: UISearchController) {
		applySnapshot()
	}
}

// MARK: - UISearchBarDelegate

extension YoutubePickerViewController: UISearchBarDelegate {

	func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {
		let alert = UIAlertController(
			title: NSLocalizedString("Add YouTube Channel", comment: "Add YouTube Channel"),
			message: nil,
			preferredStyle: .alert
		)
		alert.addTextField { textField in
			textField.text = "@"
			textField.placeholder = NSLocalizedString("@channel", comment: "YouTube channel handle placeholder")
			textField.autocapitalizationType = .none
			textField.autocorrectionType = .no
			textField.keyboardType = .twitter
			textField.addAction(UIAction { _ in
				let raw = textField.text ?? ""
				let noAt = raw.replacingOccurrences(of: "@", with: "")
				textField.text = "@" + noAt
			}, for: .editingChanged)
		}
		let add = UIAlertAction(title: NSLocalizedString("Add", comment: "Add"), style: .default) { [weak self, weak alert] _ in
			guard let self,
				  let handle = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
				  handle.count > 1 else {
				return
			}
			self.delegate?.youtubePicker(self, didEnterChannelHandle: handle)
		}
		alert.addAction(add)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
		present(alert, animated: true)
	}
}
