// Here we are making iframes responsive.  Particularly useful for inline Youtube videos.
function wrapFrames() {
	document.querySelectorAll("iframe").forEach(element => {
		if (element.height > 0 || parseInt(element.style.height) > 0)
			return;
		var wrapper = document.createElement("div");
		wrapper.classList.add("iframeWrap");
		element.parentNode.insertBefore(wrapper, element);
		wrapper.appendChild(element);
	});
}

// Strip out color and font styling

function stripStylesFromElement(element, propertiesToStrip) {
	for (name of propertiesToStrip) {
		element.style.removeProperty(name);
	}
}

// Strip inline styles that could harm readability.
function stripStyles() {
	document.getElementsByTagName("body")[0].querySelectorAll("style, link[rel=stylesheet]").forEach(element => element.remove());
	// Removing "background" and "font" will also remove properties that would be reflected in them, e.g., "background-color" and "font-family"
	document.getElementsByTagName("body")[0].querySelectorAll("[style]").forEach(element => stripStylesFromElement(element, ["color", "background", "font", "max-width", "max-height", "position"]));
}

// Constrain the height of iframes whose heights are defined relative to the document body to be at most
// 50% of the viewport width.
function constrainBodyRelativeIframes() {
	let iframes = document.getElementsByTagName("iframe");

	for (iframe of iframes) {
		if (iframe.offsetParent === document.body) {
			let heightAttribute = iframe.style.height;

			if (/%|vw|vh$/i.test(heightAttribute)) {
				iframe.classList.add("nnw-constrained");
			}
		}
	}
}

// Convert all Feedbin proxy images to be used as src, otherwise change image locations to be absolute if not already
function convertImgSrc() {
	document.querySelectorAll("img").forEach(element => {
		if (element.hasAttribute("data-canonical-src")) {
			element.src = element.getAttribute("data-canonical-src")
		} else if (!/^[a-z]+\:\/\//i.test(element.src)) {
			element.src = new URL(element.src, document.baseURI).href;
		}
	});
}

// Wrap tables in an overflow-x: auto; div
function wrapTables() {
	var tables = document.querySelectorAll("div.articleBody table");

	for (table of tables) {
		var wrapper = document.createElement("div");
		wrapper.className = "nnw-overflow";
		table.parentNode.insertBefore(wrapper, table);
		wrapper.appendChild(table);
	}
}

// Add the playsinline attribute to any HTML5 videos that don"t have it.
// Without this attribute videos may autoplay and take over the whole screen
// on an iphone when viewing an article.
function inlineVideos() {
	document.querySelectorAll("video").forEach(element => {
		element.setAttribute("playsinline", true);
		if (!element.classList.contains("nnwAnimatedGIF")) {
			element.setAttribute("controls", true);
			element.removeAttribute("autoplay");
		}
	});
}

// Remove some children (currently just spans) from pre elements to work around a strange clipping issue
var ElementUnwrapper = {
	unwrapSelector: "span",
	unwrapElement: function (element) {
		var parent = element.parentNode;
		var children = Array.from(element.childNodes);

		for (child of children) {
			parent.insertBefore(child, element);
		}

		parent.removeChild(element);
	},
	// `elements` can be a selector string, an element, or a list of elements
	unwrapAppropriateChildren: function (elements) {
		if (typeof elements[Symbol.iterator] !== 'function')
			elements = [elements];
		else if (typeof elements === "string")
			elements = document.querySelectorAll(elements);

		for (element of elements) {
			for (unwrap of element.querySelectorAll(this.unwrapSelector)) {
				this.unwrapElement(unwrap);
			}

			element.normalize()
		}
	}
};

function flattenPreElements() {
	ElementUnwrapper.unwrapAppropriateChildren("div.articleBody td > pre");
}

function reloadArticleImage(imageSrc) {
	var image = document.getElementById("nnwImageIcon");
	image.src = imageSrc + "?" + new Date().getTime();
}

function stopMediaPlayback() {
	document.querySelectorAll("iframe").forEach(element => {
		var iframeSrc = element.src;
		element.src = iframeSrc;
	});

	// We pause all videos that have controls.  Video without controls shouldn't
	// have sound and are actually converted gifs.  Basically if the user can't
	// start the video again, don't stop it.
	document.querySelectorAll("video, audio").forEach(element => {
		if (element.hasAttribute("controls")) {
			element.pause();
		}
	});
}

function error() {
	document.body.innerHTML = "error";
}

// Takes into account absoluting of URLs.
function isLocalFootnote(target) {
	return target.hash.startsWith("#fn") && target.href.indexOf(document.baseURI) === 0;
}

function styleLocalFootnotes() {
	for (elem of document.querySelectorAll("sup > a[href*='#fn'], sup > div > a[href*='#fn']")) {
		if (isLocalFootnote(elem)) {
			elem.classList.add("footnote");
		}
	}
}

// convert <img alt="📰" src="[...]" class="wp-smiley"> to a text node containing 📰
function removeWpSmiley() {
	for (const img of document.querySelectorAll("img.wp-smiley[alt]")) {
		 img.parentNode.replaceChild(document.createTextNode(img.alt), img);
	}
}

// Create a collapsible section with dropdown arrow
function createCollapsibleSection(headerElement, headerText, headerClass, siblings, startCollapsed) {
	const wrapper = document.createElement("div");
	wrapper.className = "nnw-collapsible";
	wrapper.setAttribute("data-open", startCollapsed ? "false" : "true");

	// Create clickable header with dropdown arrow
	const headerDiv = document.createElement("div");
	headerDiv.className = "nnw-collapsible-header " + headerClass;

	// Add dropdown arrow
	const arrow = document.createElement("span");
	arrow.className = "nnw-collapsible-arrow";
	arrow.innerHTML = startCollapsed ? "▶" : "▼";

	const headerContent = document.createElement("span");
	headerContent.innerHTML = headerText;

	headerDiv.appendChild(arrow);
	headerDiv.appendChild(headerContent);

	// Create content div
	const content = document.createElement("div");
	content.className = "nnw-collapsible-content";
	if (startCollapsed) {
		content.style.display = "none";
	}

	// Move siblings to content div
	for (const sib of siblings) {
		content.appendChild(sib);
	}

	wrapper.appendChild(headerDiv);
	wrapper.appendChild(content);

	// Add click handler
	headerDiv.addEventListener("click", function(e) {
		e.preventDefault();
		e.stopPropagation();
		const section = this.closest(".nnw-collapsible");
		const contentDiv = section.querySelector(".nnw-collapsible-content");
		const arrowSpan = this.querySelector(".nnw-collapsible-arrow");
		const isOpen = section.getAttribute("data-open") === "true";

		if (isOpen) {
			section.setAttribute("data-open", "false");
			contentDiv.style.display = "none";
			arrowSpan.innerHTML = "▶";
		} else {
			section.setAttribute("data-open", "true");
			contentDiv.style.display = "block";
			arrowSpan.innerHTML = "▼";
		}
	});

	return wrapper;
}

// Make the Metadata section collapsible (collapsed by default)
function makeMetadataCollapsible() {
	const articleBody = document.querySelector(".articleBody");
	if (!articleBody) {
		return;
	}

	// Find the Metadata paragraph: <p><strong>Metadata</strong></p>
	const paragraphs = articleBody.querySelectorAll("p");
	let metadataParagraph = null;

	for (const p of paragraphs) {
		const strong = p.querySelector("strong");
		if (strong && strong.textContent.trim() === "Metadata") {
			metadataParagraph = p;
			break;
		}
	}

	if (!metadataParagraph) {
		return;
	}

	// Collect siblings until the next <hr> or header
	const siblingsToMove = [];
	let sibling = metadataParagraph.nextElementSibling;

	while (sibling) {
		if (sibling.tagName === "HR" || /^H[1-6]$/.test(sibling.tagName)) {
			break;
		}
		const nextSibling = sibling.nextElementSibling;
		siblingsToMove.push(sibling);
		sibling = nextSibling;
	}

	// Create collapsible section (collapsed by default)
	const wrapper = createCollapsibleSection(
		metadataParagraph,
		"Metadata",
		"nnw-collapsible-metadata",
		siblingsToMove,
		true // start collapsed
	);

	// Replace the metadata paragraph with the wrapper
	metadataParagraph.parentNode.replaceChild(wrapper, metadataParagraph);
}

// Make headers collapsible - tap header to collapse/expand
function makeHeadersCollapsible() {
	const articleBody = document.querySelector(".articleBody");
	if (!articleBody) {
		return;
	}

	// Get all headers in the article body
	const headers = articleBody.querySelectorAll("h1, h2, h3, h4, h5, h6");
	if (headers.length === 0) {
		return;
	}

	// Count H1s - if there's only one, remove it (title is already shown above)
	const h1Headers = articleBody.querySelectorAll("h1");
	if (h1Headers.length === 1) {
		h1Headers[0].remove();
	}

	// Re-query headers after potential H1 removal
	const remainingHeaders = articleBody.querySelectorAll("h1, h2, h3, h4, h5, h6");
	if (remainingHeaders.length === 0) {
		return;
	}

	// Process headers in reverse order to avoid index shifting issues
	const headerArray = Array.from(remainingHeaders);

	for (let i = headerArray.length - 1; i >= 0; i--) {
		const header = headerArray[i];
		const headerLevel = parseInt(header.tagName.charAt(1));

		// Find all siblings until the next header of same or higher level
		let sibling = header.nextElementSibling;
		const siblingsToMove = [];

		while (sibling) {
			const nextSibling = sibling.nextElementSibling;

			// Check if this is an already-processed collapsible at same or higher level
			if (sibling.classList && sibling.classList.contains("nnw-collapsible")) {
				const siblingLevel = parseInt(sibling.getAttribute("data-level") || "99");
				if (siblingLevel <= headerLevel) {
					break;
				}
			}

			// Check if this sibling is an unprocessed header
			if (/^H[1-6]$/.test(sibling.tagName)) {
				const siblingLevel = parseInt(sibling.tagName.charAt(1));
				if (siblingLevel <= headerLevel) {
					break;
				}
			}

			siblingsToMove.push(sibling);
			sibling = nextSibling;
		}

		// Create collapsible section (expanded by default)
		const wrapper = createCollapsibleSection(
			header,
			header.innerHTML,
			"nnw-collapsible-h" + headerLevel,
			siblingsToMove,
			false // start expanded
		);
		wrapper.setAttribute("data-level", String(headerLevel));

		// Replace the header with the wrapper
		header.parentNode.replaceChild(wrapper, header);
	}
}

// Parse timestamp string like "[01:50]" or "[1:23:45]" to seconds
function parseTimestamp(timestampStr) {
	// Remove brackets and trim
	const clean = timestampStr.replace(/[\[\]]/g, "").trim();
	const parts = clean.split(":").map(Number);

	if (parts.length === 2) {
		// MM:SS format
		return parts[0] * 60 + parts[1];
	} else if (parts.length === 3) {
		// HH:MM:SS format
		return parts[0] * 3600 + parts[1] * 60 + parts[2];
	}
	return 0;
}

// Check if URL is a YouTube video and extract video ID
function getYouTubeVideoID(url) {
	if (!url) return null;

	// Match various YouTube URL formats
	const patterns = [
		/(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/,
		/youtube\.com\/v\/([a-zA-Z0-9_-]{11})/,
		/youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/
	];

	for (const pattern of patterns) {
		const match = url.match(pattern);
		if (match) {
			return match[1];
		}
	}
	return null;
}

// Find the media URL from the metadata section (supports both old MP3: and new Media: format)
function findMediaUrl() {
	const listItems = document.querySelectorAll(".articleBody li");
	for (const li of listItems) {
		const strong = li.querySelector("strong");
		if (strong) {
			const label = strong.textContent.trim();
			// Support both "MP3:" and "Media:" labels
			if (label === "MP3:" || label === "Media:") {
				const link = li.querySelector("a");
				if (link && link.href) {
					return link.href;
				}
			}
		}
	}
	return null;
}

// Fallback media source from the top title media icon/link.
function findTopMediaInfo() {
	const topMediaLink = document.querySelector(".articleTitle .nnw-top-media-link");
	if (!topMediaLink) {
		return { url: null, type: null };
	}

	const url = (topMediaLink.dataset.mediaUrl || "").trim();
	const type = (topMediaLink.dataset.mediaType || "").trim().toLowerCase();
	return {
		url: url.length > 0 ? url : null,
		type: type.length > 0 ? type : null
	};
}

// Add play buttons next to media links in metadata and outline timestamps
function addMp3PlayButtons() {
	const topMedia = findTopMediaInfo();
	const mediaUrl = findMediaUrl() || topMedia.url;
	const titleElement = document.querySelector(".articleTitle h1 .nnw-title-text, .articleTitle h1 a:not(.nnw-top-media-link), .articleTitle h1");
	const articleTitle = titleElement ? titleElement.textContent : "Podcast";

	// Collect all timestamps for calculating end times
	const outlineItems = [];

	// Find all list items
	const listItems = document.querySelectorAll(".articleBody li");

	for (const li of listItems) {
		// Skip if already processed
		if (li.querySelector(".nnw-mp3-play-button")) {
			continue;
		}

		const strong = li.querySelector("strong");
		if (!strong) continue;

		const strongText = strong.textContent.trim();

		// Check for MP3: or Media: label - replace with play button
		if (strongText === "MP3:" || strongText === "Media:") {
			const link = li.querySelector("a");
			if (link && link.href) {
				const mediaUrl = link.href;
				const youtubeID = getYouTubeVideoID(mediaUrl);

				// Change label to "Media:"
				strong.textContent = "Media:";

				// Create play button
				const playButton = document.createElement("button");
				playButton.className = "nnw-mp3-play-button";
				playButton.innerHTML = "&#9654;"; // Play triangle
				playButton.title = youtubeID ? "Play video" : "Play media";

				playButton.addEventListener("click", function(e) {
					e.preventDefault();
					e.stopPropagation();

					if (youtubeID) {
						// Send message to play YouTube video
						if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playVideo) {
							window.webkit.messageHandlers.playVideo.postMessage({
								videoID: youtubeID,
								title: articleTitle
							});
						}
					} else {
						// Send message to play audio
						if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playAudio) {
							window.webkit.messageHandlers.playAudio.postMessage({
								url: mediaUrl,
								title: articleTitle,
								startTime: 0
							});
						}
					}
				});

				// Remove the link and insert play button after the label
				link.remove();
				strong.parentNode.insertBefore(playButton, strong.nextSibling);
			}
		}
		// Check for timestamp format like [00:00] or [01:50]
		else if (/^\[\d{1,2}:\d{2}(:\d{2})?\]$/.test(strongText)) {
			outlineItems.push({
				element: li,
				strong: strong,
				timestamp: strongText,
				seconds: parseTimestamp(strongText)
			});
		}
	}

	// Check if the media URL is a YouTube video.
	// If URL parsing doesn't detect it, trust explicit top-link media type.
	let youtubeVideoID = getYouTubeVideoID(mediaUrl);
	if (!youtubeVideoID && topMedia.type === "youtube" && topMedia.url) {
		youtubeVideoID = getYouTubeVideoID(topMedia.url);
	}

	// Now convert timestamps to clickable blue links
	for (let i = 0; i < outlineItems.length; i++) {
		const item = outlineItems[i];
		const nextItem = outlineItems[i + 1];
		const endTime = nextItem ? nextItem.seconds : null;

		const startSeconds = item.seconds;
		const endSeconds = endTime;

		// Create a clickable link from the timestamp
		const timestampLink = document.createElement("a");
		timestampLink.href = "#";
		timestampLink.className = "nnw-timestamp-link";
		timestampLink.textContent = item.timestamp;
		timestampLink.title = "Play from " + item.timestamp;

		timestampLink.addEventListener("click", function(e) {
			e.preventDefault();
			e.stopPropagation();

			if (youtubeVideoID) {
				// Play YouTube video at timestamp
				if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playVideo) {
					window.webkit.messageHandlers.playVideo.postMessage({
						videoID: youtubeVideoID,
						title: articleTitle,
						startTime: startSeconds
					});
				}
			} else if (mediaUrl && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playAudio) {
				const message = {
					url: mediaUrl,
					title: articleTitle,
					startTime: startSeconds
				};
				if (endSeconds !== null) {
					message.endTime = endSeconds;
				}
				window.webkit.messageHandlers.playAudio.postMessage(message);
			}
		});

		// Replace the strong element with the link
		item.strong.parentNode.replaceChild(timestampLink, item.strong);
	}
}

function wireTopMediaButton() {
	const topMediaLink = document.querySelector(".articleTitle .nnw-top-media-link");
	if (!topMediaLink || topMediaLink.dataset.nnwBound === "1") {
		return;
	}
	topMediaLink.dataset.nnwBound = "1";

	topMediaLink.addEventListener("click", function(e) {
		e.preventDefault();
		e.stopPropagation();

		const mediaUrl = topMediaLink.dataset.mediaUrl || "";
		const mediaType = (topMediaLink.dataset.mediaType || "").toLowerCase();
		if (!mediaUrl) {
			return;
		}

		const titleElement = document.querySelector(".articleTitle h1 .nnw-title-text, .articleTitle h1");
		const articleTitle = titleElement ? titleElement.textContent : "Podcast";
		const youtubeID = getYouTubeVideoID(mediaUrl);

		if ((mediaType === "youtube" || youtubeID) && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playVideo && youtubeID) {
			window.webkit.messageHandlers.playVideo.postMessage({
				videoID: youtubeID,
				title: articleTitle,
				startTime: 0
			});
			return;
		}

		if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playAudio) {
			window.webkit.messageHandlers.playAudio.postMessage({
				url: mediaUrl,
				title: articleTitle,
				startTime: 0
			});
			return;
		}

		window.location.href = mediaUrl;
	});
}

function processPage() {
	wrapFrames();
	wrapTables();
	inlineVideos();
	stripStyles();
	constrainBodyRelativeIframes();
	convertImgSrc();
	flattenPreElements();
	styleLocalFootnotes();
	removeWpSmiley()
	wireTopMediaButton();
	addMp3PlayButtons();
	postRenderProcessing();
}

document.addEventListener("DOMContentLoaded", function(event) {
	processPage();
})
