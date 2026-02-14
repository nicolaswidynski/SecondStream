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

	private let iconImageView: UIImageView = {
		let iv = UIImageView()
		iv.contentMode = .scaleAspectFill
		iv.clipsToBounds = true
		iv.layer.cornerRadius = 12
		iv.backgroundColor = .secondarySystemFill
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
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		iconImageView.image = nil
		iconImageView.backgroundColor = .secondarySystemFill
		iconImageView.contentMode = .scaleAspectFill
		iconImageView.tintColor = nil
		nameLabel.text = nil
		nameLabel.textColor = .label
		currentImageURL = nil
	}

	func configure(name: String, imageURL: String?, isCustomEntry: Bool = false) {
		nameLabel.text = name
		currentImageURL = imageURL

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

		guard let imageURL else {
			showPlaceholder()
			return
		}

		if let image = SourceImageCache.shared.image(for: imageURL) {
			iconImageView.image = image
		} else {
			showPlaceholder()
		}
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

	private func showPlaceholder() {
		iconImageView.image = UIImage(systemName: "photo")
		iconImageView.tintColor = .tertiaryLabel
		iconImageView.contentMode = .center
	}
}
