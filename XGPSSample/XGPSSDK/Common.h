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

#define LOGBULK_DIRECTORYNAME @"logBulk.dat"
#define ERROR_DATA_SUCCESS  1
#define ERROR_DATA_INVALID  0
#define COMMON_KEEPDATAID   @"KeepDataId"
#define ERROR_DATA_OUTOF_INDEX  2
#define ERROR_DATA_NOT_EXIST    3
#define KEEPDATA_DIRECTORYNAME @"CardName"

#define TITLETEXT @"titleText"
#define LOGNAME @"LOGNAME"

#define LOG_LIST_LOADING 1
#define LOG_BULK_LOADING 2
#define LOG_DELETE 3
#define LOG_LIST_LOADING_FROM_APPFILE 4


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

