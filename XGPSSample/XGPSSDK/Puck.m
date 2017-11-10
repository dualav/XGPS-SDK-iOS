/*
 Puck.m
 XGPS150/XGPS160 Developers Kit.
 
 Version 2.2
 Integration X150 and X160
 Make the separated code to United
 
 Version 2.1
 Licensed under the terms of the BSD License, as specified below.
 
 Changes since 2.0:
 - Adjusted closeSession to first close session and then set the delegate to nil.
 - Adjusted NSStreamEventEndEncountered handler to not close the connection.
 - fixed why self.serialNumber was getting empty data
 - changed the streams to currentRunLoop from mainRunLoop
 - added checks to confirm it was an XGPS150/160 on the connect and disconnect notification handlers
 - updated for 64-bit compatibility
 
 Changes since 1.5:
 - switched to the RMC sentence for reading lat/lon
 - updated for iOS 8.
 - improvements for use with XGPS150/XGPS160 data streams
 
 Changes since 1.2.1:
 - bluetooth session management updated to be more stable under iOS 6
 
 Changes since V1.0:
 - parseGPS method optimizatized for nominal speed improvements
 - parseGPS does not use Regex for parsing incoming NMEA string any more
 - minimized longitude and latitude position error due to floating point conversions
 
 Copyright (c) 2015 Dual Electronics Corp.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of the Dual Electronics Corporation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "Puck.h"
#import "Common.h"

#define kBufferSize				2048    // I/O stream buffer size 150 is 1024, 160 is 2048
#define kProcessTimerDelay		0.6     // See note in the processConnectNotifications method for explanation of this.
#define kVolt415				644     // Battery level conversion constant.
#define kVolt350				543     // Battery level conversion constant.
#define kMaxNumberOfSatellites  16      // Max number of visible satellites
#define kSleepTimeBetweenCommandRetries 0.3
#define kCalcAvgSNRUsingGPS             YES
#define kCalcAvgSNRUsingGLONASS         NO
#define kLogListItemProcessingDelayTime 0.2
#define kReadDeviceSettingAfterDelay    0.5

// Set these to YES to see the NMEA sentence data logged to the debugger console
#define DEBUG_SENTENCE_PARSING  NO
#define DEBUG_DEVICE_DATA       NO
#define DEBUG_PGGA_INFO			NO
#define DEBUG_PGSA_INFO			NO
#define DEBUG_PGSV_INFO			NO
#define DEBUG_PVTG_INFO			NO
#define DEBUG_PRMC_INFO			NO
#define DEBUG_PGLL_INFO         NO
#define DEBUG_SESSION           NO
#define DEBUG_CRC_CHECK         NO

@interface Puck()

@property BOOL logListItemTimerStarted;
@property BOOL newLogListItemReceived;
@property (nonatomic, strong) NSTimer *logListItemTimer;

// These are for communicating with the XGPS150/XGPS160. Your app can ignore these.
@property bool notificationType;
@property (strong, nonatomic) NSNotification *mostRecentNotification;
@property (strong, nonatomic) EAAccessory *accessory;
@property NSUInteger accessoryConnectionID;
@property (strong, nonatomic) EASession   *session;
@property (strong, nonatomic) NSString *protocolString;
@property bool queueTimerStarted;

@end

@implementation Puck

static unsigned int		rxIdx = 0;
static bool		rxSync = 0;
static bool		rxBinSync;
static unsigned int		rxBinLen;

volatile int	rsp160_cmd;
volatile unsigned char  rsp160_buf[256];
volatile unsigned int   rsp160_len;

UINT	rxBytesCount;
UINT	rxBytesTotal;
UINT	rxMessagesTotal;

BYTE	pktBuf[4096];
NSMutableArray *commandQueue;

BYTE	cfgGpsSettings;
BYTE	cfgLogInterval;
USHORT	cfgLogBlock;
USHORT	cfgLogOffset;

UINT	tLogListCommand;
bool    isBackground;

logentry_t      logRecords[185 * 510];      // 185 records per block, 510 blocks total
unsigned long   logReadBulkCount;
unsigned long   logBulkRecodeCnt;
unsigned long   logBulkByteCnt;

bool queueTimerStarted = NO;

unsigned short  indexOfLastValidGPSSampleInLog;
unsigned short  totalGPSSamplesInLogEntry;

#pragma mark - Puck Mode Change Methods
-(BOOL)isFastSampleRateAvailable
{
    // XGPS150 only (XGPS160 runs at 10Hz)
    if ([self.serialNumber hasPrefix:@"XGPS160"]) return NO;
    
    // Devices with firmware above (but not including) 1.0.34 have a fast refresh rate mode and can accept mode change
    // commands. Devices with firmware versions 1.0.34 and below cannot accept mode change commands.
    
    NSArray *versionNumbers = [self.firmwareRev componentsSeparatedByString:@"."];
    int majorVersion = [[versionNumbers objectAtIndex:0] intValue];
    int minorVersion = [[versionNumbers objectAtIndex:1] intValue];
    
    if ((majorVersion == 1) && (minorVersion > 0)) return YES;
    else
    {
        NSLog(@"Firmware version does not support fast sample rate mode. Please update the device to version 1.2.6 or higher.");
        return NO;
    }
}

- (void)setFastSampleRate
{
    // XGPS150 only (XGPS160 runs at 10Hz)
    if ([self.serialNumber hasPrefix:@"XGPS160"]) return;

    NSInteger written;
    const uint8_t cfg5hz[12] = {
        'S', '0', '5',
        'F', 'F', 'F', 'F',
        'F', 'F', 'F', 'F',
        0x0a
    };
    
    if ([self isFastSampleRateAvailable] == YES)
    {
        if( _session && [_session outputStream] )
        {
            if( [[_session outputStream] hasSpaceAvailable] ) {
                written = [[_session outputStream] write: cfg5hz maxLength:12];
            }
        }
    }
}

- (void)setNormalSampleRate
{
    // XGPS150 only (XGPS160 runs at 10Hz)
    if ([self.serialNumber hasPrefix:@"XGPS160"]) return;

    NSInteger written;
    const uint8_t cfg1hz[12] = {
        'S', '0', '0',
        'F', 'F', 'F', 'F',
        'F', 'F', 'F', 'F',
        0x0a
    };
    
    if ([self isFastSampleRateAvailable] == YES)
    {
        if( _session && [_session outputStream] )
        {
            if( [[_session outputStream] hasSpaceAvailable] ) {
                written = [[_session outputStream] write: cfg1hz maxLength:12];
            }
        }    
    }
}

# pragma mark - Data Input and Processing Methods
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    if( self == nil || aStream == nil )
        return;
    
    switch(eventCode)
    {
        case NSStreamEventEndEncountered:
        {
            NSLog(@"%s. NSStreamEventEndEncountered\n", __FUNCTION__);
            break;
        }
        case NSStreamEventHasBytesAvailable:
        {
            uint len = 0;
            uint8_t buffer[kBufferSize] = {0,};
//            NSLog(@"%s. NSStreamEventHasBytesAvailable\n", __FUNCTION__);
            
            len = (uint) [[_session inputStream] read:buffer maxLength:kBufferSize];
//            NSLog(@"%s. read buffer %d\n", __FUNCTION__, len);
            if (len == 0)   break;
            
            [self handleInputStream:(const char* )buffer len:len];
            break;
        }
            
        case NSStreamEventHasSpaceAvailable:
        {
            NSLog(@"%s. NSStreamEventHasSpaceAvailable\n", __FUNCTION__);
            break;
        }
            
        case NSStreamEventErrorOccurred:
        {
            NSLog(@"%s. NSStreamEventErrorOccurred\n", __FUNCTION__);
            break;
        }
        case NSStreamEventNone:
        {
            NSLog(@"%s. NSStreamEventNone\n", __FUNCTION__);
            break;
        }
        case NSStreamEventOpenCompleted:
        {
            NSLog(@"%s. NSStreamEventOpenCompleted\n", __FUNCTION__);
            break;
        }
        default:
        {
            NSLog(@"%s. Some other stream event occurred.\n", __FUNCTION__);
            break;
        }
    }
}  // stream:handleEvent

// TODO : change pktBuf to pLine
- (void)parseCommandResponsesFromXGPS:(const char *)pLine length:(NSUInteger)len
{
    BYTE	cs = 0;
    BYTE	i;
    BYTE	size;
    size = rxBinLen + 3;
    
    for( i=0; i<size; i++ ) {
        cs += pktBuf[i];
    }
    
    if( cs != pktBuf[rxBinLen + 3] )
    {
        //NSLog(@"%s. Checksum error. Skipping...", __FUNCTION__);
        return;
    }
    
    switch (pktBuf[3])
    {
        case cmd160_ack:
        case cmd160_nack:
            rsp160_cmd = pktBuf[3];
            rsp160_len = 0;
            break;
            
        case cmd160_fwRsp:
            rsp160_cmd = pktBuf[3];
            rsp160_buf[0] = pktBuf[4];
            rsp160_buf[1] = pktBuf[5];
            rsp160_buf[2] = pktBuf[6];
            rsp160_buf[3] = pktBuf[7];
            rsp160_len = rxBinLen;
            
            if (pktBuf[4] == cmd160_getSettings)
            {
                //NSLog(@"%s. XGPS160 sending settings.", __FUNCTION__);
                USHORT	blk;
                USHORT	offset;
                
                blk = pktBuf[8];
                blk <<= 8;
                blk |= pktBuf[7];
                
                offset = pktBuf[10];
                offset <<= 8;
                offset |= pktBuf[9];
                
                cfgGpsSettings = pktBuf[5];
                cfgLogInterval = pktBuf[6];
                self.logUpdateRate = pktBuf[6];
                //NSLog(@"%s. log update rate byte value is %d.", __FUNCTION__, self.logUpdateRate);
                
                cfgLogBlock = blk;
                cfgLogOffset = offset;
                
                if( cfgGpsSettings & 0x40 )
                {
                    //NSLog(@"Datalog Enabled\r\n");
                    self.alwaysRecordWhenDeviceIsOn = YES;
                }
                else
                {
                    //NSLog(@"Datalog Disabled\r\n");
                    self.alwaysRecordWhenDeviceIsOn = NO;
                }
                
                if( cfgGpsSettings & 0x80 )
                {
                    //NSLog(@"Datalog OverWrite\r\n");
                    self.stopRecordingWhenMemoryFull = NO;
                }
                else
                {
                    //NSLog(@"Datalog no OverWrite\r\n");
                    self.stopRecordingWhenMemoryFull = YES;
                }
                
                self.deviceSettingsHaveBeenRead = YES;
                NSNotification *status = [NSNotification notificationWithName:@"DeviceSettingsValueChanged" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:status];
            }
            else if (pktBuf[4] == cmd160_logListItem)
            {
                NSMutableDictionary *logDic;
                
                USHORT          listIdx;
                USHORT          listTotal;
                loglistitem_t	li;
                loglistitem_t   *plistitem;
                
                listIdx = pktBuf[6];
                listIdx <<= 8;
                listIdx |= pktBuf[7];
                
                listTotal = pktBuf[8];
                listTotal <<= 8;
                listTotal |= pktBuf[9];
                
                plistitem = &li;
                
                // There is bug in firmware v. 1.3.0. The cmd160_logList command will append a duplicate of the last long
                // entry. For example, if there are 3 recorded logs, the command will repond that there are four: log 0,
                // log 1, log 2 and log 2 again.
                
                if (listIdx == listTotal)
                {
                    listIdx = 0;
                    listTotal = 0;
                    logDic = nil;
                }
                else
                {
                    memcpy ((void *)plistitem, &pktBuf[10], sizeof(loglistitem_t));
                    
                    logDic = nil;
                    logDic = [[NSMutableDictionary alloc] init];
                    
                    // Create the date & time objects
                    NSString *dateString = [NSString stringWithFormat:@"%s",dateStr(plistitem->startDate)];
                    NSString *timeString = [NSString stringWithFormat:@"%s",todStr(plistitem->startTod)];
                    
                    //UTC time
                    NSDateFormatter *utcDateFormatter = [[NSDateFormatter alloc] init] ;
                    [utcDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    [utcDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
                    
                    // utc format
                    NSDate *dateInUTC = [utcDateFormatter dateFromString: [NSString stringWithFormat:@"%@ %@",dateString,timeString]];
                    
                    // offset second
                    NSInteger seconds = [[NSTimeZone systemTimeZone] secondsFromGMT];
                    
                    // format it and send
                    NSDateFormatter *localDateFormatter = [[NSDateFormatter alloc] init] ;
                    [localDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
                    
                    // formatted string
                    NSString *str_localDate = [localDateFormatter stringFromDate: dateInUTC];
                    //               NSDate *DeviceDate = [utcDateFormatter dateFromString:str_localDate];
                    
                    
                    
                    [localDateFormatter setDateFormat:@"yyyy-MM-dd"];
                    NSString *str_date = [localDateFormatter stringFromDate:dateInUTC];
                    
                    
                    
                    [localDateFormatter setDateFormat:@"HH:mm:ss"];
                    NSString *str_time = [localDateFormatter stringFromDate:dateInUTC];
                    [logDic setObject:str_date forKey:@"DeviceStartDate"];
                    [logDic setObject:str_time forKey:@"DeviceStartTime"];
                    [logDic setObject:[NSString stringWithFormat:@"%@ %@",str_date,str_time] forKey:@"DevicerecordingStart"];
                    
                    
                    
                    
                    
                    
                    
                    
                    
                    [logDic setObject:dateString forKey:@"humanFriendlyStartDate"];
                    [logDic setObject:[self prettyTime:(plistitem->startTod)] forKey:@"humanFriendlyStartTime"];
                    [logDic setObject:[self dateFromTime:timeString andDate:dateString] forKey:@"recordingStart"];
                    
                    // Create the duration objects
                    [logDic setObject: [NSNumber numberWithUnsignedChar:plistitem->interval] forKey:@"interval"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->countEntry] forKey:@"countEntry"];
                    
                    float sampleInterval = (float)plistitem->interval;
                    if (plistitem->interval == 255) sampleInterval = 10.0;
                    
                    float recordingLengthInSecs = (float)plistitem->countEntry * sampleInterval / 10.0;
                    unsigned durationHrs, durationMins, durationSecs;
                    durationHrs = floor(recordingLengthInSecs / 3600);
                    durationMins = floor((recordingLengthInSecs - (durationHrs * 3600)) / 60.0);
                    durationSecs = recordingLengthInSecs - (durationHrs * 3600) - (durationMins * 60);
                    
                    if (durationHrs > 0)
                        [logDic setObject:[NSString stringWithFormat:@"%02d:%02d:%02d", durationHrs, durationMins, durationSecs] forKey:@"humanFriendlyDuration"];
                    else if (durationMins > 0)
                        [logDic setObject:[NSString stringWithFormat:@"00:%02d:%02d", durationMins, durationSecs] forKey:@"humanFriendlyDuration"];
                    else
                        [logDic setObject:[NSString stringWithFormat:@"00:00:%02d", durationSecs] forKey:@"humanFriendlyDuration"];
                    
                    
                    // Add the remaining elements
                    [logDic setObject: [NSString stringWithFormat:@"%s",todStr(plistitem->sig)] forKey:@"sig"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->startDate] forKey:@"startDate"];
                    [logDic setObject: [NSNumber numberWithUnsignedInt:plistitem->startTod] forKey:@"startTod"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->startBlock] forKey:@"startBlock"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->countBlock] forKey:@"countBlock"];
                    
                    [self.logListEntries addObject:logDic];
                    
                    logDic = nil;
                    self.newLogListItemReceived = YES;
                    [self processLogListEntriesAfterDelay];
                }
            }
            else if (pktBuf[4] == cmd160_logReadBulk)
            {
                UINT	addr;
                BYTE	dataSize;
                
                addr = pktBuf[6];
                addr <<= 8;
                addr |= pktBuf[7];
                addr <<= 8;
                addr |= pktBuf[8];
                
                dataSize = pktBuf[9];
                
                logReadBulkCount += (dataSize / sizeof(logentry_t));
                
                if (addr == 0 && dataSize == 0)
                {
                    // End-of-data
                    logReadBulkCount |= 0x1000000;
                    
                    [self decodeLogBulk];
                    
                    logReadBulkCount = 0;
                    logBulkRecodeCnt = 0;
                    logBulkByteCnt = 0;
                    memset(logRecords, 0, 185 * 510);
                }
                else
                {
                    BYTE *p = &pktBuf[10];
                    
                    for (i=0; i<5; i++)
                    {
                        memcpy (&logRecords[logBulkRecodeCnt + i], p, sizeof(logentry_t));
                        p += sizeof(logentry_t);
                    }
                    
                    logBulkRecodeCnt += 5;
                    logBulkByteCnt = logBulkRecodeCnt;
                }
            }
            else if (pktBuf[4] == cmd160_logDelBlock)
            {
                
                //if (pktBuf[5] == 0x01) [self getListOfRecordedLogs];
                //else NSLog(@"Error deleting block data.");
                
                if (pktBuf[5] != 0x01) NSLog(@"Error deleting block data.");
                
            }
            else if (pktBuf[4] == cmd160_logInterval) {
                self.logUpdateRate = pktBuf[5];
                NSNotification *status = [NSNotification notificationWithName:@"DeviceSettingsValueChanged" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:status];
            }
            break;
            
        case cmd160_response:
            rsp160_cmd = pktBuf[3];
            rsp160_len = 0;
            break;
            
        default:
            break;
    }
}

- (int) getUsedStoragePercent
{
    int percent;
    int countBlock=0;
    
    for (NSDictionary*dic in _logListEntries) {
        countBlock += [[dic objectForKey:@"countBlock"]integerValue];
    }
    
    percent = (countBlock * 1000 / 520);
    if( percent > 0 && percent < 10) {
        percent = 10;
    }
    
    return percent / 10;
}


//======================================================================================
// LOG DATA DECODE
//======================================================================================

static double getLatLon24bit( BYTE* buf )
{
#define kLatLonBitResolution       2.1457672e-5
    
    double  d;
    int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    
    d = ((double)r) * kLatLonBitResolution;
    
    if( r & 0x800000 ) {	// is South / West ?
        d = -d;
    }
    
    return d;
}

static unsigned int getUInt24bit( BYTE* buf )
{
    unsigned int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    
    return r;
}

static double getLatLon32bit( BYTE* buf )
{
    double  d;
    int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    r <<= 8;
    r |= buf[3];
    
    d = ((double)r) * 0.000001;
    
    return d;
}

- (void)decodeLogBulk
{
    logentry_t*		e;
    UINT			tod;
    UINT			tod10th;
    UINT            spd;
    USHORT          dateS;
    double			fLat=0;
    double			fLon=0;
    double          fAlt=0;
    double          fHeading=0;
    
    [self.logDataSamples removeAllObjects];
    
    for (unsigned long i=0; i<logBulkRecodeCnt; i++)
    {
        e = &logRecords[i];
        
        if( e->type == 0 )// type=0 Original XGPS160 24-bit lat/lon (pre-v2.4/v3.4)
        {
            dataentry_t*    d = &e->data;
            
            tod = (d->tod2 & 0x10);
            tod <<= 12;
            tod |= d->tod;
            tod10th = d->tod2 & 0x0F;
            
            fLat = getLatLon24bit( d->lat );
            fLon = getLatLon24bit( d->lon );
            //fAlt = getUInt24bit( d->alt ) * 5.0 / 3.2808399;// 5feet unit -> meters
            fAlt = getUInt24bit( d->alt ) * 5.0;// 5feet unit -> 1feet unit
            
            spd = d->spd[0];
            spd <<= 8;
            spd |= d->spd[1];
            
            fHeading = (double)d->heading * 360.0 / 256.0;
            
            dateS = d->date;
        }
        else if( e->type == 2 )// type=2 New 32-bit lat/lon
        {
            data2entry_t*    d = &e->data2;
            
            tod = (d->tod2 & 0x10);
            tod <<= 12;
            tod |= d->tod;
            tod10th = d->tod2 & 0x0F;
            
            fLat = getLatLon32bit( d->lat );
            fLon = getLatLon32bit( d->lon );
            // altitude in data2entry_t is in centimeter unit
            //fAlt = ((double)getUInt24bit( d->alt )) / 100.0;// cm(centi-meter) unit -> meters
            fAlt = ((double)getUInt24bit( d->alt )) / 100.0 / 0.3048;// cm(centi-meter) unit -> feet
            
            spd = d->spd[0];
            spd <<= 8;
            spd |= d->spd[1];
            
            fHeading = (double)d->heading * 360.0 / 256.0;
            
            dateS = d->date;
        }
        else
        {
            break;
        }
        //UTC time
        NSDateFormatter *utcDateFormatter = [[NSDateFormatter alloc] init] ;
        [utcDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SS"];
        [utcDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
        
        // utc format
        NSDate *dateInUTC = [utcDateFormatter dateFromString: [NSString stringWithFormat:@"%@ %@",[NSString stringWithFormat:@"%s",dateStr(dateS)],[NSString stringWithFormat:@"%s",tod2Str(tod, tod10th)]]];
        
        // offset second
        NSInteger seconds = [[NSTimeZone systemTimeZone] secondsFromGMT];
        
        // format it and send
        NSDateFormatter *localDateFormatter = [[NSDateFormatter alloc] init] ;
        [localDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SS"];
        [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
        
        
        // formatted string
        NSString *str_localDate = [localDateFormatter stringFromDate: dateInUTC];
        NSDate *DeviceDate = [utcDateFormatter dateFromString:str_localDate];
        
        
        [localDateFormatter setDateFormat:@"yyyy-MM-dd"];
        NSString *str_date = [localDateFormatter stringFromDate:dateInUTC];
        [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
        
        [localDateFormatter setDateFormat:@"HH:mm:ss.S"];
        NSString *str_timeinMilesec = [localDateFormatter stringFromDate:dateInUTC];
        [localDateFormatter setDateFormat:@"HH:mm:ss"];
        NSString *str_time = [localDateFormatter stringFromDate:dateInUTC];
        
        //
        //
        //        NSLog(@"DDate %@ DTime %@",str_date,str_time);
        //
        //        NSLog(@"utc date%@   utctime%@",[NSString stringWithFormat:@"%s",dateStr(le->data.date)],[NSString stringWithFormat:@"%s",tod2Str(tod, tod10th)]);
        //        NSLog(@"device Date %@",DeviceDate);
        
        
        
        NSMutableDictionary *bulkDic = [[NSMutableDictionary alloc] init];
        
        
        [bulkDic setObject:str_date forKey:@"Devicedate"];
        [bulkDic setObject:str_time forKey:@"Devicetime"];
        [bulkDic setObject:str_timeinMilesec forKey:@"DeviceTimeInMiliseconds"];
        
        
        [bulkDic setObject:[NSString stringWithFormat:@"%s",dateStr(dateS)] forKey:@"date"];
        [bulkDic setObject:[NSNumber numberWithDouble:fLat] forKey:@"lat"];
        [bulkDic setObject:[NSNumber numberWithDouble:fLon] forKey:@"lon"];
        [bulkDic setObject:[NSNumber numberWithDouble:fAlt] forKey:@"alt"];
        [bulkDic setObject:[NSString stringWithFormat:@"%s",todTimeOnly(tod)] forKey:@"time"];
        [bulkDic setObject:[NSString stringWithFormat:@"%s",tod2Str(tod, tod10th)] forKey:@"utc"];
        [bulkDic setObject:[NSNumber numberWithUnsignedInt:spd] forKey:@"speed"];
        [bulkDic setObject:[NSNumber numberWithDouble:fHeading] forKey:@"heading"];
        [bulkDic setObject:[NSString stringWithFormat:@"%s %s",dateStr(dateS), tod2Str(tod, tod10th)] forKey:@"titleText"];
        
        [self.logDataSamples addObject:bulkDic];
    }
    
    // The device returns all data samples in the block and this will usually extend beyond the end of the valid data.
    // So truncate the returned array of data at the end of the actual data.
    [self.logDataSamples removeObjectsInRange:NSMakeRange(totalGPSSamplesInLogEntry, [self.logDataSamples count] - totalGPSSamplesInLogEntry)];
    
    NSNotification *status = [NSNotification notificationWithName:@"DoneReadingGPSSampleData" object:self];
    [[NSNotificationCenter defaultCenter] postNotification:status];
}


- (bool)sendCommandToDevice:(BYTE)cmd payloadDataArray:(unsigned char *)buf lengthOfPayloadDataArray:(unsigned int)bufLen
{
    static	BYTE	xbuf[256];
    UINT	size = 0;
    UINT	i;
    BYTE	cs;
    
    xbuf[0] = 0x88;
    xbuf[1] = 0xEE;
    xbuf[2] = bufLen + 1;	// length
    xbuf[3] = (BYTE) cmd;
    
    if( bufLen > 0 ) {
        if( buf == NULL ) {
            return FALSE;
        }
        if( bufLen > 248 ) {
            return FALSE;
        }
        memcpy( &xbuf[4], buf, bufLen );
    }
    
    size = 4 + bufLen;
    
    cs = 0;
    for( i=0; i<size; i++ ) {
        cs += xbuf[i];
    }
    
    xbuf[size] = cs;
    size++;
    
    NSInteger written = 0;
    char maxRetries = 5;
    
    // for log
    NSMutableString *logString = [[NSMutableString alloc] initWithString:@""];
    for (i = 0; i < size; i++) {
        [logString appendString:[NSString stringWithFormat:@"%02x", xbuf[i]]];
    }
    NSLog(@"sendCommandToDevice : 0x%@", logString);
    
    do {
        if (self.session && [self.session outputStream])
        {
            if ([[self.session outputStream] hasSpaceAvailable])
            {
                written = [[self.session outputStream] write: xbuf maxLength:size];
            }
        }
        
        [NSThread sleepForTimeInterval:kSleepTimeBetweenCommandRetries];
        maxRetries--;
        
    } while (written == 0 || maxRetries == 0);
    
    if (written > 0) return TRUE;
    else
    {
        //NSLog(@"%s. Nothing written to device.", __FUNCTION__);
        return FALSE;
    }
}

- (void)notifyUIOfNewLogListData
{
    if (self.newLogListItemReceived == YES)
    {
        self.newLogListItemReceived = NO;
    }
    else
    {
        // stop the timer
        if (self.logListItemTimer != nil)
        {
            if ([self.logListItemTimer isValid])
            {
                [self.logListItemTimer invalidate];
                self.logListItemTimer = nil;
            }
        }
        self.logListItemTimerStarted = NO;
        
        // sort the log list entry array going first to last
        NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"recordingStart" ascending:YES];
        NSArray *descriptors = [NSArray arrayWithObject:valueDescriptor];
        self.logListEntries = [NSMutableArray arrayWithArray:[self.logListEntries sortedArrayUsingDescriptors:descriptors]];
        
        // notify any view controllers that the log list creation is complete
        NSNotification *status = [NSNotification notificationWithName:@"DoneReadingLogListEntries" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:status];
    }
}

- (void)processLogListEntriesAfterDelay
{
    /* In firmware versions earlier than 1.3.5, the device doesn't reliably send the total number of log entries
     stored in memory. So there is no way to know when transfer of the log entry list is finished, other than
     to use a timer.
     
     So what happens here is the utilization of a timer to defer processing until a few moments after the last
     log_entry_item message is received.
     
     A repeating timer is started. When the timer ends, there is a check whether new data has arrived. If so, the
     timer is allowed to repeat. If no new data has been received, the timer is cancelled and the received data
     is processed.
     */
    
    if (self.logListItemTimerStarted == NO)
    {
        //create timer
        self.logListItemTimer = [NSTimer timerWithTimeInterval:(kLogListItemProcessingDelayTime)
                                                        target:self
                                                      selector:@selector(notifyUIOfNewLogListData)
                                                      userInfo:nil
                                                       repeats:YES];
        
        [[NSRunLoop currentRunLoop] addTimer:self.logListItemTimer forMode:NSDefaultRunLoopMode];
        self.logListItemTimerStarted = YES;
    }
    else return;
}

#pragma mark - Utility methods
char *dateStr(USHORT ddd)
{
    static char str[20];
    
    
    int tmp;
    int yy, mm, dd;
    
    tmp = ddd;
    yy = 2012 + tmp/372;
    mm = 1 + (tmp % 372) / 31;
    dd = 1 + tmp % 31;
    
    //sprintf(str, "%04d/%02d/%02d", yy, mm, dd);  // e.g. 2014/06/14
    sprintf(str, "%04d-%02d-%02d", yy,mm, dd);    // e.g. 06/14/2014
    
    return str;
}

char *todStr(UINT tod)  // Returns time with whole seconds: HH:MM:SS
{
    static char str[20];
    int	hr, mn, ss;
    
    hr = tod / 3600;
    mn = (tod % 3600) / 60;
    ss = tod % 60;
    
    sprintf(str, "%02d:%02d:%02d", hr, mn, ss);
    
    return str;
}

char *tod2Str(USHORT tod, BYTE tod2)  // Returns time to the hundredth of a sec: HH:MM:SS.ss
{
    static char str[20];
    int	hr, mn, ss, tenths;
    
    hr = tod / 3600;
    mn = (tod % 3600) / 60;
    ss = tod % 60;
    tenths = tod2 & 0x0F;
    
    sprintf(str, "%02d:%02d:%02d.%01d", hr, mn, ss, tenths);
    
    return str;
}


char *todTimeOnly(USHORT tod)  // Returns time to the hundredth of a sec: HH:MM:SS.ss
{
    static char str[20];
    int	hr, mn, ss;
    
    hr = tod / 3600;
    mn = (tod % 3600) / 60;
    ss = tod % 60;
    sprintf(str, "%02d:%02d:%02d", hr, mn, ss);
    
    return str;
}


- (NSDate *)dateFromTime:(NSString *)timeString andDate:(NSString *)dateString
{
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [df setTimeZone:[NSTimeZone localTimeZone]];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    NSString *combined = [NSString stringWithFormat:@"%@ %@", dateString, timeString];
    
    
    
    
    
    
    
    /*
     
     NSDateFormatter *utcDateFormatter = [[NSDateFormatter alloc] init] ;
     [utcDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
     [utcDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
     
     // utc format
     NSDate *dateInUTC = [utcDateFormatter dateFromString: combined];
     
     // offset second
     NSInteger seconds = [[NSTimeZone systemTimeZone] secondsFromGMT];
     
     // format it and send
     NSDateFormatter *localDateFormatter = [[NSDateFormatter alloc] init] ;
     [localDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
     [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
     
     
     // formatted string
     NSString *str_localDate = [localDateFormatter stringFromDate: dateInUTC];
     NSDate *date_final = [localDateFormatter dateFromString:str_localDate];
     
     NSLog(@"%@",dateInUTC);
     
     */
    
    
    
    
    return [df dateFromString:combined];
}

- (NSString *)prettyTime:(UINT)tod
{
    int	hr, mn;
    
    hr = tod / 3600;
    if (hr == 0) hr = 12;
    
    mn = (tod % 3600) / 60;
    
    if (hr > 12) return [NSString stringWithFormat:@"%2d:%02d PM", (hr-12), mn];
    else return [NSString stringWithFormat:@"%2d:%02d AM", hr, mn];
}

- (float)calculateAvgUsableSatSNRWithSatSystem:(bool)GPSorGLONASS
{
    NSMutableArray *satData;
    int sumSatStrength=0;
    float avgSNR=0.0;
    
    NSNumber *numOfSatInUse;
    NSMutableDictionary *dictOfSatInfo;
    NSMutableArray *satsUsedInPosCalc;
    
    if (GPSorGLONASS == kCalcAvgSNRUsingGPS)
    {
        numOfSatInUse = self.numOfSatInUse;
        dictOfSatInfo = self.dictOfGPSSatInfo;
        satsUsedInPosCalc = self.gpsSatsUsedInPosCalc;
    }
    else
    {
        numOfSatInUse = self.numOfGLONASSSatInUse;
        dictOfSatInfo = self.dictOfGLONASSSatInfo;
        satsUsedInPosCalc = self.glonassSatsUsedInPosCalc;
    }
    
    if (numOfSatInUse == 0) return 0.0f;	// error prevention
    
    for (NSNumber *sat in [dictOfSatInfo allKeys])
    {
        for (NSNumber *satInUse in satsUsedInPosCalc)
        {
            if ([sat intValue] == [satInUse intValue])
            {
                satData = [dictOfSatInfo objectForKey:sat];
                sumSatStrength += [[satData objectAtIndex:2] intValue];
            }
        }
    }
    
    avgSNR = (float)sumSatStrength / [numOfSatInUse floatValue];
    
    if (isnan(avgSNR) != 0) avgSNR = 0.0;   // check: making sure all SNR values are valid
    
    return avgSNR;
}

#pragma mark - Log Control Methods
- (void)startLoggingNow
{
    [self sendCommandToDevice:cmd160_logEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
}

- (void)stopLoggingNow
{
    [self sendCommandToDevice:cmd160_logDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
}

#pragma mark - Log Access and Management
- (void)getListOfRecordedLogs
{
    [self.logListEntries removeAllObjects];
    
    [self sendCommandToDevice:cmd160_logList payloadDataArray:0 lengthOfPayloadDataArray:0];
}

- (void)getGPSSampleDataForLogListItem:(NSDictionary *)logListItem
{
    if (logListItem == nil) return;
    else
    {
        [self.logDataSamples removeAllObjects];
        
        totalGPSSamplesInLogEntry = [[logListItem objectForKey:@"countEntry"] unsignedShortValue];
        unsigned short startBlock = [[logListItem objectForKey:@"startBlock"] unsignedShortValue];
        unsigned short countBlock = [[logListItem objectForKey:@"countBlock"] unsignedShortValue];
        
        uint8_t startBlockHigh = (startBlock & 0xFF00) >> 8;
        uint8_t startBlockLow = startBlock & 0x00FF;
        uint8_t countBlockHigh = (countBlock & 0xFF00) >> 8;
        uint8_t countBlockLow = countBlock & 0x00FF;
        
        unsigned char payloadArray[4] = {startBlockHigh, startBlockLow, countBlockHigh, countBlockLow};
        [self sendCommandToDevice:cmd160_logReadBulk payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
    }
}

- (void)deleteGPSSampleDataForLogListItem:(NSDictionary *)logListItem
{
    if (logListItem == nil) return;
    else
    {
        // Delete the recorded log from the XGPS160 memory
        unsigned short startBlock = [[logListItem objectForKey:@"startBlock"] unsignedShortValue];
        unsigned short countBlock = [[logListItem objectForKey:@"countBlock"] unsignedShortValue];
        
        uint8_t startBlockHigh = (startBlock & 0xFF00) >> 8;
        uint8_t startBlockLow = startBlock & 0x00FF;
        uint8_t countBlockHigh = (countBlock & 0xFF00) >> 8;
        uint8_t countBlockLow = countBlock & 0x00FF;
        
        unsigned char payloadArray[4] = {startBlockHigh, startBlockLow, countBlockHigh, countBlockLow};
        [self sendCommandToDevice:cmd160_logDelBlock payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
        
        // Remove the log entry from the log list array
        [self.logListEntries removeObject:logListItem];
    }
}

- (void)enterLogAccessMode
{
    /* It's much simpler to deal with log data information while the device is not streaming GPS data. So the
     recommended practice is to pause the NMEA stream output during the time that logs are being accessed
     and manipulated.
     
     However, the command to pause the output needs to be sent from a background thread in order to ensure there
     is space available for an output stream. Only this command needs to be on the background thread. Once
     the stream is paused, commands can be sent on the main thread.
     */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        [self sendCommandToDevice:cmd160_streamStop payloadDataArray:0 lengthOfPayloadDataArray:0];
        
        self.streamingMode = NO;
        
        // get the list of log data
        [self getListOfRecordedLogs];
    });
    
}

- (void)exitLogAccessMode
{
    // Remember to tell the XGPS160 to resume sending NMEA data once you are finished with the log data.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        [self sendCommandToDevice:cmd160_streamResume payloadDataArray:0 lengthOfPayloadDataArray:0];
        
        self.streamingMode = YES;
    });
}

# pragma mark - Device Settings Methods
- (void)setNewLogDataToOverwriteOldData:(bool)overwrite
{
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            if (overwrite) [self sendCommandToDevice:cmd160_logOWEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
            else [self sendCommandToDevice:cmd160_logOWDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
            
        });
    }
    else
    {
        if (overwrite) [self sendCommandToDevice:cmd160_logOWEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
        else [self sendCommandToDevice:cmd160_logOWDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
    }
}

- (void)setAlwaysRecord:(bool)record
{
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            if (record) [self sendCommandToDevice:cmd160_logEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
            else [self sendCommandToDevice:cmd160_logDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
            
        });
    }
    else
    {
        if (record) [self sendCommandToDevice:cmd160_logEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
        else [self sendCommandToDevice:cmd160_logDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
    }
}

-(BOOL)checkForAdjustableRateLogging
{
    // Devices with firmware 1.3.5 and above have a configurable logging rate.
    // Devices with firmware versions less than 1.3.5 below cannot accept the rate change commands.
    // So check the firmware version and report yes if 1.3.5 or above.
    
    NSArray *versionNumbers = [self.firmwareRev componentsSeparatedByString:@"."];
    int majorVersion = [[versionNumbers objectAtIndex:0] intValue];
    int minorVersion = [[versionNumbers objectAtIndex:1] intValue];
    int subVersion = [[versionNumbers objectAtIndex:2] intValue];
    
    if (majorVersion > 1) return YES;
    else if (minorVersion > 3) return YES;
    else if ((minorVersion == 3) && (subVersion >= 5)) return YES;
    else return NO;
}

- (bool)setLoggingUpdateRate:(unsigned char)rate
{
    if ([self checkForAdjustableRateLogging] == NO) {
        NSLog(@"Device firware version does not support adjustable logging rates. Firmware 1.3.5 or greater is required.");
        NSLog(@"Firware updates are available through the XGPS160 Status Tool app.");
        return NO;
    }
    
    /* rate can only be one of the following vales:
     value  ->      device update rate
     1               10 Hz
     2               5 Hz
     5               2 Hz
     10              1 Hz
     20              once every 2 seconds
     30              once every 3 seconds
     40              once every 4 seconds
     50              once every 5 seconds
     100             once every 10 seconds
     120             once every 12 seconds
     150             once every 15 seconds
     200             once every 20 seconds
     */
    
    if ((rate != 1) && (rate != 2) && (rate != 5) && (rate != 10) &&
        (rate != 20) && (rate != 30) && (rate != 40) && (rate != 50) &&
        (rate != 100) && (rate != 120) && (rate != 150) && (rate != 200))
    {
        NSLog(@"%s. Invaid rate: %d", __FUNCTION__, rate);
        return NO;
    }
    
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            unsigned char payloadArray[1] = {rate};
            NSLog(@"%s. Streaming mode. Requested logging rate: %d", __FUNCTION__, rate);
            [self sendCommandToDevice:cmd160_logInterval payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
        });
    }
    else
    {
        NSLog(@"%s. log access mode. Requested logging rate: %d", __FUNCTION__, rate);
        unsigned char payloadArray[1] = {rate};
        [self sendCommandToDevice:cmd160_logInterval payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
    }
    
    return YES;
}

- (void)readDeviceSettings
{
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            [self sendCommandToDevice:cmd160_getSettings payloadDataArray:0 lengthOfPayloadDataArray:0];
        });
    }
    else
    {
        [self sendCommandToDevice:cmd160_getSettings payloadDataArray:0 lengthOfPayloadDataArray:0];
    }
    
}

# pragma mark - Data Input and Processing Methods
// Only for XGPS150
- (void)separateSentences:(const char *)buf length:(NSUInteger)len
{
    char *token, *string;
    
    if (strncmp(buf, "@", 1) == 0)
    {
        [self parseDeviceInfoSentence:buf length:len];
        buf = nil;
        return;
    }
    
    string = strdup(buf);
    if (string != NULL)
    {
        while ((token = strsep(&string, "\r\n")) != NULL)
        {
            if (strlen(token) > 2)
            {
                [self parseNMEA:token length:strlen(token)];
            }
        }
    }
    buf = nil;
}

// for XGPS 160 code
-(NSArray *) separateCommands :(NSData *)bufferData {
    NSMutableArray *commandList = [NSMutableArray new];
    UInt8 customSeperator[] = { 0x88, 0xee };
    UInt8 commandSeparator[] = { 0x0a };
    NSData *dataCustomSeperator = [NSData dataWithBytes:customSeperator
                                        length:sizeof(customSeperator)];
    NSData *dataCommandSeperator = [NSData dataWithBytes:commandSeparator
                                                 length:sizeof(commandSeparator)];

    NSRange customRange = NSMakeRange(0u, bufferData.length);
    NSRange commandRange = NSMakeRange(0u, bufferData.length);
    NSRange range = NSMakeRange(0u, bufferData.length);
    u_long lastLocation = 0;
    do {
        // 먼저 custom 명령어를 스캔한 후
        customRange = [bufferData rangeOfData:dataCustomSeperator
                                    options:kNilOptions
                                      range:NSMakeRange(lastLocation, [bufferData length] - lastLocation)];
        commandRange = [bufferData rangeOfData:dataCommandSeperator
                                options:kNilOptions
                                  range:NSMakeRange(lastLocation, [bufferData length] - lastLocation)];
        if (customRange.location == NSNotFound && commandRange.location == NSNotFound)
            break;
        // 일반 명령어가 앞에 있으면 일반 명령어부터 처리
        if (customRange.location > commandRange.location) {
            range = NSMakeRange(lastLocation, commandRange.location - lastLocation);
            lastLocation = commandRange.location + commandRange.length;
            if (lastLocation > [bufferData length]) {
                lastLocation = [bufferData length];
            }
        }
        // Custom 명령어가 앞에 있으면 Custom 명령어 처리
        else {
            char buffer[1];
            [bufferData getBytes:buffer range:NSMakeRange(customRange.location + 2, 1)];
            int length = buffer[0] + 4;
//            range = NSMakeRange(customRange.location, length);
            lastLocation = customRange.location + length;
            if (lastLocation > [bufferData length]) {
                lastLocation = [bufferData length];
            }
            range = NSMakeRange(customRange.location, lastLocation - customRange.location);
        }
        if (range.length == 0) {
            break;
        }
        [commandList addObject:[bufferData subdataWithRange:range]];
    } while(range.location != NSNotFound);
    return commandList;
}

-(void) handleInputStream :(const char*)pLine len:(int)len{
    
//    int     i;
//    uint8_t     x;
    
//    NSLog(@"%s",pLine);
    
    NSData *bufferData = [NSData dataWithBytes:pLine length:len];
    NSMutableData *bufferQueue = [NSMutableData data];
//    NSLog(@"commandQueue remains : %d", (int)commandQueue.count);
    if (commandQueue.count > 0) {
        [bufferQueue appendData:[commandQueue objectAtIndex:0]];
        [commandQueue removeAllObjects];
    }
    [bufferQueue appendData:bufferData];
    NSArray* commandList = [self separateCommands: bufferQueue];
    [commandQueue addObjectsFromArray:commandList];
    int loopCount = (int)commandQueue.count;
    if (len == kBufferSize)
        loopCount -= 1;
    
//    NSString *commandString = [NSString stringWithCString:pLine encoding:NSASCIIStringEncoding];
//    NSArray *commandList= [commandString componentsSeparatedByString: @"\r\n"];
    
    for (int i = 0; i < loopCount; i++) {
        NSData *oneCommand = (NSData*) [commandQueue objectAtIndex:0];
        Byte *commandBuffer = (Byte *)oneCommand.bytes;
        if (commandBuffer == nil)
            break;
        if (commandBuffer[0] == '@') {
            [self parseDeviceInfoSentence:(char *)commandBuffer length:oneCommand.length];
        }
        else if (commandBuffer[0] == '$' && commandBuffer[1] == 'G') {
            // x == 'P' || x == 'N' || x == 'L' || x == '@' || x == 'X'
            if ([self.serialNumber hasPrefix:@"XGPS150"])
                [self parseNMEA:(char *)&commandBuffer[2] length:oneCommand.length];
            else
                [self parseGPS:(char *)&commandBuffer[2] length:oneCommand.length];
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                [self parseGPS:(const char *)pktBuf length:(rxIdx + 1)];
//            });
        }
        else if (commandBuffer[0] == 0x88 && commandBuffer[1] == 0xee) {
//            [self handle160command];
            memcpy(pktBuf, commandBuffer, oneCommand.length);
            rxIdx = (int)oneCommand.length;
            rxBinLen = pktBuf[2];
            [self parseCommandResponsesFromXGPS:(char *)commandBuffer length:oneCommand.length];
        }
        [commandQueue removeObjectAtIndex:0];
//        for (int count = 0; count < oneCommand.length; count++) {
//            NSLog(@"%x ", commandBuffer[count]);
//        }
    }
    
//    UInt8 bytes_to_find[] = { 0x88, 0xEE };
//    NSData *dataToFind = [NSData dataWithBytes:bytes_to_find
//                                        length:sizeof(bytes_to_find)];
//
//    NSRange range = [bufferData rangeOfData:dataToFind
//                                    options:kNilOptions
//                                      range:NSMakeRange(0u, [bufferData length])];
//
//    if (range.location == NSNotFound) {
//        NSLog(@"Not found custom command");
//    }
//    else {
//        NSLog(@"Bytes found at position %lu", (unsigned long)range.location);
//    }
//    rxBytesCount += len;
    
    
//    for( i=0; i<len; i++ )
//    {
//
//        x = pLine[i];
//
//        if( rxBinSync ) {
//            pktBuf[rxIdx] = x;
//            rxIdx++;
//            switch( rxIdx ) {
//                case 2:    // second marker
//                    if( x != 0xEE ) {
//                        rxBinSync = FALSE;
//                    }
//                    break;
//
//                case 3:    // length
//                    rxBinLen = x;
//                    break;
//            }
//            if( rxIdx == (rxBinLen + 4) ) {
//
//                [self handle160command];
//                rxBinSync = FALSE;
//            }
//            continue;
//        }
//
//        if( x == 0x88 ) {
//            rxBinSync = TRUE;
//            rxBinLen = 0;
//            rxIdx = 1;
//            pktBuf[0] = x;
//            continue;
//        }
//
//        if( !rxSync ) {
//            if( x == 'P' || x == 'N' || x == 'L' || x == '@' || x == 'X' ) {
//                rxSync = 1;
//                rxIdx = 0;
//                pktBuf[0] = x;
//            }
//        }
//        else {
//            rxIdx++;
//            pktBuf[rxIdx] = x;
//
//            if( x == '\n' ) {
//                rxMessagesTotal++;
//                rxSync = 0;
//
//                pktBuf[rxIdx+1] = 0;
//
//                //                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
////                [self parseGPS:(const char *)pktBuf length:(rxIdx + 1)];
//                //                });
//            }
//        }
//    }
    
}

- (void)parseDeviceInfoSentence:(const char *)pLine length:(NSUInteger)len
{
    int vbat;
    float bvolt, batLevel;
    
    vbat = (unsigned char)pLine[1];
    vbat <<= 8;
    vbat |= (unsigned char)pLine[2];
    if (vbat < kVolt350) vbat = kVolt350;
    if (vbat > kVolt415) vbat = kVolt415;
    
    bvolt = (float)vbat * 330.0f / 512.0f;
    batLevel = ((bvolt / 100.0f) - 3.5f) / 0.65f;
    if (batLevel > 1.0) self.batteryVoltage = 1.0;
    else if (batLevel < 0) self.batteryVoltage = 0.0;
    else self.batteryVoltage = batLevel;
    
    if( pLine[5] & 0x04 ) self.isCharging = YES;
    else self.isCharging = NO;
    
    if (DEBUG_DEVICE_DATA)
    {
        NSLog(@"%s. Battery voltage = %.2f (%.0f%%), Charging = %@.", __FUNCTION__, bvolt/100.0f,
              self.batteryVoltage * 100,
              (self.isCharging)?@"Yes":@"No");
    }
    
    pLine = nil;
    
    // trigger a notification to the view controllers that the device data has been updated
    NSNotification *puckDataUpdated = [NSNotification notificationWithName:@"DeviceDataUpdated" object:self];
    [[NSNotificationCenter defaultCenter] postNotification:puckDataUpdated];
}

-(void) handle160command
{
    Byte    cs = 0;
    Byte    i;
    Byte    size;
    size = rxBinLen + 3;
    
    for( i=0; i<size; i++ ) {
        cs += pktBuf[i];
    }
    
    if( cs != pktBuf[rxBinLen + 3] ) {
        return;
    }
    
    switch( pktBuf[3] ) {
        case cmd160_ack:
        case cmd160_nack:
            rsp160_cmd = pktBuf[3];
            rsp160_len = 0;
            break;
            
        case cmd160_response:
            rsp160_cmd = pktBuf[3];
            rsp160_len = 0;
            NSLog(@"cmd160_response");
            break;
            
        default:
            break;
    }
}

- (void)parseNMEA:(const char *)pLine length:(NSUInteger)len
{
    // Parse the NMEA data stream from the GPS chipset. Check out http://aprs.gids.nl/nmea/ for a good
    // explanation of the various NMEA sentences.
    
    NSArray *elementsInSentence;
    
    if (DEBUG_SENTENCE_PARSING) NSLog(@"%s. buffer text: %s", __FUNCTION__, pLine);
    
    // Create a string from the raw buffer data
    NSString *sentence = [[NSString alloc] initWithUTF8String:pLine];
    if (DEBUG_SENTENCE_PARSING) NSLog(@"%s. sentence is: %@", __FUNCTION__, sentence);
    
    // Perform a CRC check. The checksum field consists of a "*" and two hex digits representing
    // the exclusive OR of all characters between, but not including, the "$" and "*".
    unichar digit=0, crcInString=0, calculatedCrc='G';
    NSUInteger i=0;
    
    while (i < [sentence length])
    {
        digit = [sentence characterAtIndex:i];
        if (digit == 42)    // found the asterisk
        {
            unichar firstCRCChar = [sentence characterAtIndex:(i+1)];
            unichar secondCRCChar = [sentence characterAtIndex:(i+2)];
            
            if (firstCRCChar > 64) firstCRCChar = (firstCRCChar - 55) * 16;
            else firstCRCChar = (firstCRCChar - 48) * 16;
            
            if (secondCRCChar > 64) secondCRCChar = secondCRCChar - 55;
            else secondCRCChar = secondCRCChar - 48;
            
            crcInString = firstCRCChar + secondCRCChar;
            break;
        }
        
        calculatedCrc = calculatedCrc ^ digit;
        
        i++;
    }
    
    if (DEBUG_CRC_CHECK)
    {
        if (crcInString == calculatedCrc) NSLog(@"%s. CRC matches.", __FUNCTION__);
        else NSLog(@"%s. CRC does not match.\nCalculated CRC is 0x%.2X. NMEA sentence is: %@", __FUNCTION__, calculatedCrc, sentence);
    }
    
    if (crcInString != calculatedCrc) return;
    
    // Break the data into an array of elements
    elementsInSentence = [sentence componentsSeparatedByString:@","];
    
    // Parse the data based on the NMEA sentence identifier
    if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PGGA"])
    {
        // Case 2: parse the location info
        if (DEBUG_PGGA_INFO)
        {
            NSLog(@"%s. PGGA sentence with location info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s", __FUNCTION__, pLine);
        }
        
        if ([elementsInSentence count] < 10) return;    // malformed sentence

        // extract the number of satellites in use by the GPS
        if (DEBUG_PGGA_INFO) NSLog(@"%s. PGGA num of satellites in use = %@.", __FUNCTION__, [elementsInSentence objectAtIndex:7]);
        
        // extract the altitude
        self.alt = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:9] floatValue]];
        if (DEBUG_PGGA_INFO) NSLog(@"%s. altitude = %.1f.", __FUNCTION__, [self.alt floatValue]);
    }
    else if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PGSV"])
        // Case 3: parse the satellite info. Note the uBlox chipset can pick up more satellites than the
        //         Skytraq chipset. Sentences can look like:
        //
        // Skytraq chipset:
        // e.g. PGSV,3,1,11,03,03,111,00,04,15,270,00,06,01,010,00,13,06,292,00*74
        //      PGSV,3,2,11,14,25,170,00,16,57,208,39,18,67,296,40,19,40,246,00*74
        //      PGSV,3,3,11,22,42,067,42,24,14,311,43,27,05,244,00,,,,*4D
        //      no PGSV sentence produce when no signal
        //
        // uBlox chipset:
        // e.g. PGSV,1,1,00*79    (no signal)
        //      PGSV,4,1,15,02,49,269,42,04,68,346,45,05,13,198,32,09,16,269,29*78
        //      PGSV,4,2,15,10,57,149,47,12,21,319,38,13,02,101,,17,47,069,47*7E
        //      PGSV,4,3,15,20,03,038,21,23,02,074,24,27,16,254,32,28,30,154,41*79
        //      PGSV,4,4,15,33,13,102,,48,25,249,41,51,46,225,44*4E
    {
        // Case 3: parse the satellite info.
        if (DEBUG_PGSV_INFO) NSLog(@"%s. buffer text = %s.", __FUNCTION__, pLine);
        
        if ([elementsInSentence count] < 4) return;    // malformed sentence
        
        self.numOfSatInView = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:3] intValue]];
        if (DEBUG_PGSV_INFO) NSLog(@"%s. number of satellites in view = %d.", __FUNCTION__, [self.numOfSatInView intValue]);
        
        // handle the case of the uBlox chip returning no satellites
        if ([self.numOfSatInView intValue] == 0)
        {
            [self.dictOfSatInfo removeAllObjects];
        }
        else
        {
            // If this is first GSV sentence, reset the dictionary of satellite info
            if ([[elementsInSentence objectAtIndex:2] intValue] == 1) [self.dictOfSatInfo removeAllObjects];
            
            NSNumber *satNum, *satElev, *satAzi, *satSNR, *inUse;
            NSMutableArray *satInfo;
            
            // The number of satellites described in a sentence can vary up to 4.
            int numOfSatsInSentence;

            if ([elementsInSentence count] == 8) numOfSatsInSentence = 1;
            else if ([elementsInSentence count] == 12) numOfSatsInSentence = 2;
            else if ([elementsInSentence count] == 16) numOfSatsInSentence = 3;
            else if ([elementsInSentence count] == 20) numOfSatsInSentence = 4;
            else return;       // malformed sentence

            for (int i=0; i<numOfSatsInSentence; i++)
            {
                int index = i*4 + 4;
                inUse = [NSNumber numberWithBool:NO];
                
                satNum = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:index] intValue]];
                satElev = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+1)] intValue]];
                satAzi = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+2)] intValue]];
                // The stream data will not contain a comma after the last value and before the checksum.
                // So, for example, this sentence can occur:
                //	  PGSV,3,3,10,04,12,092,,21,06,292,29*73
                // But if the last SNR value is NULL, the device will skip the comma separator and
                // just append the checksum. For example, this sentence can occur if the SNR value for the last
                // satellite in the sentence is 0:
                //    PGSV,3,3,10,15,10,189,,13,00,033,*7F
                // The SNR value for the second satellite is NULL, but unlike the same condition with the first
                // satellite, the sentence does not include two commas with nothing between them (to indicate NULL).
                // All of that said, the line below handles the conversion properly.
                satSNR = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:(index+3)] floatValue]];
                
                // On random occasions, either the data is bad or the parsing fails. Handle any not-a-number conditions.
                if (isnan([satSNR floatValue]) != 0) satSNR = [NSNumber numberWithFloat:0.0];
                
                for (NSNumber *n in self.satsUsedInPosCalc)
                {
                    if ([n intValue] == [satNum intValue])
                    {
                        inUse = [NSNumber numberWithBool:YES];
                        break;
                    }
                }
                satInfo = [NSMutableArray arrayWithObjects:satAzi, satElev, satSNR, inUse, nil];
                
                [self.dictOfSatInfo setObject:satInfo forKey:satNum];
            }
            
            // It can take multiple PGSV sentences to deliver all of the satellite data. Update the UI after
            // the last of the data arrives. If the current PGSV sentence number (2nd element in the sentence)
            // is equal to the total number of PGSV messages (1st element in the sentence), that means you have received
            // the last of the satellite data.
            if ([[elementsInSentence objectAtIndex:2] intValue] == [[elementsInSentence objectAtIndex:1] intValue])
            {
                // print the captured data
                if (DEBUG_PGSV_INFO)
                {
                    NSMutableArray *satNums, *satData;
                    satNums = [NSMutableArray arrayWithArray:[_dictOfSatInfo allKeys]];
                    
                    // sort the array of satellites in numerical order
                    NSSortDescriptor *sorter = [[NSSortDescriptor alloc] initWithKey:@"intValue" ascending:YES];
                    [satNums sortUsingDescriptors:[NSArray arrayWithObject:sorter]];
                    
                    for (int i=0; i<[satNums count]; i++)
                    {
                        satData = [self.dictOfSatInfo objectForKey:[satNums objectAtIndex:i]];
                        NSLog(@"%s. SatNum=%d. Elev=%d. Azi=%d. SNR=%d. inUse=%@", __FUNCTION__,
                              [[satNums objectAtIndex:i] intValue],
                              [[satData objectAtIndex:0] intValue],
                              [[satData objectAtIndex:1] intValue],
                              [[satData objectAtIndex:2] intValue],
                              ([[satData objectAtIndex:3] boolValue])?@"Yes":@"No");
                    }
                }
                
                // Post a notification to the view controllers that the satellite data has been updated
                NSNotification *satDataUpdated = [NSNotification notificationWithName:@"SatelliteDataUpdated" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:satDataUpdated];
            }
        }
    }
    else if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PGSA"])
    {
        // Case 4: parse the dilution of precision info. Sentence will look like:
        //		eg1. PGSA,A,1,,,,,,,,,,,,,0.0,0.0,0.0*30
        //		eg2. PGSA,A,3,24,14,22,31,11,,,,,,,,3.7,2.3,2.9*3D
        //
        // Skytraq chipset:
        // e.g. PGSA,A,1,,,,,,,,,,,,,0.0,0.0,0.0*30     (no signal)
        //
        // uBlox chipset:
        // e.g. PGSA,A,1,,,,,,,,,,,,,99.99,99.99,99.99*30      (no signal)
        //      PGSA,A,3,02,29,13,12,48,10,25,05,,,,,3.93,2.06,3.35*0D
        
        /* Wikipedia (http://en.wikipedia.org/wiki/Dilution_of_precision_(GPS)) has a good synopsis on how to interpret
         DOP values:
         
         DOP Value	Rating		Description
         ---------	---------	----------------------
         1			Ideal		This is the highest possible confidence level to be used for applications demanding
         the highest possible precision at all times.
         1-2		Excellent	At this confidence level, positional measurements are considered accurate enough to meet
         all but the most sensitive applications.
         2-5		Good		Represents a level that marks the minimum appropriate for making business decisions.
         Positional measurements could be used to make reliable in-route navigation suggestions to
         the user.
         5-10		Moderate	Positional measurements could be used for calculations, but the fix quality could still be
         improved. A more open view of the sky is recommended.
         10-20		Fair		Represents a low confidence level. Positional measurements should be discarded or used only
         to indicate a very rough estimate of the current location.
         >20		Poor		At this level, measurements are inaccurate by as much as 300 meters and should be discarded.
         
         */
        
        if (DEBUG_PGSA_INFO)
        {
            NSLog(@"%s. sentence contains DOP info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s.", __FUNCTION__, pLine);
        }
        
        if ([elementsInSentence count] < 18) return;    // malformed sentence
        
        // extract whether the fix type is 0=no fix, 1=2D fix or 2=3D fix
        self.fixType = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:2] intValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. fix value = %d.", __FUNCTION__, [self.fixType intValue]);
        
        // extract PDOP
        self.pdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:15] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. PDOP value = %f.", __FUNCTION__, [self.pdop floatValue]);
        
        // extract HDOP
        self.hdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:16] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. HDOP value = %f.", __FUNCTION__, [self.hdop floatValue]);
        
        // extract VDOP
        self.vdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:17] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. VDOP value = %f.", __FUNCTION__, [self.vdop floatValue]);
        
        // extract the number of satellites used in the position fix calculation
        NSString *satInDOP;
        NSMutableArray *satsInDOPCalc = [[NSMutableArray alloc] init];
        self.waasInUse = NO;
        for (int i=3; i<15; i++)
        {
            satInDOP = [elementsInSentence objectAtIndex:i];
            if ([satInDOP length] > 0)
            {
                [satsInDOPCalc addObject:satInDOP];
                if ([satInDOP intValue] > 32) self.waasInUse = YES;
            }
            satInDOP = nil;
        }
        self.numOfSatInUse = [NSNumber numberWithUnsignedInteger:[satsInDOPCalc count]];
        self.satsUsedInPosCalc = satsInDOPCalc;
        
        if (DEBUG_PGSA_INFO)
        {
            NSLog(@"%s. # of satellites used in DOP calc: %d", __FUNCTION__, [self.numOfSatInUse intValue]);
            NSMutableString *logTxt = [NSMutableString stringWithString:@"Satellites used in DOP calc: "];
            for (NSString *s in self.satsUsedInPosCalc)
            {
                [logTxt appendFormat:@"%@, ", s];
            }
            NSLog(@"%s. %@", __FUNCTION__, logTxt);
        }
        
        satsInDOPCalc = nil;
    }
    else if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PRMC"])
    {
        // Case 6: extract whether the speed and course data are valid, as well as magnetic deviation
        //		eg1. PRMC,220316.000,V,2845.7226,N,08121.9825,W,000.0,000.0,220311,,,N*65
        //		eg2. PRMC,220426.988,A,2845.7387,N,08121.9957,W,000.0,246.2,220311,,,A*7C
        //
        // Skytraq chipset:
        // e.g. PRMC,120138.000,V,0000.0000,N,00000.0000,E,000.0,000.0,280606,,,N*75   (no signal)
        //
        //
        // uBlox chipset:
        // e.g. PRMC,,V,,,,,,,,,,N*53      (no signal)
        //      PRMC,162409.00,A,2845.73357,N,08121.99127,W,0.911,39.06,281211,,,D*4D
        
        if (DEBUG_PRMC_INFO)
        {
            NSLog(@"%s. sentence contains speed & course info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s.", __FUNCTION__, pLine);
        }
        
        if ([elementsInSentence count] < 9) return;     // malformed sentence
        
        // extract the time the coordinate was captured. UTC time format is hhmmss.sss
        NSString *timeStr, *hourStr, *minStr, *secStr;
        
        timeStr = [elementsInSentence objectAtIndex:1];
        // Check for malformed data. NMEA 0183 spec says minimum 2 decimals for seconds: hhmmss.ss
        if ([timeStr length] < 9) return;   // malformed data
        
        hourStr = [timeStr substringWithRange:NSMakeRange(0,2)];
        minStr = [timeStr substringWithRange:NSMakeRange(2,2)];
        secStr = [timeStr substringWithRange:NSMakeRange(4,5)];
        self.utc = [NSString stringWithFormat:@"%@:%@:%@", hourStr, minStr, secStr];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. UTC Time is %@.", __FUNCTION__, self.utc);
        
        // is the track and course data valid? An "A" means yes, and "V" means no.
        NSString *valid = [elementsInSentence objectAtIndex:2];
        if ([valid isEqualToString:@"A"]) self.speedAndCourseIsValid = YES;
        else self.speedAndCourseIsValid = NO;
        if (DEBUG_PRMC_INFO) NSLog(@"%s. speed & course data valid: %d.", __FUNCTION__, self.speedAndCourseIsValid);
        
        // extract latitude info
        // ex:	"4124.8963, N" which equates to 41d 24.8963' N or 41d 24' 54" N
        float mins;
        int deg, sign = 0;
        double lat, lon;
        
        if ([[elementsInSentence objectAtIndex:3] length] == 0)
        {
            // uBlox chip special case
            deg = 0;
            mins = 0.0;
        }
        // Check for corrupted data. The NMEA spec says latitude needs at least 4 digits in front of the decimal, and 2 after.
        else if ([[elementsInSentence objectAtIndex:3] length] < 7) return;
        else
        {
            sign = 1;
            lat = [[elementsInSentence objectAtIndex:3] doubleValue];
            if (DEBUG_PRMC_INFO) NSLog(@"latitude text = %@. converstion to float = %f.", [elementsInSentence objectAtIndex:3], lat);
            deg = (int)(lat / 100);
            mins = (lat - (100 * (float)deg)) / 60.0;
            if (DEBUG_PRMC_INFO) NSLog(@"degrees = %d. mins = %.5f.", deg, mins);
            
            if ([[elementsInSentence objectAtIndex:4] isEqualToString:@"S"]) sign = -1;   // capture the "N" or "S"
        }
        self.lat = [NSNumber numberWithFloat:(deg + mins)*sign];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. latitude = %.5f", __FUNCTION__, [self.lat floatValue]);
        
        // extract longitude info
        // ex: "08151.6838, W" which equates to	81d 51.6838' W or 81d 51' 41" W
        if ([[elementsInSentence objectAtIndex:5] length] == 0)
        {
            // uBlox chip special case
            deg = 0;
            mins = 0.0;
        }
        // Check for corrupted data. The NMEA spec says latitude needs at least 5 digits in front of the decimal, and 2 after.
        else if ([[elementsInSentence objectAtIndex:3] length] < 8) return;
        else
        {
            sign = 1;
            lon = [[elementsInSentence objectAtIndex:5] doubleValue];
            if (DEBUG_PRMC_INFO) NSLog(@"longitude text = %@. converstion to float = %f.", [elementsInSentence objectAtIndex:5], lon);
            deg = (int)(lon / 100);
            mins = (lon - (100 * (float)deg)) / 60.0;
            if (DEBUG_PRMC_INFO) NSLog(@"degrees = %d. mins = %.5f.", deg, mins);
            
            if ([[elementsInSentence objectAtIndex:6] isEqualToString:@"W"]) sign = -1;   // capture the "E" or "W"
        }
        self.lon = [NSNumber numberWithFloat:(deg + mins)*sign];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. longitude = %.5f", __FUNCTION__, [self.lon floatValue]);
        
        // Pull the speed information from the RMC sentence since this updates at the fast refresh rate in the Skytraq chipset
        if ([[elementsInSentence objectAtIndex:7] isEqualToString:@""]) self.speedKnots = [NSNumber numberWithFloat:0.0];
        else self.speedKnots = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:7] floatValue]];
        self.speedKph = [NSNumber numberWithFloat:([self.speedKnots floatValue] * 1.852)];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. knots = %.1f. kph = %.1f.", __FUNCTION__, [_speedKnots floatValue], [_speedKph floatValue]);
        
        // Extract the course heading
        if ([[elementsInSentence objectAtIndex:8] isEqualToString:@""]) self.trackTrue = [NSNumber numberWithFloat:0.0];
        else self.trackTrue = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:8] floatValue]];
        if (DEBUG_PVTG_INFO) NSLog(@"%s. true north course = %.1f.", __FUNCTION__, [_trackTrue floatValue]);
        
        // trigger a notification to the view controllers that the satellite data has been updated
        NSNotification *posDataUpdated = [NSNotification notificationWithName:@"PositionDataUpdated" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:posDataUpdated];
    }
    else if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PVTG"])
    {
        // Case 5: parse the speed and course info. Sentence will look like:
        //		eg1. PVTG,304.5,T,,M,002.3,N,004.3,K,N*06
        //
        // Skytraq chipset:
        // e.g. PVTG,000.0,T,,M,000.0,N,000.0,K,N*02      (no signal)
        //
        // uBlox chipset:
        // e.g. PVTG,,,,,,,,,N*30      (no signal)
        //      PVTG,45.57,T,,M,0.550,N,1.019,K,D*02
        
        if (DEBUG_PVTG_INFO)
        {
            NSLog(@"%s. PVTG sentence contains speed & course info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s.", __FUNCTION__,  pLine);
        }
    }
    else if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PGLL"])
    {
        // Case 6: Latitude, longitude and time info. Only generated by the uBlox chipset, not the Skytraq chipset.
        // Sentence will look like:
        //      eg1. PGLL,3751.65,S,14507.36,E*77
        //      eg2. PGLL,4916.45,N,12311.12,W,225444,A
        //
        // uBlox chipset:
        // e.g. PGLL,,,,,,V,N*64      (no signal)
        //      PGLL,2845.73342,N,08121.99104,W,162408.00,A,D*72
        
        if (DEBUG_PGLL_INFO)
        {
            NSLog(@"%s. PGLL sentence with location info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s", __FUNCTION__, pLine);
        }
    }
    else
    {
        if (DEBUG_SENTENCE_PARSING)
        {
            NSLog(@"%s. Unknown sentence found: %s", __FUNCTION__, pLine);
        }
    }
    
} // parseGPS

- (void)parseGPS:(const char *)pLine length:(NSUInteger)len
{
    //    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    
    //    NSLog(@"%s", pLine);
    NSArray *elementsInSentence;
    
    // Determine which kind of sentence it is   @3Ä
 /*   if (strncmp((char *)pLine, "@", 1) == 0)
    {
        if (strncmp((char *)pLine, "@@XCFG", 6) == 0){
            NSLog(@"%s. XCFG sentence. buffer text: %s", __FUNCTION__, pLine);
            
            char sdk_value[3];
            sprintf( sdk_value, "%c%c", pLine[7], pLine[8]);
            some_sdkValue = hexStrToInt(sdk_value, 2);
            
            if( some_sdkValue & 0x40 ){
                [[CommonValue sharedSingleton] setPositionEnable:YES];
                [[CommonValue sharedSingleton] setPositionDisable:NO];
            } else{
                [[CommonValue sharedSingleton] setPositionDisable:YES];
                [[CommonValue sharedSingleton] setPositionEnable:NO];
            }
            
            if( some_sdkValue & 0x80 ){
                [[CommonValue sharedSingleton] setOverWrite:YES];
                [[CommonValue sharedSingleton] setStopRecode:NO];
            } else{
                [[CommonValue sharedSingleton] setStopRecode:YES];
                [[CommonValue sharedSingleton] setOverWrite:NO];
            }
            
            if( some_sdkValue & 0x10 )
                [self xgps160ReceiveType:1];
            else
                [self xgps160ReceiveType:0];
            
            char value1_InHex[5];
            sprintf(value1_InHex, "%c%c%c%c", pLine[9], pLine[10], pLine[11], pLine[12]);
            some_data1 = hexStrToInt(value1_InHex, 4);
            
            char value2_InHex[5];
            sprintf(value1_InHex, "%c%c%c%c", pLine[13], pLine[14], pLine[15], pLine[16]);
            some_data2 = hexStrToInt(value2_InHex, 4);
            
            NSLog(@" some data 1 = %d, some data 2 = %d", some_data1, some_data2);
            
            if( [CommonValue sharedSingleton].sdk_btn_flag_yes == YES ){
                [[CommonValue sharedSingleton] setSdk_btn_flag_yes:NO];
                [self set_use_sdk:1];
            }
            if( [CommonValue sharedSingleton].sdk_btn_flag_no == YES ){
                [[CommonValue sharedSingleton] setSdk_btn_flag_no:NO];
                [self set_use_sdk:0];
            }
        }
        
        // Case 1: parse the device info
        int vbat;
        float bvolt, batLevel;
        
        vbat = (unsigned char)pLine[1];
        vbat <<= 8;
        vbat |= (unsigned char)pLine[2];
        
        if (vbat < kVolt350)
            vbat = kVolt350;
        if (vbat > kVolt415)
            vbat = kVolt415;
        
        bvolt = (float)vbat * 330.0f / 512.0f;
        batLevel = ((bvolt / 100.0f) - 3.5f) / 0.65f;
        
        if (batLevel > 1.0)
            self.batteryVoltage = 1.0;
        else if (batLevel < 0)
            self.batteryVoltage = 0.0;
        else
            self.batteryVoltage = batLevel;
        
        if( pLine[5] & 0x04 )
            self.isCharging = YES;
        else
            self.isCharging = NO;
        
        // trigger a notification to the view controllers that the device data has been updated
        //        dispatch_async(dispatch_get_main_queue(), ^{
        NSNotification *puckDataUpdated = [NSNotification notificationWithName:@"PuckDataUpdated" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:puckDataUpdated];
        //        });
        return;
    }
    */
    
    // Break the data into an array of elements
    elementsInSentence = [[NSString stringWithCString:pLine encoding:NSASCIIStringEncoding] componentsSeparatedByString:@","];
    
    if ([[elementsInSentence objectAtIndex:0] length] != 4 || elementsInSentence == nil || [elementsInSentence count] == 0)
        return;
    
    // Parse the data based on the NMEA sentence identifier
    if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PGGA"])
    {
        // extract the altitude
        if ([elementsInSentence count] < 9)
            return;
        
        self.alt = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:9] floatValue]];
        if (self.alt < 0)
            self.alt = 0;
        
        // trigger a notification to the view controllers that the satellite data has been updated
        //        dispatch_async(dispatch_get_main_queue(), ^{
        NSNotification *satDataUpdated = [NSNotification notificationWithName:@"PositionDataUpdated" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:satDataUpdated];
        //        });
    }
    
    
    
    // 러시아 글로나스 위성 정보
    else if (strncmp((char *)pLine, "LGSV", 4) == 0){
        //NSLog(@"러샤위성 %s",pLine);
        
        if (self.dictOfSatInfoGlonass == nil)
            self.dictOfSatInfoGlonass = [[NSMutableDictionary alloc]init];
        
        self.numOfGLONASSSatInView = [NSNumber numberWithInteger:[[elementsInSentence objectAtIndex:3] intValue]];
        
        if (self.numOfGLONASSSatInView == 0)
        {
            if ([self.dictOfSatInfoGlonass count])
                [self.dictOfSatInfoGlonass removeAllObjects];
        }
        else{
            
            if ([[elementsInSentence objectAtIndex:2] intValue] == 1){
                
                if ([self.dictOfSatInfoGlonass count])
                    [self.dictOfSatInfoGlonass removeAllObjects];
            }
            
            NSNumber *satNum=0, *satElev=0, *satAzi=0, *satSNR=0, *inUse;
            
            
            // The number of satellites described in a sentence can vary up to 4.
            int numOfSatsInSentence;
            if ([elementsInSentence count] < 10)
                numOfSatsInSentence = 1;
            else if ([elementsInSentence count] < 14)
                numOfSatsInSentence = 2;
            else if ([elementsInSentence count] < 18)
                numOfSatsInSentence = 3;
            else
                numOfSatsInSentence = 4;
            
            for (int i=0; i<numOfSatsInSentence; i++)
            {
                if ([elementsInSentence count] <= i*4 + 4 +3)
                    break;
                
                int index = i*4 + 4;
                inUse = [NSNumber numberWithBool:NO];
                
                satNum = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:index] intValue]];
                satElev = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+1)] intValue]];
                satAzi = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+2)] intValue]];
                satSNR = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:(index+3)] floatValue]];
                
                // On random occasions, either the data is bad or the parsing fails. Handle any not-a-number conditions.
                if (isnan([satSNR floatValue]) != 0)
                    satSNR = [NSNumber numberWithFloat:0.0];
                
                for (NSNumber *n in self.satsUsedInPosCalcGlonass)
                {
                    if ([n intValue] == [satNum intValue])
                    {
                        inUse = [NSNumber numberWithBool:YES];
                        break;
                    }
                }
                
                [self.dictOfSatInfoGlonass setObject:@[satAzi, satElev, satSNR, inUse] forKey:satNum]; // 버그지점
                
                if ([[elementsInSentence objectAtIndex:(index+3)] rangeOfString:@"LGSV"].location != NSNotFound ||
                    [[elementsInSentence objectAtIndex:(index+3)] rangeOfString:@"PGSV"].location != NSNotFound  ||
                    [[elementsInSentence objectAtIndex:(index+3)] rangeOfString:@"PRMC"].location != NSNotFound)
                {
                    NSLog(@"감도값 이상");
                    break;
                }
            }
            
            // 마지막 센텐스라면..
            if ([[elementsInSentence objectAtIndex:2] intValue] == [[elementsInSentence objectAtIndex:1] intValue])
            {
                // Post a notification to the view controllers that the satellite data has been updated
                //                dispatch_async(dispatch_get_main_queue(), ^{
                NSNotification *satDataUpdated = [NSNotification notificationWithName:@"SatelliteDataUpdated" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:satDataUpdated];
                //                });
                
            }
        }
    }
    
    
    
    // 미쿡 GPS 위성
    else if (strncmp((char *)pLine, "PGSV", 4) == 0)
    {
        self.numOfSatInView = [NSNumber numberWithInteger:[[elementsInSentence objectAtIndex:3] intValue]];
        
        if (self.dictOfSatInfo == nil)
            self.dictOfSatInfo = [[NSMutableDictionary alloc]init];
        
        if (self.numOfSatInView == 0)
        {
            if ([self.dictOfSatInfo count])
                [self.dictOfSatInfo removeAllObjects];
        }
        else
        {
            if ([[elementsInSentence objectAtIndex:2] intValue] == 1){
                if ([self.dictOfSatInfo count])
                    [self.dictOfSatInfo removeAllObjects];
            }
            NSNumber *satNum=0, *satElev=0, *satAzi=0, *satSNR=0, *inUse;
            
            // The number of satellites described in a sentence can vary up to 4.
            int numOfSatsInSentence;
            if ([elementsInSentence count] < 10)
                numOfSatsInSentence = 1;
            else if ([elementsInSentence count] < 14)
                numOfSatsInSentence = 2;
            else if ([elementsInSentence count] < 18)
                numOfSatsInSentence = 3;
            else
                numOfSatsInSentence = 4;
            
            
            for (int i=0; i<numOfSatsInSentence; i++)
            {
                if ([elementsInSentence count] <= i*4 + 4 +3)
                    break;
                
                int index = i*4 + 4;
                inUse = [NSNumber numberWithBool:NO];
                
                satNum = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:index] intValue]];
                satElev = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+1)] intValue]];
                satAzi = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+2)] intValue]];
                satSNR = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:(index+3)] floatValue]];
                
                if (isnan([satSNR floatValue]) != 0)
                    satSNR = [NSNumber numberWithFloat:0.0];
                
                for (NSNumber *n in self.satsUsedInPosCalc)
                {
                    if ([n intValue] == [satNum intValue])
                    {
                        inUse = [NSNumber numberWithBool:YES];
                        break;
                    }
                }
                
                [self.dictOfSatInfo setObject:@[satAzi, satElev, satSNR, inUse] forKey:satNum]; //버그지점
                
                if ([[elementsInSentence objectAtIndex:(index+3)] rangeOfString:@"LGSV"].location != NSNotFound  ||
                    [[elementsInSentence objectAtIndex:(index+3)] rangeOfString:@"PGSV"].location != NSNotFound  ||
                    [[elementsInSentence objectAtIndex:(index+3)] rangeOfString:@"PRMC"].location != NSNotFound)
                {
                    NSLog(@"감도값 이상으로 브레이크 ");
                    break;
                }
            }
            //            if ([[elementsInSentence objectAtIndex:2] intValue] == [[elementsInSentence objectAtIndex:1] intValue])
            //            {
            //
            //            }
        }
    }
    
    else if (strncmp((char *)pLine, "NGSA", 4) == 0){
        
        // 러샤위성 감도 평균값
        if ([elementsInSentence count] != 18 ) {
            elementsInSentence = [[NSArray alloc]initWithObjects:@"",@"",@"",@"",@"",
                                   @"",@"",@"",@"",@"",    @"",@"",@"",@"",@"",
                                   @"",@"",@"", nil];
        }
        // extract whether the fix type is 0=no fix, 1=2D fix or 2=3D fix
        self.fixType = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:2] intValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. fix value = %d.", __FUNCTION__, [self.fixType intValue]);
        
        // extract PDOP
        self.pdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:15] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. PDOP value = %f.", __FUNCTION__, [self.pdop floatValue]);
        
        // extract HDOP
        self.hdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:16] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. HDOP value = %f.", __FUNCTION__, [self.hdop floatValue]);
        
        // extract VDOP
        self.vdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:17] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. VDOP value = %f.", __FUNCTION__, [self.vdop floatValue]);
        
        
        
        
        
        // extract the number of satellites used in the position fix calculation
        
        
        // 위성 감도 평균값 내가 위한...
        NSString *satInDOP;
        NSMutableArray *satsInDOPCalc = [[NSMutableArray alloc] init];
        for (int i=3; i<15; i++)
        {
            satInDOP = [elementsInSentence objectAtIndex:i];
            if ([satInDOP length] > 0)
                [satsInDOPCalc addObject:satInDOP];
            satInDOP = nil;
        }
        self.numOfGLONASSSatInUse = [NSNumber numberWithUnsignedInteger:[satsInDOPCalc count]];
        self.satsUsedInPosCalcGlonass = satsInDOPCalc;
        
        satsInDOPCalc = nil;
    }
    else if (strncmp((char *)pLine, "PGSA", 4) == 0)
    {
        // 미국위성 감도 평균값
        
        if ([elementsInSentence count] != 18 ) {
            elementsInSentence = [[NSArray alloc]initWithObjects:@"",@"",@"",@"",@"",
                                  @"",@"",@"",@"",@"",    @"",@"",@"",@"",@"",
                                  @"",@"",@"", nil];
        }
        
        // extract whether the fix type is 0=no fix, 1=2D fix or 2=3D fix
        self.fixType = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:2] intValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. fix value = %d.", __FUNCTION__, [self.fixType intValue]);
        
        // extract PDOP
        self.pdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:15] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. PDOP value = %f.", __FUNCTION__, [self.pdop floatValue]);
        
        // extract HDOP
        self.hdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:16] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. HDOP value = %f.", __FUNCTION__, [self.hdop floatValue]);
        
        // extract VDOP
        self.vdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:17] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. VDOP value = %f.", __FUNCTION__, [self.vdop floatValue]);
        
        
        // extract the number of satellites used in the position fix calculation
        
        
        // 위성 감도 평균값 내가 위한...
        NSString *satInDOP;
        NSMutableArray *satsInDOPCalc = [[NSMutableArray alloc] init];
        self.waasInUse = NO;
        for (int i=3; i<15; i++)
        {
            satInDOP = [elementsInSentence objectAtIndex:i];
            
            if ([satInDOP length] > 0)
                [satsInDOPCalc addObject:satInDOP];
            if ([satInDOP intValue] > 32) self.waasInUse = YES;
            satInDOP = nil;
        }
        self.numOfSatInUse = [NSNumber numberWithUnsignedInteger:[satsInDOPCalc count]];
        self.satsUsedInPosCalc = satsInDOPCalc;
        
        if (DEBUG_PGSA_INFO)
        {
            NSLog(@"%s. # of satellites used in DOP calc: %d", __FUNCTION__, [self.numOfSatInUse intValue]);
            NSMutableString *logTxt = [NSMutableString stringWithString:@"Satellites used in DOP calc: "];
            for (NSString *s in self.gpsSatsUsedInPosCalc)
            {
                [logTxt appendFormat:@"%@, ", s];
            }
            NSLog(@"%s. %@", __FUNCTION__, logTxt);
        }
        satsInDOPCalc = nil;
    }
    else if (strncmp((char *)pLine, "PRMC", 4) == 0)
    {
        if ([elementsInSentence count] != 13)
        {
            elementsInSentence = [[NSArray alloc]initWithObjects:@"",@"",@"",@"",@"",
                                   @"",@"",@"",@"",@"",    @"",@"",@"",nil];
        }
        
        if ([[elementsInSentence objectAtIndex:1] length] == 0)
        {
            self.utc = @"-----";
        }
        else
        {
            NSString *timeStr=@"", *hourStr=@"", *minStr=@"", *secStr=@"";
            timeStr = [elementsInSentence objectAtIndex:1];
            // 예외처리
            if ([timeStr length] != 10) {
                hourStr = [NSString stringWithFormat:@""];
                minStr = [NSString stringWithFormat:@""];
                secStr = [NSString stringWithFormat:@""];
            }
            else{
                hourStr = [timeStr substringWithRange:NSMakeRange(0,2)];
                minStr = [timeStr substringWithRange:NSMakeRange(2,2)];
                secStr = [timeStr substringWithRange:NSMakeRange(4,5)];
            }
            self.utc = [NSString stringWithFormat:@"%@:%@:%@", hourStr, minStr, secStr];
        }
        
        // is the track and course data valid? An "A" means yes, and "V" means no.
        NSString *valid = [elementsInSentence objectAtIndex:2];
        if ([valid isEqualToString:@"A"])
            self.speedAndCourseIsValid = YES;
        else
            self.speedAndCourseIsValid = NO;
        
        
        // extract latitude info
        // ex:    "4124.8963, N" which equates to 41d 24.8963' N or 41d 24' 54" N
        
        float mins=0;
        int deg=0, offset=0;
        NSString *dir = @"-";
        const char *cString;
        double lat=0, lon=0;
        char *decimalPos;
        
        if ([[elementsInSentence objectAtIndex:3] length] == 0)
        {
            // uBlox chip special case
            deg = 0;
            mins = 0.0;
        }
        else
        {
            cString = [[elementsInSentence objectAtIndex:3] UTF8String];
            lat = atof(cString);
            deg = (int)(lat / 100);
            
            decimalPos = strchr(cString, '.');        // find the decimal point
            offset = (int) (decimalPos - cString - 2);          // move the string point back two places from the decimal
            cString += offset;
            mins = atof(cString);                           // convert the shortened string to a float
            
            // capture the "N" or "S"
            dir = [NSString stringWithFormat:@"%@", [elementsInSentence objectAtIndex:4]];
        }
        
        // self.latDegMinDir  초기화
        [self.latDegMinDir setArray:@[[NSNumber numberWithInt:deg],[NSNumber numberWithFloat:mins], dir]];
        if (DEBUG_PRMC_INFO) NSLog(@"degrees = %d. mins = %.5f.", deg, mins);

        int sign = 1;
        if ([dir isEqualToString:@"S"]) sign = -1;   // capture the "N" or "S"
        self.lat = [NSNumber numberWithFloat:(deg + mins / 60.0) * sign];
        
        
        deg = 0;
        mins = 0.0;
        dir = @"-";
        // extract longitude info
        // ex: "08151.6838, W" which equates to    81d 51.6838' W or 81d 51' 41" W
        if ([[elementsInSentence objectAtIndex:5] length] == 0)
        {
            // uBlox chip special case
            deg = 0;
            mins = 0.0;
        }
        else
        {
            cString = [[elementsInSentence objectAtIndex:5] UTF8String];
            lon = atof(cString);
            deg = (int)(lon / 100);
            
            decimalPos = strchr(cString, '.');          // find the decimal point
            offset = (int) (decimalPos - cString - 2);          // move the string point back two places from the decimal
            cString += offset;
            mins = atof(cString);                       // convert the shortened string to a float
            
            dir = [NSString stringWithFormat:@"%@", [elementsInSentence objectAtIndex:6]];        // capture the "E" or "W"
        }
        
        // self.latDegMinDir  초기화
        [self.lonDegMinDir setArray:@[[NSNumber numberWithInt:deg],[NSNumber numberWithFloat:mins], dir]];
        
        sign = 1;
        if ([dir isEqualToString:@"W"]) sign = -1;   // capture the "N" or "S"
        self.lon = [NSNumber numberWithFloat:(deg + mins / 60.0) * sign];
        
        // Pull the speed information from the RMC sentence since this updates at the fast refresh rate in the Skytraq chipset
        if ([[elementsInSentence objectAtIndex:7] isEqualToString:@""])
            self.speedKnots = 0;
        
        else
            self.speedKnots = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:7] floatValue]];
        
        self.speedKph = @([self.speedKnots doubleValue] * 1.852);
        
        // Extract the magnetic deviation values. Easterly deviation subtracts from true course.
        NSNumber *magDev = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:10] floatValue]];
        
        NSString *devDir = [elementsInSentence objectAtIndex:11];
        
        if ([devDir isEqualToString:@"E"])
            self.trackMag = [NSNumber numberWithFloat:(self.trackTrue.floatValue - magDev.floatValue)];
        else
            self.trackMag = [NSNumber numberWithFloat:(self.trackTrue.floatValue + magDev.floatValue)];
        
        
        // 헤딩 처리
        
        // extract the true north course
        if ([[elementsInSentence objectAtIndex:8] isEqualToString:@""])
            self.trackTrue = 0;
        else
            self.trackTrue = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:8] floatValue]];
        
        // create the location data required by the mapkit view
        // 주석처리함
        //[self makeLocationCoords];
    }
    //    else if (strncmp((char *)pLine, "PVTG", 4) == 0)
    //    {
    //    }
    //    else if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PGLL"])
    //    {
    //    }
    //    else
    //    {
    //    }
    //        });
}

#pragma mark - Application lifecycle methods
- (void)observeNotifications
{
    NSLog(@"observeNotifications");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueConnectNotifications:)
                                                 name:EAAccessoryDidConnectNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDisconnectNotifications:)
                                                 name:EAAccessoryDidDisconnectNotification
                                               object:nil];
    
    // Register for notifications from the iOS that accessories are connecting or disconnecting
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
}

- (void)stopObservingNotifications
{
    NSLog(@"stopObservingNotifications");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:EAAccessoryDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:EAAccessoryDidDisconnectNotification object:nil];
    [[EAAccessoryManager sharedAccessoryManager] unregisterForLocalNotifications];
}

- (id)init
{
    if ((self = [super init]))
    {
        self.isConnected = NO;
        self.firmwareRev = @"";
        self.serialNumber = @"";
        self.batteryVoltage = 0;
        self.isCharging = NO;
        self.streamingMode = YES;
        self.queueTimerStarted = NO;    // ????? 
          
        self.logListEntries = [[NSMutableArray alloc] init];
        self.logDataSamples = [[NSMutableArray alloc] init];
        
        self.logListItemTimerStarted = NO;
        self.newLogListItemReceived = NO;
        
        self.deviceSettingsHaveBeenRead = NO;
        commandQueue = [NSMutableArray new];
        
        totalGPSSamplesInLogEntry = 0;
        // Watch for local accessory connect & disconnect notifications.
        [self observeNotifications];
        
        // Check to see if device is attached.
        if ([self isPuckAnAvailableAccessory]) [self openSession];
    }
    return self;
} // init

#pragma mark - BT Connection Management Methods
#pragma mark • Application lifecycle methods

- (void)puck_applicationWillResignActive
{
    /*
     Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
     Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
     */
    
    // NOTE: this method is called when:
    //		- when a dialog box (like an alert view) opens.
    //		- by a double-tap on the home button to bring up the multitasking menu
    //		- when the iPod/iPad/iPhone goes to sleep (manually or after the timer runs out)
    //		- when app exits becuase the home button is tapped (once)
    
    // Close any open streams. The OS sends a false "Accessory Disconnected" message when the home button is double tapped
    // to bring up the mutitasking menu. So the safest thing is to disconnect from the XGPS150/XGPS160 when that happens, and reconnect
    // later.
    [self closeSession];
    
    // stop watching for Accessory notifications
    [self stopObservingNotifications];
}


- (void)puck_applicationDidEnterBackground
{
    // NOTE: this method is called when:
    //		- another app takes forefront.
    //		- after applicationWillResignActive in response to the home button is tapped (once)
    
    // Close any open streams
    isBackground = true;
    @synchronized (self) {
        [self closeSession];
    }
    
    // stop watching for Accessory notifications
//    [self stopObservingNotifications];
}

- (void)puck_applicationWillEnterForeground
{
    // Called as part of the transition from the background to the inactive state: here you can undo many of the changes
    // made on entering the background.
    
    // NOTE: this method is called:
    //		- when an app icon is already running in the background, and the app icon is clicked to resume the app
    
    // Begin watching for Accessory notifications again. Do this first because the rest of the method may complete before
    // the accessory reconnects.
    isBackground = false;
    //    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
    
    // Recheck to see if the puck disappeared while away
    @synchronized (self) {
        NSLog(@"puck_applicationWillEnterForeground %d", self.isConnected);
        // Delay execution of my block for 10 seconds.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!isBackground) {
                if ([self isPuckAnAvailableAccessory] == YES)
                    [self openSession];
            }
        });
    }
}

- (void)puck_applicationDidBecomeActive
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive.
    // If the application was previously in the background, optionally refresh the user interface.
    
    // NOTE: this method is called:
    //		- when an app first opens
    //		- when an app is running & the iPod/iPad/iPhone goes to sleep and is then reawoken, e.g. when the app is
    //		  running->iPod/iPad/iPhone goes to sleep (manually or by the timer)->iPod/iPad/iPhone is woken up & resumes the app
    //		- when the app is resumed from when the multi-tasking menu is opened (in the scenario where the
    //		  app was running, the multitasking menu opened by a double-tap of the home button, followed by a tap on the screen to
    //		  resume the app.)
    
    // begin watching for Accessory notifications again
    [self observeNotifications];
    
    // Recheck to see if the XGPS150/XGPS160 disappeared while away
    if (self.isConnected == NO)
    {
        if ([self isPuckAnAvailableAccessory]) [self openSession];
    }
    
    // NOTE: if the iPod/iPad/iPhone goes to sleep while a view controller is open, there is no notification
    // that the app is back to life, other than this applicationDidBecomeActive method being called. The viewWillAppear,
    // viewDidAppear, or viewDidOpen methods are not triggered when the iPod/iPad/iPhone is woken and the app resumes.
    // Consequently, notify the view controllers in case they need to adjust their UI if the XGPS150/XGPS160 status changed
    // while the iPod/iPad/iPhone was asleep.
    NSNotification *notification = [NSNotification notificationWithName:@"RefreshUIAfterAwakening" object:self];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)puck_applicationWillTerminate
{
    // Called when the application is about to terminate. See also applicationDidEnterBackground:.
    
    // Close session with XGPS150/XGPS160
    [self closeSession];
    
    // stop watching for Accessory notifications
    [self stopObservingNotifications];
}

#pragma mark • Session Management Methods
// open a session with the accessory and set up the input and output stream on the default run loop
- (bool)openSession
{
    NSLog(@"openSession");
    if (self.isConnected) return YES;
    
    [self.accessory setDelegate:self];
    self.session = [[EASession alloc] initWithAccessory:self.accessory forProtocol:self.protocolString];
    
    if (self.session)
    {
        [[self.session inputStream] setDelegate:self];
        [[self.session inputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[self.session inputStream] open];
        
        [[self.session outputStream] setDelegate:self];
        [[self.session outputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[self.session outputStream] open];
        
        self.isConnected = YES;
    }
    else
    {
        //NSLog(@"Session creation failed");
        self.accessory = nil;
        self.accessoryConnectionID = 0;
        self.protocolString = nil;
    }
    
    return (self.session != nil);
    
}

// close the session with the accessory.
- (void)closeSession
{
    // Closing the streams and releasing session disconnects the app from the XGPS150/XGPS160, but it does not disconnect
    // the XGPS150/XGPS160 from Bluetooth. In other words, the communication streams close, but the device stays
    // registered with the OS as an available accessory.
    //
    // The OS can report that the device has disconnected in two different ways: either that the stream has
    // ended or that the device has disconnected. Either event can happen first, so this method is called
    // in response to a NSStreamEndEventEncountered (from method -stream:handlevent) or in response to an
    // EAAccessoryDidDisconnectNotification (from method -accessoryDisconnected). It seems that the speed of
    // the Apple device being used, e.g. iPod touch gen vs. iPad, affects which event occurs first.
    // Turning off the power on the XGPS150/XGPS160 tends to cause the NSStreamEndEventEncountered to occur
    // before the EAAccessoryDidDisconnectNotification.
    //
    // Note also that a EAAccessoryDidDisconnectNotification is generated when the home button
    // is tapped (bringing up the multitasking menu) beginning in iOS 5.
    
//    if (self.session == nil) return;
//
//    [[self.session inputStream] removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
//    [[self.session inputStream] close];
//    [[self.session inputStream] setDelegate:nil];
//
//    [[self.session outputStream] removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
//    [[self.session outputStream] close];
//    [[self.session outputStream] setDelegate:nil];
//
//    self.session = nil;
//    self.isConnected = NO;
//
//    self.accessory = nil;
//    self.accessoryConnectionID = 0;
//    self.protocolString = nil;
    
    if (_session == nil)
        return;
    NSLog(@"closeSession");
    [[_session inputStream] close];
    [[_session inputStream] removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [[_session inputStream] setDelegate:nil];
    
    [[_session outputStream] close];
    [[_session outputStream] removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [[_session outputStream] setDelegate:nil];
    
    //    [_session release];
        _session = nil;
//    ReleaseObject(_session);
    self.isConnected = NO;
    [commandQueue removeAllObjects];
    
//    [self setupPuck:nil withProtocolString:nil];
}

// initialize the accessory with the protocolString
- (void)setupPuck:(EAAccessory *)accessory withProtocolString:(NSString *)protocolString
{
    //    [_accessory release];
//    _accessory = [accessory retain];
//    _accessory = nil;
    self.firmwareRev = NULL;
    self.serialNumber = NULL;
    self.accessory = nil;
    self.accessoryConnectionID = 0;
    self.protocolString = nil;
    //    [_protocolString release];
    _protocolString = [protocolString copy];
}

- (bool)isPuckAnAvailableAccessory
{
    bool	connect = NO;
    
    if (self.accessory != nil && self.accessory.isConnected)    return YES;
    self.isConnected = NO;
//    if (self.isConnected) return YES;
    
    // get the list of all attached accessories (30-pin or bluetooth)
    NSArray *attachedAccessories = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    
    for (EAAccessory *obj in attachedAccessories)
    {
        if ([[obj protocolStrings] containsObject:@"com.dualav.xgps150"])
        {
            // At this point, the XGPS150/XGPS160 has a BT connection to the iPod/iPad/iPhone, but the
            // communication streams have not been opened yet
            connect = YES;
            self.firmwareRev = [NSString stringWithString:[obj firmwareRevision]];
            self.serialNumber = [NSString stringWithString:[obj serialNumber]];
            if (self.serialNumber.length < 1) {
                self.serialNumber = obj.name;
            }
            
            self.accessory = obj;
            self.accessoryConnectionID = obj.connectionID;
            self.protocolString = @"com.dualav.xgps150";
        }
    }
    
    if (!connect)
    {
        //NSLog(@"%s. XGPS150/160 NOT detected.", __FUNCTION__);
        self.firmwareRev = NULL;
        self.serialNumber = NULL;
        
        self.accessory = nil;
        self.accessoryConnectionID = 0;
        self.protocolString = nil;
    }
    return connect;
}

#pragma mark • Accessory watchdog methods
/* When the XGPS150/XGPS160 connects after being off, the iOS generates a very rapid seqeunce of
 connect-disconnect-connect events. The solution is wait until all of the notifications have
 come in, and process the last one.
 */
- (void)processConnectionNotifications
{
    _queueTimerStarted = NO;
    
    if (self.notificationType)   // last notification was to connect
    {
        if ([self isPuckAnAvailableAccessory] == YES)
        {
            if ([self openSession] == YES)
            {
                // Notify the view controllers that the XGPS150/XGPS160 is connected and streaming data
                NSNotification *notification = [NSNotification notificationWithName:@"DeviceConnected" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:notification];
            }
        }
    }
    else    // last notification was a disconnect
    {
        // The iOS can send a false disconnect notification when the home button is double-tapped
        // to enter the multitasking menu. So in the event of a EAAccessoryDidDisconnectNotification, double
        // check that the device is actually gone before disconnecting from the XGPS150/XGPS160.
        if (self.accessory.connected == YES) return;
        else
        {
            [self closeSession];
            
            // Notify the view controllers that the XGPS150/XGPS160 disconnected
            NSNotification *notification = [NSNotification notificationWithName:@"DeviceDisconnected" object:self];
            [[NSNotificationCenter defaultCenter] postNotification:notification];
        }
    }
    
}

- (void)queueDisconnectNotifications:(NSNotification *)notification
{
    // Make sure it was the XGPS150/XGPS160 that disconnected
    if (self.accessory == nil)       // XGPS150/160 not connected
    {
        return;
    }
    
    EAAccessory *eak = [[notification userInfo] objectForKey:EAAccessoryKey];
    if (eak.connectionID != self.accessoryConnectionID)  // wasn't the XGPS150/160 that disconnected
    {
        return;
    }
    
    // It was an XGPS150/160 that disconnected
    self.mostRecentNotification = notification;
    self.notificationType = NO;
    
    if (_queueTimerStarted == NO)
    {
        [self performSelector:@selector(processConnectionNotifications) withObject:nil afterDelay:kProcessTimerDelay];
        _queueTimerStarted = YES;
    }
}

- (void)queueConnectNotifications:(NSNotification *)notification
{
    // Make sure it was the XGPS150/160 that connected
    EAAccessory *eak = [[notification userInfo] objectForKey:EAAccessoryKey];
    if ([[eak protocolStrings] containsObject:@"com.dualav.xgps150"])       // yes, an XGPS150/160 connected
    {
        self.mostRecentNotification = notification;
        self.notificationType = YES;
        
        if (_queueTimerStarted == NO)
        {
            [self performSelector:@selector(processConnectionNotifications) withObject:nil afterDelay:kProcessTimerDelay];
            _queueTimerStarted = YES;
        }
    }
    else        // It wasn't an XGPS150/160 that connected, or the correct protocols weren't included in the connect notification.
        // Note: it is normal for no protocols to be included in the first accessory connection notification. It's a iOS thing.
    {
        return;
    }
}
@end
