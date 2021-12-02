//
//  Puck500.m
//  SkyPro for XGPS160
//
//  Created by jk on 20181804.
//  Copyright © 2018 namsung. All rights reserved.
//

#import "Puck.h"
#import "Puck+XGPS500.h"
#import "ntripclient.h"     // defines extern variable: 'stop'

@implementation Puck (XGPS500)

-(void) handle500getSettingsRsp :(uint8_t*)Pkt :(uint8_t)PktLen
{
    if (( PktLen - 2) < sizeof(xgps500data_t)) {
        NSLog(@"handle500getSettingsRsp invalid length");
        return;
    }
    xgps500data_t *data = (xgps500data_t*) (&Pkt[2]);
    if (data->logOverWriteEnable) {
        self.logOverWriteEnabled = YES;
    }
    else {
        self.logOverWriteEnabled = NO;
    }
    
    if (data->GpsOptions & 0x40) {
        self.loggingEnabled = YES;
    }
    else {
        self.loggingEnabled = NO;
    }
    
    //[CommonValue sharedSingleton].streamMode = data->streamMode;
    self.xgps500_streamMode = data->streamMode;
    
    self.logType = data->logType;
    if (data->logInterval > 0)
        self.logInterval = data->logInterval;
    else
        self.logInterval = 1;
            
    self.gpsRefreshRate = data->GpsRefreshRateX10 / 10;
    
    NSLog(@"handle500getSettingsRsp size=%d, sizeof(xgps500data)=%lu", PktLen, sizeof(xgps500data_t));
}

-(void) handle500LogList : (uint8_t*)Pkt : (uint8_t)PktLen
{
    if (PktLen < sizeof(xgps_fileinfo_t)) {
        NSLog(@"handle500LogList %s, len : %d", (char*)Pkt, PktLen);
        if (self.tripLogDelegate != nil)
            [self.tripLogDelegate logListComplete];
        return;
    }
    xgps_fileinfo_t fileInfo;
    memcpy( (void*) &fileInfo, &Pkt[2], sizeof(xgps_fileinfo_t) );
    char *filename = (char *)(Pkt + sizeof(xgps_fileinfo_t));
//    NSLog(@"handle500LogList %s, len : %d, attr : %u, time : %u", filename, PktLen, fileInfo.filesize, fileInfo.filetime);
    
    NSString *fileNameString =  [NSString stringWithFormat:@"%s", filename];
    if ([fileNameString containsString:@".kml"] || [fileNameString containsString:@".bin"] || [fileNameString containsString:@".txt"]
        || [fileNameString containsString:@".gpx"] || [fileNameString containsString:@".ubx"]) {
        NSMutableDictionary * logDic = [[NSMutableDictionary alloc]init];
        
        [logDic setObject: [NSNumber numberWithLong: fileInfo.filesize] forKey:FILE_SIZE];
        [logDic setObject: [NSNumber numberWithLong: fileInfo.filetime] forKey:FILE_TIME];
        [logDic setObject: fileNameString forKey: TITLETEXT];
        
        [self.logListData addObject:logDic];
        
        logDic = nil;
    }
}

NSMutableData *logDumpData;

-(void) handle500LogDump : (uint8_t*)Pkt : (uint8_t)PktLen
{
    NSLog(@"handle500LogDump len : %d", PktLen);
    int rsize = 0;
    if( PktLen - 2 >= 4 ) {
        rsize = PktLen - 2 - 4 - 3;
    }
    else {
        rsize = 0;
    }
    if (rsize == 0) {
        if (self.tripLogDelegate != nil) {
            [self.tripLogDelegate logBulkComplete:logDumpData];
            logDumpData = nil;
            logBulkRecodeCnt = 0;
        }
    }
    else {
        if (logBulkRecodeCnt == 0) {
            logDumpData = [[NSMutableData alloc] init];
        }
        logBulkRecodeCnt += rsize;
        [logDumpData appendBytes:&Pkt[6] length:rsize];
        if (self.tripLogDelegate != nil) {
            [self.tripLogDelegate logBulkProgress:logBulkRecodeCnt];
        }
    }
}

-(void) handle500FreeSpace : (uint8_t*)Pkt : (uint8_t)PktLen
{
    if (PktLen < sizeof(xgps_storageinfo_t)) {
        return;
    }
    xgps_storageinfo_t storageInfo;
    memcpy( (void*) &storageInfo, &Pkt[2], sizeof(xgps_storageinfo_t) );
    
    float usedSize = 0;
    if (storageInfo.totalSize > 0)
        usedSize = (storageInfo.totalSize - storageInfo.availableSize) * 100 / storageInfo.totalSize;
    
    if (self.tripLogDelegate != nil) {
        [self.tripLogDelegate getUsedSpace:usedSize];
    }
}

-(void) handle500DeleteLog: (uint8_t*)Pkt : (uint8_t)PktLen
{
    [self.logListData removeAllObjects];
    [self sendCommandToDevice:cmd160_fileList :0 :NULL :0];
}

// MARK: for Ntrip callback functions
NSMutableString *mountListString = nil;
void ntripMountPoints (void *self, char *buffer, int buffLen)
{
    if (buffLen != 0 && mountListString != nil) {
        NSString *mountpoint = [NSString stringWithUTF8String:buffer];
        if (mountpoint != nil)
            [mountListString appendString:[NSString stringWithUTF8String:buffer]];
    }
    else if (buffLen == 0) {
//        NSLog(@"%@", mountListString);
        stop = 1;
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"STR;.+RTCM 2[.0-9]*;.+" options:NSRegularExpressionCaseInsensitive error:&error];
        if (error != nil || mountListString == nil) {
            NSLog(@"fail to find regex");
        }
        NSArray* matches = [regex matchesInString:mountListString options:0 range:NSMakeRange(0, [mountListString length])];
        if (matches == nil || [matches count] < 1) {
            NSLog(@"not found matched regex");
            return;
        }
        else {      // find shortest mount point
            CLLocationDistance shortestDistance = 100000;   // allow within 100km
            NSString *mountPoint = @"";

            for (NSTextCheckingResult *result in matches) {
                NSString* matchText = [mountListString substringWithRange:[result range]];
                NSArray *elements = [matchText componentsSeparatedByString:@";"];
                if ([elements count] < 11)
                    continue;
                float latitude = [[elements objectAtIndex:9] floatValue];
                float longitude = [[elements objectAtIndex:10] floatValue];
                float xgpsLatitude = [(__bridge id)self latitude];
                float xgpsLongitude = [(__bridge id)self longitude];
                CLLocation *startLocation = [[CLLocation alloc] initWithLatitude:xgpsLatitude longitude:xgpsLongitude];
                CLLocation *endLocation = [[CLLocation alloc] initWithLatitude:latitude longitude:longitude];
                CLLocationDistance distance = [startLocation distanceFromLocation:endLocation];
                if (distance <= shortestDistance && distance != 0) {
                    shortestDistance = distance;
                    mountPoint = [elements objectAtIndex:1];
//                    if (mountPoint != nil)
//                        [(__bridge id)self setMountPoint:mountPoint];
                }
                [(__bridge id)self addMountPoint:[elements objectAtIndex:1]];
            }
            if (mountPoint.length > 0) {
                [(__bridge id)self setMountPointName:mountPoint];
//                [(__bridge id)self startNtripNetwork:mountPoint];
            }
        }
    }
}

void ntripDataWrite (void *self, char *buffer, int buffLen, int error)
{
    // Call the Objective-C method using Objective-C syntax
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
                   ^{
                       NSLog(@"ntripDataWrite : %x, %d, %d", buffer[0], buffLen, error);
                       if (error == 0) {
                           [(__bridge id) self writeNtripData :(uint8_t*)buffer :buffLen];
                       }
                       else {
                           [(__bridge id) self alertErrorMessage :(uint8_t*)buffer :buffLen];
                       }
                   });
}

- (void)writeNtripData:(const uint8_t *)buf : (uint32_t) bufLen {
    [self getGGASentence];
    self.ntripReceived += (long)bufLen;
    [self writeBufferToStream:buf :bufLen];
}

- (void)alertErrorMessage:(const uint8_t *)buf :(uint32_t) bufLen {
//    [CommonUtil ShowAlertWithYes:@"TITLE" message:@"Message" delegate:self tag:0];
    self.ntripErrorMessage = [NSString stringWithUTF8String:(const char*)buf];
    NSLog(@"alertErrorMessage : %@", self.ntripErrorMessage);
}

- (void)getGGASentence {
    if (self.sentenceGGA == nil || self.sentenceGGA.length == 0)
        return;
    ggaSentence = (char *)[self.sentenceGGA UTF8String];
//    NSLog(@"getGGA : %s", ggaSentence);
    self.sentenceGGA = @"";
}

- (void)setMountPointName:(NSString *)mountName {
    self.mountPoint = mountName;
    bool isAutoMountPoint = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_AUTO_MOUNTPOINT];
    if (isAutoMountPoint) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self startNtripNetwork:mountName];
        });
    }
}

//- (void)setMountPoint:(NSString *)mountPoint
//{
//    self.mountPoint = mountPoint;
//}

- (void)addMountPoint:(NSString *)mountPoint
{
    [self.mountPointList addObject:mountPoint];
}

- (void)startNtripNetwork:(NSString *)mountPoint 
{
    NSLog(@"startNtripNetwork with %@", mountPoint);
    if (self.latitude == 0 && self.longitude == 0 && stop == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self startNtripNetwork:mountPoint];
        });
        return;
    }
    stop = 0;
    NSString *server = [[NSUserDefaults standardUserDefaults] stringForKey:KEY_SERVER];
    NSString *port = [[NSUserDefaults standardUserDefaults] stringForKey:KEY_PORT];
    NSString *user = [[NSUserDefaults standardUserDefaults] stringForKey:KEY_USER];
    NSString *password = [[NSUserDefaults standardUserDefaults] stringForKey:KEY_PASSWORD];
    NSInteger mode = [[NSUserDefaults standardUserDefaults] integerForKey:KEY_MODE];
    if (mountPoint == NULL) {
        if (mountListString == nil)
            mountListString = [[NSMutableString alloc]initWithString:@""];
        else
            [mountListString setString:@""];
        [self.mountPointList removeAllObjects];
        self.mountPoint = @"";
        self.ntripErrorMessage = @"";
        self.ntripReceived = 0;
    }
    else {
//        self.mountPoint = mountPoint;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
                   ^{
                       self.isRunningNtrip = YES;
                       [self getGGASentence];
                       int result = ntripTest((__bridge void *)(self),
                                 (char *)[server cStringUsingEncoding:NSUTF8StringEncoding],
                                 (char *)[port cStringUsingEncoding:NSUTF8StringEncoding],
                                 (char *)[user cStringUsingEncoding:NSUTF8StringEncoding],
                                 (char *)[password cStringUsingEncoding:NSUTF8StringEncoding],
                                 (mountPoint == NULL)?NULL:(char *)[mountPoint cStringUsingEncoding:NSUTF8StringEncoding],
                                 (int)mode);
                       NSLog(@"return ntripTest : %d", result);
                       sigstop = 1;
                       stop = 1;
                       self.ntripReceived = 0;
                       self.isRunningNtrip = NO;
                   });
}

- (void)stopNtripNetwork
{
    stop = 1;
    self.ntripReceived = 0;
//    self.mountPoint = @"";
}

@end

