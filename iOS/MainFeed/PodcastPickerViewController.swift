//
//  PodcastPickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-23.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol PodcastPickerDelegate: AnyObject {
	func podcastPickerDidSelectPodcastName(_ picker: PodcastPickerViewController)
	func podcastPickerDidSelectCustomURL(_ picker: PodcastPickerViewController)
	func podcastPicker(_ picker: PodcastPickerViewController, didSelectPodcast source: PodcastSource)
	func podcastPickerDidCancel(_ picker: PodcastPickerViewController)
}

final class PodcastPickerViewController: UIViewController, UISearchResultsUpdating {

	weak var delegate: PodcastPickerDelegate?

	private var allSources: [PodcastSource] = []
	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<SourcePickerSection, SourcePickerItem>!
	private var sectionIndexView = SectionIndexView()
	private let searchController = UISearchController(searchResultsController: nil)
	private var currentSearchText: String = ""

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add Podcast", comment: "Add Podcast")
		view.backgroundColor = .systemBackground

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		configureSearchController()
		configureCollectionView()
		configureDataSource()
		configureSectionIndex()

		allSources = PodcastSourcesManager.shared.podcastSources.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}

		applySnapshot()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sourceImageDidBecomeAvailable(_:)),
			name: .sourceImageDidBecomeAvailable,
			object: SourceImageCache.shared
		)
	}

	// MARK: - Configuration

	private func configureSearchController() {
		searchController.searchResultsUpdater = self
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchBar.placeholder = NSLocalizedString("Search Podcasts", comment: "Search Podcasts")
		navigationItem.searchController = searchController
		navigationItem.hidesSearchBarWhenScrolling = false
		definesPresentationContext = true
	}

	private func configureCollectionView() {
		let layout = createLayout()
		collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
		collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		collectionView.backgroundColor = .systemBackground
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
			section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 16, trailing: 28)

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
				cell.configure(name: NSLocalizedString("Add via Name", comment: "Add via Name"), imageURL: nil, isCustomEntry: true)
			case .customEntryURL:
				cell.configure(name: NSLocalizedString("Add via RSS URL", comment: "Add via RSS URL"), imageURL: nil, isCustomEntry: true)
			case .podcastSource(let source):
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
			case .alphabetical(let letter):
				header.configure(letter: letter)
			}

			return header
		}
	}

	private func configureSectionIndex() {
		sectionIndexView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(sectionIndexView)
		NSLayoutConstraint.activate([
			sectionIndexView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
			sectionIndexView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
			sectionIndexView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
			sectionIndexView.widthAnchor.constraint(equalToConstant: 20),
		])

		sectionIndexView.onSelectLetter = { [weak self] letter in
			guard let self else {
				return
			}
			let snapshot = self.dataSource.snapshot()
			let targetSection = SourcePickerSection.alphabetical(letter)
			guard snapshot.sectionIdentifiers.contains(targetSection),
				  let sectionIndex = snapshot.sectionIdentifiers.firstIndex(of: targetSection) else {
				return
			}
			let indexPath = IndexPath(item: 0, section: sectionIndex)
			self.collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
		}
	}

	// MARK: - Snapshot

	private func applySnapshot() {
		var snapshot = NSDiffableDataSourceSnapshot<SourcePickerSection, SourcePickerItem>()

		let isSearching = !currentSearchText.isEmpty
		let sources: [PodcastSource]

		if isSearching {
			let query = currentSearchText.lowercased()
			sources = allSources.filter { $0.name.lowercased().contains(query) }
		} else {
			// Show custom entry section when not searching
			snapshot.appendSections([.customEntry])
			snapshot.appendItems([.customEntryName, .customEntryURL], toSection: .customEntry)
			sources = allSources
		}

		// Group by first letter
		var grouped: [String: [PodcastSource]] = [:]
		for source in sources {
			let firstChar = source.name.first.map { String($0).uppercased() } ?? "#"
			let letter = firstChar.first?.isLetter == true ? firstChar : "#"
			grouped[letter, default: []].append(source)
		}

		let sortedLetters = grouped.keys.sorted()
		for letter in sortedLetters {
			let section = SourcePickerSection.alphabetical(letter)
			snapshot.appendSections([section])
			let items = grouped[letter]!.map { SourcePickerItem.podcastSource($0) }
			snapshot.appendItems(items, toSection: section)
		}

		dataSource.apply(snapshot, animatingDifferences: true)

		// Update section index
		sectionIndexView.configure(letters: sortedLetters)
		sectionIndexView.isHidden = sortedLetters.count < 3
	}

	// MARK: - Actions

	@objc private func cancelTapped() {
		delegate?.podcastPickerDidCancel(self)
	}

	@objc private func sourceImageDidBecomeAvailable(_ notification: Notification) {
		guard let url = notification.userInfo?["url"] as? String else {
			return
		}
		for cell in collectionView.visibleCells {
			(cell as? SourcePickerCell)?.updateImageIfNeeded(for: url)
		}
	}

	// MARK: - UISearchResultsUpdating

	func updateSearchResults(for searchController: UISearchController) {
		currentSearchText = searchController.searchBar.text ?? ""
		applySnapshot()
	}
}

// MARK: - UICollectionViewDelegate

extension PodcastPickerViewController: UICollectionViewDelegate {

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let item = dataSource.itemIdentifier(for: indexPath) else {
			return
		}

		switch item {
		case .customEntryName:
			delegate?.podcastPickerDidSelectPodcastName(self)
		case .customEntryURL:
			delegate?.podcastPickerDidSelectCustomURL(self)
		case .podcastSource(let source):
			delegate?.podcastPicker(self, didSelectPodcast: source)
		default:
			break
		}
	}
}
