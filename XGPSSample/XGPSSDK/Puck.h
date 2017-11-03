//
//  Puck.h
//  XGPS150/XGPS160 Developers Kit.
//
//  Version 2.2
//  Licensed under the terms of the BSD License, as specified below.
//  last modify by hjlee on 2017. 10. 30

/*
 Copyright (c) 2017 Dual Electronics Corp.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of the Dual Electronics Corporation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <ExternalAccessory/ExternalAccessory.h>

@interface Puck : NSObject <EAAccessoryDelegate, NSStreamDelegate>

// This is information about the XGPS150/XGPS160 hardware
@property bool   isConnected;                           // YES when there is an established connection between the iOS device and the XGPS150/XGPS160
@property bool   isCharging;                            // YES when XGPS150/XGPS160 is connected to power
@property float  batteryVoltage;                        // Value between 0.0 (0%) and 1.0 (100%) representing the level of the XGPS150/XGPS160's battery
@property (nonatomic, strong) NSString *firmwareRev;    // Firmware version installed in the XGPS150/XGPS160, e.g. 1.3.0
@property (nonatomic, strong) NSString *serialNumber;   // Unique ID of the XGPS150/XGPS160, e.g. XGPS150-28645E
@property bool   streamingMode;                         // YES if streaming GPS data, NO if not (i.e. in log access mode)
@property bool   deviceSettingsHaveBeenRead;            // The settable options values below will not be valid until this boolean is true.

// These are the settable options for the XGPS160
@property bool   alwaysRecordWhenDeviceIsOn;            // YES means the device will record position information whenever it is on. NO means logging must be enabled manually.
@property bool   stopRecordingWhenMemoryFull;           // YES means the recording stops when the internal memory fills up. NO means old data is overwritten.
@property unsigned char logUpdateRate;                  // Position sampling rate for logging. See comments in 'setLoggingUpdateRate' method for explanation of values.

// This is the raw GPS data available from the XGPS150/XGPS160
@property (nonatomic, strong) NSNumber	*lat;           // Latitude. 6 decimals of precision: nn.nnnnnn
@property (nonatomic, strong) NSNumber	*lon;           // Longitude. 6 decimals of precision: nn.nnnnnn
@property (nonatomic, strong) NSNumber	*alt;           // Altitude in meters
@property (nonatomic, strong) NSString	*utc;           // UTC time of latest position sample
@property (nonatomic, strong) NSNumber	*fixType;       // 1 = position fix not available, 2 = 2D fix, 3 = 3D fix
@property (nonatomic, strong) NSNumber	*numOfSatInUse;   // Number of satellites in use (not the number in view)
@property (nonatomic, strong) NSNumber	*numOfSatInView;  // The total number of satellites in view
@property (nonatomic, strong) NSNumber	*numOfGLONASSSatInUse;              // Number of satellites in use (not the number in view), integer.
@property (nonatomic, strong) NSNumber	*numOfGLONASSSatInView;             // The total number of satellites in view, integer.
@property (nonatomic, strong) NSNumber	*hdop;          // Horizontal dilution of position, float. More info in Puck.m.
@property (nonatomic, strong) NSNumber	*vdop;          // Vertical dilution of position, float
@property (nonatomic, strong) NSNumber	*pdop;          // Postional (3D) dilution of position, float
@property (nonatomic, strong) NSNumber	*trackTrue;     // Track in degrees (true north), float
@property (nonatomic, assign) NSNumber  *trackMag;
@property (nonatomic, strong) NSNumber	*speedKnots;    // Speed in knots, float
@property (nonatomic, strong) NSNumber	*speedKph;      // Speed in km/hr, float
@property bool		speedAndCourseIsValid;              // Whether the speed and course data is valid or not
@property bool      waasInUse;      // YES when at least one WAAS/EGNOS/MSAS satellite is being used in position calculations
@property (nonatomic, retain) NSMutableArray *latDegMinDir;
@property (nonatomic, retain) NSMutableArray *lonDegMinDir;

// An array containing the satellite numbers which the XGPS150 is reporting to be used
// in the position (and DOP) calculations. Array contains up to 16 NSNumbers which
// are integers.
@property (nonatomic, strong) NSMutableArray *satsUsedInPosCalc;
@property (nonatomic, retain) NSMutableArray *satsUsedInPosCalcGlonass;

// A dictionary with arrays as the objects. Each array has four components:
// azimuth, elevation, signal strength, and a boolean value of whether the satellite
// is being used in position calculations - all NSNumber types. The keys to the dictionary
// are the satellite numbers - also NSNumber types.
@property (nonatomic, strong) NSMutableDictionary *dictOfSatInfo;
@property (nonatomic, retain) NSMutableDictionary *dictOfSatInfoGlonass;

// An array containing the satellite numbers which the XGPS160 is reporting to be used
// in the position (and DOP) calculations. Array contains up to 16 NSNumbers which
// are integers.
@property (nonatomic, strong) NSMutableArray *gpsSatsUsedInPosCalc;

// A dictionary with arrays as the objects. Each array has four components:
// azimuth, elevation, signal strength, and a boolean value of whether the satellite
// is being used in position calculations - all NSNumber types. The keys to the dictionary
// are the satellite numbers - also NSNumber types.
@property (nonatomic, strong) NSMutableDictionary *dictOfGPSSatInfo;

// An array containing the satellite numbers which the XGPS160 is reporting to be used
// in the position (and DOP) calculations. Array contains up to 16 NSNumbers which
// are integers.
@property (nonatomic, strong) NSMutableArray *glonassSatsUsedInPosCalc;

// A dictionary with arrays as the objects. Each array has four components:
// azimuth, elevation, signal strength, and a boolean value of whether the satellite
// is being used in position calculations - all NSNumber types. The keys to the dictionary
// are the satellite numbers - also NSNumber types.
@property NSMutableDictionary *dictOfGLONASSSatInfo;

// This is information about the recorded log data
@property (strong, nonatomic) NSMutableArray *logDataSamples;
@property (strong) NSMutableArray *logListEntries;

// These methods are for reading and changing the device settings
- (void)readDeviceSettings;
- (void)setNewLogDataToOverwriteOldData:(bool)overwrite;
- (void)setAlwaysRecord:(bool)record;

// These methods are used for controlling and reading the logs in the XGPS160
- (void)startLoggingNow;
- (void)stopLoggingNow;
- (void)enterLogAccessMode;
- (void)exitLogAccessMode;
- (bool)setLoggingUpdateRate:(unsigned char)rate;
- (void)getListOfRecordedLogs;
- (void)getGPSSampleDataForLogListItem:(NSDictionary *)logListItem;
- (void)deleteGPSSampleDataForLogListItem:(NSDictionary *)logListItem;

- (int) getUsedStoragePercent;


// Call these methods in the corresponding methods in your app delegate
- (void)puck_applicationWillResignActive;
- (void)puck_applicationDidEnterBackground;
- (void)puck_applicationWillEnterForeground;
- (void)puck_applicationDidBecomeActive;
- (void)puck_applicationWillTerminate;

// These two methods can be used to change the GPS sampling rate. NOTE: there are two different
// GPS chipsets used in the XGPS150. One chipset has a maximum sampling rate of 4Hz and the other
// will run at 5Hz. The setFastSampleRate method will automatically handle this difference. Normal
// sample rate for both chipsets is 1Hz.
-(void)setFastSampleRate;
-(void)setNormalSampleRate;

typedef unsigned int UINT;
typedef unsigned char BYTE;
typedef unsigned short USHORT;
typedef unsigned long DWORD;

typedef struct {
    
    USHORT    date;    // date: ((year-2012)  12 + (month - 1))  31 + (day - 1)
    //  year  = 2012 + (dd/372)
    //  month = 1 + (dd % 372) / 31
    //  day   = 1 + dd % 31
    USHORT    tod;    // 16 LSB of time of day in second
    BYTE    tod2;    // [0..3] 1/10 of second
    // [4]    1 MSB of the time of day
    // [5..7] reserved
    
    BYTE    lat[3];        // Latitude  - as 24bit integer, MSB byte first
    BYTE    lon[3];        // Longitude - as 24bit integer, MSB byte first
    BYTE    alt[3];        // Altitude, in 5 ft unit.
    BYTE    spd[2];        // speed over ground
    BYTE    heading;    // True north heading in 360/256 step
    BYTE    satnum;        // in view, in use
    BYTE    satsig;
    BYTE    dop;        // HDOP, VDOP
} dataentry_t;


typedef struct {
    
    USHORT    date;    // date: ((year-2012)  12 + (month - 1))  31 + (day - 1)
    //  year  = 2012 + (dd/372)
    //  month = 1 + (dd % 372) / 31
    //  day   = 1 + dd % 31
    USHORT    tod;    // 16 LSB of time of day in second
    BYTE    tod2;    // [0..3] 1/10 of second
    // [4]    1 MSB of the time of day
    // [5..7] reserved
    
    BYTE    lat[4];        // Latitude  - as 32bit integer, MSB byte first
    BYTE    lon[4];        // Longitude - as 32bit integer, MSB byte first
    
    BYTE    alt[3];        // Altitude, in CM unit
    BYTE    spd[2];        // speed over ground, knots
    BYTE    heading;    // True north heading in 360/256 step
    BYTE    satsig;
} data2entry_t;




typedef struct {
    USHORT	ttff;
    BYTE	batt;
    BYTE	gpsStat;
    BYTE	devOp;
    BYTE	chStat;
    BYTE	bdCh;
    BYTE	bdOp;
    BYTE	bdAddr[6];
} statentry_t;  // 9 bytes




typedef struct {
    BYTE    seq;    // sequence number of the record (wrap after 255)
    BYTE    type;    // 0= dataentry_t, 2=dataentry2_t, others not defined yet.
    
    union {
        dataentry_t        data;
        data2entry_t    data2;
    };
    
} logentry_t;


typedef struct {
    BYTE	sig;
    BYTE	interval;
    USHORT	startDate;
    UINT	startTod;
    USHORT	startBlock;
    USHORT	countEntry;
    USHORT	countBlock;
} loglistitem_t;    // 14 bytes

enum {
    cmd160_ack,
    cmd160_nack,
    cmd160_response,
    cmd160_fwRsp,
    cmd160_fwData,
    cmd160_fwDataR,
    cmd160_fwErase,
    cmd160_fwUpdate,
    cmd160_fwBDADDR,
    cmd160_fwCancel,
    cmd160_streamStop,
    cmd160_streamResume,
    cmd160_logDisable,
    cmd160_logEnable,
    cmd160_logOneshot,
    cmd160_logPause,
    cmd160_logResume,
    cmd160_logInterval,
    cmd160_logOWEnable,
    cmd160_logOWDisable,
    cmd160_getSettings,
    cmd160_logReadBulk,
    cmd160_logList,
    cmd160_logListItem,
    cmd160_logRead,
    cmd160_logDelBlock,
    cmd160_resetSettings,
    cmd160_fwVersion,
    cmd160_recentList,
    cmd160_recentDel,
};
@end
