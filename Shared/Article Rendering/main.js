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

		// Create wrapper div for the collapsible section
		const wrapper = document.createElement("div");
		wrapper.className = "nnw-collapsible";
		wrapper.setAttribute("data-open", "true");
		wrapper.setAttribute("data-level", String(headerLevel));

		// Create clickable header
		const headerDiv = document.createElement("div");
		headerDiv.className = "nnw-collapsible-header nnw-collapsible-h" + headerLevel;
		headerDiv.innerHTML = header.innerHTML;

		// Create a div to hold the content
		const content = document.createElement("div");
		content.className = "nnw-collapsible-content";

		// Find all siblings until the next header of same or higher level
		// Skip any already-processed collapsible wrappers at same or higher level
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

		// Move siblings to content div
		for (const sib of siblingsToMove) {
			content.appendChild(sib);
		}

		// Build the wrapper
		wrapper.appendChild(headerDiv);
		wrapper.appendChild(content);

		// Add click handler to header
		headerDiv.addEventListener("click", function(e) {
			e.preventDefault();
			e.stopPropagation();
			const section = this.closest(".nnw-collapsible");
			const contentDiv = section.querySelector(".nnw-collapsible-content");
			const isOpen = section.getAttribute("data-open") === "true";

			if (isOpen) {
				section.setAttribute("data-open", "false");
				contentDiv.style.display = "none";
			} else {
				section.setAttribute("data-open", "true");
				contentDiv.style.display = "block";
			}
		});

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

// Find the MP3 URL from the metadata section
function findMp3Url() {
	const listItems = document.querySelectorAll(".articleBody li");
	for (const li of listItems) {
		const strong = li.querySelector("strong");
		if (strong && strong.textContent.trim() === "MP3:") {
			const link = li.querySelector("a");
			if (link && link.href) {
				return link.href;
			}
		}
	}
	return null;
}

// Add play buttons next to MP3 links in metadata and outline timestamps
function addMp3PlayButtons() {
	const mp3Url = findMp3Url();
	const titleElement = document.querySelector(".articleTitle h1 a, .articleTitle h1");
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

		// Check for MP3: label - replace with "Podcast: triangle"
		if (strongText === "MP3:") {
			const link = li.querySelector("a");
			if (link && link.href) {
				const audioUrl = link.href;

				// Change label from "MP3:" to "Podcast:"
				strong.textContent = "Podcast:";

				// Create play button
				const playButton = document.createElement("button");
				playButton.className = "nnw-mp3-play-button";
				playButton.innerHTML = "&#9654;"; // Play triangle
				playButton.title = "Play podcast";

				playButton.addEventListener("click", function(e) {
					e.preventDefault();
					e.stopPropagation();

					// Send message to native code
					if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playAudio) {
						window.webkit.messageHandlers.playAudio.postMessage({
							url: audioUrl,
							title: articleTitle,
							startTime: 0
						});
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

			if (mp3Url && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playAudio) {
				const message = {
					url: mp3Url,
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
	addMp3PlayButtons();
	postRenderProcessing();
}

document.addEventListener("DOMContentLoaded", function(event) {
	processPage();
})
