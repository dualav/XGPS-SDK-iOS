# XGPS-SDK-iOS

![](https://img.shields.io/badge/language-swift3-orange.svg?style=flat)
![](https://img.shields.io/badge/sdk-objectiveC-orange.svg?style=flat)
![Platform](https://img.shields.io/cocoapods/p/LFAlertController.svg?style=flat)
![](https://img.shields.io/badge/version-2.2-blue.svg?style=flat)

This project provides the source code and example code that XGPS150/XGPS160 exchanges data with iPhone device via Bluetooth connection.

## Usage

The name of core SDK is Puck. You can use the puck.m and puck.h file.

Please reference the sample code how to use the Puck.

### Implement the XGPSManager 

add the XGPSManager() into your appDelegate
```swift
var xGpsManager: XGPSManager = XGPSManager()
```
### Get GPS Information 
add the XGPSDelegate in your viewcontroller
```swift
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
```

### Get Satelletes Information
add the observer for NotificationCenter name "SatelliteDataUpdated"
for more detail option see the puck code.

### Request Trip log list
```swift
let xGpsManager = AppDelegate.getDelegate().xGpsManager
if xGpsManager.isConnected() {
    xGpsManager.commandGetLogList(delegate: self)
}
```
add logListComplete() delegate function

### Delete Trip log
```swift
func deleteFromXGPS(logData: LogData) {
    xGpsManager.commandLogDelete(logData: logData)
}
```

see the 'TripsViewController.swift

### Set the Logging rate
```swift
xGpsManager.commandLoggingUpdateRate(UInt8(settingValue))
```
see the SettingsViewController.swift
it allows only XGPS160

## Product
![](http://gps.dualav.com/wp-content/uploads/xgps150_HeaderImage.jpg) ![](http://gps.dualav.com/wp-content/uploads/xgps160_HeaderImage.jpg)


http://gps.dualav.com/
