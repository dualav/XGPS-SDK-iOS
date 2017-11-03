//
//  TripDetailViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 11. 2..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit

class TripDetailCell : UITableViewCell {
    @IBOutlet weak var sampleIndexLabel: UILabel!
    @IBOutlet weak var latitudeLabel: UILabel!
    @IBOutlet weak var longitudeLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
    @IBOutlet weak var movementLabel: UILabel!
    @IBOutlet weak var timestampLabel: UILabel!
}

class TripDetailViewController : UITableViewController, ProgressDialogViewControllerDelegate {
    private let appDelegate = AppDelegate.getDelegate()
    var xGpsManager: XGPSManager?
    var waitingView: WaitingToConnectView!
    
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
        if xGpsManager?.puck?.isConnected == false {
            displayDeviceNotAttachedMessage()
        }
        else {
            dismissDeviceNotAttachedMessage()
        }
    }
    
    // MARK: - View lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        // It will take a moment or two for the XGPS150/160 to send the sample data to the app, particularly
        // when the log file is large. So look for a notification from the API that the sample data has
        // all been download into app memory.
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshGPSDataTableView), name: NSNotification.Name(rawValue: "DoneReadingGPSSampleData"), object: nil)
        // register for notifications from the app delegate that the XGPS150/160 has connected to the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceConnected), name: NSNotification.Name(rawValue: "DeviceConnected"), object: nil)
        // register for notifications from the app delegate that the XGPS150/160 has disconnected from the iPod/iPad/iPhone
        NotificationCenter.default.addObserver(self, selector: #selector(self.deviceDisconnected), name: NSNotification.Name(rawValue: "DeviceDisconnected"), object: nil)
        // Listen for notification from the app delegate that the app has resumed becuase the UI may need to
        // update itself if the device status changed while the iPod/iPad/iPhone was asleep.
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshUIAfterAwakening), name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
        if xGpsManager?.puck?.isConnected == false {
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
        if xGpsManager?.puck?.streamingMode == true {
            xGpsManager?.puck?.enterLogAccessMode()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DeviceConnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DeviceDisconnected"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "RefreshUIAfterAwakening"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "DoneReadingGPSSampleData"), object: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "ExportSegue") {
            let progressDialog = segue.destination as? ProgressDialogViewController
            progressDialog?.delegate = self
        }
    }
    
    @IBAction func doneButtonAction(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    // MARK: - Table view data source
    @objc func refreshGPSDataTableView() {
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count: Int? = xGpsManager?.puck?.logDataSamples.count
        if count == 0 {
            spinner.startAnimating()
        }
        else {
            spinner.stopAnimating()
        }
        return count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TripDetailCell", for: indexPath) as! TripDetailCell
        if let sample = xGpsManager?.puck?.logDataSamples[indexPath.row] {
            let dict = sample as? NSDictionary
            let latitude = dict!["lat"] as! Float
            let longigude = dict!["lon"] as! Float
            let altitude = dict!["alt"] as! Float
            let heading = dict!["heading"] as! Float
            let speed = dict!["speed"] as! Int
            
            cell.sampleIndexLabel.text = "#\(Int(indexPath.row) + 1)"
            cell.latitudeLabel.text = String(format: "%.4f˚", latitude)
            cell.longitudeLabel.text = String(format: "%.4f˚", longigude)
            cell.altitudeLabel.text = String(format: "%.0f feet", altitude)
            cell.movementLabel.text = String(format: "%.0f˚ at %ld mph", heading, speed)
        }
        return cell as? UITableViewCell ?? UITableViewCell()
    }
    
    // MARK: - progress Dialog delegate
    func progressDialogViewControllerDidCancel(_ controller: ProgressDialogViewController) {
        dismiss(animated: true, completion: nil)
    }
    
    func progressDialogViewControllerIsDone(_ controller: ProgressDialogViewController) {
        dismiss(animated: true, completion: nil)
    }

}

