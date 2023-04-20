# XGPS-SDK-iOS

![](https://img.shields.io/badge/Swift-4.0_5.0-orange.svg?style=flat)
![](https://img.shields.io/badge/sdk-Swift_ObjectiveC-orange.svg?style=flat)
![](https://img.shields.io/badge/Platforms-iOS-Green?style=flat-square)
![](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)

This project provides the source code and example code that XGPS150/XGPS160/DashPro exchanges data with iPhone device via Bluetooth connection.


## Installation

#### 1. File > Add Package 
![](https://user-images.githubusercontent.com/33018203/231606594-dca26a40-25d1-440a-a32e-424ee9a8c7c8.png)

#### 2. Find 'xgps' and click 'Add Package'
![](https://user-images.githubusercontent.com/33018203/231606598-30478a64-6f16-4e0a-b40b-0b4e4be3f7d0.png)

#### 3. Select XGPSSDK module. (If you Swift language, also select XGPSSDKSwift)
![](https://user-images.githubusercontent.com/33018203/231606601-c95793a5-787a-4a12-a474-11ddda49772c.png)

#### 4. Add 'Supported external accessory protocols' key in your target.
![](https://user-images.githubusercontent.com/33018203/231606602-61512a21-a92b-4bca-8273-6d1aee911b8a.png)

#### 5. Click the triangle of this key and set the value for the “Item 0” to 'com.dualav.xgps150'.
![](https://user-images.githubusercontent.com/33018203/231606604-342625c8-031b-43a8-8eb7-3eea232787f4.png)


## Usage

### Implemention (Swift)

#### 1. import this SDK
```swift
import XGPSSDKSwift
```

#### 2. add the XGPSManager() into your appDelegate
```swift
var xgpsManager: XGPSManager = XGPSManager()
```

#### 3. Use XGPSDelegate 

```swift
/* this protocol is declared within SDK
public protocol XGPSDelegate: AnyObject {
    func didUpdate(connected: Bool) -> Void
    func didUpdateGpsInfo(modelNumber:String, isCharging:Bool, betteryLevel:Float) -> Void
    func didUpdateSettings() -> Void
    func didUpdatePositionData(fixType: Int, latitude:Double, longitude: Double, altitude: Float,
                                              speedAndCourseIsValid:Bool, speed: Float, heading: Float,
                                              utcTime: String, waas: Bool, dgps: Bool) -> Void
    func didUpdateSatelliteData(systemId: GnssSystemId, usedArray : NSArray,
                                systemInfo : NSDictionary,
                                averageSNR : Int) -> Void
}
*/

class ViewController: UIViewController, XGPSDelegate {
    func didUpdate(connected: Bool) {
        // Called when connection information changes.
    }
    
    func didUpdateGpsInfo(modelNumber: String, isCharging: Bool, betteryLevel: Float) {
        // Called when the status of a device's battery, etc. changes.
    }
    
    func didUpdateSettings() {
        // Called when reflection to the device is complete after setting up the setting command.
    }
    
    func didUpdatePositionData(fixType: Int, latitude: Double, longitude: Double, altitude: Float, speedAndCourseIsValid: Bool, speed: Float, heading: Float, utcTime: String, waas: Bool, dgps: Bool) {
        // GPS location information is received.
    }
    
    func didUpdateSatelliteData(systemId: XGPSSDKSwift.GnssSystemId, usedArray: NSArray, systemInfo: NSDictionary, averageSNR: Int) {
        // Satellite information is received.
    }
}
```

#### 3. Use functions for logs

```swift
func logListData() -> NSMutableArray    
func logBulkDic() -> NSMutableArray     
func loggingEnabled() -> Bool     
func logOverWriteEnabled() -> Bool
func logInterval() -> Int32
```


#### 4. Use command for setting 

```swift
func commandGetSettings()    
func commandLogAccessMode()    
func commandStreamEnable()    
func commandStreamDisable()    
func commandGetLogList(delegate: TripLogDelegate)    
func commandGetFreeSpace()    
func commandLogDelete(logData: LogData)    
func commandGetLogBulk(logData: LogData, delegate: TripLogDelegate)    
func commandSetAlwaysRecord(isOn: Bool)    
func commandSetOverwriteOld(isOn: Bool)
```

### Structure

This section describes the internal structure of the data in 'didUpdateSatelliteData' that sends satellite information values.

#### GnssSystemId

This is GNSS system id.
```swift
enum GnssSystemId: Int {
    case gps = 1
    case glonass = 2
    case galileo = 3
    case beidou = 4
    case qzss = 5
    case navic = 6
    case unknown = 7
}
```

#### usedArray (NSArray)

This value is the 'String' array of satellites ID that used in solution.

`
ex) 
usedArray : "01","08","10","27"
`

#### systemInfo (NSDictionary) 
            
```bash
systemInfo
├── NSDictionary 
│   ├── key : Signal ID
│   │    
│   └── value : NSDictionary
│       ├── key : Satellite ID : NSNumber 
│       │    
│       └── value : NSArray
│             ├── azimuth : NSNumber
│             ├── elevation : NSNumber
│             ├── SNR : NSNumber
│             └── inUse : NSNumber 
└── NSDictionary 
    ├── key : Signal ID
    │    
    └── value : NSDictionary
        ├── key : Satellite ID : NSNumber 
        │    
        └── value : NSArray
              ├── azimuth : NSNumber
              ├── elevation : NSNumber
              ├── SNR : NSNumber
              └── inUse : NSNumber 
``` 

### Trip logs
This is only for XGPS160 

#### Getting logs

```swift
let xgpsManager = AppDelegate.getDelegate().xGpsManager
if xgpsManager.isConnected() {
    xgpsManager.commandGetLogList(delegate: self)
}
```
add logListComplete() delegate function

#### Delete log
```swift
xgpsManager.commandLogDelete(logData: logData)
```

see the 'TripsViewController.swift

#### Set the Logging rate
```swift
xgpsManager.commandLoggingUpdateRate(UInt8(settingValue))
```
see the SettingsViewController.swift

## Product
![](http://gps.dualav.com/wp-content/uploads/xgps150_HeaderImage.jpg) ![](http://gps.dualav.com/wp-content/uploads/xgps160_HeaderImage.jpg)

http://gps.dualav.com/
