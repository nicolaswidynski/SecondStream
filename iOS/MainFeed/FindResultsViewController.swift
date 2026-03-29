//
//  FindResultsViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-03-28.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

enum FindSourceType {
	case podcast
	case youtube
}

@MainActor
final class FindResultsViewController: UITableViewController {

	var onSelect: ((FindShowCandidate) -> Void)?

	private let sourceType: FindSourceType
	private var rows: [FindResultRow] = []
	private var loadedImages: [String: UIImage] = [:]
	private var remoteTask: Task<Void, Never>?

	private enum FindResultRow: Equatable {
		case candidate(FindShowCandidate)
		case loading
	}

	init(title: String, sourceType: FindSourceType) {
		self.sourceType = sourceType
		super.init(style: .plain)
		self.title = title
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background
		tableView.register(FindResultCell.self, forCellReuseIdentifier: FindResultCell.reuseIdentifier)
		tableView.register(FindLoadingCell.self, forCellReuseIdentifier: FindLoadingCell.reuseIdentifier)
		tableView.rowHeight = 60
		tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		remoteTask?.cancel()
		loadedImages.removeAll()
	}

	@objc private func cancelTapped() {
		dismiss(animated: true)
	}

	// MARK: - Update

	func update(localCandidates: [FindShowCandidate], remoteFetch: @escaping () async -> FindShowResult) {
		remoteTask?.cancel()
		loadedImages.removeAll()
		rows = localCandidates.map { .candidate($0) } + [.loading]
		tableView.reloadData()

		remoteTask = Task {
			let result = await remoteFetch()
			guard !Task.isCancelled else { return }
			var remoteItems: [FindShowCandidate] = []
			if case .success(let candidates) = result {
				remoteItems = candidates
			}
			rows = localCandidates.map { .candidate($0) } + remoteItems.map { .candidate($0) }
			tableView.reloadData()
		}
	}

	// MARK: - UITableViewDataSource

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		rows.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch rows[indexPath.row] {
		case .loading:
			let cell = tableView.dequeueReusableCell(withIdentifier: FindLoadingCell.reuseIdentifier, for: indexPath) as! FindLoadingCell
			cell.configure(sourceType: sourceType)
			return cell
		case .candidate(let candidate):
			let cell = tableView.dequeueReusableCell(withIdentifier: FindResultCell.reuseIdentifier, for: indexPath) as! FindResultCell
			let imageKey = candidate.artworkUrl ?? ""
			cell.configure(name: candidate.name, author: candidate.author, image: loadedImages[imageKey])
			if loadedImages[imageKey] == nil, let urlString = candidate.artworkUrl, let url = URL(string: urlString) {
				Task {
					guard let (data, _) = try? await URLSession.shared.data(from: url),
						  let image = UIImage(data: data) else {
						return
					}
					loadedImages[urlString] = image
					guard let currentIndex = rows.firstIndex(of: .candidate(candidate)),
						  let visibleCell = tableView.cellForRow(at: IndexPath(row: currentIndex, section: 0)) as? FindResultCell else {
						return
					}
					visibleCell.setImage(image)
				}
			}
			return cell
		}
	}

	// MARK: - UITableViewDelegate

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		guard case .candidate(let candidate) = rows[indexPath.row] else { return }
		onSelect?(candidate)
	}
}

// MARK: - FindLoadingCell

final class FindLoadingCell: UITableViewCell {

	static let reuseIdentifier = "FindLoadingCell"

	private let iconView: UIImageView = {
		let iv = UIImageView()
		iv.translatesAutoresizingMaskIntoConstraints = false
		iv.contentMode = .scaleAspectFit
		iv.clipsToBounds = true
		iv.layer.cornerRadius = 8
		iv.backgroundColor = .secondarySystemFill
		iv.tintColor = .tertiaryLabel
		return iv
	}()

	private let loadingLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.text = NSLocalizedString("Loading...", comment: "Loading placeholder")
		label.font = .preferredFont(forTextStyle: .body)
		label.textColor = .secondaryLabel
		return label
	}()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none
		contentView.addSubview(iconView)
		contentView.addSubview(loadingLabel)
		NSLayoutConstraint.activate([
			iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 44),
			iconView.heightAnchor.constraint(equalToConstant: 44),
			loadingLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
			loadingLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			loadingLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(sourceType: FindSourceType) {
		let symbolName = sourceType == .podcast ? "mic.fill" : "play.rectangle.fill"
		iconView.image = UIImage(systemName: symbolName)
	}
}

// MARK: - FindResultCell

final class FindResultCell: UITableViewCell {

	static let reuseIdentifier = "FindResultCell"

	private let artworkView: UIImageView = {
		let iv = UIImageView()
		iv.translatesAutoresizingMaskIntoConstraints = false
		iv.contentMode = .scaleAspectFill
		iv.clipsToBounds = true
		iv.layer.cornerRadius = 8
		iv.backgroundColor = .secondarySystemFill
		iv.tintColor = .secondaryLabel
		return iv
	}()

	private let nameLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .preferredFont(forTextStyle: .body)
		label.numberOfLines = 1
		return label
	}()

	private let authorLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .preferredFont(forTextStyle: .caption1)
		label.textColor = .secondaryLabel
		label.numberOfLines = 1
		return label
	}()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)

		contentView.addSubview(artworkView)
		contentView.addSubview(nameLabel)
		contentView.addSubview(authorLabel)

		NSLayoutConstraint.activate([
			artworkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			artworkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			artworkView.widthAnchor.constraint(equalToConstant: 44),
			artworkView.heightAnchor.constraint(equalToConstant: 44),

			nameLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
			nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

			authorLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
			authorLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
			authorLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
			authorLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(name: String, author: String?, image: UIImage?) {
		nameLabel.text = name
		authorLabel.text = author
		authorLabel.isHidden = author == nil || author?.isEmpty == true
		setImage(image)
	}

	func setImage(_ image: UIImage?) {
		if let image {
			artworkView.image = image
			artworkView.tintColor = nil
		} else {
			artworkView.image = UIImage(systemName: "photo")
			artworkView.tintColor = .secondaryLabel
		}
	}
}
