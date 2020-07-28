//
//  MemberShipCommonValue.m
//  SWallet
//
//  Created by SeokJae Lee on 12. 8. 9..
//  Copyright (c) 2012년 __MyCompanyName__. All rights reserved.
//

#import "CommonValue.h"

@implementation CommonValue

@synthesize formatSpeed;
@synthesize formatAltitude;
@synthesize formatPosition;
@synthesize didSelectLogList;
@synthesize didSelectLogListBulkData;
@synthesize logBulkByteCnt, isLogDetailIndex;

static CommonValue * _commonValue = nil ;

+(CommonValue*) sharedSingleton{
    
    @synchronized([CommonValue class])
    {
        if(!_commonValue) {
            [[self alloc] init];
        }
        return _commonValue;
    }
    return nil;
}


+(id)alloc{
    
    @synchronized([CommonValue class])
    {
        NSAssert(_commonValue == nil, @"Singleton");
        _commonValue = [super alloc];
        return _commonValue;
    }
    return nil;
}


-(id)init{

    self.isLogDetailIndex = 0;
    self.logBulkByteCnt = 0;
    self.didSelectLogListBulkData = [[NSMutableDictionary alloc]init];
    self.didSelectLogList = [[NSMutableArray alloc]init];
    return [super init];
}


@end
