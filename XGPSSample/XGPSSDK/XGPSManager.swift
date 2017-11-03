//
//  XGPSAPI.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//

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
    var puck: Puck? = nil
    var currentModel:String?
    var delegate: XGPSDelegate?
    
    init() {
        print("XGPSManager init")
        self.puck = Puck.init()
        
        if let serialNumber = puck?.serialNumber as String! {
            if serialNumber.contains(XGPSManager.XGPS150) || serialNumber.contains(XGPSManager.XGPS160) {
                currentModel = serialNumber
            }
        }
        

        NotificationCenter.default.addObserver(self, selector: #selector(deviceDataUpdated), name: NSNotification.Name(rawValue: "DeviceDataUpdated"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceConnected), name: NSNotification.Name(rawValue: "DeviceConnected"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceDisConnected), name: NSNotification.Name(rawValue: "DeviceDisconnected"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(positionDataUpdated), name: NSNotification.Name(rawValue: "PositionDataUpdated"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(positionDataUpdated), name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        self.puck = nil
    }
    
    @objc func deviceDataUpdated() {
        if delegate?.didUpdateGpsInfo == nil {
            return
        }
        delegate?.didUpdateGpsInfo!(modelNumber: (puck?.serialNumber)!, isCharging: (puck?.isCharging)!, betteryLevel: (puck?.batteryVoltage)!)
    }
    
    @objc func deviceConnected() {
        print("deviceConnected")
        if let serialNumber = puck?.serialNumber as String! {
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
        if let value = puck!.lat {
            latitude = value.floatValue
        }
        if let value = puck!.lon {
            longitude = value.floatValue
        }
        if let value = puck!.alt {
            altitude = value.floatValue
        }
        if let value = puck!.speedKph {
            speed = value.floatValue
        }
        if let value = puck!.trackTrue {
            heading = value.floatValue
        }
        if let value = puck!.numOfSatInView {
            satellitesInView = value.intValue
        }
        if let value = puck!.numOfSatInUse {
            satellitesInUse = value.intValue
        }
        if let value = puck!.numOfGLONASSSatInView {
            glonassInView = value.intValue
        }
        if let value = puck!.numOfGLONASSSatInUse {
            glonassInUse = value.intValue
        }
        if let value = puck!.fixType {
            fixType = value.intValue
        }
        if let value = puck!.utc {
            utcTime = value
        }
        delegate?.didUpdatePositionData!(fixType: fixType, latitude:latitude, longitude: longitude, altitude: altitude,
                                         speedAndCourseIsValid: puck!.speedAndCourseIsValid, speed: speed, heading: heading,
                                         utcTime:utcTime, waas:puck!.waasInUse,
                                         satellitesInView:satellitesInView, satellitesInUse: satellitesInUse,
                                         glonassInView: glonassInView, glonassInUse: glonassInUse)

    }
    
//        // Listen for notification from the app delegate that the app has resumed becuase the UI may need to
//        // update itself if the device status changed while the iPod/iPad/iPhone was asleep.
//        [[NSNotificationCenter defaultCenter] addObserver:self
//            selector:@selector(refreshUIAfterAwakening)
//            name:@"RefreshUIAfterAwakening"
//            object:nil];
//    }
}

