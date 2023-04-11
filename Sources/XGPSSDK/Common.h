//
//  Common.h
//  nameCard
//
//  Created by 석재 이 on 13. 5. 23..
//  Copyright (c) 2013년 석재 이. All rights reserved.
//

#include <sys/time.h>

#define BASIC_FONT_SIZE 15
#define DISTANCE 88

#define LOGBULK_LISTNAME @"loglist.dat"
#define LOGBULK_DIRECTORYNAME @"logBulk.dat"
#define KEY_SERIAL @"serial_number"
#define ERROR_DATA_SUCCESS  1
#define ERROR_DATA_INVALID  0
#define COMMON_KEEPDATAID   @"KeepDataId"
#define ERROR_DATA_OUTOF_INDEX  2
#define ERROR_DATA_NOT_EXIST    3
#define KEEPDATA_DIRECTORYNAME @"CardName"

// for ntrip network
#define KEY_NETWORK @"key_network"
#define KEY_SERVER @"key_server"
#define KEY_PORT @"key_port"
#define KEY_USER @"key_user"
#define KEY_PASSWORD @"key_password"
#define KEY_MODE @"key_mode"
#define KEY_AUTO_MOUNTPOINT @"key_auto_mountpoint"
#define KEY_MOUNT_POINT @"key_mount_point"
#define KEY_MOUNT_POINT_LOCATION @"key_mount_point_location"

#define KEY_DEVIATION @"key_deviation"

#define KEY_NTRIP_SERVICE @"key_ntrip_service"

#define TITLETEXT @"titleText"
#define FILE_FORMAT @"file_format"
#define FILE_SIZE @"file_size"
#define FILE_TIME @"file_time"
#define LOGNAME @"LOGNAME"

#define LOG_LIST_LOADING 1
#define LOG_BULK_LOADING 2
#define LOG_DELETE 3
#define LOG_LIST_LOADING_FROM_APPFILE 4

#define XGPS_160 @"XGPS160"
#define XGPS_150 @"XGPS150"
#define XGPS_360 @"XGPS360"
#define XGPS_500 @"XGPS500"

#define ABOUT_XGPS_160 @"If you own an XGPS160 Universal Bluetooth GPS Receiver from Dual Electronics, this app will tell you status information about your device, including whether it has determined your location or if it is still searching for satellite signals."
#define ABOUT_XGPS_150 @"If you own an XGPS150 Universal Bluetooth GPS Receiver from Dual Electronics, this app will tell you status information about your device, including whether it has determined your location or if it is still searching for satellite signals."
#define ABOUT_XGPS_360 @"If you own an XGPS360 Precision Bluetooth GPS Receiver from Dual Electronics, this app will tell you status information about your device, including whether it has determined your location or if it is still searching for satellite signals."
#define ABOUT_XGPS_500 @"If you own an XGPS500 Precision Bluetooth GPS Receiver from Dual Electronics, this app will tell you status information about your device, including whether it has determined your location or if it is still searching for satellite signals."



/*
 정수형 색상 값을 실수 값으로 반환.
 */
#define floatColorValue(x) x/255.f

/*
 객체 nil 체크해서 해제
 */
#define ReleaseObject(x) \
{ \
if (x != nil) [x release]; \
x = nil; \
}

/*
 * 각 변환
 */
#define degreesToRadians(x) (M_PI * x / 180.0)


#define ColorWithRGBA(r,g,b,a)          [UIColor colorWithRed:floatColorValue(r) green:floatColorValue(g) blue:floatColorValue(b) alpha:a]
#define ColorWithRGB(r,g,b)             ColorWithRGBA(r,g,b,1)
#define GetImageWithName(x)             [CommonUtil getImageWithName:x]
#define GetSessionManaer(x)             [SessionManager sharedInstance:x]
#define GetDataManager(x)               [DataManager sharedInstance:x]
#define GetVersionManager(x)            [VersionManager sharedInstance:x]
#define GetMainViewController(x)        [MainViewController sharedInstance:x]
#define GetImageDownloader              [ImageDownloader getInstance]





enum {
    SCALE_NONE = 0,
    SCALE_AUTO = 1,
    SCALE_MAX
};

enum GPS_MODULE {
    GPS_UNKNOWN = 0,
    GPS_UBLOX = 1,
    GPS_SKYTRAQ = 2,
    GPS_MTK = 3
};

enum GNSS_SYSTEM_ID {
    GNSSSYSTEMID_GPS = 1,
    GNSSSYSTEMID_GLONASS = 2,
    GNSSSYSTEMID_GALILEO = 3,
    GNSSSYSTEMID_BEIDOU = 4,
    GNSSSYSTEMID_QZSS = 5,
    GNSSSYSTEMID_NAVIC = 6,
    GNSSSYSTEMID_UNKNOWN = 7,
    GNSSSYSTEMID_MAX = 6
};
