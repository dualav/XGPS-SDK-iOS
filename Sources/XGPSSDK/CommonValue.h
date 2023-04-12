//
//  MemberShipCommonValue.h
//  SWallet
//
//  Created by SeokJae Lee on 12. 8. 9..
//  Copyright (c) 2012년 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

// UI settings are manipulated with this object
// Device settings will stay in Puck class
@interface CommonValue : NSObject

@property(nonatomic, assign) int  formatSpeed;        // 0=knots, 1=mph, 2=kph
@property(nonatomic, assign) int  formatAltitude;     // 0=feet, 1=meter
@property(nonatomic, assign) int  formatPosition;     // 0=Deg.Min.Sec, 1=Deg,Min.Fraction, 2=Deg.Fraction

@property(nonatomic, retain) NSMutableArray * didSelectLogList;
@property(nonatomic, retain) NSMutableDictionary * didSelectLogListBulkData;

//  상세 클릭할때
@property(nonatomic, assign) int isLogDetailIndex;
@property(nonatomic, assign) unsigned long logBulkByteCnt;


+(CommonValue*)sharedSingleton;


@end
