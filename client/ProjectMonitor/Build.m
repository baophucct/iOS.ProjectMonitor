//
//  Build.m
//  ProjectMonitor
//
//  Created by Dimitri Roche on 2/14/14.
//  Copyright (c) 2014 Dimitri Roche. All rights reserved.
//

#import "Build.h"
#import "ParseHelper.h"
#import "Helper.h"

@implementation Build

@dynamic project;
@dynamic branch;
@dynamic type;
@dynamic url;
@dynamic startedAt;
@dynamic finishedAt;
@dynamic updatedAt;
@dynamic status;
@dynamic objectId;
@dynamic isInvalid;
@dynamic invalidMessage;

@dynamic commitSha;
@dynamic commitAuthor;
@dynamic commitEmail;
@dynamic commitMessage;

// [Name of associated class] + [Did | Will] + [UniquePartOfName] + Notification
NSString * const PMBuildDidSaveNotication = @"PMBuildDidSaveNotication";
NSString * const PMBuildDidBecomeSelected = @"PMBuildDidBecomeSelected";
NSString * const PMBuildsDidBecomeActiveNotication = @"PMBuildsDidBecomeActiveNotication";
NSString * const sortString = @"type,project,branch";

// Thread safe: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html
static NSArray* whitelistedKeys;

+ (void)initialize
{
    static BOOL initialized = NO;
    if(!initialized)
    {
        initialized = YES;
        whitelistedKeys = [NSArray arrayWithObjects:
                           @"type", @"project", @"branch", @"status", @"url",
                           @"startedAt", @"finishedAt", @"commitSha", @"commitMessage",
                           @"commitAuthor", @"commitEmail", @"accessToken",
                           @"isInvalid", @"invalidMessage",
                           nil];
    }
}

+ (NSArray *)all
{
    return [Build MR_findAllSortedBy:sortString ascending:YES];
}

+ (NSArray *)forType:(NSString*)type
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"type = %@ AND NOT objectId = nil",type];

    return [Build MR_findAllSortedBy:sortString ascending:YES withPredicate:predicate];
}

+ (NSArray *)saved
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT objectId = nil"];
    return [Build MR_findAllSortedBy:sortString ascending:YES withPredicate:predicate];
}

+ (NSArray *)allInContext:(NSManagedObjectContext *)context
{
    return [Build MR_findAllSortedBy:sortString ascending:YES inContext:context];
}

+ (void)refreshSavedBuildsInBackground:(void (^)(BOOL, NSArray *))callback
{
    // Retrieve from parse
    PFQuery *query = [PFQuery queryWithClassName:@"Build"];
    [query orderByAscending:sortString];
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        if (!error) {
            __block NSArray *refreshedBuilds;
            // Save in Core Data
            [MagicalRecord saveUsingCurrentThreadContextWithBlockAndWait:^(NSManagedObjectContext *localContext) {
                [Build MR_truncateAllInContext:localContext];
                [self createBuilds:objects InContext:localContext];
                refreshedBuilds = [Build allInContext:localContext];
            }];
            
            // invoke callback with new builds
            callback(YES, refreshedBuilds);
        } else {
            NSLog(@"# Failed to refresh saved builds\n%@", error);
            callback(NO, nil);
        }
    }];
}

+ (void)createBuilds:(NSArray*)parseBuilds InContext:(NSManagedObjectContext *)localContext {
    for (PFObject *parseBuild in parseBuilds) {
        Build *build = [Build MR_createInContext:localContext];
        [build setFromDictionary: [ParseHelper toDictionary: parseBuild]];
        [build setObjectId: parseBuild.objectId];
        [build setUpdatedAt: parseBuild.updatedAt];
    }
}

+ (void)updateSavedBuild:(NSDictionary *)dictionary
{
    [MagicalRecord saveWithBlockAndWait:^(NSManagedObjectContext *localContext) {
        Build* build;
        NSString *objectId = [dictionary objectForKey:@"objectId"];
        
        build = [Build MR_findFirstByAttribute:@"objectId" withValue:objectId inContext:localContext];
        if (!build) {
            build = [Build MR_createInContext:localContext];
        }
        
        [build setFromDictionary:dictionary];
    }];
}

+ (void)saveInBackground:(NSArray *)builds withBlock:(void (^)(BOOL))mainThreadCallback
{
    NSArray *parseObjects = _.arrayMap(builds, ^PFObject *(Build*build) {
        return [self generateParseObject:build];
    });
    
    [PFObject saveAllInBackground:parseObjects block:^(BOOL succeeded, NSError *error) {
        if (succeeded) {
            [MagicalRecord saveWithBlockAndWait:^(NSManagedObjectContext *localContext) {
                NSLog(@"# Writing added builds to Core Data!");
                [self createBuilds:parseObjects InContext:localContext];
            }];
            
            [self notifyBuildsSaved];
        } else {
            NSLog(@"Failed to save parse objects:\n%@", [error description]);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            mainThreadCallback(succeeded);
        });
    }];
}


+ (id)valueOrNSNull:(id)value
{
    if (value) {
        return value;
    } else {
        return [NSNull null];
    }
}

- (id)valueOrNil:(id)value
{
    if ([Helper isAnyNull:value]) {
        return nil;
    } else if ([value respondsToSelector:@selector(objectForKey:)]) {
        return [Helper parseDateSafelyFromDictionary:value withKey:@"iso"];
    } else {
        return value;
    }
}

+ (PFObject *)generateParseObject:(Build*) build
{
    PFObject *buildObject = [PFObject objectWithClassName:@"Build"];
    for (NSString* key in whitelistedKeys) {
        buildObject[key] = [self valueOrNSNull: [build valueForKey:key]];
    }
    
    buildObject[@"user"] = [PFUser currentUser];
    buildObject.ACL = [PFACL ACLWithUser:[PFUser currentUser]];
    return buildObject;
}

- (NSString *)description
{
    return [NSString stringWithFormat: @"Build: ObjectId=%@ Project=%@ Branch=%@ Status=%@ Url=%@", self.objectId, self.project, self.branch, self.status, self.url];
}

- (BOOL)isSimilarTo:(Build *)build
{
    return [[self project] isEqualToString:[build project]] &&
        [[self type] isEqualToString: [build type]];
}

- (void)setFromDictionary:(NSDictionary*)dic
{
    for (NSString* key in whitelistedKeys) {
        id someVal = [self valueOrNil:dic[key]];
        [self setValue:someVal forKey:key];
    }
    
    if ([dic objectForKey:@"objectId"]) {
        [self setObjectId:[dic objectForKey:@"objectId"]];
    }
}

+ (void)notifyBuildsSaved
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:PMBuildDidSaveNotication object:nil];
}

- (void)deleteInBackground
{
    PFObject *object = [PFObject objectWithoutDataWithClassName:@"Build" objectId:[self objectId]];
    [object deleteInBackground];
    [self MR_deleteEntity];
}

@end