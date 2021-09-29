//
//  TripDetailViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 11. 2..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit

class LogBulkData:NSObject, NSCoding {
    let date: String
    let latitude: Float
    let longitude: Float
    let altitude: Float
    let speed: Int64
    let heading: Int
    let tod: Int
    let utc: String
    let todString: String
    
    init(date: String, latitude: Float, longitude: Float,
         altitude: Float, speed: Int64, heading: Int,
         tod: Int, utc: String, todString: String) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.heading = heading
        self.tod = tod
        self.utc = utc
        self.todString = todString
    }
    
    required convenience init(coder aDecoder: NSCoder) {
        let date = aDecoder.decodeObject(forKey: "date") as! String
        let latitude = aDecoder.decodeFloat(forKey: "latitude")
        let longitude = aDecoder.decodeFloat(forKey: "longitude")
        let altitude = aDecoder.decodeFloat(forKey: "altitude")
        let speed = aDecoder.decodeInt64(forKey: "speed")
        let heading = aDecoder.decodeInteger(forKey: "heading")
        let tod = aDecoder.decodeInteger(forKey: "tod")
        let utc = aDecoder.decodeObject(forKey: "utc") as! String
        let todString = aDecoder.decodeObject(forKey: "todString") as! String
        self.init(date: date, latitude: latitude, longitude: longitude,
                  altitude: altitude, speed: speed, heading: heading,
                  tod: tod, utc: utc, todString: todString)
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(date, forKey: "date")
        aCoder.encode(latitude, forKey: "latitude")
        aCoder.encode(longitude, forKey: "longitude")
        aCoder.encode(altitude, forKey: "altitude")
        aCoder.encode(speed, forKey: "speed")
        aCoder.encode(heading, forKey: "heading")
        aCoder.encode(tod, forKey: "tod")
        aCoder.encode(utc, forKey: "utc")
        aCoder.encode(todString, forKey: "todString")
    }
}

class TripDetailCell : UITableViewCell {
    @IBOutlet weak var sampleIndexLabel: UILabel!
    @IBOutlet weak var latitudeLabel: UILabel!
    @IBOutlet weak var longitudeLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
    @IBOutlet weak var movementLabel: UILabel!
    @IBOutlet weak var timestampLabel: UILabel!
}

class TripDetailViewController : UITableViewController, ProgressDialogViewControllerDelegate, TripLogDelegate {
    private let appDelegate = AppDelegate.getDelegate()
    var xGpsManager = AppDelegate.getDelegate().xGpsManager
    var waitingView: WaitingToConnectView!
    var logBulkDataList:[LogBulkData] = []
    
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    let kNoXGPSMessageView = 100
    
    // MARK: - Methods to update UI based on device connection status
    
    func displayDeviceNotAttachedMessage() {
        view.viewWithTag(kNoXGPSMessageView)?.isHidden = false
    }
    
    func dismissDeviceNotAttachedMessage() {
        view.viewWithTag(kNoXGPSMessageView)?.isHidden = true
    }
    
    @objc func deviceConnected() {
        dismissDeviceNotAttachedMessage()
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
    
    // MARK: - View lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        // It will take a moment or two for the XGPS150/160 to send the sample data to the app, particularly
        // register for notifications from the app delegate that the XGPS150/160 has connected to the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceConnected), name: NSNotification.Name(rawValue: "PuckConnected"), object: nil)
        // register for notifications from the app delegate that the XGPS150/160 has disconnected from the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceDisconnected), name: NSNotification.Name(rawValue: "PuckDisconnected"), object: nil)
        // Listen for notification from the app delegate that the app has resumed becuase the UI may need to
        // update itself if the device status changed while the iPod/iPad/iPhone was asleep.
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshUIAfterAwakening), name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
        if xGpsManager.isConnected() == false {
            displayDeviceNotAttachedMessage()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        xGpsManager = appDelegate.xGpsManager
        waitingView = WaitingToConnectView()
        self.view.addSubview(waitingView)
        waitingView.isHidden = true;
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // No need to enter log access mode if we're already in it, e.g. coming back from the detailed log view
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "PuckConnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "PuckDisconnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "ExportSegue") {
            let progressDialog = segue.destination as? ProgressDialogViewController
            progressDialog?.delegate = self
            progressDialog?.logBulkDataList = logBulkDataList
        }
    }
    
    @IBAction func doneButtonAction(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    func loadFromXGPS(logData: LogData) {
//        loadingEnable = true
        logBulkDataList.removeAll()
        print("setLogDataAndLoad : \(logData)")
//        self.logData = logData
        xGpsManager.commandGetLogBulk(logData: logData, delegate: self)
    }
    
    // MARK: TripLogDelegate
    func logListComplete() {
    }
    
    func getUsedSpace(_ usedSize:Float) {
    }
    
    @objc func logBulkProgress(_ progress: UInt) {
    }
    
    @objc func logBulkComplete(_ data: Data) {
        logBulkDataList.removeAll()
        for dic in xGpsManager.logBulkDic() {
            let date : String = ((dic as! NSDictionary).object(forKey: "date") as? String)!
            let lat : Float = ((dic as! NSDictionary).object(forKey: "lat") as? NSNumber)?.floatValue ?? 0
            let long : Float = ((dic as! NSDictionary).object(forKey: "long") as? NSNumber)?.floatValue ?? 0
            let alt : Float = ((dic as! NSDictionary).object(forKey: "alt") as? NSNumber)?.floatValue ?? 0
            let utc : String = ((dic as! NSDictionary).object(forKey: "utc") as? String)!
            let tod : Int = ((dic as! NSDictionary).object(forKey: "tod") as? NSNumber)?.intValue ?? 0
            let spd : String = ((dic as! NSDictionary).object(forKey: "spd") as? String)!
            let heading: Int = ((dic as! NSDictionary).object(forKey: "heading") as? NSNumber)?.intValue ?? 0
            let titleText : String = ((dic as! NSDictionary).object(forKey: TITLETEXT) as? String)!
            let logBulkData = LogBulkData(date: date, latitude: lat, longitude: long,
                                          altitude: alt, speed: Int64(spd) ?? 0, heading: heading, 
                                          tod: tod, utc: utc, todString: XGPSManager.UTCToLocal(date: titleText))
            logBulkDataList.append(logBulkData)
        }
        tableView.reloadData()
    }
    
    
    // MARK: - Table view data source
    @objc func refreshGPSDataTableView() {
//        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count: Int = logBulkDataList.count
        if count == 0 {
            spinner.startAnimating()
        }
        else {
            spinner.stopAnimating()
        }
        return count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TripDetailCell", for: indexPath) as! TripDetailCell
        if logBulkDataList.count > indexPath.row {
            let sample = logBulkDataList[indexPath.row]
            cell.sampleIndexLabel.text = "#\(Int(indexPath.row) + 1)"
            cell.latitudeLabel.text = String(format: "%.4f", sample.latitude)
            cell.longitudeLabel.text = String(format: "%.4f˚", sample.longitude)
            cell.altitudeLabel.text = String(format: "%.0f feet", sample.altitude)
            cell.movementLabel.text = String(format: "%.0f˚ at %ld mph", sample.heading, sample.speed)
            cell.timestampLabel.text = sample.utc
        }
        return cell
    }
    
    // MARK: - progress Dialog delegate
    func progressDialogViewControllerDidCancel(_ controller: ProgressDialogViewController) {
        dismiss(animated: true, completion: nil)
    }
    
    func progressDialogViewControllerIsDone(_ controller: ProgressDialogViewController) {
        dismiss(animated: true, completion: nil)
    }

}

