//
//  SecondViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 27..
//  Copyright © 2017년 namsung. All rights reserved.
//
// This View controller visible only XGPS160

import UIKit

class TripsCell : UITableViewCell {
    @IBOutlet weak var dateAndTimeLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var logListIndexLabel: UILabel!
    @IBOutlet weak var numberOfGPSSamplesLabel: UILabel!
    
}

class TripViewController: UITableViewController {
    @IBOutlet weak var spinner: UIActivityIndicatorView!
//    @IBOutlet weak var topTitleBar: UINavigationItem!
    var topTitleBar: UINavigationItem?
    
    private let appDelegate = AppDelegate.getDelegate()
    var xGpsManager: XGPSManager?
    
    let kNoXGPSMessageView = 100
    private var selectedIndex: Int = 0
    private var lastSelectedIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        xGpsManager = appDelegate.xGpsManager
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshInvoked(_:forState:)), for: .valueChanged)
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
        xGpsManager?.puck?.enterLogAccessMode()
    }
    
    func setTableTitleText() {
        var num: Int = 0
        if let count = xGpsManager?.puck?.logListEntries.count {
            num = count
        }
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
    
    @objc func refreshInvoked(_ sender: Any, forState: UIControlState) {
        print("\(#function). clearing logListEntries array")
        topTitleBar?.title = "%Reloading Recorded Trips..."
        if let entry = xGpsManager?.puck?.logListEntries {
            entry.removeAllObjects()
            tableView.reloadData()
            xGpsManager?.puck?.getListOfRecordedLogs()
            refreshLogEntryTableView()
            refreshControl?.endRefreshing()
        }
    }
    
    // MARK: - View lifecycle methods
    
    override func viewWillAppear(_ animated: Bool) {
        topTitleBar = self.navigationController?.navigationBar.topItem
        topTitleBar?.rightBarButtonItem = editButtonItem
        setTableTitleText()
        // register for notifications from the app delegate that the XGPS150/160 has connected to the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceConnected), name: NSNotification.Name(rawValue: "DeviceConnected"), object: nil)
        // register for notifications from the app delegate that the XGPS150/160 has disconnected from the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceDisconnected), name: NSNotification.Name(rawValue: "DeviceDisconnected"), object: nil)
        // register for notifications from the API that the device (XGPS160 only) is done reading the log list entries
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshLogEntryTableView), name: NSNotification.Name(rawValue: "DoneReadingLogListEntries"), object: nil)
        // Listen for notification from the app delegate that the app has resumed becuase the UI may need to
        // update itself if the device status changed while the iPod/iPad/iPhone was asleep.
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshUIAfterAwakening), name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
        if xGpsManager?.puck?.isConnected == false {
            displayDeviceNotAttachedMessage()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // No need to enter log access mode if we're already in it, e.g. coming back from the detailed log view
        if xGpsManager?.puck?.streamingMode == true {
            xGpsManager?.puck?.enterLogAccessMode()
            setTableTitleText()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DeviceConnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DeviceDisconnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DoneReadingLogListEntries"), object: nil)
    }
    
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var count: Int = 0
        
        if let entry = self.xGpsManager?.puck?.logListEntries {
            count = entry.count
        }
        if count == 0 {
            spinner.startAnimating()
        }
        else {
            spinner.stopAnimating()
        }
        return count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let CellIdentifier = "LogListEntryCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier, for: indexPath) as? TripsCell
        if let logListEntry = xGpsManager?.puck?.logListEntries[indexPath.row] {
            let dict = logListEntry as? NSDictionary
            let date = dict!["humanFriendlyStartDate"] as? String
            let time = dict!["humanFriendlyStartTime"] as? String
            let duration = dict!["humanFriendlyDuration"] as? String
            let samples = dict!["countEntry"] as? Int
            
            cell?.logListIndexLabel.text = "#\(Int(indexPath.row) + 1)"
            cell?.dateAndTimeLabel.text = String(format:"%@ %@", date!, time!)
            cell?.durationLabel.text = duration
            cell?.numberOfGPSSamplesLabel.text = String(describing: samples!) // "\(samples))"
        }
        return cell as? UITableViewCell ?? UITableViewCell()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndex = indexPath.row
        if selectedIndex == lastSelectedIndex {
            return
        }
        let logListEntry = xGpsManager?.puck?.logListEntries[selectedIndex]
        //NSLog(@"%s. loglistEntry = %@", __FUNCTION__, logListEntry);
        lastSelectedIndex = selectedIndex
        xGpsManager?.puck?.getGPSSampleData(forLogListItem: logListEntry as! [AnyHashable : Any])
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
            let logListEntry = xGpsManager?.puck?.logListEntries[indexPath.row]
            xGpsManager?.puck?.deleteGPSSampleData(forLogListItem: logListEntry as! [AnyHashable : Any])
            self.tableView.beginUpdates()
            self.tableView.deleteRows(at: [indexPath], with: .fade)
            self.tableView.endUpdates()
            setTableTitleText()
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
        if xGpsManager?.puck?.isConnected == false {
            displayDeviceNotAttachedMessage()
        }
        else {
            dismissDeviceNotAttachedMessage()
        }
    }
    

}

