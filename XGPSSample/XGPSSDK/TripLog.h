//
//  TripLog.h
//  SkyPro for XGPS160
//
//  Created by hjlee on 2018. 3. 20..
//  Copyright © 2018년 namsung. All rights reserved.
//

@protocol TripLogDelegate <NSObject>
@optional
- (void)logListComplete;
- (void)logBulkProgress:(unsigned long)progress;
- (void)logBulkComplete:(NSData *)data;
- (void)getUsedSpace:(float)usedSize;
@end
