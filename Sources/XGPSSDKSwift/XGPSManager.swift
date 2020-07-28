//
//  XGPSAPI.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//

import Foundation
import XGPSSDK

////////////////////////////////////////////////////////////////////////////////////////////////
// Delegate
@objc
public protocol XGPSDelegate: class {
    func didUpdate(connected: Bool) -> Void
    @objc optional func didUpdateGpsInfo(modelNumber:String, isCharging:Bool, betteryLevel:Float) -> Void
    @objc optional func didUpdateSettings() -> Void
    @objc optional func didUpdatePositionData(fixType: Int, latitude:Float, longitude: Float, altitude: Float,
                                              speedAndCourseIsValid:Bool, speed: Float, heading: Float,
                                              utcTime: String, waas: Bool,
                                              satellitesInView:Int, satellitesInUse: Int,
                                              glonassInView: Int, glonassInUse: Int) -> Void
}

//extension XGPSDelegate {
//    func didUpdateGpsInfo(modelNumber:String, isCharging:Bool, betteryLevel:Float) -> Void {}
//}

public class XGPSManager {
    public static let XGPS150 = "XGPS150"
    public static let XGPS160 = "XGPS160"
    public var puck: Puck
    public var currentModel:String?
    public var delegate: XGPSDelegate?
    
    public init() {
        print("XGPSManager init")
        self.puck = Puck()
        
        if let serialNumber = puck.serialNumber as String? {
            if serialNumber.contains(XGPSManager.XGPS150) || serialNumber.contains(XGPSManager.XGPS160) {
                currentModel = serialNumber
            }
        }
        

        NotificationCenter.default.addObserver(self, selector: #selector(deviceDataUpdated), name: NSNotification.Name(rawValue: "PuckDataUpdated"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceConnected), name: NSNotification.Name(rawValue: "PuckConnected"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceDisConnected), name: NSNotification.Name(rawValue: "PuckDisconnected"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(positionDataUpdated), name: NSNotification.Name(rawValue: "PositionDataUpdated"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(positionDataUpdated), name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func deviceDataUpdated() {
        if delegate?.didUpdateGpsInfo == nil {
            return
        }
        delegate?.didUpdateGpsInfo!(modelNumber: (puck.serialNumber)! as String, isCharging: puck.isCharging, betteryLevel: puck.batteryVoltage)
    }
    
    @objc func deviceConnected() {
        print("deviceConnected")
        if let serialNumber = puck.serialNumber as String? {
            if serialNumber.contains(XGPSManager.XGPS150) || serialNumber.contains(XGPSManager.XGPS160) {
                currentModel = serialNumber
            }
        }
        delegate?.didUpdate(connected: true)
    }

    @objc func deviceDisConnected() {
        print("deviceDisConnected")
        currentModel = nil
        delegate?.didUpdate(connected: false)
    }
    
    @objc func refreshUIAfterAwakening() {
        print("refreshUIAfterAwakening")
    }

    @objc func positionDataUpdated() {
        if delegate?.didUpdatePositionData == nil {
            return
        }
        
        var latitude, longitude, altitude, speed, heading: Float
        (latitude, longitude, altitude, speed, heading) = (0.0, 0.0, 0.0, 0.0, 0.0)
        var fixType, satellitesInView, satellitesInUse, glonassInView, glonassInUse: Int
        (fixType, satellitesInView, satellitesInUse, glonassInView, glonassInUse) = (1, 0, 0, 0, 0)
        var utcTime: String = ""
        latitude = puck.latitude
        longitude = puck.longitude
        altitude = puck.alt
        speed = puck.speedKph
        heading = puck.trackTrue
        satellitesInView = Int(puck.numOfSatInView)
        satellitesInUse = Int(puck.numOfSatInUse)
        glonassInView = Int(puck.numOfSatInViewGlonass)
        glonassInUse = Int(puck.numOfSatInUseGlonass)
        fixType = Int(puck.fixType)
        utcTime = puck.utc as String
        delegate?.didUpdatePositionData!(fixType: fixType, latitude:latitude, longitude: longitude, altitude: altitude,
                                         speedAndCourseIsValid: puck.speedAndCourseIsValid, speed: speed, heading: heading,
                                         utcTime:utcTime, waas:puck.waasInUse,
                                         satellitesInView:satellitesInView, satellitesInUse: satellitesInUse,
                                         glonassInView: glonassInView, glonassInUse: glonassInUse)

    }
    
    public func isConnected() -> Bool {
        return puck.isConnected
    }
    
    public func logListData() -> NSMutableArray {
        return puck.logListData
    }
    
    public func logBulkDic() -> NSMutableArray {
        return puck.logBulkDic
    }
    
    public func loggingEnabled() -> Bool {
        return puck.loggingEnabled
    }
    
    public func logOverWriteEnabled() -> Bool {
        return puck.logOverWriteEnabled
    }
    
    public func logInterval() -> Int32 {
        return puck.logInterval
    }
    
    // MARK: puck command list
    public func commandGetSettings() {
        puck.sendCommand(toDevice: Int32(cmd160_getSettings), 0, nil, 0)
    }
    
    public func commandLogAccessMode() {
        /* It's much simpler to deal with log data information while the device is not streaming GPS data. So the
         recommended practice is to pause the NMEA stream output during the time that logs are being accessed
         and manipulated.
         
         However, the command to pause the output needs to be sent from a background thread in order to ensure there
         is space available for an output stream. Only this command needs to be on the background thread. Once
         the stream is paused, commands can be sent on the main thread.
         */
        DispatchQueue.global(qos: .default).async(execute: {
            self.puck.sendCommand(toDevice: Int32(cmd160_streamStop), 0, nil, 0)
        })
    }
    
    public func commandStreamEnable() {
        puck.streamEnable()
    }
    
    public func commandStreamDisable() {
        puck.streamDisable()
    }
    
    public func commandGetLogList(delegate: TripLogDelegate) {
        print("cmd160_logList")
        puck.logListData.removeAllObjects()
        puck.logBulkDic.removeAllObjects()
        puck.tripLogDelegate = delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.puck.sendCommand(toDevice: Int32(cmd160_logList), 0, nil, 0)
        }
//        DispatchQueue.global(qos: .default).async(execute: {
//            self.puck.sendCommand(toDevice: Int32(cmd160_logList), 0, nil, 0)
//        })
    }
    
    public func commandGetFreeSpace() {
        puck.sendCommand(toDevice: Int32(cmd160_fileFreeSpace), 0, nil, 0)
    }
    
    public func commandLogDelete(logData: LogData) {
        let startBlock = (logData.startBlock)
        let countBlock = (logData.countBlock)
        print("start block: \(startBlock) -- block number: \(countBlock)")
        
        if startBlock < 0 || startBlock >= 520 {
            return
        }
        if countBlock < 0 || countBlock > 520 {
            return
        }
        let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        var bytes = [UInt8(startBlock >> 8), UInt8(startBlock), UInt8(countBlock >> 8), UInt8(countBlock)]
        buff.initialize(from: &bytes, count: 4)
        puck.sendCommand(toDevice: Int32(cmd160_logDelBlock), 0, buff, 4)
    }
    
    public func commandGetLogBulk(logData: LogData, delegate: TripLogDelegate) {
        puck.tripLogDelegate = delegate
        let dataExportBlock = logData.startBlock
        let dataExportNumBlock = logData.countBlock
        let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        var bytes = [UInt8(dataExportBlock >> 8), UInt8(dataExportBlock), UInt8(dataExportNumBlock >> 8), UInt8(dataExportNumBlock)]
        buff.initialize(from: &bytes, count: 4)
        puck.sendCommand(toDevice: Int32(cmd160_logReadBulk), 0, buff, 4)
    }
    
    public func commandSetAlwaysRecord(isOn: Bool) {
        if isOn {
            puck.loggingEnabled = true
            puck.sendCommand(toDevice: Int32(cmd160_logEnable), 0, nil, 0)
        }
        else {
            puck.loggingEnabled = false
            puck.sendCommand(toDevice: Int32(cmd160_logDisable), 0, nil, 0)
        }
    }
    
    public func commandSetOverwriteOld(isOn: Bool) {
        if isOn {
            puck.logOverWriteEnabled = true
            puck.sendCommand(toDevice: Int32(cmd160_logOWEnable), 0, nil, 0)
        }
        else {
            puck.logOverWriteEnabled = false
            puck.sendCommand(toDevice: Int32(cmd160_logOWDisable), 0, nil, 0)
        }
    }
    
    @discardableResult
    public func commandLoggingUpdateRate(_ rate: UInt8) -> Bool {
        if checkForAdjustableRateLogging() == false {
            print("Device firware version does not support adjustable logging rates. Firmware 1.3.5 or greater is required.")
            print("Firware updates are available through the XGPS160 Status Tool app.")
            return false
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
        if (Int(rate) != 1) && (Int(rate) != 2) && (Int(rate) != 5) && (Int(rate) != 10) && (Int(rate) != 20) && (Int(rate) != 30) && (Int(rate) != 40) && (Int(rate) != 50) && (Int(rate) != 100) && (Int(rate) != 120) && (Int(rate) != 150) && (Int(rate) != 200) {
            print("\(#function). Invaid rate: \(rate)")
            return false
        }
        /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
         is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
         */
        // Break the data into an array of elements
        let buff = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        buff.initialize(to: UInt8(rate))
        puck.sendCommand(toDevice: Int32(cmd160_logInterval), 0, buff, 1)
        
        return true
    }
    
    public static func UTCToLocal(date:String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd  HH:mm:ss"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let dt = dateFormatter.date(from: date)
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy/MM/dd  HH:mm:ss"
        if dt == nil {
            return date
        }
        
        return dateFormatter.string(from: dt!)
    }
    
    func checkForAdjustableRateLogging() -> Bool {
        // Devices with firmware 1.3.5 and above have a configurable logging rate.
        // Devices with firmware versions less than 1.3.5 below cannot accept the rate change commands.
        // So check the firmware version and report yes if 1.3.5 or above.
        let versionNumbers = puck.firmwareRev.components(separatedBy: ".")
        let majorVersion = Int(versionNumbers[0]) ?? 0
        let minorVersion = Int(versionNumbers[1]) ?? 0
        let subVersion = Int(versionNumbers[2]) ?? 0
        if majorVersion > 1 {
            return true
        } else if minorVersion > 3 {
            return true
        } else if (minorVersion == 3) && (subVersion >= 5) {
            return true
        } else {
            return false
        }
    }

}

