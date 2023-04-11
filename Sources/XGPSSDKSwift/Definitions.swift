//
//  Definitions.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 30..
//  Copyright © 2017년 namsung. All rights reserved.
//

public struct Definitions {
    public static let kBufferSize = 1024    // I/O stream buffer size
    public static let kProcessTimerDelay = 0.6   // See note in the processConnectNotifications method for explanation of this.
    
    public static let kVolt415 = 644    // Battery level conversion constant.
    public static let kVolt350 = 543    // Battery level conversion constant.
    public static let kMaxNumberOfSatellites = 16   // Max number of visible satellites
    
    // Set these to YES to see the NMEA sentence data logged to the debugger console
    public static let DEBUG_SENTENCE_PARSING = false
    public static let DEBUG_DEVICE_DATA = false
    public static let DEBUG_PGGA_INFO = false
    public static let DEBUG_PGSA_INFO = false
    public static let DEBUG_PGSV_INFO = false
    public static let DEBUG_PVTG_INFO = false
    public static let DEBUG_PRMC_INFO = false
    public static let DEBUG_PGLL_INFO = false
    public static let DEBUG_SESSION = false
    public static let DEBUG_CRC_CHECK = false
 
}
