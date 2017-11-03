//
//  SettingsViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit

class SettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, XGPSDelegate, SettingDetailDelegate {
    static let KEY_SPEED_UNIT = "Show speed in"
    static let KEY_ALTITUDE_UNIT = "Show altitude in"
    static let KEY_POSITION_UNIT = "Display position as"
    static let KEY_UPDATE_RATE = "Update Rate"
    static let KEY_RECORD_TURN_ON = "Always record position when turned on"
    static let KEY_OVERWRITE_OLD = "When memory is full, overwrite it."
    static let KEY_RECORD_RATE = "Log recording rate"
    let TAG_RECORD_TURN_ON = 1
    let TAG_OVERWRITE_OLD = 2
    let section150 = ["Display Units", "Update Setting"]
    let section160 = ["Display Units", "Log Record Settings"]
    let items150 = [[KEY_SPEED_UNIT, KEY_ALTITUDE_UNIT, KEY_POSITION_UNIT], [KEY_UPDATE_RATE]]
    let items160 = [[KEY_SPEED_UNIT, KEY_ALTITUDE_UNIT, KEY_POSITION_UNIT], [KEY_RECORD_TURN_ON, KEY_OVERWRITE_OLD, KEY_RECORD_RATE]]
    var section:[String] = []
    var items:[[String]] = [[]]

    let appDelegate = AppDelegate.getDelegate()
    var xGpsManager: XGPSManager?
    var sectionCount: Int = 0
    
    @IBOutlet weak var settingsTableView: UITableView!
    var waitingView: WaitingToConnectView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        waitingView = WaitingToConnectView()
        self.view.addSubview(waitingView)
        xGpsManager = appDelegate.xGpsManager
        xGpsManager?.delegate = self
        settingsTableView.delegate = self
        settingsTableView.dataSource = self
        initializeObject()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.navigationBar.topItem?.title = "Settings"
        xGpsManager?.puck?.readDeviceSettings()
        setAvailabilityOfUI()
        // register for notifications from the app delegate that the XGPS150/160 has connected to the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceConnected), name: NSNotification.Name(rawValue: "DeviceConnected"), object: nil)
        // register for notifications from the app delegate that the XGPS150/160 has disconnected from the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceDisconnected), name: NSNotification.Name(rawValue: "DeviceDisconnected"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.setAvailabilityOfUI), name: NSNotification.Name(rawValue: "DeviceSettingsValueChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshUIAfterAwakening), name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
        if xGpsManager?.puck?.isConnected == false {
            displayDeviceNotAttachedMessage()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DeviceConnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DeviceDisconnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DeviceSettingsValueChanged"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: - custom functions
    func initializeObject() {
        if let title = xGpsManager?.currentModel {
            if title.contains(XGPSManager.XGPS150) {
                items = items150
                section = section150
            }
            else if title.contains(XGPSManager.XGPS160) {
                items = items160
                section = section160
            }
            sectionCount = section.count
            waitingView.isHidden = true
        }
        clearItemValues()
    }
    
    func clearItemValues() {
    }
    
    // MARK: - tableview delegate
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        return self.section[section]
        
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
//        return self.section.count
        return sectionCount
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        
        return self.items[section].count
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "settingCell")

        // Configure the cell...
        // TODO : integrate user default key & dictionary key
        let key = self.items[indexPath.section][indexPath.row]
        if key == SettingsViewController.KEY_SPEED_UNIT {
            cell.accessoryType = UITableViewCellAccessoryType.disclosureIndicator
            if let unit = UserDefaults.standard.string(forKey: "speed_preference") {
                cell.detailTextLabel?.text = unit
            }
        }
        else if key == SettingsViewController.KEY_ALTITUDE_UNIT {
            cell.accessoryType = UITableViewCellAccessoryType.disclosureIndicator
            let unit = UserDefaults.standard.string(forKey: "altitude_preference")
            cell.detailTextLabel?.text = unit
        }
        else if key == SettingsViewController.KEY_POSITION_UNIT {
            cell.accessoryType = UITableViewCellAccessoryType.disclosureIndicator
            let unit = UserDefaults.standard.string(forKey: "position_preference")
            cell.detailTextLabel?.text = unit
        }
        else if key == SettingsViewController.KEY_RECORD_TURN_ON {
            let value = UserDefaults.standard.bool(forKey: "record_turn_on_preference")
            let switchView = UISwitch(frame: .zero)
            switchView.setOn(value, animated: true)
            switchView.tag = TAG_RECORD_TURN_ON
            switchView.addTarget(self, action: #selector(self.switchChanged(_:)), for: .valueChanged)
            cell.accessoryView = switchView
        }
        else if key == SettingsViewController.KEY_OVERWRITE_OLD {
            let value = UserDefaults.standard.bool(forKey: "record_overwrite_preference")
            let switchView = UISwitch(frame: .zero)
            switchView.setOn(value, animated: true)
            switchView.tag = TAG_OVERWRITE_OLD
            switchView.addTarget(self, action: #selector(self.switchChanged(_:)), for: .valueChanged)
            cell.accessoryView = switchView
        }
        else if key == SettingsViewController.KEY_RECORD_RATE {
            cell.accessoryType = UITableViewCellAccessoryType.disclosureIndicator
            let unit = UserDefaults.standard.string(forKey: "record_rate_preference")
            cell.detailTextLabel?.text = unit
        }
        else if key == SettingsViewController.KEY_UPDATE_RATE {
            cell.accessoryType = UITableViewCellAccessoryType.disclosureIndicator
            let unit = UserDefaults.standard.string(forKey: "update_rate_preference")
            cell.detailTextLabel?.text = unit
        }
        
        cell.textLabel?.text = key
//        cell.detailTextLabel?.text = itemValues[key]
        
        return cell
        
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)
        if cell?.accessoryType == UITableViewCellAccessoryType.disclosureIndicator {
            let vc =  self.storyboard?.instantiateViewController(withIdentifier: "SettingDetail") as! SettingDetailViewController
            let title: String = (cell?.textLabel?.text)!
            let value: String = (cell?.detailTextLabel?.text)!
            var details:[String] = []
            // TODO : setting next time
            /*if title == SettingsViewController.KEY_SPEED_UNIT {
                details = Constants.speedUnits
            }
            else if title == SettingsViewController.KEY_ALTITUDE_UNIT {
                details = Constants.altitudeUnits
            }
            else if title == SettingsViewController.KEY_POSITION_UNIT {
                details = Constants.positionUnits
            }
            else */if title == SettingsViewController.KEY_UPDATE_RATE {
                details = Constants.updateRates
                vc.setData(section: title, items: details, selected: value)
                vc.delegate = self
                self.show(vc, sender: nil)
            }
            else if title == SettingsViewController.KEY_RECORD_RATE {
                details = Constants.recordingRates
                vc.setData(section: title, items: details, selected: value)
                vc.delegate = self
                self.show(vc, sender: nil)
            }
            // TODO : setting next time
//            vc.setData(section: title, items: details, selected: value)
//            vc.delegate = self
//            self.show(vc, sender: nil)
        }
        print("tableview didselect")
    }
    
    // MARK: - SettingDetail delegate
    func didSelected(key:String, selected: Int) {
        print("didSelect \(key) selected : \(selected)")
        // TODO : save keys to predefinition
        if key == SettingsViewController.KEY_SPEED_UNIT {
            UserDefaults.standard.set(Constants.speedUnits[selected], forKey: "speed_preference")
        }
        else if key == SettingsViewController.KEY_ALTITUDE_UNIT {
            UserDefaults.standard.set(Constants.altitudeUnits[selected], forKey: "altitude_preference")
        }
        else if key == SettingsViewController.KEY_POSITION_UNIT {
            UserDefaults.standard.set(Constants.positionUnits[selected], forKey: "position_preference")
        }
        else if key == SettingsViewController.KEY_RECORD_RATE {
            UserDefaults.standard.set(Constants.recordingRates[selected], forKey: "record_rate_preference")
            var settingValue: Int = 10
            if selected == 0 {
                settingValue = 1
            }
            else if selected == 1 {
                settingValue = 2
            }
            else if selected == 2 {
                settingValue = 10
            }
            else if selected == 3 {
                settingValue = 50
            }
            else if selected == 4 {
                settingValue = 200
            }
            xGpsManager?.puck?.setLoggingUpdateRate(UInt8(settingValue))
        }
        else if key == SettingsViewController.KEY_UPDATE_RATE {
            UserDefaults.standard.set(Constants.updateRates[selected], forKey: "update_rate_preference")
        }
        settingsTableView.reloadData()
//        let speedUnit = UserDefaults.standard.string(forKey: "speed_preference")
    }
    
    @objc func switchChanged(_ sender : UISwitch!) {
        print("table row switch Changed \(sender.tag)")
        print("The switch is \(sender.isOn ? "ON" : "OFF")")
        if sender.tag == TAG_RECORD_TURN_ON {
            UserDefaults.standard.set(sender.isOn, forKey: "record_turn_on_preference")
            xGpsManager?.puck?.setAlwaysRecord(sender.isOn)
        }
        else if sender.tag == TAG_OVERWRITE_OLD {
            UserDefaults.standard.set(sender.isOn, forKey: "record_overwrite_preference")
            xGpsManager?.puck?.setNewLogDataToOverwriteOldData(sender.isOn)
        }
    }
    
    // MARK: - XGPS delegate
    func didUpdate(connected: Bool) {
        print("didUpdate \(connected)")
        if connected {
            waitingView.isHidden = true
            appDelegate.loadingCustomLayouts()
            initializeObject()
        }
        else {
            waitingView.isHidden = false
            clearItemValues()
        }
    }
    
    func displayDeviceNotAttachedMessage() {
        waitingView.isHidden = false
    }
    
    func dismissDeviceNotAttachedMessage() {
        waitingView.isHidden = true
        setAvailabilityOfUI()
    }
    
    
    @objc func deviceConnected() {
        dismissDeviceNotAttachedMessage()
    }
    
    @objc func deviceDisconnected() {
        displayDeviceNotAttachedMessage()
    }
    
    @objc func refreshUIAfterAwakening() {
        if xGpsManager?.puck?.isConnected == false {
            displayDeviceNotAttachedMessage()
        }
        else {
            dismissDeviceNotAttachedMessage()
        }
    }
    
    @objc func setAvailabilityOfUI() {
        if xGpsManager?.puck?.deviceSettingsHaveBeenRead == false {
            sectionCount = 1
//            xGpsManager?.puck?.readDeviceSettings()
            settingsTableView.reloadData()
        }
        else {
            sectionCount = section.count
            waitingView.isHidden = true
            settingsTableView.reloadData()
            if let value = xGpsManager?.puck?.alwaysRecordWhenDeviceIsOn {
                UserDefaults.standard.set(value, forKey: "record_turn_on_preference")
            }
            else {
                UserDefaults.standard.set(false, forKey: "record_turn_on_preference")
            }
            if let value = xGpsManager?.puck?.stopRecordingWhenMemoryFull {
                UserDefaults.standard.set(!value, forKey: "record_overwrite_preference")
            }
            else {
                UserDefaults.standard.set(false, forKey: "record_overwrite_preference")
            }
            // a log update rate value of 255 means the XGPS160 is using the default value of one sample per second.
//            recordingRates = ["10Hz", "5Hz", "1Hz", "5sec", "20sec"]
            if let value = xGpsManager?.puck?.logUpdateRate {
                if value == 1 {  // 10 hz
                    UserDefaults.standard.set(Constants.recordingRates[0], forKey: "record_rate_preference")
                    //                updateRateChoice.selectedSegmentIndex = 0
                }
                else if value == 2 { // 5hz
                    UserDefaults.standard.set(Constants.recordingRates[1], forKey: "record_rate_preference")
                    //                updateRateChoice.selectedSegmentIndex = 1
                }
                else if value == 10 {
                    UserDefaults.standard.set(Constants.recordingRates[2], forKey: "record_rate_preference")
                    //                updateRateChoice.selectedSegmentIndex = 2
                }
                else if value == 255 {
                    UserDefaults.standard.set(Constants.recordingRates[2], forKey: "record_rate_preference")
                    //                updateRateChoice.selectedSegmentIndex = 2
                }
                else if value == 50 {
                    UserDefaults.standard.set(Constants.recordingRates[3], forKey: "record_rate_preference")
                    //                updateRateChoice.selectedSegmentIndex = 3
                }
                else if value == 200 {
                    UserDefaults.standard.set(Constants.recordingRates[4], forKey: "record_rate_preference")
                }
                else {
                    //                updateRateChoice.selectedSegmentIndex = Int(UISegmentedControlNoSegment)
                    UserDefaults.standard.set(Constants.recordingRates[2], forKey: "record_rate_preference")
                }
            }
            else {
                UserDefaults.standard.set(Constants.recordingRates[2], forKey: "record_rate_preference")
            }
        }
    }
            // a log update rate value of 255 means the XGPS160 is using the default value of one sample per second.
}


