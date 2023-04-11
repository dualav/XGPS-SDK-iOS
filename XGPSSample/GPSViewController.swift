//
//  FirstViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit
import XGPSSDKSwift

class GPSViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, XGPSDelegate {
    func didUpdateSettings() {
        
    }
    
    static let KEY_CONNECTION = "Connection"
    static let KEY_BATTERY = "Battery level"
    static let KEY_LATITUDE = "Latitude"
    static let KEY_LONGITUDE = "Longitude"
    static let KEY_ALTITUDE = "Altitude"
    static let KEY_HEADING = "Heading"
    static let KEY_SPEED = "Speed"
    static let KEY_UTC = "UTC Time"
    static let KEY_WAAS = "WAAS Active"
    static let KEY_AVERAGE = "Average SNR"
    static let KEY_VIEW = "# in view "
    static let KEY_USE = "# in use "
    static let KEY_GLONASS_VIEW = "# in view(GLONASS)"
    static let KEY_GLONASS_USE = "# in use(GLONASS)"
    let section = ["Device Status", "GPS Info.", "Satellites"]
    var items = [[KEY_CONNECTION, KEY_BATTERY], [KEY_LATITUDE, KEY_LONGITUDE, KEY_ALTITUDE, KEY_HEADING, KEY_SPEED, KEY_UTC, KEY_WAAS], [KEY_AVERAGE]]
    let items160 = [[KEY_CONNECTION, KEY_BATTERY], [KEY_LATITUDE, KEY_LONGITUDE, KEY_ALTITUDE, KEY_HEADING, KEY_SPEED, KEY_UTC, KEY_WAAS], [KEY_VIEW, KEY_USE], [KEY_GLONASS_VIEW, KEY_GLONASS_USE]]

    let appDelegate = AppDelegate.getDelegate()
    var xGpsManager = AppDelegate.getDelegate().xGpsManager
    
//    @IBOutlet weak var titleItem: UINavigationItem!
    @IBOutlet weak var statusTableView: UITableView!
    var waitingView: WaitingToConnectView!
   
    var itemValues:[String:String] = [:]
    var connectedFlasher : Bool = false
    override func viewDidLoad() {
        super.viewDidLoad()
        waitingView = WaitingToConnectView()
        self.view.addSubview(waitingView)
        statusTableView.delegate = self
        statusTableView.dataSource = self
        initializeObject()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if let title = xGpsManager.currentModel {
            self.navigationController?.navigationBar.topItem?.title = title
        }
        xGpsManager.delegate = self
        xGpsManager.commandStreamEnable()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        DispatchQueue.main.async() {
            self.waitingView.redraw()
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: - custom functions
    func initializeObject() {
        if let title = xGpsManager.currentModel {
            self.navigationController?.navigationBar.topItem?.title = title
            waitingView.isHidden = true
        }
        clearItemValues()
    }
    
    func clearItemValues() {
        itemValues.removeAll()
        for sectionArray in items {
            for key in sectionArray {
                itemValues[key] = "Waiting..."
            }
        }
    }

    // MARK: - tableview delegate
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        return self.section[section]
        
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.section.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        if (section >= self.items.count) {
            return 0
        }
        
        return self.items[section].count
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "tableCell")
        
        // Configure the cell...
        let key = self.items[indexPath.section][indexPath.row]
        cell.textLabel?.text = key
        if key.elementsEqual("Connection") {
            cell.detailTextLabel?.textColor = UIColor.green
        }
        cell.detailTextLabel?.text = itemValues[key]
        
        return cell
        
    }
    
    // MARK: - XGPS delegate
    func didUpdate(connected: Bool) {
        print("didUpdate \(connected)")
        if connected {
            waitingView.isHidden = true
            appDelegate.loadingCustomLayouts()
            initializeObject()
            itemValues[GPSViewController.KEY_CONNECTION] = "Connected"
        }
        else {
            waitingView.isHidden = false
            clearItemValues()
            itemValues[GPSViewController.KEY_CONNECTION] = "DisConnected"
            statusTableView.reloadData()
        }
    }
    
    func didUpdateGpsInfo(modelNumber: String, isCharging: Bool, betteryLevel: Float) {
        var appendString = ""
        if connectedFlasher {
            appendString = " _"
        }
        else {
            appendString = " •"
        }
        connectedFlasher = !connectedFlasher
        itemValues[GPSViewController.KEY_CONNECTION] = "Connected" + appendString
        var chargingInfo = ""
        if isCharging {
            chargingInfo = " (Charging)"
        }
        itemValues[GPSViewController.KEY_BATTERY] = String(format:"%.0f%%", betteryLevel * 100) + chargingInfo
        statusTableView.reloadData()
    }
    
    func didUpdatePositionData(fixType: Int, latitude:Double, longitude: Double, altitude: Float,
                               speedAndCourseIsValid:Bool, speed: Float, heading: Float,
                               utcTime: String, waas: Bool, dgps: Bool) {
        
        if fixType > 1 {   // 1 = Fix not available, 2 = 2D fix, 3 = 3D fix
            itemValues[GPSViewController.KEY_LATITUDE] = String(format: "%.2f", latitude) + "˚"
            itemValues[GPSViewController.KEY_LONGITUDE] = String(format: "%.2f", longitude) + "˚"
            itemValues[GPSViewController.KEY_ALTITUDE] = "Waiting more"
            itemValues[GPSViewController.KEY_UTC] = utcTime
            if waas {
                itemValues[GPSViewController.KEY_WAAS] = "Yes"
            }
            else {
                itemValues[GPSViewController.KEY_WAAS] = "No"
            }
            if fixType == 3 {
                itemValues[GPSViewController.KEY_ALTITUDE] = String(altitude) + " m"
            }
            
            if speedAndCourseIsValid {
                itemValues[GPSViewController.KEY_SPEED] = String(speed) + " kph"
                itemValues[GPSViewController.KEY_HEADING] = String(heading) + "˚"
            }
            else {
                itemValues[GPSViewController.KEY_SPEED] = "N/A"
                itemValues[GPSViewController.KEY_HEADING] = "N/A"
            }
        }
    }
    
    
    func getSystemName(forRawValue rawValue: Int) -> String {
        if let name = GnssSystemId(rawValue: rawValue) {
            return String(format: "\(name)")
        }
        return "UNKNOWN"
    }
    
    func didUpdateSatelliteData(systemId: GnssSystemId,
                                usedArray : NSArray,
                                systemInfo : NSDictionary,
                                averageSNR : Int) {
       
        let systemName = getSystemName(forRawValue: systemId.rawValue)
        var satNums:[Int] = []
        for signalId in systemInfo.allKeys {
            let dictInfo = systemInfo.object(forKey: signalId) as! NSDictionary
            for key in dictInfo.allKeys as! [Int] { // key means sat num
                if !satNums.contains(key) {
                    satNums.append(key)
                }
            }
        }
        for item in items[2] {
            if (item.contains(systemName)) {
                if (item.contains(GPSViewController.KEY_VIEW)) {
                    itemValues["\(GPSViewController.KEY_VIEW) \(systemName)"] = String(satNums.count)
                } else if (item.contains(GPSViewController.KEY_USE)) {
                    itemValues["\(GPSViewController.KEY_USE) \(systemName)"] = String(usedArray.count)
                }
            } else if (items[2].filter { $0.contains(systemName) }.count == 0) {
                items[2].append("\(GPSViewController.KEY_VIEW) \(systemName)")
                items[2].append("\(GPSViewController.KEY_USE) \(systemName)")
                itemValues["\(GPSViewController.KEY_VIEW) \(systemName)"] = String(satNums.count)
                itemValues["\(GPSViewController.KEY_USE) \(systemName)"] = String(usedArray.count)
            } else if (item.contains(GPSViewController.KEY_AVERAGE)) {
                itemValues[GPSViewController.KEY_AVERAGE] = String(averageSNR)
            }
        }

    }
}

