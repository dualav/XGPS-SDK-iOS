//
//  xgps160def.h
//  SkyPro for XGPS160
//
//  Created by jk on 20181804.
//  Copyright © 2018 namsung. All rights reserved.
//

#ifndef xgps160def_h
#define xgps160def_h

/*
#define BlockHeadSignature    0x20308090

#define MaxBlock            510

#define SectSize            4096

#define NumRecInSect        185        // 22 bytes record x 185 = 4070 bytes

 
 #define romBtStorAddr1    0x01FE000
 #define romBtStorAddr2    0x01FF000

 */




#define MaxRecentDevices    5



typedef struct {
    uint32_t    sig;        // BlockHeadSignature
    uint16_t    seq;        // valid range=[1..65535]
    uint16_t    seqchk;        // seq ^ seqchk = 0xFFFF
    
    uint16_t    rsvd[4];
} blockhead_t;

typedef struct { // size 13
    
    uint16_t    date;    // date: ((year-2012) * 12 + (month - 1)) * 31 + (day - 1)
    //  year  = 2012 + (dd/372)
    //  month = 1 + (dd % 372) / 31
    //  day   = 1 + dd % 31
    uint16_t    tod;    // 16 LSB of time of day in second
    uint8_t    tod2;    // [0..3] 1/10 of second
    // [4]    1 MSB of the time of day
    // [5..7] reserved
    
    uint8_t    lat[3];        // Latitude
    uint8_t    lon[3];        // Longitude
    uint8_t    alt[3];        // Altitude with 5 ft. unit
    uint8_t    spd[2];        // speed over ground
    uint8_t    heading;    // True north heading in 360/256 step
    uint8_t    satnum;        // in view, in use
    uint8_t    satsig;
    uint8_t    dop;        // HDOP, VDOP
} dataentry_t;


typedef struct {
    
    uint16_t    date;    // date: ((year-2012) * 12 + (month - 1)) * 31 + (day - 1)
    //  year  = 2012 + (dd/372)
    //  month = 1 + (dd % 372) / 31
    //  day   = 1 + dd % 31
    uint16_t    tod;    // 16 LSB of time of day in second
    uint8_t    tod2;    // [0..3] 1/10 of second
    // [4]    1 MSB of the time of day
    // [5..7] reserved
    
    uint8_t    lat[4];        // Latitude
    uint8_t    lon[4];        // Longitude
    
    uint8_t    alt[3];        // Altitude in cm
    uint8_t    spd[2];        // speed over ground
    uint8_t    heading;    // True north heading in 360/256 step
    uint8_t    satsig;
} data2entry_t;

typedef struct { // size 9
    uint16_t    ttff;
    uint8_t    batt;
    uint8_t    gpsStat;
    
    uint8_t    devOp;        // 0-Power Off, 1-Powered On, 3-OneShot Log Enable, 3-OneShot Log Disable,
    uint8_t    chStat;        // bit-field stat for SPP connection
    
    uint8_t    bdCh;
    uint8_t    bdOp;        // 0-disconnect, 1-connect, 2-paired
    uint8_t    bdAddr[6];
} statentry_t;

typedef struct {
    uint8_t    seq;    // sequence number of the record (wrap after 255)
    uint8_t    type;    // 0= dataentry_t, others not defined yet.
    
    union {
        dataentry_t        data;
        statentry_t        stat;
        data2entry_t    data2;
    };
    
} logentry_t;


typedef struct {
    uint8_t    sig;
    uint8_t    interval;
    uint16_t    startDate;
    uint32_t    startTod;
    uint16_t    startBlock;
    uint16_t    countEntry;
    uint16_t    countBlock;
    
} loglistitem_t;




#endif /* xgps160def_h */
