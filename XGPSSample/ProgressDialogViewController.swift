//
//  ProgressDialogViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 11. 2..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit

protocol ProgressDialogViewControllerDelegate: NSObjectProtocol {
    func progressDialogViewControllerDidCancel(_ controller: ProgressDialogViewController)
    
    func progressDialogViewControllerIsDone(_ controller: ProgressDialogViewController)
}

class ProgressDialogViewController: UIViewController, UIDocumentInteractionControllerDelegate, UIAlertViewDelegate {
    var docController: UIDocumentInteractionController!
    var fp: FILE?
    var gpxString = ""
    var fileNameWithPath:URL!
    var fileName = ""
    var delegate: ProgressDialogViewControllerDelegate?
    var logBulkDataList:[LogBulkData] = []
    @IBOutlet weak var exportProgress: UIProgressView!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var exportLabel: UILabel!
    @IBOutlet weak var cancelDoneButton: UIButton!
    
    // MARK: - View lifecycle
    override func viewWillAppear(_ animated: Bool) {
        shareButton.isEnabled = false
        cancelDoneButton.setTitle("Cancel", for: .normal)
        exportLabel.text = "Exporting..."
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        docController = UIDocumentInteractionController()
        gpxString = "" /* String.reserveCapacity(d.xgps160.arr_logDataSamples.count()) */
    }
    
    override func viewDidAppear(_ animated: Bool) {
        createGPXLogFile()
        // do this first to define the filename - it's used to name the GPX string
        createGPXString()
        writeGPXLogFile()
        exportLabel.text = "Exporting complete."
        shareButton.isEnabled = true
        cancelDoneButton.setTitle("Done", for: .normal)
    }
    
    
    // MARK: - GPX string creation
//
//    func createBogusGPXString() {
//        gpxString += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
//        gpxString += "<gpx version=\"1.0\">"
//        gpxString += "  <name>Example gpx</name>"
//        gpxString += "  <wpt lat=\"46.57638889\" lon=\"8.89263889\">"
//        gpxString += "    <ele>2372</ele>"
//        gpxString += "    <name>LAGORETICO</name>"
//        gpxString += "  </wpt>"
//        gpxString += "  <trk><name>Example gpx</name><number>1</number><trkseg>"
//        gpxString += "    <trkpt lat=\"46.57608333\" lon=\"8.89241667\"><ele>2376</ele><time>2007-10-14T10:09:57Z</time></trkpt>"
//        gpxString += "    <trkpt lat=\"46.57619444\" lon=\"8.89252778\"><ele>2375</ele><time>2007-10-14T10:10:52Z</time></trkpt>"
//        gpxString += "    <trkpt lat=\"46.57641667\" lon=\"8.89266667\"><ele>2372</ele><time>2007-10-14T10:12:39Z</time></trkpt>"
//        gpxString += "    <trkpt lat=\"46.57650000\" lon=\"8.89280556\"><ele>2373</ele><time>2007-10-14T10:13:12Z</time></trkpt>"
//        gpxString += "    <trkpt lat=\"46.57638889\" lon=\"8.89302778\"><ele>2374</ele><time>2007-10-14T10:13:20Z</time></trkpt>"
//        gpxString += "    <trkpt lat=\"46.57652778\" lon=\"8.89322222\"><ele>2375</ele><time>2007-10-14T10:13:48Z</time></trkpt>"
//        gpxString += "    <trkpt lat=\"46.57661111\" lon=\"8.89344444\"><ele>2376</ele><time>2007-10-14T10:14:08Z</time></trkpt>"
//        gpxString += "  </trkseg></trk>"
//        gpxString += "</gpx>"
//    }
//
    func convertDateString(dateString : String!, fromFormat sourceFormat : String!, toFormat desFormat : String!) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = sourceFormat
        let date = dateFormatter.date(from: dateString)
        dateFormatter.dateFormat = desFormat
        return dateFormatter.string(from: date!)
    }
    
    func createGPXString() {
        let sizeOfTrack: Int = logBulkDataList.count
        var index: Int = 0
        // create the GPX string header
        gpxString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        gpxString += "<gpx version=\"1.0\">\n"
        gpxString += "\t<trk><name>\(fileName)</name><trkseg>\n"
        // add the trackpoint data
        for data in logBulkDataList {
            let latString = String(format : "%.6f", data.latitude)
            let lotString = String(format : "%.6f", data.longitude)
            let altString = String(format : "%.2f", data.altitude)
            let timeString = convertDateString(dateString: data.date, fromFormat: "YYYY/MM/dd", toFormat: "YYYY-MM-dd") + "T" + data.utc + "Z"
            let trackPoint = "\t\t<trkpt lat=\"\(latString)\" lon=\"\(lotString)\"><ele>\(altString)</ele><time>\(timeString)</time></trkpt>\n"
            gpxString += "\(trackPoint)"
            // update progress bar
            index += 1
            exportProgress.progress = Float(index) / Float(sizeOfTrack)
        }
        // properly terminate GPX file
        gpxString += "\t</trkseg></trk>\n"
        gpxString += "</gpx>"
        print("GPX String:\n\(gpxString)")
    }
    
    // MARK: - GPX file creation
    
    func createGPXLogFile() {
        let dir = FileManager.default.urls(for: FileManager.SearchPathDirectory.documentDirectory, in: FileManager.SearchPathDomainMask.userDomainMask).first!
//        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
//        let documentsDirectory: String = paths[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yy.dd.MM-HH.mm"
        let dateString: String = dateFormatter.string(from: Date())
        fileName = "\(dateString)-XGPS160.gpx"
//        fileNameWithPath = URL(fileURLWithPath: documentsDirectory).appendingPathComponent(fileName).absoluteString
        //NSLog(@"Filename with path =\n%@", fileNameWithPath);
        fileNameWithPath =  dir.appendingPathComponent(fileName)
    }
    
    func writeGPXLogFile() {
        let data = gpxString.data(using: .utf8, allowLossyConversion: false)!
        
        if FileManager.default.fileExists(atPath: fileNameWithPath.path) {
            if let fileHandle = try? FileHandle(forUpdating: fileNameWithPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try! data.write(to: fileNameWithPath, options: Data.WritingOptions.atomic)
        }
    }
    
    // MARK: - GPX string sharing
    
    func shareGPXString() {
        docController = UIDocumentInteractionController(url: fileNameWithPath)
        docController.delegate = self
        if !(docController.presentOptionsMenu(from: view.frame, in: view, animated: true)) {
            let alertView = UIAlertView(title: "", message: "You don't have an app installed that can handle GPX files.", delegate: self, cancelButtonTitle: "OK", otherButtonTitles: "")
            alertView.show()
        }
    }
    
 
    // MARK: - Delegate methods
    
    @IBAction func cancelButtonPressed(_ sender: Any) {
        delegate?.progressDialogViewControllerDidCancel(self)
    }
    
    @IBAction func shareButtonPressed(_ sender: Any) {
        shareGPXString()
    }
    
    func isDone(_ sender: Any) {
        delegate?.progressDialogViewControllerIsDone(self)
    }
    
    // MARK: - UIDocumentInteractionControllerDelegate methods
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, willBeginSendingToApplication application: String?) {
        //NSLog(@"Starting to send GPX file to %@", application);
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, didEndSendingToApplication application: String?) {
        //NSLog(@"GPX file sent.");
    }
    
}
