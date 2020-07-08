
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

 Version 1.5.
 Licensed under the terms of the BSD License, as specified below.
 - switched to the RMC sentence for reading lat/lon
 - updated for iOS 8.
 - improvements for use with XGPS150/XGPS160 data streams

 Changes since 1.2.1:
 - bluetooth session management updated to be more stable under iOS 6
 
 Changes since V1.0:
 - parseGPS method optimizatized for nominal speed improvements
 - parseGPS does not use Regex for parsing incoming NMEA string any more
 - minimized longitude and latitude position error due to floating point conversions
 
 Copyright (c) 2017 Dual Electronics Corp.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of the Dual Electronics Corporation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */



/*==============================================================
 
 Firmware Update for XGPS Models
 
 XGPS150  Support only USB. OTA Firmware Update not supported.
 XGPS160  Support USB & OTA(Bluetooth) using commands
 XGPS170  Same as XGPS160, but the 'firmware address' should be changed.
 XGPS190/XGPS170D Support firmware update using file copy over the MSD(USB Mass Storage Device) interface.
           Also support firmware file transfer using command and control.
 XGPS500  Same as XGPS190
 
 
 
 
 LOG Data Access
 
 XGPS150  No LOG feature
 XGPS160  Commands to manipulate raw blocks
 XGPS170  No LOG feature
 XGPS500  Commands to manipulate files in the MSD
 XGPS190/XGPS170D Same as XGPS500
 
 
 ==============================================================*/

#import "Puck.h"
#import "Puck+XGPS160.h"
#import "Puck+XGPS500.h"
#import "TripLog.h"
#import "ntripclient.h"

#define kBufferSize				2048    // I/O stream buffer size
#define kProcessTimerDelay		1.2     // See note in the processConnectNotifications method for explanation of this.
#define kVolt415				644     // Battery level conversion constant.
#define kVolt350				543     // Battery level conversion constant.
#define kMaxNumberOfSatellites  16      // Max number of visible satellites

// Set these to YES to see the NMEA sentence data logged to the debugger console
#define DEBUG_SENTENCE_PARSING  NO
#define DEBUG_DEVICE_DATA       NO
#define DEBUG_PGGA_INFO			NO
#define DEBUG_PGSA_INFO			NO
#define DEBUG_PGSV_INFO			NO
#define DEBUG_PVTG_INFO			NO
#define DEBUG_PRMC_INFO			NO
#define DEBUG_PGLL_INFO         NO





@interface Puck()
@property (strong, nonatomic) EAAccessory *accessory;
@property (strong, nonatomic) NSString *protocolString;
@end

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation Puck

@synthesize isPaired;
@synthesize isConnected;
@synthesize isCharging;
@synthesize batteryVoltage;
@synthesize serialNumber;
@synthesize firmwareRev;
@synthesize alt, latitude, longitude;
@synthesize utc;
@synthesize numOfSatInUseGlonass;
@synthesize numOfSatInView;
@synthesize hdop;
@synthesize vdop;
@synthesize pdop;
@synthesize trackTrue;
@synthesize trackMag;
@synthesize speedKnots;
@synthesize	speedKph;
@synthesize speedAndCourseIsValid;
@synthesize latDegMinDir;
@synthesize lonDegMinDir;
@synthesize satsUsedInPosCalc;
@synthesize satsUsedInPosCalcGlonass;
@synthesize dictOfSatInfo, dictOfSatInfoGlonass;
@synthesize coordinates;
//@synthesize accessory = _accessory;
//@synthesize protocolString = _protocolString;
@synthesize notificationType;
@synthesize logListData;
@synthesize logBulkDic;
@synthesize fixType;
@synthesize numOfSatInUse;

@synthesize supportBinCommand;// XGPS160, XGPS190, XGPS500 and XGPS150 v3.0
@synthesize supportOldCommand;// XGPS150 FW below 1.1 do not support config change

@synthesize xgps500_streamMode;
@synthesize loggingEnabled;
@synthesize logOverWriteEnabled;
@synthesize useShortNMEA;
@synthesize logType;
@synthesize logInterval;
@synthesize gpsRefreshRate;

@synthesize isFWUpdateWorking;
@synthesize coldStartResult;


char connectNotifications = 0;
char disconnectNotifications = 0;
BOOL queueTimerStarted = NO;
BOOL isBackground = NO;

static uint32_t		rxIdx = 0;
static uint32_t		rxSync = 0;
static uint32_t		rxBinLen;
static uint8_t      rxBuf[kBufferSize * 2];

volatile int		rsp160_cmd;
volatile uint32_t   rsp160_len;
volatile uint8_t    rsp160_buf[256];

uint32_t    txBytesCount;
uint32_t    rxBytesCount;

uint32_t    rxMessagesTotal;
uint32_t    rxBinMessages;
uint32_t    rxDevMessages;
uint32_t    rxCfgMessages;
uint32_t    rxNmeaMessages = 0;
uint32_t    rxNmeaMessagesOK = 0;
uint32_t    rxUbxMessages = 0;

// XGPS Firmware Configurations with 'old' XGPS150 Set/Query commands
uint8_t		    cfgGpsSettings;   // 4 bits flags + GPS refresh rate
uint16_t        cfgGpsPowerTime;  // timeout for GPS power off when not in use
uint16_t        cfgBtPowerTime;   // timeout for BT power off when not in use

uint8_t		    cfgLogInterval;
uint16_t		cfgLogBlock;
uint16_t		cfgLogOffset;



#pragma mark - Application lifecycle
- (id)init
{
    if ((self = [super init]))
    {
        delegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
        self.logBulkDic = [[NSMutableArray alloc]init];
        logBulkRecodeCnt = 0;
        self.logListData = [[NSMutableArray alloc]init];
        self.isPaired = NO;
        self.isConnected = NO;
        self.isCharging = NO;
        self.isDGPS = NO;
        self.isRunningNtrip = NO;
        self.batteryVoltage = 0.0f;
        self.serialNumber = [[NSMutableString alloc] initWithString:@""];
        self.firmwareRev = [[NSMutableString alloc] initWithString:@""];
        self.utc = [[NSMutableString alloc]initWithString:@""];
        self.mountPoint = @"";
        self.ntripErrorMessage = @"";
        self.mountPointList = [[NSMutableArray alloc] init];
        self.latitude = 0.0;
        self.longitude = 0.0;
        self.alt = 0.0;
        self.fixType = 0;
        self.numOfSatInUse = 0;
        self.numOfSatInUseGlonass = 0;
        self.numOfSatInView = 0;
        self.numOfSatInViewGlonass = 0;
        self.hdop = 0.0;
        self.vdop = 0.0;
        self.pdop = 0.0;
        self.trackTrue = 0.0;
        self.trackMag = 0.0;
        self.speedKnots = 0.0;
        self.speedKph = 0.0;
        self.speedAndCourseIsValid = NO;
        self.latDegMinDir = [[NSMutableArray alloc] init];
        self.lonDegMinDir = [[NSMutableArray alloc] init];
        self.satsUsedInPosCalc = [[NSMutableArray alloc] init];
        self.satsUsedInPosCalcGlonass = [[NSMutableArray alloc] init];
        self.dictOfSatInfo = [[NSMutableDictionary alloc] init];
        self.dictOfSatInfoGlonass = [[NSMutableDictionary alloc]init];
        self.sentenceGGA = @"";
        self.ntripReceived = 0;
        
        
        // XGPS150 with FW version below 1.1 has refresh rate fixed to 1Hz
        // So, it is very much reasonable to assume we can change the refresh rate.
        // until we check out it is not.
        self.supportOldCommand = true;
        self.supportBinCommand = true;
        self.gpsRefreshRate = 1;
        
        self.useShortNMEA = false;         // start including "$G" for NMEA sentence


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
        
        // Check to see if puck is attached.
        if ([self isPuckAnAvailableAccessory])
            [self openSession];
    }
    
    return self;
}

- (void)clearVariable
{
    [self.logBulkDic removeAllObjects];
    logBulkRecodeCnt = 0;
    [self.logListData removeAllObjects];
    //    self.isPaired = NO;
    //    self.isConnected = NO;
    //    self.isCharging = NO;
    self.isDGPS = NO;
    self.isRunningNtrip = NO;
    self.batteryVoltage = 0.0f;
    self.serialNumber = [[NSMutableString alloc] initWithString:@""];
    self.firmwareRev = [[NSMutableString alloc] initWithString:@""];
    self.utc = [[NSMutableString alloc] initWithString:@""];
    self.mountPoint = @"";
    self.ntripErrorMessage = @"";
    [self.mountPointList removeAllObjects];
    self.latitude = 0.0;
    self.longitude = 0.0;
    self.alt = 0.0;
    self.fixType = 0;
    self.numOfSatInUse = 0;
    self.numOfSatInUseGlonass = 0;
    self.numOfSatInView = 0;
    self.numOfSatInViewGlonass = 0;
    self.hdop = 0.0;
    self.vdop = 0.0;
    self.pdop = 0.0;
    self.trackTrue = 0.0;
    self.trackMag = 0.0;
    self.speedKnots = 0.0;
    self.speedKph = 0.0;
    self.speedAndCourseIsValid = NO;
    [self.latDegMinDir removeAllObjects];
    [self.lonDegMinDir removeAllObjects];
    [self.satsUsedInPosCalc removeAllObjects];
    [self.satsUsedInPosCalcGlonass removeAllObjects];
    [self.dictOfSatInfo removeAllObjects];
    [self.dictOfSatInfoGlonass removeAllObjects];
    self.ntripReceived = 0;
}

#pragma mark -
#pragma mark Memory management
- (void)dealloc {
    
    //    [serialNumber release];
    //    [firmwareRev release];
    ////    [alt release];
    //    [utc release];
    ////    [numOfSatInView release];
    ////    [hdop release];
    ////    [vdop release];
    ////    [pdop release];
    ////    [trackTrue release];
    ////    [trackMag release];
    ////    [speedKnots release];
    ////    [speedKph release];
    //    [satsUsedInPosCalc release];
    //    [satsUsedInPosCalcGlonass release];
    //    [latDegMinDir release];
    //    [lonDegMinDir release];
    //    [dictOfSatInfo release];
    //    [dictOfSatInfoGlonass release];
    //
    //    [super dealloc];
}

- (void)puck_applicationWillResignActive
{
    // Close any open streams.
    [self closeSession];
    
    // stop watching for Accessory notifications
    [[EAAccessoryManager sharedAccessoryManager] unregisterForLocalNotifications];
}


- (void)puck_applicationDidEnterBackground
{
    isBackground = true;
    @synchronized (self) {
        [self closeSession];
    }
    // stop watching for Accessory notifications
    //    [[EAAccessoryManager sharedAccessoryManager] unregisterForLocalNotifications];
}

- (void)puck_applicationWillEnterForeground
{
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
        
        //        if (self.isConnected == NO)
        //        {
        //            if ([self isPuckAnAvailableAccessory] == YES)
        //                [self openSession];
        //        }
        //        else {
        //            [self closeSession];
        //            if ([self isPuckAnAvailableAccessory] == YES)
        //                [self openSession];
        //        }
    }
}

- (void)puck_applicationDidBecomeActive
{
    // begin watching for Accessory notifications again
    //    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
    
    // Recheck to see if the puck disappeared while away
    if (self.isConnected == NO)
    {
        if ([self isPuckAnAvailableAccessory] == YES)
            [self openSession];
    }
    NSNotification *notification = [NSNotification notificationWithName:@"refreshUIAfterAwakening" object:self];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)puck_applicationWillTerminate
{
    // Close session with Puck
    [self closeSession];
    
    // stop watching for Accessory notifications
    [[EAAccessoryManager sharedAccessoryManager] unregisterForLocalNotifications];
    
    // remove the observers before dealloc is called
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark -
#pragma mark Puck interface methods

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    if( self == nil || aStream == nil )
        return;
    
    
    switch(eventCode)
    {
        case NSStreamEventEndEncountered:
        {
            //            NSLog(@"스트림이 끊김");
            //            [aStream close];
            //            [aStream removeFromRunLoop:[NSRunLoop currentRunLoop]
            //                               forMode:NSDefaultRunLoopMode];
            //            [aStream setDelegate:nil];
            //
            //            // Disconnect from the puck. NOTE: a NSStreamEndEventEncountered can occur before the
            //            // EAAccessoryDidDisconnectNotification is generated if the puck is turned off. So the
            //            // sessionClose method can be called from either here or from the accessoryDisconnected method.
            //            [self closeSession];
            //
            //            // Post a notification that the puck has disconnected
            //            NSNotification *notification = [NSNotification notificationWithName:@"PuckDisconnected" object:self];
            //            [[NSNotificationCenter defaultCenter] postNotification:notification];
            break;
        }
        case NSStreamEventHasBytesAvailable:
        {
            uint32_t            len = 0;
            static UInt8        buffer[kBufferSize];
            
            len = (uint32_t) [[_session inputStream] read:buffer maxLength:kBufferSize];
            if( 0 < len && len <= kBufferSize ) {
                [self handleInputStream :(const char* )buffer :len];
            }
            break;
        }
        case NSStreamEventHasSpaceAvailable:
        {
            break;
        }
            
        case NSStreamEventErrorOccurred:
        {
            break;
        }
        case NSStreamEventNone:
        {
            break;
        }
        case NSStreamEventOpenCompleted:
        {
            break;
        }
        default:
        {
            break;
        }
    }
}

- (void)closeSession
{
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
    [self clearVariable];
    
    [self stopNtripNetwork];    // for 500
    
//    [self setupPuck:nil withProtocolString:nil];
}

- (BOOL)openSession
{
	if (self.isConnected)
        return YES;

	NSLog(@"openSession");
    [_accessory setDelegate:self];

//    [_session release];
    _session = [[EASession alloc] initWithAccessory:_accessory forProtocol:_protocolString];

    if (_session)
    {
        [[_session inputStream] setDelegate:self];
        [[_session inputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[_session inputStream] open];
        
        [[_session outputStream] setDelegate:self];
        [[_session outputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[_session outputStream] open];
        
        //[_session autorelease]; DO NOT AUTORELEASE - THIS FAILS UNDER 6.0
        
        self.isConnected = YES;
        bool isUsingEnable = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_NETWORK];
        if (isUsingEnable && [self.modelNumber isEqualToString:XGPS_500]) {
            NSObject *object = [[NSUserDefaults standardUserDefaults] valueForKey:KEY_AUTO_MOUNTPOINT];
            NSString *mountPoint = NULL;
            if (object != nil) {
                bool isAutoMountPoint = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_AUTO_MOUNTPOINT];
                if (isAutoMountPoint == NO) {
                    mountPoint = [[NSUserDefaults standardUserDefaults] stringForKey:KEY_MOUNT_POINT];
                    self.mountPoint = mountPoint;
                }
            }
            [self startNtripNetwork:mountPoint];
        }

    }
    else
    {
        NSLog(@"openSession failed");
        self.accessory = nil;
        self.protocolString = nil;
    }
    
    return (_session != nil);
    
} // openStreamFromPuck

// initialize the accessory with the protocolString
- (void)setupPuck:(EAAccessory *)accessory withProtocolString:(NSString *)protocolString
{
//    [_accessory release];
//    _accessory = [accessory retain];
//    [_protocolString release];
    _protocolString = [protocolString copy];
}

- (void)getAccessory:(EAAccessory *)accessory
{
    NSLog(@"accessory : %@", [accessory name]);
    [self.serialNumber setString:[accessory name]];
    
    self.supportBinCommand = true;
    self.supportOldCommand = true;
    self.firmwareRev = @"2.5.3"; //[accessory firmwareRevision];
    
    if([self.serialNumber hasPrefix:@"XGPS160"]) {
        self.modelNumber = @"XGPS160";
    }
    else if([self.serialNumber  hasPrefix:@"XGPS150"]) {
        self.modelNumber = @"XGPS150";
        
        // XGPS150 F/W version prior to v3.0 does not support commands over binary packets.
        // Only simple Query/Set commands and 'XCFG' response is supported.
        
        NSArray *versionNumbers = [self.firmwareRev componentsSeparatedByString:@"."];
        int majorVersion = [[versionNumbers objectAtIndex:0] intValue];
        int minorVersion = [[versionNumbers objectAtIndex:1] intValue];
        
        if( majorVersion <= 1 && minorVersion < 1 ) {
            self.supportOldCommand = false;
            self.supportBinCommand = false;
        }
        else if( majorVersion < 3 ) {
            self.supportOldCommand = true;
            self.supportBinCommand = false;
        }
    }
    else if ([self.serialNumber  hasPrefix:@"XGPS500"]) {
        self.modelNumber = @"XGPS500";
    }
    else
        self.modelNumber = @"";
    
    [[NSUserDefaults standardUserDefaults] setValue:self.serialNumber forKey:KEY_SERIAL];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    self.isPaired = YES;
    self.protocolString = @"com.dualav.xgps150";
}

- (BOOL)isPuckAnAvailableAccessory
{
	BOOL	connect = NO;
	
    NSLog(@"isPuckAnAvailableAccessory  isConnected : %d", self.accessory.isConnected);
    if (self.accessory != nil && self.accessory.isConnected) {
        [self getAccessory:self.accessory];
        return YES;
    }
    self.isConnected = NO;
    
	// get the list of all attached accessories (30-pin or bluetooth)
	NSArray *attachedAccessories = (NSArray *)[[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    
    NSLog(@"connect available %d", (int)attachedAccessories.count);

	for( EAAccessory *obj in attachedAccessories )
	{
		if( [[obj protocolStrings] containsObject:@"com.dualav.xgps150"] )
		{
			// At this point, the puck has a BT connection to the iPod/iPad/iPhone, but the communication stream
			// has not been opened yet
            [self getAccessory:obj];
            self.accessory = obj;
            connect = YES;
		}
	}
	
	if (!connect)
	{
		// XGPS150 is not available in list of Accessories.");
		[self.serialNumber setString:@""];
        self.firmwareRev = @"";
        self.isPaired = NO;
	}
	
	return connect;
}

#pragma mark -
#pragma mark EAAccessoryDelegate methods
- (void)accessoryDidDisconnect:(EAAccessory*)accessory
{
	// don't have to do anything here.
}

#pragma mark -
#pragma mark Accessory watchdog methods

- (void)processConnectionNotifications
{
    NSLog(@"processConnectionNotifications");
	queueTimerStarted = NO;

    @synchronized (self) {
    if (notificationType)   // last notification was to connect
    {
        if ([self isPuckAnAvailableAccessory] == YES)
        {
            if ([self openSession] == YES)
            {
                // Notify the view controllers that the blackjack is connected and streaming data
                NSNotification *notification = [NSNotification notificationWithName:@"PuckConnected" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:notification];                
            }
        }
    }
    else    // last notification was a disconnect
    {
        if (_accessory.connected == YES) return;
        else
        {
            [self closeSession];
            
            // Notify the view controllers that the blackjack disconnected
            NSNotification *notification = [NSNotification notificationWithName:@"PuckDisconnected" object:self];
            [[NSNotificationCenter defaultCenter] postNotification:notification];
        }
    }
    }
	
}


- (void)queueDisconnectNotifications:(NSNotification *)notification
{
//    [_mostRecentNotification release];
//    _mostRecentNotification = [notification retain];
    notificationType = NO;
    
    if (queueTimerStarted == NO)
    {
        [self performSelector:@selector(processConnectionNotifications) withObject:nil afterDelay:kProcessTimerDelay];
        queueTimerStarted = YES;
    }
    
}

- (void)queueConnectNotifications:(NSNotification *)notification
{
//    [_mostRecentNotification release];
//    _mostRecentNotification = [notification retain];
    notificationType = YES;
    
    if (queueTimerStarted == NO)
    {
        NSLog(@"kProcessTimerDelay");
        [self performSelector:@selector(processConnectionNotifications) withObject:nil afterDelay:kProcessTimerDelay];
        queueTimerStarted = YES;
    }
    
}

static inline int Char2HexNum( char c )
{
    if( '0' <= c && c <= '9' )
        return c - '0';
    
    if( 'A' <= c && c <= 'F' )
        return c - 'A' + 10;
    
    if( 'a' <= c && c <= 'f' )
        return c - 'a' + 10;
    
    return 0;
}

static int hexStrToInt( const char *value, int len)
{
    const char *ptr = value;
    int result = 0;
    
    while( len-- ) {
        result <<= 4;
        result |= Char2HexNum(*ptr);
        ptr++;
    }
    return result;
}

# pragma mark - Data Input and Processing Methods


- (NSInteger)avgUsableSatSNR
{
    NSMutableArray *satData;
    int sumSatStrength=0;
    float avgSNR=0.0, avgSNRGlonass=0.0;
    
    if (numOfSatInUse == 0 && numOfSatInUseGlonass == 0) return 0.0f;    // error prevention
    
    // GPS 평균
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
    
    avgSNR = (float)sumSatStrength / numOfSatInUse;
    //NSLog(@"avgSNR  %f",avgSNR);
    
    if (isnan(avgSNR) != 0) avgSNR = 0.0;   // check: making sure all SNR values are valid
    
    // 글로나스 평균
    sumSatStrength = 0;
    for (NSNumber *sat in [dictOfSatInfoGlonass allKeys])
    {
        for (NSNumber *satInUse in satsUsedInPosCalcGlonass)
        {
            if ([sat intValue] == [satInUse intValue])
            {
                satData = [dictOfSatInfoGlonass objectForKey:sat];
                sumSatStrength += [[satData objectAtIndex:2] intValue];
            }
        }
    }
    avgSNRGlonass = (float)sumSatStrength / numOfSatInUseGlonass;
    //NSLog(@"avgSNRGlonass   %f",avgSNRGlonass);
    
    NSInteger avgInt=0;
    if (isnan(avgSNRGlonass) != 0)
        avgSNRGlonass = 0;
    
    if (avgSNRGlonass == 0) {
        avgInt = avgSNR;
    }
    else
        avgInt = (avgSNR+avgSNRGlonass)/2;
    
    return avgInt;
}


bool NMEAVerifyChecksum( const char* data, int dataLen )
{
    int        i;
    uint8_t    cs = (int)'G';
    uint8_t    vv = 0;
    uint8_t    ch;
    
    for (i = 0;  i < dataLen ; i++) {
        ch = (uint8_t) *data++;
        if( ch == '*' ) {
            vv = (uint8_t) hexStrToInt( data, 2 );
            if( vv == cs ) {
                return true;
            }
            break;
        }
        cs ^= ch;
    }
    NSLog(@"CS %02x %02x", cs, vv);
    return false;
}

- (void) handleNMEASentence: (char *)Sentence :(uint8_t)SentenceLength
{
    //NSLog(@"<IN> %s", pLine);
    if( Sentence[0] == '$' ) {
        Sentence += 2;// skip '$G'
    }
    if( !NMEAVerifyChecksum(Sentence, (int)SentenceLength) ) {
        NSLog(@"senetence checksum failed (%d) %02x", (int)SentenceLength, (uint8_t)Sentence[0]);
        //NSLog(@"%s", Sentence);
        return;
    }
    rxNmeaMessagesOK++;

    // Break the data into an array of elements
    NSArray *elementsInSentence = [[NSString stringWithUTF8String:Sentence] componentsSeparatedByString:@","];
    
    if ( elementsInSentence == nil || [elementsInSentence count] == 0 || [[elementsInSentence objectAtIndex:0] length] != 4 ) {
        NSLog(@"senetence dropped");
        return;
    }
    
    // Parse the data based on the NMEA sentence identifier
    if (strncmp((char *)Sentence, "PGGA", 4) == 0)
    {
        float   Alt;
//        NSLog(@"<IN> %s", Sentence);
        // extract the altitude
        if ([elementsInSentence count] < 10)
            return;
        
        Alt = [[elementsInSentence objectAtIndex:9] floatValue];
        if( Alt < 0.0f )
            Alt = 0.0f;

        self.alt = Alt;
        
        self.isDGPS = ([[elementsInSentence objectAtIndex:6] intValue] == 2)? YES : NO;
        
        // trigger a notification to the view controllers that the satellite data has been updated
//        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"PositionDataUpdated" object:self]];
//        });
        
        if (self.sentenceGGA != nil)
            self.sentenceGGA = [NSString stringWithFormat:@"$G%s", Sentence];
    }
    else if (strncmp((char *)Sentence, "PRMC", 4) == 0)
    {
        if ([elementsInSentence count] != 13)
        {
            elementsInSentence = [[NSArray alloc]initWithObjects:@"",@"",@"",@"",@"",  @"",@"",@"",@"",@"",  @"",@"",@"",nil];
        }
        
        if ([[elementsInSentence objectAtIndex:1] length] == 0)
        {
            [self.utc setString:@"-----"];
        }
        else
        {
            NSString *timeStr=@"", *hourStr=@"", *minStr=@"", *secStr=@"", *secPoint=@"";
            timeStr = [elementsInSentence objectAtIndex:1];
            
            NSArray *timeArray = [timeStr componentsSeparatedByString:@"."];
            if (timeArray.count < 2 || [[timeArray objectAtIndex:0] length] < 6) {
                hourStr = [NSString stringWithFormat:@""];
                minStr = [NSString stringWithFormat:@""];
                secStr = [NSString stringWithFormat:@""];
            }
            else {
                NSString *integerNumber = [timeArray objectAtIndex:0];
                NSString *decimalPoint = [timeArray objectAtIndex:1];
                hourStr = [integerNumber substringWithRange:NSMakeRange(0,2)];
                minStr = [integerNumber substringWithRange:NSMakeRange(2,2)];
                secStr = [integerNumber substringWithRange:NSMakeRange(4,2)];
                secPoint = decimalPoint;
            }
            [self.utc setString:[NSString stringWithFormat:@"%@:%@:%@.%@", hourStr, minStr, secStr, secPoint]];
        }
        
        // is the track and course data valid? An "A" means yes, and "V" means no.
        NSString *valid = [elementsInSentence objectAtIndex:2];
        self.speedAndCourseIsValid = ([valid isEqualToString:@"A"])? YES : NO;
        
        // extract latitude info
        // ex:    "4124.8963, N" which equates to 41d 24.8963' N or 41d 24' 54" N
        
        float mins=0;
        int deg=0, offset=0;
        NSString *dir = @"-";
        const char *cString = "0";
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
        [self.latDegMinDir setArray:@[[NSNumber numberWithInt:deg],[NSNumber numberWithFloat:mins], dir, [NSString stringWithFormat:@"%s", cString]]];
        self.latitude =  (float)(deg + mins / 60) * ([dir isEqualToString:@"N"]?1:-1);
        
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
        [self.lonDegMinDir setArray:@[[NSNumber numberWithInt:deg],[NSNumber numberWithFloat:mins], dir, [NSString stringWithFormat:@"%s", cString]]];
        self.longitude =  (float)(deg + mins / 60) * ([dir isEqualToString:@"E"]?1:-1);
        
        // Pull the speed information from the RMC sentence since this updates at the fast refresh rate in the Skytraq chipset
        if ([[elementsInSentence objectAtIndex:7] isEqualToString:@""])
            self.speedKnots = 0.0f;
        else
            self.speedKnots = [[elementsInSentence objectAtIndex:7] floatValue];
        
        self.speedKph = (self.speedKnots  * 1.852f);
        
        // Extract the magnetic deviation values. Easterly deviation subtracts from true course.
        NSNumber *magDev = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:10] floatValue]];
        
        NSString *devDir = [elementsInSentence objectAtIndex:11];
        
        if ([devDir isEqualToString:@"E"])
            self.trackMag = (self.trackTrue  - [magDev floatValue]);
        else
            self.trackMag = (self.trackTrue  + [magDev floatValue]);
        
        // 헤딩 처리
        
        // extract the true north course
        if ([[elementsInSentence objectAtIndex:8] isEqualToString:@""])
            self.trackTrue = 0.0;
        else
            self.trackTrue = [[elementsInSentence objectAtIndex:8] floatValue];
    }
    
    // 러시아 글로나스 위성 정보
    else if (strncmp((char *)Sentence, "LGSV", 4) == 0)
    {
        //NSLog(@"러샤위성 %s",pLine);
        
        if (self.dictOfSatInfoGlonass == nil)
            self.dictOfSatInfoGlonass = [[NSMutableDictionary alloc]init];
        
        self.numOfSatInViewGlonass = [[elementsInSentence objectAtIndex:3] intValue];
        
        if (self.numOfSatInViewGlonass == 0)
        {
            if ([self.dictOfSatInfoGlonass count])
                [self.dictOfSatInfoGlonass removeAllObjects];
        }
        else
        {
            if( [[elementsInSentence objectAtIndex:2] intValue] == 1 && [self.dictOfSatInfoGlonass count] ) {
                [self.dictOfSatInfoGlonass removeAllObjects];
            }
            
            NSNumber *satNum=0, *satElev=0, *satAzi=0, *satSNR=0, *inUse;
            NSMutableArray *satInfo;
            
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
                satInfo = [NSMutableArray arrayWithObjects:satAzi, satElev, satSNR, inUse, nil];
                [self.dictOfSatInfoGlonass setObject:satInfo forKey:satNum]; //버그지점
            }
        }
    }
    
    // GPS 위성
    else if (strncmp((char *)Sentence, "PGSV", 4) == 0)
    {
        self.numOfSatInView = [[elementsInSentence objectAtIndex:3] intValue];
        
        if (self.dictOfSatInfo == nil)
            self.dictOfSatInfo = [[NSMutableDictionary alloc]init];
        
        if (self.numOfSatInView == 0)
        {
            if ([self.dictOfSatInfo count])
                [self.dictOfSatInfo removeAllObjects];
        }
        else
        {
            if ([[elementsInSentence objectAtIndex:2] intValue] == 1 && [self.dictOfSatInfo count] ) {
                [self.dictOfSatInfo removeAllObjects];
            }
            NSNumber *satNum=0, *satElev=0, *satAzi=0, *satSNR=0, *inUse;
            NSMutableArray *satInfo;
            
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
                
                if( isnan([satSNR floatValue]) )
                    satSNR = [NSNumber numberWithFloat:0.0];
                else if ([satSNR floatValue] > 50) {
                    //NSLog(@"Abnormal SNR %.1f in %s", [satSNR floatValue], pLine);
                    //return;
                    satSNR = [NSNumber numberWithFloat:50.0];
                }
                
                for (NSNumber *n in self.satsUsedInPosCalc)
                {
                    if ([n intValue] == [satNum intValue])
                    {
                        inUse = [NSNumber numberWithBool:YES];
                        break;
                    }
                }
                
                satInfo = [NSMutableArray arrayWithObjects:satAzi, satElev, satSNR, inUse, nil];
                [self.dictOfSatInfo setObject:satInfo forKey:satNum]; //버그지점
            }
        }
        
        if ([[elementsInSentence objectAtIndex:2] intValue] == [[elementsInSentence objectAtIndex:1] intValue])
        {
            // Post a notification to the view controllers that the satellite data has been updated
            NSNotification *satDataUpdated = [NSNotification notificationWithName:@"SatelliteDataUpdated" object:self];
            [[NSNotificationCenter defaultCenter] postNotification:satDataUpdated];
        }
    }
        
    else if (strncmp((char *)Sentence, "NGSA", 4) == 0)
    {
        // 러샤위성 감도 평균값
        if ([elementsInSentence count] != 18 ) {
            elementsInSentence = [[NSArray alloc]initWithObjects:@"",@"",@"",@"",@"",
                                   @"",@"",@"",@"",@"",    @"",@"",@"",@"",@"",
                                   @"",@"",@"", nil];
        }
        
        // extract whether the fix type is 0=no fix, 1=2D fix or 2=3D fix
        self.fixType = [[elementsInSentence objectAtIndex:2] intValue];
        
        // extract PDOP
        self.pdop = [[elementsInSentence objectAtIndex:15] floatValue];

        // extract HDOP
        self.hdop = [[elementsInSentence objectAtIndex:16] floatValue];
        
        // extract VDOP
        self.vdop = [[elementsInSentence objectAtIndex:17] floatValue];
        
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
        self.numOfSatInUseGlonass = (int) [satsInDOPCalc count];
        self.satsUsedInPosCalcGlonass = satsInDOPCalc;
        
        //[satsInDOPCalc release];
        satsInDOPCalc = nil;
    }
    else if (strncmp((char *)Sentence, "PGSA", 4) == 0)
    {
        // 미국위성 감도 평균값
        
        if ([elementsInSentence count] != 18 ) {
            elementsInSentence = [[NSArray alloc]initWithObjects:@"",@"",@"",@"",@"",
                                   @"",@"",@"",@"",@"",    @"",@"",@"",@"",@"",
                                   @"",@"",@"", nil];
        }
        
        // extract whether the fix type is 0=no fix, 1=2D fix or 2=3D fix
        self.fixType = [[elementsInSentence objectAtIndex:2] intValue];
        
        // extract PDOP
        self.pdop = [[elementsInSentence objectAtIndex:15] floatValue];
        
        // extract HDOP
        self.hdop = [[elementsInSentence objectAtIndex:16] floatValue];
        
        // extract VDOP
        self.vdop = [[elementsInSentence objectAtIndex:17] floatValue];
        
        // extract the number of satellites used in the position fix calculation
        
        // 위성 감도 평균값 내기 위한...
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
        self.numOfSatInUse = (int) [satsInDOPCalc count];
        self.satsUsedInPosCalc = satsInDOPCalc;
        
        //[satsInDOPCalc release];
        satsInDOPCalc = nil;
    }
    else if (strncmp((char *)Sentence, "PPWR", 4) == 0) {
        //NSLog(@"PPWR");
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
}



// We have fairly complex mixture for a data stream with com.dualav.xgps150 session.
// It can be any random combination of followings:
//  - Standard NMEA-0183 messages (starting with '$G')
//  - Shortened NMEA messages with XGPS (omitting '$G')
//  - cmd160 a binary formated packet structure
//  - XCFG Query/Set
//  - Ublox binary packets for RAW RXM data (UBX messages)
//  - XGPS device status messages (starting with '@')
//
-(void) handleInputStream :(const char*)pLine :(int)len
{
    int     i;
    uint8_t     x;
    
    rxBytesCount += len;
    
    for( i=0; i<len; i++ )
    {
        x = pLine[i];
        
        if( rxSync == 1 )// XGPS Binary Packet
        {
            rxBuf[rxIdx] = x;
            rxIdx++;
            switch( rxIdx ) {
                case 2:    // second marker
                    if( x != 0xEE ) {
                        rxSync = 0;
                    }
                    break;
                    
                case 3:    // length
                    rxBinLen = x;
                    break;
            }
            if( rxIdx == (rxBinLen + 4) ) {
                uint8_t    i;
                uint8_t    cs = 0;
                uint8_t    size = rxBinLen + 3;
                
                for( i=0; i<size; i++ ) {
                    cs += rxBuf[i];
                }
                
                if( cs == rxBuf[rxBinLen + 3] ) {
                    rxBinMessages++;
                    [self handleBinaryPacket :((uint8_t*)&rxBuf[3]) :rxBinLen];
                }
                else {
                    NSLog(@"cmd cs mismatch");
                }
                
                rxSync = 0;
            }
        }
        else if( rxSync == 2 )// NMEA Sentence
        {
            rxBuf[++rxIdx] = x;
            
            if( (x == '\n' || rxIdx >= 80) ) {// Max length of NMEA-0183 message is defined 80
                rxBuf[++rxIdx] = 0;
                
                if( rxIdx > 10 ) {
                    rxNmeaMessages++;
                    [self handleNMEASentence :(char *)rxBuf :rxIdx];
                }
                rxSync = 0;
            }
        }
        else if( rxSync == 3 )// '@'
        {
            rxBuf[++rxIdx] = x;
            if( rxIdx == 8 ) {
                [self handleDeviceMessage :(uint8_t*)rxBuf :rxIdx];
                rxSync = 0;
            }
        }
        else if( rxSync == 4 )// 'X'
        {
            rxBuf[++rxIdx] = x;
            if( rxIdx >= 18 && x == 0x0a ) {
                [self handleDeviceMessage :(uint8_t*)rxBuf :rxIdx];
                rxSync = 0;
            }
        }
        else if( rxSync == 5 ) // UBX Binary Header
        {
            if( x == 0x62 ) {
                rxSync = 6;
                rxBuf[rxIdx++] = x;
            }
            else if( x == 0xB5 ) {
                // UBX: Duplicated first sync header
            }
            else {
                rxSync = 0;
            }
        }
        else if( rxSync == 6 )
        {
            rxBuf[rxIdx++] = x;
            
            if( rxIdx == 6 ) {
                rxBinLen = getU16L( &rxBuf[4] ) + 8;// +8 for UBX overhead
            }
            else if( rxIdx >= rxBinLen ) {
                // do any necessory processing for UBX/RXM here
                rxUbxMessages++;
                //NSLog(@"UBX %d bytes", rxBinLen);
                rxSync = 0;
            }
        }
        else
        {
            if( x == 0x88 )  {
                rxSync = 1;
                rxBinLen = 0;
                rxIdx = 1;
                rxBuf[0] = x;
            }
            else if( x == 0xB5 ) {
                rxSync = 5;
                rxBinLen = 6;
                rxIdx = 1;
                rxBuf[0] = x;
            }
            else {
                if( x == '$' || x == 'P' || x == 'N' || x == 'L' ) {
                    rxSync = 2;
                    rxIdx = 0;
                    rxBuf[0] = x;
                }
                else if( x == '@' ) {
                    rxSync = 3;
                    rxIdx = 0;
                    rxBuf[0] = x;
                }
                else if( x == 'X' ) {// XCFGxxyyyyzzzz
                    rxSync = 4;
                    rxIdx = 0;
                    rxBuf[0] = x;
                }
            }
            
            if( !rxSync ) {
//                NSLog(@"%02x drop", x);
            }
        }
    }
}



- (void) handleDeviceMessage :(uint8_t*)data :(uint8_t)dataLen
{
    // Determine which kind of sentence it is   @3Ä
    if( strncmp((char*)data, "XCFG", 4) == 0 || strncmp((char *)&data[2], "XCFG", 4) == 0 )
    {
        char* msg = (char*)data;
        if( msg[0] == '@' )
            msg += 2;
        
        NSLog(@"XCFG sentence: %s", msg);
        rxCfgMessages++;
        
        cfgGpsSettings = hexStrToInt( (const char*)&msg[5], 2);
        cfgGpsPowerTime = hexStrToInt( (const char*)&msg[7], 4 );
        cfgBtPowerTime = hexStrToInt( (const char*)&msg[11], 4);
        
        self.loggingEnabled = (cfgGpsSettings & 0x40)? YES : NO;
        self.logOverWriteEnabled = (cfgGpsSettings & 0x80)? YES : NO;
        
        if ([self.serialNumber containsString:XGPS_160]) {
            self.gpsRefreshRate = 10;
        }
        else if ([self.serialNumber containsString:XGPS_150]) {
            switch( (cfgGpsSettings & 0x0F) ) {
            case 0:
                self.gpsRefreshRate = 1;
                break;
                
            case 8:
                self.gpsRefreshRate = 8;
                break;
                
            default:
                self.gpsRefreshRate = 5;
                break;
            }
        }
        else if ([self.serialNumber containsString:XGPS_500]) {
            // XGPS500 does not send refresh rate with XCFG. should check cmd160_getSettings.
        }
        else {
            self.gpsRefreshRate = 1;
        }
        
        NSNotification *notification = [NSNotification notificationWithName:@"updateSettings" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
    else if( data[0] == '@' && dataLen == 8 )
    {
        //NSLog(@"Device Status %d bytes", dataLen);
        
        // Case 1: parse the device info
        float bvolt, batLevel;
        int vbat = getU16M( (uint8_t*)&data[1] );
        const char* battxt = "";
        const char* dctxt = "";
        
        rxDevMessages++;
        
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

        // get charging status flag
        self.isCharging = (data[5] & 0x04)? YES : NO;
        
        // decode charger connect flag
        if( data[3] & 0x40 )
            dctxt = "charger connected";
        else
            dctxt = "charger disconnected";
        
        if( self.isCharging )
            battxt = "charging";
        else
            battxt = "not charging";
        
//        NSLog(@"Device Battery %.2fV %d%% %s, %s, [%d u=%d n=%d b=%d c=%d]", bvolt/100.0f, (int)(batLevel*100), battxt, dctxt,
//              rxDevMessages, rxUbxMessages, rxNmeaMessages, rxBinMessages, rxCfgMessages);

        // trigger a notification to the view controllers that the device data has been updated
        //        dispatch_async(dispatch_get_main_queue(), ^{
        NSNotification *puckDataUpdated = [NSNotification notificationWithName:@"PuckDataUpdated" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:puckDataUpdated];
        //        });
    }
    else
    {
        NSLog(@"handleDeviceMessage %d bytes drop ", dataLen);
    }
}


uint16_t getU16M( uint8_t* buf )
{
    uint16_t    v;
    
    v = buf[0];
    v <<= 8;
    v |= buf[1];
    
    return v;
}
uint32_t getU24M( uint8_t* buf )
{
    uint32_t    v;
    
    v = buf[0];
    v <<= 8;
    v |= buf[1];
    v <<= 8;
    v |= buf[2];
    
    return v;
}

uint16_t getU16L( uint8_t* buf )
{
    uint16_t    v;
    
    v = buf[1];
    v <<= 8;
    v |= buf[0];
    
    return v;
}
uint32_t getU32M( uint8_t* buf )
{
    uint32_t    v;
    
    v = buf[0];
    v <<= 8;
    v |= buf[1];
    v <<= 8;
    v |= buf[2];
    v <<= 8;
    v |= buf[3];
    
    return v;
}

-(void) handleBinaryPacket :(uint8_t*)Pkt :(uint8_t)PktLen
{
    uint8_t     cmd = Pkt[0];
    
//    NSLog(@"cmd %02x %02x %02x %02x", Pkt[0], Pkt[1], Pkt[2], Pkt[3]);
    
    switch( cmd ) {
        case cmd160_ack:
        case cmd160_nack:
            rsp160_cmd = cmd;
            rsp160_len = 0;
            if (Pkt[1] == cmd160_gpsForceColdStart) {
                BOOL result = false;
                if (rsp160_cmd == cmd160_ack)
                    result = true;
                self.coldStartResult = result;
                NSNotification *notification = [NSNotification notificationWithName:@"coldStarted" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:notification];
            }
            break;
            
        case cmd160_fwRsp:
            rsp160_cmd = cmd;
            rsp160_buf[0] = Pkt[1];
            rsp160_buf[1] = Pkt[2];
            rsp160_buf[2] = Pkt[3];
            rsp160_buf[3] = Pkt[4];
            rsp160_len = rxBinLen;
            
            if( Pkt[1] == cmd160_fwUpdate ) {
            }
            else if( Pkt[1] == cmd160_getSettings )
            {
                NSLog(@"cmd160_getSettings RSP");
                if ([self.serialNumber containsString:XGPS_160]) {
                    [self handle160getSettingsRsp: Pkt: PktLen];
                }
                else if ([self.serialNumber containsString:XGPS_150]) {
                    // 1 byte - GpsCfgFlag
                    // 2 bytes - Gps Power timeout
                    // 2 bytes - BT Power timeout
                    
                    cfgGpsSettings = Pkt[2];
                    cfgGpsPowerTime = getU16L( &Pkt[3] );
                    cfgBtPowerTime = getU16L( &Pkt[5] );
                    
                    switch( (cfgGpsSettings & 0x0F) ) {
                    case 0:
                        self.gpsRefreshRate = 1;
                        break;
                        
                    case 8:
                        self.gpsRefreshRate = 8;
                        break;
                        
                    default:
                        self.gpsRefreshRate = 5;
                        break;
                    }
                }
                else if ([self.serialNumber containsString:XGPS_500]) {
                    [self handle500getSettingsRsp: Pkt: PktLen];
                }
                NSNotification *notification = [NSNotification notificationWithName:@"updateSettings" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:notification];
            }
            // 로그 리스트를 받는다
            else if( Pkt[1] == cmd160_logListItem )
            {
                [self handle160LogList: Pkt: PktLen];
            }
            else if( Pkt[1] == cmd160_logReadBulk )
            {
                [self handle160LogBlock: Pkt: PktLen];
            }
            else if( Pkt[1] == cmd160_logDelBlock )
            {
                [self handle160LogDelRsp: Pkt: PktLen];
            }
            else if( Pkt[1] == cmd160_fwVersion )
            {
            }
            else if (Pkt[1] == cmd160_logPause){
                NSLog(@"로그 일시중지");
            }
            else if (Pkt[1] == cmd160_logResume)
            {
                NSLog(@"로그 다시시작");
            }
            else if( Pkt[1] == cmd160_recentList )
            {
                // list of recently connected devices kept in XGPS
                // it is an array of 5 x (Bluetooth Device Address (6 Bytes) + Status Flags (1 uint8_t))
            }
            else if( Pkt[1] == cmd160_recentDel )
            {
                // delete from recently connected device list
            }
            else if( Pkt[1] == cmd160_fileList )
            {
                [self handle500LogList: Pkt: PktLen];
            }
            else if ( Pkt[1] == cmd160_fileDump )
            {
                [self handle500LogDump: Pkt: PktLen];
            }
            else if ( Pkt[1] == cmd160_fileFreeSpace )
            {
                [self handle500FreeSpace: Pkt: PktLen];
            }
            break;
            
        case cmd160_fwData:
            [self handle160fwDataRsp: Pkt: PktLen];
            break;
            
        case cmd160_response:
            rsp160_cmd = Pkt[0];
            rsp160_len = 0;
            NSLog(@"cmd160_response");
            break;
            
        default:
            break;
    }
}


- (void) writeBufferToStream:(const uint8_t *)buf :(uint32_t) bufLen
{
    NSInteger written;
    
    if( _session && [_session outputStream] )
    {
        if( [[_session outputStream] hasSpaceAvailable] ) {
            written = [[_session outputStream] write: buf maxLength:bufLen];
        }
    }
}


-(bool) sendCommandToDevice:(int)cmd :(int)item :(uint8_t*) buf :(uint32_t) bufLen
{
    static    uint8_t    xbuf[256];
    uint32_t    size = 0;
    uint32_t    i;
    uint8_t    cs;
    
    if( bufLen > 0 ) {
        NSLog(@"sendCommandToDevice %d (%d bytes) 0x%02x", cmd, bufLen, buf[0]);
    }
    else {
        NSLog(@"sendCommandToDevice %d", cmd);
    }
    
    if( cmd == cmd160_getSettings )
    {
        NSLog(@"cmd160_getSettings");
        if ([self.serialNumber containsString:XGPS_150])
        {
            
        }
    }
    
    xbuf[0] = 0x88;
    xbuf[1] = 0xEE;
    xbuf[2] = bufLen + 1;    // length
    xbuf[3] = (uint8_t) cmd;
    
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
    
    [self writeBufferToStream: xbuf: size];
    
    return TRUE;
}


- (bool) streamEnable        // enable NMEA stream output
{
    [self sendCommandToDevice:cmd160_streamResume :0 :NULL :0];
    
    return TRUE;
}
- (bool) streamDisable        // disable NMEA stream output
{
    [self sendCommandToDevice:cmd160_streamStop :0 :NULL :0];
    
    return TRUE;
}



- (bool) fwupdateCancel
{
    // return true if the operation can be stopped, after stopping it
    return false;
}


- (void)getSettingValue
{
    const uint8_t data[5] = { 'Q', '0', '0', '0', 0x0a };
    
    [self writeBufferToStream: data: 5];
    
    // XGPS150/160/170/190/170D/500 will respond with 'XCFGxxyyyyzzzz'
    // except XGPS150 FW version 1.0.x
}

-(void) sendSetConfigCommand
{
    char cmd[16];
    
    sprintf( cmd, "S%02X%04X%04X\x0a", cfgGpsSettings, cfgGpsPowerTime, cfgBtPowerTime);
    NSLog(@"sendSetConfigCommand : %s", cmd);
    
    [self writeBufferToStream: (const uint8_t*)cmd: 12];
}

-(void) setShortNMEA :(bool)ShortNMEA
{
    if( ShortNMEA ){
        cfgGpsSettings |= 0x10;
    } else{
        cfgGpsSettings &= 0xEF;
    }
    
    [self sendSetConfigCommand];
}

-(void) setRefreshRate:(int)value
{
    cfgGpsSettings = (cfgGpsSettings & 0xF0) | ((uint8_t)value);
    
    [self sendSetConfigCommand];
}

@end
