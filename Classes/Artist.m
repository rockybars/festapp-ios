//
//  Gig.m
//  FestApp
//

#import "Artist.h"
#import "NSDate+Additions.h"
#import <CoreLocation/CoreLocation.h>

#import "AFNetworking.h"
#import "FestHTTPSessionManager.h"

@interface Artist () {
    BOOL loadingImage;
}

@end

@implementation Artist

@dynamic image;
@dynamic isLoadingArtistImage;
@dynamic hasLoadedArtistImage;
@dynamic timeIntervalString;
@dynamic stageAndTimeIntervalString;
@dynamic duration;
@dynamic favorite;

NSInteger alphabeticalGigSort(id gig1, id gig2, void *context)
{
    NSString *artist1 = [(Artist *) gig1 artistName];
    NSString *artist2 = [(Artist *) gig2 artistName];
    return [artist1 compare:artist2 options:NSCaseInsensitiveSearch];
}

NSInteger chronologicalGigSort(id gig1, id gig2, void *context)
{
    NSDate *begin1 = [(Artist *) gig1 begin];
    NSDate *begin2 = [(Artist *) gig2 begin];
    return [begin1 compare:begin2];
}

+ (NSArray *)gigsFromArrayOfDicts:(NSArray *)dicts
{
	NSMutableArray *gigs = [NSMutableArray arrayWithCapacity:[dicts count]];

    NSUInteger gigCount = [dicts count];
    NSLog(@"parsing %d gigs", gigCount);

	for (NSUInteger i = 0; i < gigCount; i++) {

        NSDictionary *dict = dicts[i];

		Artist *gig            = [[Artist alloc] init];
		gig.artistId        = [NSString cast:dict[@"id"]];
		gig.artistName      = [NSString cast:dict[@"nimi"]];
		gig.venue           = [[NSString cast:dict[@"lava"]] capitalizedString];
        gig.description     = [NSString cast:dict[@"kohokohtia"]];
        gig.day             = [[NSString cast:dict[@"paiva"]] capitalizedString];

        NSString *spotifyUrlStr = [NSString cast:dict[@"spotify"]];
        if([spotifyUrlStr length] != 0) {
            gig.spotifyUrl = [NSURL URLWithString:spotifyUrlStr];
        }
        
        NSString *youtubeUrlStr = [NSString cast:dict[@"youtube"]];
        if([youtubeUrlStr length] != 0) {
            gig.youtubeUrl = [NSURL URLWithString:youtubeUrlStr];
        }

        NSString *imagePath = [NSString cast:dict[@"kuva"]];
        if (imagePath) {
            gig.imagePath = imagePath;
            gig.imageURL = [NSURL URLWithString:[NSString stringWithFormat:kResourceImageURLFormat, imagePath]];
        }

        NSScanner *scanner = [NSScanner scannerWithString:gig.artistName];
        NSString *text = nil;

        while ([scanner isAtEnd] == NO) {
            [scanner scanUpToString:@"(" intoString:NULL];
            [scanner scanUpToString:@")" intoString:&text];

            if (text != nil) {
                gig.country = [text substringFromIndex:1];  // omit the (
                gig.artistName = [gig.artistName stringByReplacingOccurrencesOfString:gig.country withString:gig.country.uppercaseString];
            }
        }

        NSTimeInterval begin = [dict[@"aika"] doubleValue];
        NSTimeInterval end   = [dict[@"aika_stop"] doubleValue];

        if (begin > 0 && end > 0 && gig.venue != nil && ![gig.venue isEqual:[NSNull null]]) {

            gig.begin = [NSDate dateWithTimeIntervalSince1970:begin];
            gig.end = [NSDate dateWithTimeIntervalSince1970:end];

            // Taking into account the magical year 2103 summer gig:
            if ([gig.end timeIntervalSinceDate:gig.begin] > 24 * kOneHour) {
                gig.end = [gig.begin dateByAddingTimeInterval:(2 * kOneHour)];
            }

           // NSLog(@"%@ %@ - %@", gig.artistName, gig.begin, gig.end);

            NSTimeInterval timeInterval = floor(-kOneHour*[gig.begin hourValueWithDayDelimiterHour:6]);
            if (((int)timeInterval)%10 != 0) {
                timeInterval -= ((int)timeInterval)%10;
            }
            gig.date = [gig.begin dateByAddingTimeInterval:timeInterval];
            // NSLog(@"%f %@", timeInterval, gig.artistName);

            NSString *favoriteKey = [NSString stringWithFormat:@"isFavorite_%@", gig.artistId];
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            gig.favorite = [defaults boolForKey:favoriteKey];

            for (Artist *existingGig in gigs) {

                if ([existingGig.artistName isEqualToString:gig.artistName]) {

                    if (existingGig.alternativeGigs == nil) {
                        existingGig.alternativeGigs = [NSMutableArray array];
                    }
                    [existingGig.alternativeGigs addObject:gig];

                    if (gig.alternativeGigs == nil) {
                        gig.alternativeGigs = [NSMutableArray array];
                    }
                    [gig.alternativeGigs addObject:existingGig];
                }
            }

            [gigs addObject:gig];
        }
	}
	return gigs;
}

- (BOOL)isFavorite
{
    return favorite;
}

- (void)setFavorite:(BOOL)isFavorite
{
    favorite = isFavorite;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *favoriteKey = [NSString stringWithFormat:@"isFavorite_%@", self.artistId];

    if (favorite != [defaults boolForKey:favoriteKey]) {

        if (favorite) {

            if ([self.begin after:[NSDate date]]) {

                NSString *alertText = [NSString stringWithFormat:@"%@\n%@-%@ (%@)", self.artistName, [self.begin hourAndMinuteString], [self.end hourAndMinuteString], self.venue];

                UILocalNotification *localNotif = [[UILocalNotification alloc] init];
                if (localNotif == nil) return;
                localNotif.fireDate = [self.begin dateByAddingTimeInterval:-kAlertIntervalInMinutes*kOneMinute];
                localNotif.alertBody = alertText;
                localNotif.soundName = @"Riff2.aif";
                [[UIApplication sharedApplication] scheduleLocalNotification:localNotif];

                NSLog(@"added alert: %@", alertText);
            }

        } else {

            UILocalNotification *notificationToCancel = nil;
            for (UILocalNotification *aNotif in [[UIApplication sharedApplication] scheduledLocalNotifications]) {
                if([aNotif.alertBody rangeOfString:self.artistName].location == 0) {
                    notificationToCancel = aNotif;
                    break;
                }
            }
            if (notificationToCancel != nil) {
                NSLog(@"removed alert: %@", notificationToCancel.alertBody);
                [[UIApplication sharedApplication] cancelLocalNotification:notificationToCancel];
            }
        }

        [defaults setBool:favorite forKey:favoriteKey];
        [defaults synchronize];
    }
}

- (BOOL)isLoadingArtistImage
{
    return loadingImage;
}

- (BOOL)hasLoadedArtistImage
{
    NSString *path;
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	path = [paths[0] stringByAppendingPathComponent:@"ArtistImages"];
    NSString *imageName = [NSString stringWithFormat:@"artistimg_%@.jpg", self.artistId];
    path = [path stringByAppendingPathComponent:imageName];

    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (UIImage *)image
{
    NSString *path;
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	path = [paths[0] stringByAppendingPathComponent:@"ArtistImages"];
	NSError *fileError;
    NSFileManager *fileManager = [NSFileManager defaultManager];
	if (![fileManager fileExistsAtPath:path]) {
		if (![fileManager createDirectoryAtPath:path
                    withIntermediateDirectories:NO
                                     attributes:nil
                                          error:&fileError]) {
			NSLog(@"Create directory error: %@", fileError);
		}
	}

    NSString *imageName = [NSString stringWithFormat:@"artistimg_%@.jpg", self.artistId];
    path = [path stringByAppendingPathComponent:imageName];

    if (![fileManager fileExistsAtPath:path] && !loadingImage) {
        CLLocationDistance distance = [[NSUserDefaults standardUserDefaults] doubleForKey:kDistanceFromFestKey];
        BOOL isWifi = [[AFNetworkReachabilityManager sharedManager] isReachableViaWiFi];
        if (distance > 0 && distance < 1000 && isWifi) {
            // Okay, we're in the area, let's not load the images now.
            return nil;
        }

        NSLog(@"loading %@", self.imageURL);

        FestHTTPSessionManager *httpManager = [FestHTTPSessionManager sharedFestHTTPSessionManager];

        NSURLRequest *request = [NSURLRequest requestWithURL:self.imageURL];

        AFHTTPRequestOperation *requestOperation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
        requestOperation.outputStream = [NSOutputStream outputStreamToFileAtPath:path append:NO];
        [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            NSLog(@"Loaded image: %@", self.imageURL);

            loadingImage = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationForLoadedArtistImage object:self];

            NSURL *URL = [NSURL fileURLWithPath:path];
            NSError *error = nil;
            [URL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error];
            if (error) {
                NSLog(@"error excluding from backup: %@", error);
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Image error: %@", error);
            loadingImage = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationForFailedLoadingArtistImage object:self];
        }];

        [httpManager.operationQueue addOperation:requestOperation];

        NSLog(@"loading %@ to %@", self.imageURL, path);

        return nil;

    } else {

        return [UIImage imageWithContentsOfFile:path];
    }
}

- (NSString *)timeIntervalString
{
    if ([self.begin timeIntervalSinceNow] > 18*kOneHour) {
        return [NSString stringWithFormat:@"%@ %@–%@", self.begin.weekdayName, self.begin.hourAndMinuteString, self.end.hourAndMinuteString];
    } else {
        // no need to display weekday name as a part of a current-day gig:
        return [NSString stringWithFormat:@"%@–%@", self.begin.hourAndMinuteString, self.end.hourAndMinuteString];
    }
}

- (NSString *)stageAndTimeIntervalString
{
    return [NSString stringWithFormat:@"%@ %@–%@ %@", self.begin.weekdayName, self.begin.hourAndMinuteString, self.end.hourAndMinuteString, self.venue];
}

- (NSTimeInterval)duration
{
	return [self.end timeIntervalSinceDate:self.begin];
}

- (NSComparisonResult)compare:(Artist *)otherGig
{
    return [self.begin compare:otherGig.begin];
}

@end
