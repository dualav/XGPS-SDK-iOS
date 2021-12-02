//
//  SettingDetailViewController.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 11. 2..
//  Copyright © 2017년 namsung. All rights reserved.
//

import UIKit

protocol SettingDetailDelegate: class {
    func didSelected(key:String, selected: Int) -> Void
}

class SettingDetailViewController : UIViewController, UITableViewDelegate, UITableViewDataSource {
    var section:String = ""
    var items:[String] = []
    var selectedItem: String = "0"
    var delegate: SettingDetailDelegate?
    
    @IBOutlet weak var settingTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        settingTableView.delegate = self
        settingTableView.dataSource = self
    }
    
    func setData(section:String, items:[String], selected: String) {
        self.section = section
        self.items = items
        self.selectedItem = selected
    }
    
    // MARK: - tableview delegate
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        return self.section
        
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "settingDetailCell")
        // Configure the cell...
        let key = self.items[indexPath.row]
        if key == selectedItem {
            cell.accessoryType = UITableViewCell.AccessoryType.checkmark
        }
        cell.textLabel?.text = key
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.didSelected(key: self.section, selected: indexPath.row)
        self.navigationController?.popViewController(animated: true)
    }
}
