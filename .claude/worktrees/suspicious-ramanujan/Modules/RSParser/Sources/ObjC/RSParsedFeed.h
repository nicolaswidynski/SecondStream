//
//  RSParsedFeed.h
//  RSParser
//
//  Created by Brent Simmons on 7/12/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

@import Foundation;

@class RSParsedArticle;

@interface RSParsedFeed : NSObject

- (nonnull instancetype)initWithURLString:(NSString * _Nonnull)urlString title:(NSString * _Nullable)title homepageURLString:(NSString * _Nullable)homepageURLString language:(NSString * _Nullable)language articles:(NSArray <RSParsedArticle *>* _Nonnull)articles iconURLString:(NSString * _Nullable)iconURLString feedURLString:(NSString * _Nullable)feedURLString;

@property (nonatomic, readonly, nonnull) NSString *urlString;
@property (nonatomic, readonly, nullable) NSString *title;
@property (nonatomic, readonly, nullable) NSString *homepageURLString;
@property (nonatomic, readonly, nullable) NSString *language;
@property (nonatomic, readonly, nonnull) NSSet <RSParsedArticle *>*articles;
@property (nonatomic, readonly, nullable) NSString *iconURLString;
@property (nonatomic, readonly, nullable) NSString *feedURLString;

@end
