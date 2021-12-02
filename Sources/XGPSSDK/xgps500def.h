//
//  xgps500def.h
//  SkyPro for XGPS160
//
//  Created by jk on 20181904.
//  Copyright © 2018 namsung. All rights reserved.
//

#ifndef xgps500def_h
#define xgps500def_h
#include <stdint.h>
#include <stdbool.h>
#include "xgps160def.h"


typedef struct {
    uint32_t    signature;
    uint32_t    revision;
    
    signed char    adc_offset;
    uint8_t        adc_calibrated;
    
    // bit[4]: Force HDOP
    uint8_t        GpsOptions;
    
    // GPS Refresh Rate x 10: 0.1~20Hz (1~200)
    uint8_t        GpsRefreshRateX10;
    
    
    uint16_t    GpsForceHDOP;
    uint16_t    GpsPowerTime;
    uint16_t    BtPowerTime;
    
    uint8_t        LedBrightness;        //    0~100 in % for all LEDs
    uint8_t        LedBrightness2;        //  0~100 in % for ADS-B data indication
    
    uint8_t        bdaddr[6];            // local Bt address
    
    uint8_t        recentDev[7 * MaxRecentDevices];// XGPS_CHANNELS
    
    uint8_t        logInterval;
    
    uint8_t        logType;            // 0 = XGPS160 native, 1=Raw NMEA stream
    
    bool        logOverWriteEnable;
    
    uint32_t    logStorePosition;
    
    uint8_t        opMode;                // [0]
    
    
    // XGPS500 Specific Configurations below
    uint8_t        streamMode;            // NMEA, UBX_RXM, NMEA + UBX_RXM
    
    
    uint8_t        rsvdb[3];
    uint32_t    rsvd[7];
    
    uint32_t    signature2;
    
} xgps500data_t;


typedef struct {
    uint32_t    filesize;
    uint32_t    fileattr;
    uint32_t    filetime;
    uint8_t        rsvd;
    uint8_t        filenameLen;
    //    char    filename[filenameLen];            //
} xgps_fileinfo_t;

typedef struct {
    uint32_t    totalSize;
    uint32_t    availableSize;
} xgps_storageinfo_t;

enum {
    StreamMode_NMEA = 0,
    StreamMode_RXM,
    StreamMode_NMEA_RXM,
    StreamMode_Max    // Invalid value
};

enum {
    LogType_Native = 0,
    LogType_NMEA = 1,
    LogType_GPX = 2,
    LogType_KML = 3,
    LogType_RTK = 4,
};


#endif /* xgps500def_h */
