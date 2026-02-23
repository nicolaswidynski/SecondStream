//
//  RSSPickerViewController.swift
//  NetNewsWire
//
//  Created by Codex on 2026-02-17.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol RSSPickerDelegate: AnyObject {
	func rssPickerDidSelectCustomURL(_ picker: RSSPickerViewController)
	func rssPicker(_ picker: RSSPickerViewController, didSelectFeed source: RSSSource)
	func rssPickerDidCancel(_ picker: RSSPickerViewController)
}

final class RSSPickerViewController: UIViewController {

	weak var delegate: RSSPickerDelegate?

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<SourcePickerSection, SourcePickerItem>!

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add RSS Feed", comment: "Add RSS Feed")
		view.backgroundColor = .systemBackground

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		configureCollectionView()
		configureDataSource()
		applySnapshot()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sourceImageDidBecomeAvailable(_:)),
			name: .sourceImageDidBecomeAvailable,
			object: SourceImageCache.shared
		)
	}

	// MARK: - Configuration

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
		let layout = UICollectionViewCompositionalLayout { _, _ in
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
			case .customEntryURL:
				cell.configure(name: NSLocalizedString("Add RSS URL", comment: "Add RSS URL"), imageURL: nil, isCustomEntry: true)
			case .rssSource(let source):
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
		var snapshot = NSDiffableDataSourceSnapshot<SourcePickerSection, SourcePickerItem>()

		snapshot.appendSections([.customEntry])
		snapshot.appendItems([.customEntryURL], toSection: .customEntry)

		// Top Picks section
		let topSources = RSSSourcesManager.shared.rssSources.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}

		if !topSources.isEmpty {
			let topPicks = SourcePickerSection.sources(NSLocalizedString("Top Picks", comment: "Top Picks"))
			snapshot.appendSections([topPicks])
			let items = topSources.map { SourcePickerItem.rssSource($0) }
			snapshot.appendItems(items, toSection: topPicks)
		}

		// Library section (exclude sources already in top picks)
		let topNames = Set(topSources.map { $0.name.lowercased() })
		let librarySources = RSSSourcesManager.shared.rssLibrarySources
			.filter { !topNames.contains($0.name.lowercased()) }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		if !librarySources.isEmpty {
			let otherSection = SourcePickerSection.sources(NSLocalizedString("Other RSS Feeds", comment: "Other RSS Feeds"))
			snapshot.appendSections([otherSection])
			let items = librarySources.map { SourcePickerItem.rssSource($0) }
			snapshot.appendItems(items, toSection: otherSection)
		}

		dataSource.apply(snapshot, animatingDifferences: false)
	}

	// MARK: - Actions

	@objc private func cancelTapped() {
		delegate?.rssPickerDidCancel(self)
	}

	@objc private func sourceImageDidBecomeAvailable(_ notification: Notification) {
		guard let url = notification.userInfo?["url"] as? String else {
			return
		}
		for cell in collectionView.visibleCells {
			(cell as? SourcePickerCell)?.updateImageIfNeeded(for: url)
		}
	}
}

// MARK: - UICollectionViewDelegate

extension RSSPickerViewController: UICollectionViewDelegate {

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let item = dataSource.itemIdentifier(for: indexPath) else {
			return
		}

		switch item {
		case .customEntryURL:
			delegate?.rssPickerDidSelectCustomURL(self)
		case .rssSource(let source):
			delegate?.rssPicker(self, didSelectFeed: source)
		default:
			break
		}
	}
}
