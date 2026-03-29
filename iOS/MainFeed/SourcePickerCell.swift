//
//  SourcePickerCell.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-13.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

final class SourcePickerCell: UICollectionViewCell {

	static let reuseIdentifier = "SourcePickerCell"

	private(set) var currentImageURL: String?
	private var imageURLDark: String?
	private var imageURLLight: String?
	private var imageLoadTask: Task<Void, Never>?

	private let iconImageView: UIImageView = {
		let iv = UIImageView()
		iv.contentMode = .scaleAspectFill
		iv.clipsToBounds = true
		iv.layer.cornerRadius = 12
		iv.backgroundColor = Assets.Colors.interactionBackground
		iv.translatesAutoresizingMaskIntoConstraints = false
		return iv
	}()

	private let nameLabel: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .caption1)
		label.textAlignment = .center
		label.numberOfLines = 2
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = Assets.Colors.background
		contentView.addSubview(iconImageView)
		contentView.addSubview(nameLabel)

		NSLayoutConstraint.activate([
			iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
			iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
			iconImageView.widthAnchor.constraint(equalToConstant: 80),
			iconImageView.heightAnchor.constraint(equalToConstant: 80),

			nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
			nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
			nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
		])

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (cell: SourcePickerCell, _: UITraitCollection) in
			guard let self, self.imageURLLight != nil else {
				return
			}
			let newURL = self.activeImageURL
			self.currentImageURL = newURL
			guard let newURL else {
				self.showPlaceholder()
				return
			}
			if let image = SourceImageCache.shared.image(for: newURL) {
				self.iconImageView.image = image
				self.iconImageView.tintColor = nil
				self.iconImageView.contentMode = .scaleAspectFill
			} else {
				self.showPlaceholder()
			}
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		imageLoadTask?.cancel()
		imageLoadTask = nil
		iconImageView.image = nil
		iconImageView.backgroundColor = Assets.Colors.interactionBackground
		iconImageView.contentMode = .scaleAspectFill
		iconImageView.tintColor = nil
		nameLabel.text = nil
		nameLabel.textColor = .label
		currentImageURL = nil
		imageURLDark = nil
		imageURLLight = nil
	}

	func configure(name: String, imageURL: String?, imageURLLight: String? = nil, isCustomEntry: Bool = false) {
		nameLabel.text = name

		if isCustomEntry {
			nameLabel.textColor = Assets.Colors.primaryAccent
			iconImageView.backgroundColor = Assets.Colors.primaryAccent.withAlphaComponent(0.1)
			let symbolName = name.lowercased().contains("url") || name.lowercased().contains("rss") ? "link" : "plus.circle"
			let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
			iconImageView.image = UIImage(systemName: symbolName, withConfiguration: config)
			iconImageView.tintColor = Assets.Colors.primaryAccent
			iconImageView.contentMode = .center
			return
		}

		iconImageView.contentMode = .scaleAspectFill
		iconImageView.tintColor = nil

		self.imageURLDark = imageURL
		self.imageURLLight = imageURLLight
		let effectiveURL = activeImageURL
		currentImageURL = effectiveURL

		guard let effectiveURL else {
			showPlaceholder()
			return
		}

		if let image = SourceImageCache.shared.image(for: effectiveURL) {
			iconImageView.image = image
		} else {
			showPlaceholder()
		}
	}

	private var activeImageURL: String? {
		if traitCollection.userInterfaceStyle == .light, let light = imageURLLight {
			return light
		}
		return imageURLDark
	}

	func updateImageIfNeeded(for downloadedURL: String) {
		guard currentImageURL == downloadedURL else {
			return
		}
		if let image = SourceImageCache.shared.image(for: downloadedURL) {
			iconImageView.image = image
			iconImageView.tintColor = nil
			iconImageView.contentMode = .scaleAspectFill
		}
	}

	func configureFindCandidate(name: String, artworkURL: String?) {
		nameLabel.text = name
		nameLabel.textColor = .label
		currentImageURL = artworkURL
		imageURLDark = artworkURL
		imageURLLight = nil

		guard let urlString = artworkURL, let url = URL(string: urlString) else {
			showPlaceholder()
			return
		}

		showPlaceholder()
		imageLoadTask = Task { @MainActor [weak self] in
			guard let (data, _) = try? await URLSession.shared.data(from: url),
				  let image = UIImage(data: data),
				  !Task.isCancelled else {
				return
			}
			guard let self, self.currentImageURL == urlString else { return }
			self.iconImageView.image = image
			self.iconImageView.tintColor = nil
			self.iconImageView.contentMode = .scaleAspectFill
		}
	}

	func configureFindLoading(sourceType: FindSourceType) {
		nameLabel.text = NSLocalizedString("Loading...", comment: "Loading placeholder")
		nameLabel.textColor = .secondaryLabel
		let symbolName = sourceType == .podcast ? "mic.fill" : "play.rectangle.fill"
		let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
		iconImageView.image = UIImage(systemName: symbolName, withConfiguration: config)
		iconImageView.tintColor = .tertiaryLabel
		iconImageView.contentMode = .center
		iconImageView.backgroundColor = Assets.Colors.interactionBackground
	}

	private func showPlaceholder() {
		iconImageView.image = UIImage(systemName: "photo")
		iconImageView.tintColor = .tertiaryLabel
		iconImageView.contentMode = .center
	}
}
