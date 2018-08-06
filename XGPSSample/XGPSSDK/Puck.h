//
//  Puck.h
//  XGPS150 Developers Kit.
//
//  Version 1.5.
//  Licensed under the terms of the BSD License, as specified below.

/*
 Copyright (c) 2013 Dual Electronics Corp.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of the Dual Electronics Corporation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#ifdef __OBJC__
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#endif
#import <CoreLocation/CoreLocation.h>       // only used for the CLLocationCoordinate2D data structure. Location manager is not used.
#import <ExternalAccessory/ExternalAccessory.h>

#import "Common.h"
#import "CommonUtil.h"
#import "CommonValue.h"

#import "TripLog.h"

#import "xgps160def.h"
#import "xgps500def.h"
#import "xgpscommand.h"


@class AppDelegate;

@interface Puck : NSObject <EAAccessoryDelegate, NSStreamDelegate, TripLogDelegate>
{
    AppDelegate *delegate;
    FILE*	fileLogExport;
    
    //++ XGPS160 only
    unsigned long logReadBulkCount;
    logentry_t      logRecords[185 * 510];
    unsigned long logBulkRecodeCnt;
    //--

    
    // These are for communicating with the puck
    NSNotification      *_mostRecentNotification;
    bool                notificationType;
//    EAAccessory         *_accessory;
    EASession           *_session;
//    NSString            *_protocolString;

    // This is the information available about the XGPS150 hardware
    bool        isPaired;                   // Whether the puck is avaiable via Bluetooth
	bool        isConnected;                // Whether there is an established connection between the iPxx and the puck
	bool        isCharging;                 // Whether the puck is charging or not
	float       batteryVoltage;             // Value between 0.0 (0%) and 1.0 (100%) representing the level of the puck's battery
    NSMutableString	*serialNumber;              // Unique ID of the puck, e.g. XGPS150-28645E
    NSString	*firmwareRev;               // Firmware version in the puck, e.g. 1.0.23
    NSString *modelNumber;                      // model number
    
    // This is the raw GPS data available from the XGPS150
//	NSNumber	*alt;                       // Altitude in meters
	NSMutableString	*utc;                       // UTC time of latest position sample
	int         fixType;                   // 1 = position fix not available, 2 = 2D fix, 3 = 3D fix
	int         numOfSatInUse;             // Number of satellites in use (not the number in view)
//	NSNumber	*numOfSatInView;            // The total number of satellites in view
//	float	*hdop;                      // Horizontal dilution of position, float. More info in Puck.m.
//	float	*vdop;                      // Vertical dilution of position, float
//	float	*pdop;                      // Postional (3D) dilution of position, float
//	NSNumber	*trackTrue;                 // Track in degrees (true north), float
//	NSNumber	*trackMag;                  // Track in degrees (magnetic north), float. NOTE: the current chipset does not
                                            // provide magnetic heading info. Until the chipset is updated, trackMag will
                                            // always equal trackTrue.
//	NSNumber	*speedKnots;                // Speed in knots, float
//	NSNumber	*speedKph;                  // Speed in km/hr, float
	bool		speedAndCourseIsValid;		// Whether the speed and course data is valid or not
	NSMutableArray		*latDegMinDir;		// A 3 element array containing degrees, minutes and a "N" or "S" character.
                                            // Degrees will be an integer (0-359) stored as an NSNumber. Minutes will always
                                            // be a floating point value (mm.mmmm) stored as an NSNumber. The "N"/"S" character
                                            // will be stored as an NSString.
	NSMutableArray		*lonDegMinDir;		// A 3 element array containing degrees, minutes and a "E" or "W" character.
                                            // Degrees will be an integer (0-359) stored as an NSNumber. Minutes will always
                                            // be a floating point value (mm.mmmm) stored as an NSNumber. The "E"/"W" character
                                            // will be stored as an NSString.
	NSMutableArray		*satsUsedInPosCalc;	// An array containing the satellite numbers which the puck is reporting to be used
                                            // in the position (and DOP) calculations. Array contains up to 12 NSNumbers which
                                            // are integers.
	NSMutableDictionary *dictOfSatInfo;		// A dictionary with arrays as the objects. Each array has four components:
                                            // azimuth, elevation, signal strength, and a boolean value of whether the satellite
                                            // is being used in position calculations - all NSNumber types. The keys to the dictionary
                                            // are the satellite numbers - also NSNumber types. This dictionary is set by the
                                            // parseGPS method.
	CLLocationCoordinate2D	coordinates;	// The puck's location, calculated by a class method
    
}
@property (nonatomic, retain) NSMutableArray* logBulkDic;
@property (nonatomic, retain) NSMutableArray* logListData;

@property bool notificationType;    // true = connect. false = disconnect
//@property (nonatomic, readonly) EAAccessory *accessory;
//@property (nonatomic, readonly) NSString *protocolString;
@property bool isPaired;
@property bool isConnected;
@property bool isCharging;
@property bool isDGPS;
@property bool isRunningNtrip;
@property float batteryVoltage;
@property (nonatomic, retain) NSMutableString *serialNumber;
@property (nonatomic, retain) NSString *firmwareRev;
@property (nonatomic, retain) NSString *modelNumber;
@property (nonatomic, retain) NSString *mountPoint;
@property (nonatomic, retain) NSString *ntripErrorMessage;
@property (nonatomic, retain) NSMutableArray *mountPointList;
@property (nonatomic, assign) float latitude;
@property (nonatomic, assign) float longitude;
@property (nonatomic, assign) float alt;
@property (nonatomic, retain) NSMutableString *utc;
@property (nonatomic, assign) int fixType;
@property (nonatomic, assign) int numOfSatInUse;
@property (nonatomic, assign) int numOfSatInView;
@property (nonatomic, assign) int numOfSatInUseGlonass;
@property (nonatomic, assign) int numOfSatInViewGlonass;
@property (nonatomic, assign) float hdop;
@property (nonatomic, assign) float vdop;
@property (nonatomic, assign) float pdop;
@property (nonatomic, assign) float trackTrue;
@property (nonatomic, assign) float trackMag;
@property (nonatomic, assign) float speedKnots;
@property (nonatomic, assign) float speedKph;
@property bool speedAndCourseIsValid;
@property bool waasInUse;
@property (nonatomic, retain) NSMutableArray *latDegMinDir;
@property (nonatomic, retain) NSMutableArray *lonDegMinDir;
@property (nonatomic, retain) NSMutableArray *satsUsedInPosCalc;
@property (nonatomic, retain) NSMutableArray *satsUsedInPosCalcGlonass;
@property (nonatomic, retain) NSMutableDictionary *dictOfSatInfo;
@property (nonatomic, retain) NSMutableDictionary *dictOfSatInfoGlonass;
@property (nonatomic, readwrite) CLLocationCoordinate2D coordinates;
@property(nonatomic, assign) id <TripLogDelegate> tripLogDelegate;

@property bool supportBinCommand;// XGPS160, XGPS190, XGPS500 and XGPS150 v3.0
@property bool supportOldCommand;// XGPS150 FW below 1.1 do not support config change

@property uint8_t   xgps500_streamMode;
@property(nonatomic, assign) BOOL loggingEnabled;
@property(nonatomic, assign) BOOL logOverWriteEnabled;
@property(nonatomic, assign) BOOL useShortNMEA;

@property(nonatomic, assign) int logType;
@property(nonatomic, assign) int logInterval;
@property(nonatomic, assign) int gpsRefreshRate;

@property(nonatomic, assign) BOOL coldStartResult;

@property(nonatomic, assign) BOOL isFWUpdateWorking;


- (void)puck_applicationWillResignActive;
- (void)puck_applicationDidEnterBackground;
- (void)puck_applicationWillEnterForeground;
- (void)puck_applicationDidBecomeActive;
- (void)puck_applicationWillTerminate;

-(NSInteger) avgUsableSatSNR;

-(void) handleInputStream :(const char*)pLine :(int)len;
-(void) handleBinaryPacket :(uint8_t*)Pkt :(uint8_t)PktLen;
-(void) handleDeviceMessage :(uint8_t*)data :(uint8_t)dataLen;
-(void) handleNMEASentence :(char*)Sentence :(uint8_t)SentenceLength;

-(void) writeBufferToStream:(const uint8_t *)buf :(uint32_t) bufLen;
-(bool) sendCommandToDevice:(int)cmd :(int)item :(uint8_t*) buf :(uint32_t) bufLen;

-(bool) streamEnable;		// enable NMEA stream output
-(bool) streamDisable;		// disable NMEA stream output

// Old(Compatibility Mode) commands (XGPS150 prior to v3.0)
-(void) setRefreshRate:(int)value;
-(void) getSettingValue;
-(void) setShortNMEA:(bool)ShortNMEA;

//
// LOG Access
//
-(void) cancelLoading:(int)whatCancel;

//
// OTA Firmware Update
//
- (bool) fwupdateNeeded;
- (bool) fwupdateStart:(NSMutableData*)firmwareData fileSize:(int)fwsize progress:(void (^)(float percent))progressBlock;
- (bool) fwupdateCancel;

//
// RTCM Feed into XGPS500
//
//int ntripTest(char **buf, int *bufSize);
int ntripTest(void *object, char *server, char *port, char *user, char *pw, char *mount, int mode);
- (void)startNtripNetwork:(NSString *)mountPoint;
- (void)stopNtripNetwork;
- (void)addMountPoint:(NSString *)mountPoint;
//- (void)setMountPoint:(NSString *)mountPoint;
@property (nonatomic, retain) NSString *sentenceGGA;
@property long ntripReceived;

@end
