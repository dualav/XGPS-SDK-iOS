//
//  Puck160.h
//  SkyPro for XGPS160
//
//  Created by jk on 20181804.
//  Copyright © 2018 namsung. All rights reserved.
//


#ifndef Puck160_h
#define Puck160_h

#include "Puck.h"







@interface Puck (XGPS160)


-(void) decodeLogBulk;

-(void) deleteAllLog;


-(void) handle160getSettingsRsp :(uint8_t*)Pkt :(uint8_t)PktLen;
-(void) handle160fwDataRsp :(uint8_t*)Pkt :(uint8_t)PktLen;

-(void) handle160LogList :(uint8_t*)Pkt :(uint8_t)PktLen;
-(void) handle160LogBlock :(uint8_t*)Pkt :(uint8_t)PktLen;
-(void) handle160LogDelRsp :(uint8_t*)Pkt :(uint8_t)PktLen;



//-(BOOL) update160command:(int) cmd :(BYTE*) buf :(UINT) bufLen;



@end

#endif /* Puck160_h */
