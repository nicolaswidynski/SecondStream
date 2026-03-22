//
//  SourceSearchViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-21.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

struct SourceSearchItem {
	let name: String
	let author: String?
}

/// A reusable search VC that shows a search bar with autocomplete suggestions
/// from a list of source items. Presented modally for podcast/youtube name entry.
final class SourceSearchViewController: UIViewController {

	private let placeholder: String
	private let allItems: [SourceSearchItem]
	private let onSelect: (SourceSearchItem) -> Void
	private let onManualAdd: (String) -> Void
	private let matchesQuery: (SourceSearchItem, String) -> Bool

	private var filteredItems: [SourceSearchItem] = []

	private let searchBar = UISearchBar()
	private let tableView = UITableView(frame: .zero, style: .insetGrouped)

	private static let minimumQueryLength = 2
	private static let cellReuseIdentifier = "SourceSearchCell"

	init(
		placeholder: String,
		items: [SourceSearchItem],
		matchesQuery: @escaping (SourceSearchItem, String) -> Bool = { item, query in
			item.name.localizedCaseInsensitiveContains(query)
		},
		onSelect: @escaping (SourceSearchItem) -> Void,
		onManualAdd: @escaping (String) -> Void
	) {
		self.placeholder = placeholder
		self.allItems = items
		self.matchesQuery = matchesQuery
		self.onSelect = onSelect
		self.onManualAdd = onManualAdd
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .systemGroupedBackground

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		navigationItem.rightBarButtonItem = UIBarButtonItem(
			title: NSLocalizedString("Add", comment: "Add"),
			style: .plain,
			target: self,
			action: #selector(addButtonTapped)
		)
		navigationItem.rightBarButtonItem?.isEnabled = false

		configureSearchBar()
		configureTableView()
		layoutViews()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		searchBar.becomeFirstResponder()
	}

	// MARK: - Configuration

	private func configureSearchBar() {
		searchBar.placeholder = placeholder
		searchBar.searchBarStyle = .minimal
		searchBar.autocapitalizationType = .words
		searchBar.autocorrectionType = .default
		searchBar.returnKeyType = .done
		searchBar.translatesAutoresizingMaskIntoConstraints = false
		searchBar.delegate = self
		view.addSubview(searchBar)
	}

	private func configureTableView() {
		tableView.translatesAutoresizingMaskIntoConstraints = false
		tableView.dataSource = self
		tableView.delegate = self
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
		tableView.keyboardDismissMode = .onDrag
		view.addSubview(tableView)
	}

	private func layoutViews() {
		NSLayoutConstraint.activate([
			searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
			searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

			tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
			tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
	}

	// MARK: - Actions

	@objc private func cancelTapped() {
		dismiss(animated: true)
	}

	@objc private func addButtonTapped() {
		guard let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
			  !text.isEmpty else {
			return
		}
		dismiss(animated: true) {
			self.onManualAdd(text)
		}
	}

	// MARK: - Filtering

	private func updateFilteredItems() {
		let query = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

		navigationItem.rightBarButtonItem?.isEnabled = !query.isEmpty

		if query.count < Self.minimumQueryLength {
			filteredItems = []
		} else {
			filteredItems = allItems.filter { matchesQuery($0, query) }
		}

		tableView.reloadData()
	}
}

// MARK: - UISearchBarDelegate

extension SourceSearchViewController: UISearchBarDelegate {

	func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
		updateFilteredItems()
	}

	func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
		addButtonTapped()
	}
}

// MARK: - UITableViewDataSource

extension SourceSearchViewController: UITableViewDataSource {

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		filteredItems.count
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard !filteredItems.isEmpty else {
			return nil
		}
		return NSLocalizedString("Suggestions", comment: "Suggestions section header")
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
		let item = filteredItems[indexPath.row]

		var config = cell.defaultContentConfiguration()
		config.text = item.name
		config.secondaryText = item.author
		config.secondaryTextProperties.color = .secondaryLabel
		cell.contentConfiguration = config

		return cell
	}
}

// MARK: - UITableViewDelegate

extension SourceSearchViewController: UITableViewDelegate {

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		let item = filteredItems[indexPath.row]
		dismiss(animated: true) {
			self.onSelect(item)
		}
	}
}
