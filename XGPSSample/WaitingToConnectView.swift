//
//  WaitingToConnectView.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 11. 1..
//  Copyright © 2017년 namsung. All rights reserved.
//
import UIKit

class WaitingToConnectView: UIView {
    
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        backgroundColor = UIColor.clear
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.clear
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func redraw() {
        self.frame = getFrame()
    }
    
    func getFrame() -> CGRect {
        let screenWidth = Int(UIScreen.main.bounds.width)
        let screenHeight = Int(UIScreen.main.bounds.height)
        var viewWidth: Int
        if screenWidth > screenHeight {
            viewWidth = screenHeight / 2
        }
        else {
            viewWidth = screenWidth / 2
        }
        return CGRect(x:Int(screenWidth/2 - viewWidth/2), y:Int(screenHeight/2 - viewWidth/2),
                            width:viewWidth, height:viewWidth)
    }
    
    override func draw(_ rect: CGRect) {
        let context: CGContext? = UIGraphicsGetCurrentContext()
        context?.saveGState()
        let radius: CGFloat = 32
        let minx: CGFloat = rect.minX
        let midx: CGFloat = rect.midX
        let maxx: CGFloat = rect.maxX
        let miny: CGFloat = rect.minY
        let midy: CGFloat = rect.midY
        let maxy: CGFloat = rect.maxY
        // Start at 1
        context?.move(to: CGPoint(x: minx, y: midy))
        // Add an arc through 2 to 3
        context?.addArc(tangent1End: CGPoint(x: minx, y: miny), tangent2End: CGPoint(x: midx, y: miny), radius: radius)
        // Add an arc through 4 to 5
        context?.addArc(tangent1End: CGPoint(x: maxx, y: miny), tangent2End: CGPoint(x: maxx, y: midy), radius: radius)
        // Add an arc through 6 to 7
        context?.addArc(tangent1End: CGPoint(x: maxx, y: maxy), tangent2End: CGPoint(x: midx, y: maxy), radius: radius)
        // Add an arc through 8 to 9
        context?.addArc(tangent1End: CGPoint(x: minx, y: maxy), tangent2End: CGPoint(x: minx, y: midy), radius: radius)
        // Close the path
        context?.closePath()
        // Fill the path
        context?.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context?.drawPath(using: .fill)
        context?.restoreGState()
        // add the text and the spinner
        let waitingLabel = UILabel(frame: CGRect(x: 11, y: 5, width: 179, height: 53))
        waitingLabel.backgroundColor = UIColor.clear
        waitingLabel.textColor = UIColor.white
        waitingLabel.textAlignment = .center
        waitingLabel.font = UIFont(name: "Helvetica-Bold", size: 16)!
        waitingLabel.numberOfLines = 2
        waitingLabel.text = "Waiting for the XGPS..."
        let spinner = UIActivityIndicatorView(frame: CGRect(x: 82, y: 66, width: 37, height: 37))
        spinner.style = .whiteLarge
        spinner.startAnimating()
        addSubview(waitingLabel)
        addSubview(spinner)
    }
}
