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

		title = NSLocalizedString("Add Weekly News", comment: "Add Weekly News")
		view.backgroundColor = Assets.Colors.AddContentBgColor

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		configureCollectionView()
		configureDataSource()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sourceImageDidBecomeAvailable(_:)),
			name: .sourceImageDidBecomeAvailable,
			object: SourceImageCache.shared
		)

		applySnapshot()

		Task { [weak self] in
			await NewsSourcesManager.shared.fetchFresh()
			self?.applySnapshot()
		}
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		configureOpaqueNavigationBar()
	}

	/// Forces an opaque nav bar at every scroll position. Called from viewWillAppear
	/// so traitCollection is resolved against the live window (not the pre-presentation default).
	private func configureOpaqueNavigationBar() {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = Assets.Colors.AddNavBarColor.resolvedColor(with: traitCollection)
		let textColor = UIColor.label.resolvedColor(with: traitCollection)
		appearance.titleTextAttributes = [.foregroundColor: textColor]
		appearance.largeTitleTextAttributes = [.foregroundColor: textColor]
		navigationItem.standardAppearance = appearance
		navigationItem.scrollEdgeAppearance = appearance
		navigationItem.compactAppearance = appearance
		navigationItem.compactScrollEdgeAppearance = appearance
	}

	// MARK: - Configuration

	private func configureCollectionView() {
		let layout = createLayout()
		collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
		collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		collectionView.backgroundColor = Assets.Colors.AddContentBgColor
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
				cell.configure(name: source.name, imageURL: source.imageURL, imageURLLight: source.imageURLLight)
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
				header.configure(title: "")
			case .sources(let title):
				header.configure(title: title)
			case .paidSources, .findResults:
				header.configure(title: "")
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
			let popularPicks = SourcePickerSection.sources(NSLocalizedString("Popular Picks", comment: "Popular Picks"))
			snapshot.appendSections([popularPicks])
			let items = sources.map { SourcePickerItem.newsSource($0) }
			snapshot.appendItems(items, toSection: popularPicks)
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

		reloadItemsIfNeeded(forImageURL: url)

		for cell in collectionView.visibleCells {
			(cell as? SourcePickerCell)?.updateImageIfNeeded(for: url)
		}
	}

	private func reloadItemsIfNeeded(forImageURL url: String) {
		var snapshot = dataSource.snapshot()
		let matchingItems = snapshot.itemIdentifiers.filter { item in
			guard case .newsSource(let source) = item else {
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
