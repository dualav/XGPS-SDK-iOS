//
//  Puck500.h
//  SkyPro for XGPS160
//
//  Created by jk on 20181804.
//  Copyright © 2018 namsung. All rights reserved.
//

#ifndef Puck500_h
#define Puck500_h





@interface Puck (XGPS500)

-(void) handle500getSettingsRsp :(uint8_t*)Pkt :(uint8_t)PktLen;
-(void) handle500LogList : (uint8_t*)Pkt : (uint8_t)PktLen;
-(void) handle500LogDump : (uint8_t*)Pkt : (uint8_t)PktLen;
-(void) handle500FreeSpace : (uint8_t*)Pkt : (uint8_t)PktLen;
-(void) handle500DeleteLog: (uint8_t*)Pkt : (uint8_t)PktLen;

@end

#endif /* Puck500_h */
