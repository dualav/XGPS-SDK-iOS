//
//  SecondViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//
// This View controller visible only XGPS160

import UIKit
import XGPSSDKSwift
import XGPSSDK

class TripsCell : UITableViewCell {
    @IBOutlet weak var dateAndTimeLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var logListIndexLabel: UILabel!
    @IBOutlet weak var numberOfGPSSamplesLabel: UILabel!
    
}

class TripViewController: UITableViewController, TripLogDelegate {
    @IBOutlet weak var spinner: UIActivityIndicatorView!
//    @IBOutlet weak var topTitleBar: UINavigationItem!
    var topTitleBar: UINavigationItem?
    
    let appDelegate = AppDelegate.getDelegate()
    let xGpsManager = AppDelegate.getDelegate().xGpsManager
    
    let kNoXGPSMessageView = 100
    var selectedIndex: Int = 0
    var selectedLogData: LogData? = nil
    var lastSelectedIndex: Int = 0
    var logItems:[LogData] = []
    var timeoutTask: DispatchWorkItem? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
//        refreshControl = UIRefreshControl()
//        refreshControl?.addTarget(self, action: #selector(refreshInvoked(_:forState:)), for: .valueChanged)
        selectedIndex = 0
        lastSelectedIndex = -1

    }
    
    override func viewDidDisappear(_ animated: Bool) {
        topTitleBar?.rightBarButtonItem = nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func stopStreaming() {
        xGpsManager.commandLogAccessMode()
    }
    
    func setTableTitleText() {
        let num: Int = logItems.count
        print("\(#function). here. # of records = \(num).")
        if num == 0 {
            topTitleBar?.title = "No Trips in Memory"
        }
        else if num == 1 {
            topTitleBar?.title = "1 Trip in Memory"
        }
        else {
            topTitleBar?.title = "\(num) Trips in Memory"
        }
        
    }
    
    @objc func refreshLogEntryTableView() {
        setTableTitleText()
        tableView.reloadData()
    }

    // MARK: - View lifecycle methods
    
    override func viewWillAppear(_ animated: Bool) {
        topTitleBar = self.navigationController?.navigationBar.topItem
        topTitleBar?.rightBarButtonItem = editButtonItem
        setTableTitleText()
        // register for notifications from the app delegate that the XGPS150/160 has connected to the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceConnected), name: NSNotification.Name(rawValue: "PuckConnected"), object: nil)
        // register for notifications from the app delegate that the XGPS150/160 has disconnected from the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceDisconnected), name: NSNotification.Name(rawValue: "PuckDisconnected"), object: nil)
        // update itself if the device status changed while the iPod/iPad/iPhone was asleep.
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshUIAfterAwakening), name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
        
        if xGpsManager.isConnected() == false {
            displayDeviceNotAttachedMessage()
        }
        else {
            xGpsManager.commandLogAccessMode()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        getLogList()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "PuckConnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "PuckDisconnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "TripDetail" {
            let nextController = segue.destination as! TripDetailViewController
            if let indexPath = tableView.indexPathForSelectedRow {
                let logData = logItems[indexPath.row]
                nextController.loadFromXGPS(logData: logData)
            }
        }
    }
    
    // MARK: getting log list command
    func getLogList() {
        logItems.removeAll()
        if xGpsManager.isConnected() {
            xGpsManager.commandGetLogList(delegate: self)
            
            timeoutTask = DispatchWorkItem {
                // TODO : close or dismiss something within 9 sec
            }
            
            // execute task in 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 9, execute: timeoutTask!)
        }

    }
    
    func reload() {
        print("reload()")
        DispatchQueue.global(qos: .default).async(execute: {() -> Void in

            DispatchQueue.main.async(execute: {() -> Void in
                self.timeoutTask?.cancel()
                if self.xGpsManager.isConnected() {
                    // get Storage   /////////////////////////////////////////////////////////////////////
                    var countBlock: Float = 0
                    for dic in self.xGpsManager.logListData() {
                        if let block: String = ((dic as! NSDictionary).object(forKey: "countBlock") as? String) {
                            countBlock += Float(block)!
                            let sig : String = ((dic as! NSDictionary).object(forKey: "sig") as? String)!
                            let interval : String = ((dic as! NSDictionary).object(forKey: "interval") as? String)!
                            let startBlock : String = ((dic as! NSDictionary).object(forKey: "startBlock") as? String)!
                            let countEntry : String = ((dic as! NSDictionary).object(forKey: "countEntry") as? String)!
                            let startDate : String = ((dic as! NSDictionary).object(forKey: "startDate") as? String)!
                            let startTod : String = ((dic as! NSDictionary).object(forKey: "startTod") as? String)!
                            let titleText : String = ((dic as! NSDictionary).object(forKey: TITLETEXT) as? String)!
                            let localDateTime : String = XGPSManager.UTCToLocal(date: titleText)
                            let logData = LogData.init(sig: (Int(sig) ?? 0), interval: Int(interval)!,
                                                       startBlock: Int(startBlock)!, countEntry: Int(countEntry)!,
                                                       countBlock: Int(block)!, createDate: startDate, createTime: startTod, fileSize: 0,
                                                       defaultString: localDateTime, localFilename: "")
                            self.logItems.append(logData)
                        }
                    }
                    countBlock = (countBlock / 520) * 100
                    if countBlock > 0 && countBlock < 1 {
                        countBlock = 1
                    }
                }
                self.refreshLogEntryTableView()
                ////////////////////////////////////////////////////////////////////////////////////////
            })
        })
    }
    
    func deleteFromXGPS(logData: LogData) {
        xGpsManager.commandLogDelete(logData: logData)
        getLogList()
    }
    
    // MARK: TripLogDelegate
    func logListComplete() {
        xGpsManager.commandGetFreeSpace()
        print("\(#function). clearing logListEntries array")
        topTitleBar?.title = "%Reloading Recorded Trips..."
        reload()
    }
    
    func getUsedSpace(_ usedSize:Float) {
        print("getFreeSpace : \(usedSize)")
    }
    
    func logBulkProgress(_ progress: UInt) {
    }
    
    func logBulkComplete(_ data: Data) {
    }
    
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return logItems.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let CellIdentifier = "LogListEntryCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier, for: indexPath) as! TripsCell
        if logItems.count <= indexPath.row {
            return cell
        }
        
        let key = logItems[indexPath.row]

        cell.logListIndexLabel.text = "#\(Int(indexPath.row) + 1)"
        cell.dateAndTimeLabel.text = String(format:"%@ %@", key.createDate, key.createTime)
        cell.durationLabel.text = ""
        cell.numberOfGPSSamplesLabel.text = "\(key.countEntry)"
        
        return cell
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .delete
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if (indexPath.row < logItems.count) {
                let logData = logItems[indexPath.row]
                deleteFromXGPS(logData: logData)
                setTableTitleText()
            }
        }
    }
    
    // MARK: - Methods to update UI based on device connection status
    
    func displayDeviceNotAttachedMessage() {
        view.viewWithTag(kNoXGPSMessageView)?.isHidden = false
    }
    
    func dismissDeviceNotAttachedMessage() {
        view.viewWithTag(kNoXGPSMessageView)?.isHidden = true
        stopStreaming()
    }
    
    @objc func deviceConnected() {
        dismissDeviceNotAttachedMessage()
        stopStreaming()
    }
    
    @objc func deviceDisconnected() {
        displayDeviceNotAttachedMessage()
    }
    
    @objc func refreshUIAfterAwakening() {
        if xGpsManager.isConnected() == false {
            displayDeviceNotAttachedMessage()
        }
        else {
            dismissDeviceNotAttachedMessage()
        }
    }
    

}

