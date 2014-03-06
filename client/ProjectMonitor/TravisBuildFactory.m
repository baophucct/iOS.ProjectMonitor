//
//  TravisBuild.m
//  ProjectMonitor
//
//  Created by Dimitri Roche on 3/5/14.
//  Copyright (c) 2014 Dimitri Roche. All rights reserved.
//

#import "TravisBuildFactory.h"
#import "Build.h"
#import "Helper.h"

@implementation TravisBuildFactory : BuildFactory

- (void)fetchWithSuccess:(FetchBuildCallback)success failure:(void (^)(NSError *)) failure
{
    NSString *URLString = @"https://api.travis-ci.com/repos";
    NSDictionary *parameters = @{@"access_token": [self token]};
    
    NSLog(@"# Fetching travis builds with access token: %@", [self token]);

    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    [manager GET:URLString parameters:parameters success:
     ^(AFHTTPRequestOperation *operation, id responseObject) {
        [self handleResponseWith:responseObject andRespondWith:success];
    } failure: ^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"# Error: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(error);
        });
    }];
}

- (void)handleResponseWith:(id)responseObject andRespondWith:(FetchBuildCallback)callback
{
    NSArray *travisBuilds = [self arrayFromResponse:responseObject];
    NSArray* array = [self removeExistingBuilds:travisBuilds];
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(array);
    });
}

- (NSArray *)arrayFromResponse:(NSArray *)response
{
    NSArray* builds = _.arrayMap(response, ^Build* (NSDictionary *entry) {
        return [self fromDictionary:entry];
    });
    
    return builds;
}

- (Build *)fromDictionary:(NSDictionary *)input
{
    NSMutableDictionary *dic = [NSMutableDictionary dictionary];
    
    [dic setValue:@"TravisBuild" forKey:@"type"];
    [dic setValue:input[@"slug"] forKey:@"project"];
    
    [dic setValue:[self statusFromResult:[input[@"last_build_result"] intValue]] forKey:@"status"];
    
    [dic setValue:[self token] forKey:@"accessToken"];
    [dic setValue:[self generateUrlWithProject:input[@"slug"]] forKey:@"url"];
    
    [dic setValue:[Helper parseDateSafelyFromDictionary:input withKey:@"last_build_started_at"] forKey:@"startedAt"];
    [dic setValue:[Helper parseDateSafelyFromDictionary:input withKey:@"last_build_finished_at"] forKey:@"finishedAt"];
    
    Build *build = [Build MR_createEntity];
    [build setFromDictionary: dic];
    return build;
}

- (NSString *)generateUrlWithProject:(NSString*) project
{
    return [NSString stringWithFormat:@"https://api.travis-ci.com/repos/%@/builds?access_token=%@", project, [self token]];
}

- (NSString *)statusFromResult:(NSInteger)result
{
    switch (result) {
        case 0:
            return @"passed";
        case 1:
            return @"failed";
        case 2:
            return @"pending";
        default:
            NSLog(@"Unexpectedly received travis result %ld", (long)result);
            return @"undetermined";
    }
}

@end
