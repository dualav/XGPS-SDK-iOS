//
//  FirstViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit

class GPSViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, XGPSDelegate {
    static let KEY_CONNECTION = "Connection"
    static let KEY_BATTERY = "Battery level"
    static let KEY_LATITUDE = "Latitude"
    static let KEY_LONGITUDE = "Longitude"
    static let KEY_ALTITUDE = "Altitude"
    static let KEY_HEADING = "Heading"
    static let KEY_SPEED = "Speed"
    static let KEY_UTC = "UTC Time"
    static let KEY_WAAS = "WAAS Active"
    static let KEY_VIEW = "# in view"
    static let KEY_USE = "# in use"
    static let KEY_GLONASS_VIEW = "# in view(GLONASS)"
    static let KEY_GLONASS_USE = "# in use(GLONASS)"
    let section150 = ["Device Status", "GPS Info.", "GPS Satellites"]
    let section160 = ["Device Status", "GPS Info.", "GPS Satellites", "GLONASS Satellites"]
    let items150 = [[KEY_CONNECTION, KEY_BATTERY], [KEY_LATITUDE, KEY_LONGITUDE, KEY_ALTITUDE, KEY_HEADING, KEY_SPEED, KEY_UTC, KEY_WAAS], [KEY_VIEW, KEY_USE]]
    let items160 = [[KEY_CONNECTION, KEY_BATTERY], [KEY_LATITUDE, KEY_LONGITUDE, KEY_ALTITUDE, KEY_HEADING, KEY_SPEED, KEY_UTC, KEY_WAAS], [KEY_VIEW, KEY_USE], [KEY_GLONASS_VIEW, KEY_GLONASS_USE]]

    let appDelegate = AppDelegate.getDelegate()
    var xGpsManager = AppDelegate.getDelegate().xGpsManager
    
//    @IBOutlet weak var titleItem: UINavigationItem!
    @IBOutlet weak var statusTableView: UITableView!
    var waitingView: WaitingToConnectView!
   
    var section:[String] = []
    var items:[[String]] = [[]]
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
            if title.contains(XGPSManager.XGPS150) {
                items = items150
                section = section150
            }
            else if title.contains(XGPSManager.XGPS160) {
                items = items160
                section = section160
            }
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
//        print("didUpdateGpsInfo : \(betteryLevel)")
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
    
    func didUpdatePositionData(fixType: Int, latitude:Float, longitude: Float, altitude: Float,
                               speedAndCourseIsValid:Bool, speed: Float, heading: Float,
                               utcTime: String, waas: Bool,
                               satellitesInView:Int, satellitesInUse: Int,
                               glonassInView: Int, glonassInUse: Int) {
        
        if fixType > 1 {   // 1 = Fix not available, 2 = 2D fix, 3 = 3D fix
            itemValues[GPSViewController.KEY_LATITUDE] = String(latitude) + "˚"
            itemValues[GPSViewController.KEY_LONGITUDE] = String(longitude) + "˚"
            itemValues[GPSViewController.KEY_ALTITUDE] = "Waiting more"
            itemValues[GPSViewController.KEY_UTC] = utcTime
            if waas {
                itemValues[GPSViewController.KEY_WAAS] = "Yes"
            }
            else {
                itemValues[GPSViewController.KEY_WAAS] = "No"
            }
            itemValues[GPSViewController.KEY_VIEW] = String(satellitesInView)
            itemValues[GPSViewController.KEY_USE] = String(satellitesInUse)
            itemValues[GPSViewController.KEY_GLONASS_VIEW] = String(glonassInView)
            itemValues[GPSViewController.KEY_GLONASS_USE] = String(glonassInUse)
            
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
}

