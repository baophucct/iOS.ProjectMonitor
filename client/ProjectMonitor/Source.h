//
//  BuildSource.h
//  ProjectMonitor
//
//  Created by Dimitri Roche on 2/8/14.
//  Copyright (c) 2014 Dimitri Roche. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BuildFactory.h"

@protocol Source <NSObject>

@property (nonatomic, strong) BuildFactory *buildFactory;

@end