//
//  xgpscommand.h
//  SkyPro for XGPS160
//
//  Created by jk on 20181904.
//  Copyright © 2018 namsung. All rights reserved.
//

#ifndef xgpscommand_h
#define xgpscommand_h


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
    
    cmd160_streamStop = 10,
    cmd160_streamResume,
    
    cmd160_logDisable,
    cmd160_logEnable,  // 전원 껏다켜도 로그기능 살아잇음
    cmd160_logOneshot, //  전원 켜면 로그 기능 꺼짐
    
    cmd160_logPause, // 로그 일시정지
    cmd160_logResume,// 로그 재시작
    
    cmd160_logInterval,  // 로그가 날아오는 hz 설정
    cmd160_logOWEnable,    // datalog over-write enable
    cmd160_logOWDisable,// datalog over-write disable
    
    cmd160_getSettings = 20, // 기기의 모든 설정정보 가져옴
    
    cmd160_logReadBulk, // 로그 상세 가져옴
    cmd160_logList,     // 로그 리스트 헤더 정보만 가져옴
    cmd160_logListItem, // 리스트 중에 못받은것 개별로 가져오기 -> 별로 안쓰임
    cmd160_logRead,     // 로그 상세중에 못받은것 개별로 가져오기 -> 별로 안쓰임
    cmd160_logDelBlock, // 헤어에서 날아온 블럭정보가 잇는데 그 블럭 정보로 각각의 로그를 지울수 잇음
    
    cmd160_resetSettings,
    cmd160_fwVersion,
    
    cmd160_recentList,  // 블루투스 연결기기 목록 보여줌
    cmd160_recentDel,   // 그 기기 연결 끊음
    
    cmd160_gpsForceColdStart = 44,
    
    //++++++++++++++++++++++++++++++++++
    // Commands added in the USPS firmware
    
    cmd160_logTypeSetNative = 50,
    cmd160_logTypeSetNMEA = 51,
    cmd160_logTypeGet = 52,
    cmd160_logEntrySize = 53,        // v2.2.0
    
    cmd160_logGetHostMac = 55,        // v2.0.11
    
    // commands added on v2.0.3
    cmd160_setIdleShutdown = 60,// shutdown on no connection
    cmd160_getIdleShutdown,
    cmd160_setOneDevMode,        // set max concurrent connection to 1
    cmd160_getOneDevMode,
    cmd160_setAutoLogging,        // start data log on link loss
    cmd160_getAutoLogging,
    cmd160_setLinkSave,            // store infomation on connected devices
    cmd160_getLinkSave,
    cmd160_setBtSsp,            // enable Bluetooth Secure-Simple-Pairing (SSP)
    cmd160_getBtSsp,
    //cmd160_getBdAddr,            // v2.0.6, return current Bluetooth MAC or Device address
    //++++++++++++++++++++++++++++++++++
    
    //tony-20140627-Check BTAddr
    cmd160_getBdAddr = 200,//cmd160_CheckBTAddr = 200,
    cmd160_EraseMemAllBLK = 201,
    //end of tony
    //#####################################
    // END OF XGPS160 COMMANDS
    //#####################################
    
    //#if (XGPS_MODEL != 1602 && XGPS_MODEL != 1603)
    //#####################################
    
    // XGPS500 COMMANDS
    
    cmd160_GetProductName = 202,
    cmd160_gpsSetRefreshRate = 71,
    
    cmd160_setPowerGps = 72,
    cmd160_setPowerBt = 73,
    
    cmd160_logTypeSet = 54,
    
    // commands added on 20160105
    cmd160_fileList = 80,
    cmd160_fileDelete,
    cmd160_fileReadOpen,
    cmd160_fileRead,
    cmd160_fileWriteOpen,
    cmd160_fileWrite,
    cmd160_fileClose,
    cmd160_fileDump,
    cmd160_fileFreeSpace = 110,
    cmd160_fileDumpStop = 111,
    //#endif
    
    //#if XGPS_MODEL == 165
    // commands for AHRS configuration
    cmd160_compassCalib = 90,
    cmd160_compassCalibInfo,
    //#endif
    
    //#if XGPS_MODEL == 500
    cmd160_setStreamMode = 100,
    cmd160_getStreamMode = 101,
    //#endif
};

#endif /* xgpscommand_h */
