//
//  RSAtomParser.m
//  RSParser
//
//  Created by Brent Simmons on 1/15/15.
//  Copyright (c) 2015 Ranchero Software LLC. All rights reserved.
//


#import "RSAtomParser.h"
#import "RSSAXParser.h"
#import "RSParsedFeed.h"
#import "RSParsedArticle.h"
#import "NSString+RSParser.h"
#import "RSDateParser.h"
#import "ParserData.h"
#import "RSParsedEnclosure.h"
#import "RSParsedAuthor.h"
#import "RSParserInternal.h"

#import <libxml/xmlstring.h>

@interface RSAtomParser () <RSSAXParserDelegate>

@property (nonatomic) NSData *feedData;
@property (nonatomic) NSString *urlString;
@property (nonatomic) BOOL endFeedFound;
@property (nonatomic) BOOL parsingXHTML;
@property (nonatomic) BOOL parsingSource;
@property (nonatomic) BOOL parsingArticle;
@property (nonatomic) BOOL parsingAuthor;
@property (nonatomic) NSMutableArray *attributesStack;
@property (nonatomic, readonly) NSDictionary *currentAttributes;
@property (nonatomic) NSMutableString *xhtmlString;
@property (nonatomic) NSString *link;
@property (nonatomic) NSString *homepageURLString;
@property (nonatomic) NSString *title;
@property (nonatomic) NSMutableArray *articles;
@property (nonatomic) NSDate *dateParsed;
@property (nonatomic) RSSAXParser *parser;
@property (nonatomic, readonly) RSParsedArticle *currentArticle;
@property (nonatomic) RSParsedAuthor *currentAuthor;
@property (nonatomic) RSParsedAuthor *rootAuthor;
@property (nonatomic, readonly) NSDate *currentDate;
@property (nonatomic) NSString *language;
@property (nonatomic) BOOL isDaringFireball; // Special case — sometimes permalink and external link are swapped.
@property (nonatomic) NSString *iconURLString;

@end


@implementation RSAtomParser

#pragma mark - Class Methods

+ (RSParsedFeed *)parseFeedWithData:(ParserData *)parserData {

	RSAtomParser *parser = [[[self class] alloc] initWithParserData:parserData];
	return [parser parseFeed];
}


#pragma mark - Init

- (instancetype)initWithParserData:(ParserData *)parserData {
	
	self = [super init];
	if (!self) {
		return nil;
	}
	
	_feedData = parserData.data;
	_urlString = parserData.url;
	_parser = [[RSSAXParser alloc] initWithDelegate:self];
	_attributesStack = [NSMutableArray new];
	_articles = [NSMutableArray new];
	_isDaringFireball =  [_urlString containsString:@"daringfireball.net/"];

	return self;
}


#pragma mark - API

- (RSParsedFeed *)parseFeed {

	[self parse];

	RSParsedFeed *parsedFeed = [[RSParsedFeed alloc] initWithURLString:self.urlString title:self.title homepageURLString:self.homepageURLString language:self.language articles:self.articles iconURLString:self.iconURLString feedURLString:nil];

	return parsedFeed;
}


#pragma mark - Constants

static NSString *kTypeKey = @"type";
static NSString *kXHTMLType = @"xhtml";
static NSString *kRelKey = @"rel";
static NSString *kAlternateValue = @"alternate";
static NSString *kHrefKey = @"href";
static NSString *kXMLKey = @"xml";
static NSString *kBaseKey = @"base";
static NSString *kLangKey = @"lang";
static NSString *kXMLBaseKey = @"xml:base";
static NSString *kXMLLangKey = @"xml:lang";
static NSString *kTextHTMLValue = @"text/html";
static NSString *kRelatedValue = @"related";
static NSString *kEnclosureValue = @"enclosure";
static NSString *kShortURLValue = @"shorturl";
static NSString *kHTMLValue = @"html";
static NSString *kEnValue = @"en";
static NSString *kTextValue = @"text";
static NSString *kSelfValue = @"self";
static NSString *kLengthKey = @"length";
static NSString *kTitleKey = @"title";
static NSCache<NSString *, NSData *> *kGeneratedJSONDataCache;

static const char *kID = "id";
static const NSInteger kIDLength = 3;

static const char *kTitle = "title";
static const NSInteger kTitleLength = 6;

static const char *kContent = "content";
static const NSInteger kContentLength = 8;

static const char *kSummary = "summary";
static const NSInteger kSummaryLength = 8;

static const char *kLink = "link";
static const NSInteger kLinkLength = 5;

static const char *kPublished = "published";
static const NSInteger kPublishedLength = 10;

static const char *kIssued = "issued";
static const NSInteger kIssuedLength = 7;

static const char *kUpdated = "updated";
static const NSInteger kUpdatedLength = 8;

static const char *kModified = "modified";
static const NSInteger kModifiedLength = 9;

static const char *kPubDate = "pub_date";
static const NSInteger kPubDateLength = 9;

static const char *kMp3URL = "mp3_url";
static const NSInteger kMp3URLLength = 8;

static const char *kURLJSON = "url_json";
static const NSInteger kURLJSONLength = 9;

static const char *kAuthor = "author";
static const NSInteger kAuthorLength = 7;

static const char *kName = "name";
static const NSInteger kNameLength = 5;

static const char *kEmail = "email";
static const NSInteger kEmailLength = 6;

static const char *kURI = "uri";
static const NSInteger kURILength = 4;

static const char *kEntry = "entry";
static const NSInteger kEntryLength = 6;

static const char *kSource = "source";
static const NSInteger kSourceLength = 7;

static const char *kFeed = "feed";
static const NSInteger kFeedLength = 5;

static const char *kType = "type";
static const NSInteger kTypeLength = 5;

static const char *kRel = "rel";
static const NSInteger kRelLength = 4;

static const char *kAlternate = "alternate";
static const NSInteger kAlternateLength = 10;

static const char *kHref = "href";
static const NSInteger kHrefLength = 5;

static const char *kXML = "xml";
static const NSInteger kXMLLength = 4;

static const char *kBase = "base";
static const NSInteger kBaseLength = 5;

static const char *kLang = "lang";
static const NSInteger kLangLength = 5;

static const char *kTextHTML = "text/html";
static const NSInteger kTextHTMLLength = 10;

static const char *kRelated = "related";
static const NSInteger kRelatedLength = 8;

static const char *kShortURL = "shorturl";
static const NSInteger kShortURLLength = 9;

static const char *kHTML = "html";
static const NSInteger kHTMLLength = 5;

static const char *kEn = "en";
static const NSInteger kEnLength = 3;

static const char *kText = "text";
static const NSInteger kTextLength = 5;

static const char *kSelf = "self";
static const NSInteger kSelfLength = 5;

static const char *kEnclosure = "enclosure";
static const NSInteger kEnclosureLength = 10;

static const char *kLength = "length";
static const NSInteger kLengthLength = 7;

static const char *kImageRef = "image_ref";
static const NSInteger kImageRefLength = 10;

#pragma mark - Parsing

- (void)parse {

	self.dateParsed = [NSDate date];

	@autoreleasepool {
		[self.parser parseData:self.feedData];
		[self.parser finishParsing];
	}

	// Add root author to individual articles as needed.
	RSParsedAuthor *authorToAdd = self.rootAuthor;
	if (authorToAdd) {
		for (RSParsedArticle *article in self.articles) {
			if (article.authors.count < 1) {
				[article addAuthor:authorToAdd];
			}
		}
	}
}

- (void)addArticle {

	RSParsedArticle *article = [[RSParsedArticle alloc] initWithFeedURL:self.urlString];
	article.dateParsed = self.dateParsed;

	[self.articles addObject:article];
}


- (RSParsedArticle *)currentArticle {

	return self.articles.lastObject;
}

- (NSDictionary *)currentAttributes {

	return self.attributesStack.lastObject;
}

- (NSDate *)currentDate {

	return RSDateWithBytes(self.parser.currentCharacters.bytes, self.parser.currentCharacters.length);
}

- (void)addHomePageLink {

	if (!RSParserStringIsEmpty(self.homepageURLString)) {
		return;
	}

	NSString *rawLink = self.currentAttributes[kHrefKey];
	if (RSParserStringIsEmpty(rawLink)) {
		return;
	}
	NSString *resolvedRawLink = [self resolvedURLString:rawLink];
	if (RSParserStringIsEmpty(resolvedRawLink)) {
		return;
	}

	NSString *rel = self.currentAttributes[kRelKey];
	NSString *type = self.currentAttributes[kTypeKey];
	NSString *normalizedRel = rel.lowercaseString;

	// Never treat Atom self-link (or feed/XML typed links) as the feed homepage.
	if ([normalizedRel isEqualToString:kSelfValue]) {
		return;
	}
	if (type.length > 0) {
		NSString *lowerType = type.lowercaseString;
		if ([lowerType containsString:@"atom+xml"] || [lowerType containsString:@"rss+xml"] || [lowerType containsString:@"/xml"]) {
			return;
		}
	}

	// rel="alternate" == home page URL
	// Also: spec says "alternate" is default value if not present
	// <https://datatracker.ietf.org/doc/html/rfc4287#section-4.2.7.2>
	if (!rel || [normalizedRel isEqualToString:kAlternateValue]) {
		self.homepageURLString = resolvedRawLink;
	}
}

- (void)addFeedTitle {

	if (self.title.length < 1) {
		self.title = [self currentString];
	}
}

- (void)addFeedLanguage {

	if (self.language.length < 0) {
		self.language = self.currentAttributes[kXMLLangKey];
	}
}

- (void)addPermalink:(NSString *)resolvedURLString article:(RSParsedArticle *)article {
	if (RSParserStringIsEmpty(article.permalink)) {
		article.permalink = resolvedURLString;
	}
}

- (void)addExternalLink:(NSString *)resolvedURLString article:(RSParsedArticle *)article  {
	if (RSParserStringIsEmpty(article.link)) {
		article.link = resolvedURLString;
	}
}

static NSString *daringFireballPermalinkPrefix = @"https://daringfireball.net/";

- (void)addLink {

	NSDictionary *attributes = self.currentAttributes;

	NSString *urlString = attributes[kHrefKey];
	if (urlString.length < 1) {
		return;
	}
	NSString *resolvedURLString = [self resolvedURLString:urlString];
	if (RSParserStringIsEmpty(resolvedURLString)) {
		return;
	}

	RSParsedArticle *article = self.currentArticle;

	NSString *rel = attributes[kRelKey];
	if (rel.length < 1) {
		rel = kAlternateValue;
	}

	if ([rel isEqualToString:kEnclosureValue]) {
		RSParsedEnclosure *enclosure = [self enclosureWithURLString:resolvedURLString attributes:attributes];
		[article addEnclosure:enclosure];
		if (RSParserStringIsEmpty(article.mp3URL)) {
			article.mp3URL = resolvedURLString;
		}
		return;
	}

	if (self.isDaringFireball) {
		// Permalink and external link are swapped sometimes.
		// Decide which is which by looking at the URL prefix — is it a link to daringfireball.net or to elsewhere?
		BOOL isDaringFireballLink = [resolvedURLString hasPrefix:daringFireballPermalinkPrefix];
		if (isDaringFireballLink) {
			[self addPermalink:resolvedURLString article:article];
		}
		else {
			[self addExternalLink:resolvedURLString article:article];
		}
		return;
	}

	// Standard behavior: rel="related" is external link
	if (rel == kRelatedValue) {
		[self addExternalLink:resolvedURLString article:article];
	}

	// Standard behavior: rel="alternate" is permalink
	if (rel == kAlternateValue) {
		[self addPermalink:resolvedURLString article:article];
	}
}

- (RSParsedEnclosure *)enclosureWithURLString:(NSString *)urlString attributes:(NSDictionary *)attributes {

	RSParsedEnclosure *enclosure = [[RSParsedEnclosure alloc] init];
	enclosure.url = urlString;
	enclosure.title = attributes[kTitleKey];
	enclosure.mimeType = attributes[kTypeKey];
	enclosure.length = [attributes[kLengthKey] integerValue];

	return enclosure;
}

- (void)addContent {

	NSString *content = [self currentString];
	// Only set body if content is not empty
	if (content && content.length > 0) {
		self.currentArticle.body = content;
	}
}


- (void)addSummary {

	// Use summary if body is nil or empty (consistent with XHTML handling)
	if (!self.currentArticle.body || self.currentArticle.body.length < 1) {
		self.currentArticle.body = [self currentString];
	}
}

- (BOOL)isNwidynskiFilesURLString:(NSString *)urlString {
	if (RSParserStringIsEmpty(urlString)) {
		return NO;
	}

	NSURL *url = [NSURL URLWithString:urlString];
	NSString *host = url.host.lowercaseString;
	return [host isEqualToString:@"files.nwidynski.com"];
}

- (NSString *)htmlEscapedString:(NSString *)s {
	if (RSParserStringIsEmpty(s)) {
		return @"";
	}

	NSMutableString *escaped = [s mutableCopy];
	[escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"'" withString:@"&#39;" options:0 range:NSMakeRange(0, escaped.length)];
	return escaped;
}

- (void)appendTitledContentArray:(NSArray *)array title:(NSString *)title into:(NSMutableString *)html {
	if (![array isKindOfClass:[NSArray class]] || array.count < 1) {
		return;
	}

	[html appendFormat:@"<h2>%@</h2>", [self htmlEscapedString:title]];
	[html appendString:@"<ul>"];
	for (id item in array) {
		if (![item isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NSString *itemTitle = [self htmlEscapedString:((NSDictionary *)item)[@"title"]];
		NSString *itemContent = [self htmlEscapedString:((NSDictionary *)item)[@"content"]];
		if (RSParserStringIsEmpty(itemTitle) && RSParserStringIsEmpty(itemContent)) {
			continue;
		}
		[html appendString:@"<li>"];
		if (!RSParserStringIsEmpty(itemTitle)) {
			[html appendFormat:@"<strong>%@:</strong>", itemTitle];
		}
		if (!RSParserStringIsEmpty(itemContent)) {
			if (!RSParserStringIsEmpty(itemTitle)) {
				[html appendString:@" "];
			}
			[html appendString:itemContent];
		}
		[html appendString:@"</li>"];
	}
	[html appendString:@"</ul>"];
}

- (NSString *)generatedArticleHTMLFromJSONData:(NSData *)data {
	if (!data || data.length < 1) {
		return nil;
	}

	NSError *error = nil;
	id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (error || ![object isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	NSDictionary *json = (NSDictionary *)object;
	NSMutableString *html = [NSMutableString string];

	NSDictionary *summary = json[@"summary"];
	if ([summary isKindOfClass:[NSDictionary class]]) {
		[self appendTitledContentArray:summary[@"thesis"] title:@"Executive Summary" into:html];
		[self appendTitledContentArray:summary[@"practical"] title:@"Practical Information" into:html];
	}

	NSArray *inDepth = json[@"in_depth_analysis"];
	if ([inDepth isKindOfClass:[NSArray class]] && inDepth.count > 0) {
		[html appendString:@"<h2>In-Depth Analysis</h2>"];
		for (id section in inDepth) {
			if (![section isKindOfClass:[NSDictionary class]]) {
				continue;
			}
			NSString *sectionTitle = [self htmlEscapedString:((NSDictionary *)section)[@"title"]];
			NSString *sectionContent = [self htmlEscapedString:((NSDictionary *)section)[@"content"]];
			if (!RSParserStringIsEmpty(sectionTitle)) {
				[html appendFormat:@"<h3>%@</h3>", sectionTitle];
			}
			if (!RSParserStringIsEmpty(sectionContent)) {
				[html appendFormat:@"<p>%@</p>", sectionContent];
			}
		}
	}

	NSArray *timestamps = json[@"timestamps"];
	if ([timestamps isKindOfClass:[NSArray class]] && timestamps.count > 0) {
		[html appendString:@"<h2>Timestamps</h2><ul>"];
		for (id stamp in timestamps) {
			if (![stamp isKindOfClass:[NSDictionary class]]) {
				continue;
			}
			NSString *timestamp = [self htmlEscapedString:((NSDictionary *)stamp)[@"timestamp"]];
			NSString *content = [self htmlEscapedString:((NSDictionary *)stamp)[@"content"]];
			if (RSParserStringIsEmpty(timestamp) && RSParserStringIsEmpty(content)) {
				continue;
			}
			[html appendString:@"<li>"];
			if (!RSParserStringIsEmpty(timestamp)) {
				[html appendFormat:@"<strong>%@</strong>", timestamp];
			}
			if (!RSParserStringIsEmpty(content)) {
				if (!RSParserStringIsEmpty(timestamp)) {
					[html appendString:@" - "];
				}
				[html appendString:content];
			}
			[html appendString:@"</li>"];
		}
		[html appendString:@"</ul>"];
	}

	// Keep topics/news resilient if their JSON shape diverges from podcast/youtube.
	if (html.length < 1) {
		NSError *prettyError = nil;
		NSData *prettyData = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&prettyError];
		if (!prettyError && prettyData.length > 0) {
			NSString *pretty = [[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding];
			if (!RSParserStringIsEmpty(pretty)) {
				[html appendFormat:@"<pre>%@</pre>", [self htmlEscapedString:pretty]];
			}
		}
	}

	if (html.length < 1) {
		return nil;
	}
	return [html copy];
}

- (void)addJSONContentURL {
	NSString *urlString = [self currentString];
	NSString *resolvedURLString = [self resolvedURLString:urlString];
	if (RSParserStringIsEmpty(resolvedURLString)) {
		return;
	}

	// Only hydrate generated custom sources from the nwidynski file host.
	if (![self isNwidynskiFilesURLString:resolvedURLString]) {
		return;
	}

	// Keep parser tests deterministic (no network dependency).
	if (NSClassFromString(@"XCTestCase") != Nil) {
		return;
	}

	NSURL *url = [NSURL URLWithString:resolvedURLString];
	if (!url) {
		return;
	}

	if (!kGeneratedJSONDataCache) {
		kGeneratedJSONDataCache = [NSCache new];
	}

	NSData *jsonData = [kGeneratedJSONDataCache objectForKey:resolvedURLString];
	if (!jsonData) {
		jsonData = [NSData dataWithContentsOfURL:url];
		if (jsonData.length > 0) {
			[kGeneratedJSONDataCache setObject:jsonData forKey:resolvedURLString];
		}
	}
	if (!jsonData || jsonData.length < 1) {
		return;
	}

	NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	if (!RSParserStringIsEmpty(jsonString)) {
		self.currentArticle.contentJSON = jsonString;
	}

	if (RSParserStringIsEmpty(self.currentArticle.body)) {
		NSString *generatedHTML = [self generatedArticleHTMLFromJSONData:jsonData];
		if (!RSParserStringIsEmpty(generatedHTML)) {
			self.currentArticle.body = generatedHTML;
		}
	}
}

- (NSString *)resolvedURLString:(NSString *)s {

	// Resolve against home page URL (if available) or feed URL.
	// Important: returns nil if the result does not begin with @"http://" or @"https://"
	// This is because we don’t want relative paths that might get interpreted
	// as file paths when displayed in the app.

	// Already a full URL? No need to resolve?
	if ([self isValidURLString:s]) {
		return s;
	}

	NSString *baseURLString = self.homepageURLString;
	if (RSParserStringIsEmpty(baseURLString)) {
		baseURLString = self.urlString;
	}
	if (RSParserStringIsEmpty(baseURLString)) {
		return nil; // Nothing to resolve against.
	}

	NSURL *baseURL = [NSURL URLWithString:baseURLString];
	if (!baseURL) {
		return nil; // Must have non-nil NSURL in order to resolve.
	}

	NSURL *resolvedURL = [NSURL URLWithString:s relativeToURL:baseURL];
	NSString *urlString = resolvedURL.absoluteString;
	if (!RSParserStringIsEmpty(urlString) && [self isValidURLString:urlString]) {
		return urlString; // Must be valid, resolved URL
	}

	return nil;
}

static NSString *httpsURLPrefix = @"https://";
static NSString *httpURLPrefix = @"http://";

- (BOOL)isValidURLString:(NSString *)s {

	NSString *lowercaseString = [s lowercaseString];

	return ([lowercaseString hasPrefix:httpsURLPrefix] || [lowercaseString hasPrefix:httpURLPrefix]);
}

- (NSString *)currentString {

	return self.parser.currentStringWithTrimmedWhitespace;
}


- (void)addArticleElement:(const xmlChar *)localName prefix:(const xmlChar *)prefix {

	if (prefix) {
		return;
	}

	if (RSSAXEqualTags(localName, kID, kIDLength)) {
		self.currentArticle.guid = [self currentString];
	}

	else if (RSSAXEqualTags(localName, kTitle, kTitleLength)) {
		self.currentArticle.title = [self currentString];
	}

	else if (RSSAXEqualTags(localName, kContent, kContentLength)) {
		[self addContent];
	}

	else if (RSSAXEqualTags(localName, kSummary, kSummaryLength)) {
		[self addSummary];
	}

	else if (RSSAXEqualTags(localName, kLink, kLinkLength)) {
		[self addLink];
	}

	else if (RSSAXEqualTags(localName, kPublished, kPublishedLength)) {
		self.currentArticle.datePublished = self.currentDate;
	}

	else if (RSSAXEqualTags(localName, kUpdated, kUpdatedLength)) {
		self.currentArticle.dateModified = self.currentDate;
	}

	// Atom 0.3 dates
	else if (RSSAXEqualTags(localName, kIssued, kIssuedLength)) {
		if (!self.currentArticle.datePublished) {
			self.currentArticle.datePublished = self.currentDate;
		}
	}
	else if (RSSAXEqualTags(localName, kModified, kModifiedLength)) {
		if (!self.currentArticle.dateModified) {
			self.currentArticle.dateModified = self.currentDate;
		}
	}
	// Non-standard pub_date element used by some feed generators
	else if (RSSAXEqualTags(localName, kPubDate, kPubDateLength)) {
		if (!self.currentArticle.datePublished) {
			self.currentArticle.datePublished = self.currentDate;
		}
	}
	else if (RSSAXEqualTags(localName, kMp3URL, kMp3URLLength)) {
		NSString *mp3URLString = [self currentString];
		if (!RSParserStringIsEmpty(mp3URLString)) {
			self.currentArticle.mp3URL = mp3URLString;
		}
	}
	else if (RSSAXEqualTags(localName, kURLJSON, kURLJSONLength)) {
		[self addJSONContentURL];
	}
}


- (void)addXHTMLTag:(const xmlChar *)localName {

	if (!localName) {
		return;
	}

	[self.xhtmlString appendString:@"<"];
	[self.xhtmlString appendString:[NSString stringWithUTF8String:(const char *)localName]];

	if (self.currentAttributes.count < 1) {
		[self.xhtmlString appendString:@">"];
		return;
	}

	for (NSString *oneKey in self.currentAttributes) {

		[self.xhtmlString appendString:@" "];

		NSString *oneValue = self.currentAttributes[oneKey];
		[self.xhtmlString appendString:oneKey];

		[self.xhtmlString appendString:@"=\""];

		oneValue = [oneValue stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
		[self.xhtmlString appendString:oneValue];

		[self.xhtmlString appendString:@"\""];
	}

	[self.xhtmlString appendString:@">"];
}


#pragma mark - RSSAXParserDelegate

- (void)saxParser:(RSSAXParser *)SAXParser XMLStartElement:(const xmlChar *)localName prefix:(const xmlChar *)prefix uri:(const xmlChar *)uri numberOfNamespaces:(NSInteger)numberOfNamespaces namespaces:(const xmlChar **)namespaces numberOfAttributes:(NSInteger)numberOfAttributes numberDefaulted:(int)numberDefaulted attributes:(const xmlChar **)attributes {

	if (self.endFeedFound) {
		return;
	}

	NSDictionary *xmlAttributes = [self.parser attributesDictionary:attributes numberOfAttributes:numberOfAttributes];
	if (!xmlAttributes) {
		xmlAttributes = [NSDictionary dictionary];
	}
	[self.attributesStack addObject:xmlAttributes];

	if (self.parsingXHTML) {
		[self addXHTMLTag:localName];
		return;
	}

	if (RSSAXEqualTags(localName, kEntry, kEntryLength)) {
		self.parsingArticle = YES;
		[self addArticle];
		return;
	}

	if (RSSAXEqualTags(localName, kAuthor, kAuthorLength)) {
		self.parsingAuthor = YES;
		self.currentAuthor = [[RSParsedAuthor alloc] init];
		return;
	}

	if (RSSAXEqualTags(localName, kSource, kSourceLength)) {
		self.parsingSource = YES;
		return;
	}

	BOOL isContentTag = RSSAXEqualTags(localName, kContent, kContentLength);
	BOOL isSummaryTag = RSSAXEqualTags(localName, kSummary, kSummaryLength);
	if (self.parsingArticle && (isContentTag || isSummaryTag)) {

		if (isContentTag) {
			self.currentArticle.language = xmlAttributes[kXMLLangKey];
		}

		NSString *contentType = xmlAttributes[kTypeKey];
		if ([contentType isEqualToString:kXHTMLType]) {
			self.parsingXHTML = YES;
			self.xhtmlString = [NSMutableString stringWithString:@""];
			return;
		}
	}

	if (!self.parsingArticle && RSSAXEqualTags(localName, kLink, kLinkLength)) {
		[self addHomePageLink];
		// Don't return — fall through to beginStoringCharacters so that
		// <link>text</link> content is captured for the end-element handler.
	}

	if (RSSAXEqualTags(localName, kFeed, kFeedLength)) {
		[self addFeedLanguage];
	}

	[self.parser beginStoringCharacters];
}


- (void)saxParser:(RSSAXParser *)SAXParser XMLEndElement:(const xmlChar *)localName prefix:(const xmlChar *)prefix uri:(const xmlChar *)uri {

	if (RSSAXEqualTags(localName, kFeed, kFeedLength)) {
		self.endFeedFound = YES;
		return;
	}

	if (self.endFeedFound) {
		return;
	}

	if (self.parsingXHTML) {

		BOOL isContentTag = RSSAXEqualTags(localName, kContent, kContentLength);
		BOOL isSummaryTag = RSSAXEqualTags(localName, kSummary, kSummaryLength);

		if (self.parsingArticle && (isContentTag || isSummaryTag)) {

			if (isContentTag) {
				self.currentArticle.body = [self.xhtmlString copy];
			}

			else if (isSummaryTag) {
				if (self.currentArticle.body.length < 1) {
					self.currentArticle.body = [self.xhtmlString copy];
				}
			}
		}

		if (isContentTag || isSummaryTag) {
			self.parsingXHTML = NO;
		}

		[self.xhtmlString appendString:@"</"];
		[self.xhtmlString appendString:[NSString stringWithUTF8String:(const char *)localName]];
		[self.xhtmlString appendString:@">"];
	}

	else if (self.parsingAuthor) {

		if (RSSAXEqualTags(localName, kAuthor, kAuthorLength)) {
			self.parsingAuthor = NO;
			RSParsedAuthor *author = self.currentAuthor;
			if (self.parsingArticle) {
				if (!author.isEmpty) {
					[self.currentArticle addAuthor:author];
				}
			}
			else {
				if (!self.rootAuthor && !author.isEmpty) {
					self.rootAuthor = author;
				}
			}
			self.currentAuthor = nil;
		}
		else if (RSSAXEqualTags(localName, kName, kNameLength)) {
			self.currentAuthor.name = [self currentString];
		}
		else if (RSSAXEqualTags(localName, kEmail, kEmailLength)) {
			self.currentAuthor.emailAddress = [self currentString];
		}
		else if (RSSAXEqualTags(localName, kURI, kURILength)) {
			self.currentAuthor.url = [self currentString];
		}
	}

	else if (RSSAXEqualTags(localName, kEntry, kEntryLength)) {
		self.parsingArticle = NO;
	}

	else if (self.parsingArticle && !self.parsingSource) {
		[self addArticleElement:localName prefix:prefix];
	}
	
	else if (RSSAXEqualTags(localName, kSource, kSourceLength)) {
		self.parsingSource = NO;
	}

	else if (!self.parsingArticle && !self.parsingSource && RSSAXEqualTags(localName, kTitle, kTitleLength)) {
		[self addFeedTitle];
	}

	else if (!self.parsingArticle && !self.parsingSource && RSSAXEqualTags(localName, kImageRef, kImageRefLength)) {
		NSString *imageRef = [self currentString];
		if (!RSParserStringIsEmpty(imageRef)) {
			self.iconURLString = imageRef;
		}
	}

	else if (!self.parsingArticle && !self.parsingSource && RSSAXEqualTags(localName, kLink, kLinkLength)) {
		// Handle <link>text</link> (text content) in addition to <link href="..." /> (attribute)
		NSString *linkText = [self currentString];
		if (!RSParserStringIsEmpty(linkText) && RSParserStringIsEmpty(self.currentAttributes[kHrefKey])) {
			// Some podcast Atom feeds provide only text content in <link> at feed scope.
			NSString *resolvedLinkText = [self resolvedURLString:linkText];
			if (!RSParserStringIsEmpty(resolvedLinkText)) {
				self.homepageURLString = resolvedLinkText;
			}
		}
	}

	[self.attributesStack removeLastObject];
}


- (NSString *)saxParser:(RSSAXParser *)SAXParser internedStringForName:(const xmlChar *)name prefix:(const xmlChar *)prefix {

	if (prefix && RSSAXEqualTags(prefix, kXML, kXMLLength)) {

		if (RSSAXEqualTags(name, kBase, kBaseLength)) {
			return kXMLBaseKey;
		}
		if (RSSAXEqualTags(name, kLang, kLangLength)) {
			return kXMLLangKey;
		}
	}

	if (prefix) {
		return nil;
	}

	if (RSSAXEqualTags(name, kRel, kRelLength)) {
		return kRelKey;
	}

	if (RSSAXEqualTags(name, kType, kTypeLength)) {
		return kTypeKey;
	}

	if (RSSAXEqualTags(name, kHref, kHrefLength)) {
		return kHrefKey;
	}

	if (RSSAXEqualTags(name, kAlternate, kAlternateLength)) {
		return kAlternateValue;
	}

	if (RSSAXEqualTags(name, kLength, kLengthLength)) {
		return kLengthKey;
	}

	if (RSSAXEqualTags(name, kTitle, kTitleLength)) {
		return kTitleKey;
	}

	return nil;
}


static BOOL equalBytes(const void *bytes1, const void *bytes2, NSUInteger length) {

	return memcmp(bytes1, bytes2, length) == 0;
}


- (NSString *)saxParser:(RSSAXParser *)SAXParser internedStringForValue:(const void *)bytes length:(NSUInteger)length {

	static const NSUInteger alternateLength = kAlternateLength - 1;
	static const NSUInteger textHTMLLength = kTextHTMLLength - 1;
	static const NSUInteger relatedLength = kRelatedLength - 1;
	static const NSUInteger shortURLLength = kShortURLLength - 1;
	static const NSUInteger htmlLength = kHTMLLength - 1;
	static const NSUInteger enLength = kEnLength - 1;
	static const NSUInteger textLength = kTextLength - 1;
	static const NSUInteger selfLength = kSelfLength - 1;
	static const NSUInteger enclosureLength = kEnclosureLength - 1;

	if (length == alternateLength && equalBytes(bytes, kAlternate, alternateLength)) {
		return kAlternateValue;
	}

	if (length == enclosureLength && equalBytes(bytes, kEnclosure, enclosureLength)) {
		return kEnclosureValue;
	}

	if (length == textHTMLLength && equalBytes(bytes, kTextHTML, textHTMLLength)) {
		return kTextHTMLValue;
	}

	if (length == relatedLength && equalBytes(bytes, kRelated, relatedLength)) {
		return kRelatedValue;
	}

	if (length == shortURLLength && equalBytes(bytes, kShortURL, shortURLLength)) {
		return kShortURLValue;
	}

	if (length == htmlLength && equalBytes(bytes, kHTML, htmlLength)) {
		return kHTMLValue;
	}

	if (length == enLength && equalBytes(bytes, kEn, enLength)) {
		return kEnValue;
	}

	if (length == textLength && equalBytes(bytes, kText, textLength)) {
		return kTextValue;
	}

	if (length == selfLength && equalBytes(bytes, kSelf, selfLength)) {
		return kSelfValue;
	}

	return nil;
}


- (void)saxParser:(RSSAXParser *)SAXParser XMLCharactersFound:(const unsigned char *)characters length:(NSUInteger)length {

	if (self.parsingXHTML) {
		NSString *s = [[NSString alloc] initWithBytesNoCopy:(void *)characters length:length encoding:NSUTF8StringEncoding freeWhenDone:NO];
		if (s == nil) {
			return;
		}
		// libxml decodes all entities; we need to re-encode certain characters
		// (<, >, and &) when inside XHTML text content.
		[self.xhtmlString appendString:s.rsparser_stringByEncodingRequiredEntities];
	}
}

@end
