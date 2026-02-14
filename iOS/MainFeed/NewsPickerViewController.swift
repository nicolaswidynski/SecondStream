//
//  NewsPickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-27.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol NewsPickerDelegate: AnyObject {
	func newsPickerDidCancel(_ picker: NewsPickerViewController)
	func newsPicker(_ picker: NewsPickerViewController, didSelectSource source: NewsSource)
}

final class NewsPickerViewController: UIViewController {

	weak var delegate: NewsPickerDelegate?

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<SourcePickerSection, SourcePickerItem>!

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add Topic", comment: "Add Topic")
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
			case .newsSource(let source):
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

		let sources = NewsSourcesManager.shared.newsSources.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}

		if !sources.isEmpty {
			let sourcesSection = SourcePickerSection.sources("")
			snapshot.appendSections([sourcesSection])
			let items = sources.map { SourcePickerItem.newsSource($0) }
			snapshot.appendItems(items, toSection: sourcesSection)
		}

		dataSource.apply(snapshot, animatingDifferences: false)
	}

	// MARK: - Actions

	@objc private func cancelTapped() {
		delegate?.newsPickerDidCancel(self)
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

extension NewsPickerViewController: UICollectionViewDelegate {

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let item = dataSource.itemIdentifier(for: indexPath) else {
			return
		}

		switch item {
		case .newsSource(let source):
			delegate?.newsPicker(self, didSelectSource: source)
		default:
			break
		}
	}
}
