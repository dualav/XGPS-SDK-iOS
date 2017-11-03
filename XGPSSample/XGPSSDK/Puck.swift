//
//  Puck.swift
//  XGPSSample
//
//  Created by hjlee on 2017. 10. 30..
//  Copyright © 2017년 namsung. All rights reserved.
//

import ExternalAccessory

class Puck {
    // These are for communicating with the XGPS150/XGPS160. Your app can ignore these.
    var serialNumber: String
    var firmwareRev: String
    var isConnected: Bool
    var isCharging: Bool
    var batteryVoltage: Float
    
    var isNotificationType = false
    var mostRecentNotification: Notification?
    var accessory: EAAccessory?
    var accessoryConnectionID: Int = 0
    var session: EASession?
    var protocolString = ""
    var isQueueTimerStarted = false
    
    // MARK: - Puck Mode Change Methods
    func isFastSampleRateAvailable() -> Bool {
        // XGPS150 only (XGPS160 runs at 10Hz)
        if serialNumber.hasPrefix("XGPS160") {
            return false
        }
        // Devices with firmware above (but not including) 1.0.34 have a fast refresh rate mode and can accept mode change
        // commands. Devices with firmware versions 1.0.34 and below cannot accept mode change commands.
        let versionNumbers = firmwareRev.components(separatedBy: ".")
        let majorVersion = Int(versionNumbers[0]) ?? 0
        let minorVersion = Int(versionNumbers[1]) ?? 0
        if (majorVersion == 1) && (minorVersion > 0) {
            return true
        }
        else {
            print("Firmware version does not support fast sample rate mode. Please update the device to version 1.2.6 or higher.")
            return false
        }
    }

    func setFastSampleRate() {
        // XGPS150 only (XGPS160 runs at 10Hz)
        if serialNumber.hasPrefix("XGPS160") {
            return
        }
        var written: Int
        let cfg5hz : [Character] = ["S", "0", "5", "F", "F", "F", "F", "F", "F", "F", "F", 0x0a]
        if isFastSampleRateAvailable() == true {
            if session == nil || session?.outputStream == nil {
                return
            }
            if session!.outputStream!.hasSpaceAvailable {
                written = session!.outputStream!.write(cfg5hz, maxLength: 12)
            }
        }
    }
    
    func setNormalSampleRate() {
        // XGPS150 only (XGPS160 runs at 10Hz)
        if serialNumber.hasPrefix("XGPS160") {
            return
        }
        var written: Int
        let cfg1hz = ["S", "0", "0", "F", "F", "F", "F", "F", "F", "F", "F", 0x0a] as? [UInt8]
        if isFastSampleRateAvailable() == true {
            guard session == nil else {
                
            }
            if session && session.outputStream {
                if session.outputStream.hasSpaceAvailable {
                    written = session.outputStream.write(cfg1hz as? UnsafePointer<UInt8> ?? UnsafePointer<UInt8>(), maxLength: 12)
                }
            }
        }
    }
    
    // MARK: - Data Input and Processing Methods
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .endEncountered:
            //NSLog(@"%s. NSStreamEventEndEncountered\n", __FUNCTION__)
            break
        case .hasBytesAvailable:
            var len: Int = 0
            let buffer = [UInt8](repeating: 0, count: kBufferSize)
            // read ADSB stream
            len = session.inputStream.read(buffer as? UnsafeMutablePointer<UInt8> ?? UnsafeMutablePointer<UInt8>(), maxLength: (kBufferSize - 1))
            if len == 0 {
                //NSLog(@"%s. Received 0 bytes.", __FUNCTION__);
            }
            buffer[len] = UInt8("\0")
            separateSentences(Character(buffer), length: len)
            break
        case .hasSpaceAvailable:
            //NSLog(@"%s. NSStreamEventHasSpaceAvailable\n", __FUNCTION__);
            break
        case .errorOccurred:
            //NSLog(@"%s. NSStreamEventErrorOccurred\n", __FUNCTION__);
            break
        case []:
            //NSLog(@"%s. NSStreamEventNone\n", __FUNCTION__);
            break
        case .openCompleted:
            //NSLog(@"%s. NSStreamEventOpenCompleted\n", __FUNCTION__);
            break
        default:
            //NSLog(@"%s. Some other stream event occurred.\n", __FUNCTION__);
            break
        }
    }
    
    func separateSentences(_ buf: UnsafePointer<Character>, length len: Int) {
        var token
        var string
        if strncmp(buf, "@", 1) == 0 {
            parseDeviceInfoSentence(buf, length: len)
            buf = nil
            return
        }
        string = strdup(buf)
        if string != nil {
            while (token = strsep(string, "\r\n")) != nil {
                if strlen(token) > 2 {
                    parseNMEA(token, length: strlen(token))
                }
            }
        }
        buf = nil
    }

    func parseDeviceInfoSentence(_ pLine: UnsafePointer<Character>, length len: Int) {
        var vbat: Int
        var bvolt: Float
        var batLevel: Float
        vbat = Int(UInt8(pLine[1]))
        vbat <<= 8
        vbat |= Int(UInt8(pLine[2]))
        if vbat < Definitions.kVolt350 {
            vbat = Definitions.kVolt350
        }
        if vbat > Definitions.kVolt415 {
            vbat = Definitions.kVolt415
        }
        bvolt = Float(vbat) * 330.0 / 512.0
        batLevel = ((bvolt / 100.0) - 3.5) / 0.65
        if batLevel > 1.0 {
            batteryVoltage = 1.0
        }
        else if batLevel < 0 {
            batteryVoltage = 0.0
        }
        else {
            batteryVoltage = batLevel
        }
        
        if pLine[5] & 0x04 {
            isCharging = true
        }
        else {
            isCharging = false
        }
        if DEBUG_DEVICE_DATA {
            print("\(#function). Battery voltage = %.2f (%.0f%%), Charging = \(bvolt / 100.0).")
        }
        pLine = nil
        // trigger a notification to the view controllers that the device data has been updated
        let puckDataUpdated = Notification(name: "DeviceDataUpdated", object: self)
        NotificationCenter.default.post(puckDataUpdated)
    }
    
    func parseNMEA(_ pLine: UnsafePointer<Character>, length len: Int) {
        // Parse the NMEA data stream from the GPS chipset. Check out http://aprs.gids.nl/nmea/ for a good
        // explanation of the various NMEA sentences.
        var elementsInSentence: [Any]
        if DEBUG_SENTENCE_PARSING {
            print("\(#function). buffer text: \(pLine)")
        }
        // Create a string from the raw buffer data
        let sentence = String(utf8String: pLine as? UnsafePointer<CChar> ?? UnsafePointer<CChar>())
        if DEBUG_SENTENCE_PARSING {
            print("\(#function). sentence is: \(sentence)")
        }
        // Perform a CRC check. The checksum field consists of a "*" and two hex digits representing
        // the exclusive OR of all characters between, but not including, the "$" and "*".
        var digit = unichar(0)
        var crcInString = unichar(0)
        var calculatedCrc = unichar("G")
        let i: Int = 0
        while i < sentence.length() {
            digit = unichar(sentence[sentence.index(sentence.startIndex, offsetBy: UInt(i))])
            if digit == 42 {
                var firstCRCChar = unichar(sentence[sentence.index(sentence.startIndex, offsetBy: (i + 1))])
                var secondCRCChar = unichar(sentence[sentence.index(sentence.startIndex, offsetBy: (i + 2))])
                if firstCRCChar > 64 {
                    firstCRCChar = (firstCRCChar - 55) * 16
                }
                else {
                    firstCRCChar = (firstCRCChar - 48) * 16
                }
                if secondCRCChar > 64 {
                    secondCRCChar = secondCRCChar - 55
                }
                else {
                    secondCRCChar = secondCRCChar - 48
                }
                crcInString = firstCRCChar + secondCRCChar
                break
            }
            calculatedCrc = calculatedCrc ^ digit
            i += 1
        }
        if DEBUG_CRC_CHECK {
            if crcInString == calculatedCrc {
                print("\(#function). CRC matches.")
            }
            else {
                print("\(#function). CRC does not match.\nCalculated CRC is 0x%.2X. NMEA sentence is: \(calculatedCrc)")
            }
        }
        if crcInString != calculatedCrc {
            return
        }
        // Break the data into an array of elements
        elementsInSentence = sentence.components(separatedBy: ",")
        // Parse the data based on the NMEA sentence identifier
        
        if (elementsInSentence[0] == "PGGA") {
            // Case 2: parse the location info
            if DEBUG_PGGA_INFO {
                print("\(#function). PGGA sentence with location info.")
                print("\(#function). buffer text = \(pLine)")
            }
            if elementsInSentence.count() < 10 {
                return
            }
            // malformed sentence
            // extract the number of satellites in use by the GPS
            if DEBUG_PGGA_INFO {
                print("\(#function). PGGA num of satellites in use = \(elementsInSentence[7]).")
            }
            // extract the altitude
            alt = elementsInSentence[9]
            if DEBUG_PGGA_INFO {
                print("\(#function). altitude = %.1f.")
            }
        }
        else if (elementsInSentence[0] == "PGSV") {
            // Case 3: parse the satellite info. Note the uBlox chipset can pick up more satellites than the
            //         Skytraq chipset. Sentences can look like:
            //
            // Skytraq chipset:
            // e.g. PGSV,3,1,11,03,03,111,00,04,15,270,00,06,01,010,00,13,06,292,00*74
            //      PGSV,3,2,11,14,25,170,00,16,57,208,39,18,67,296,40,19,40,246,00*74
            //      PGSV,3,3,11,22,42,067,42,24,14,311,43,27,05,244,00,,,,*4D
            //      no PGSV sentence produce when no signal
            //
            // uBlox chipset:
            // e.g. PGSV,1,1,00*79    (no signal)
            //      PGSV,4,1,15,02,49,269,42,04,68,346,45,05,13,198,32,09,16,269,29*78
            //      PGSV,4,2,15,10,57,149,47,12,21,319,38,13,02,101,,17,47,069,47*7E
            //      PGSV,4,3,15,20,03,038,21,23,02,074,24,27,16,254,32,28,30,154,41*79
            //      PGSV,4,4,15,33,13,102,,48,25,249,41,51,46,225,44*4E
            if DEBUG_PGSV_INFO {
                print("\(#function). buffer text = \(pLine).")
            }
            if elementsInSentence.count() < 4 {
                return
            }
            // malformed sentence
            numOfSatInView = elementsInSentence[3]
            if DEBUG_PGSV_INFO {
                print("\(#function). number of satellites in view = \(numOfSatInView).")
            }
            // handle the case of the uBlox chip returning no satellites
            if numOfSatInView == 0 {
                dictOfSatInfo.removeAll()
            }
            else {
                // If this is first GSV sentence, reset the dictionary of satellite info
                if elementsInSentence[2] == 1 {
                    dictOfSatInfo.removeAll()
                }
                var satNum: NSNumber?
                var satElev: NSNumber?
                var satAzi: NSNumber?
                var satSNR: NSNumber?
                var inUse: NSNumber?
                var satInfo: [Any]
                // The number of satellites described in a sentence can vary up to 4.
                var numOfSatsInSentence: Int
                if elementsInSentence.count() == 8 {
                    numOfSatsInSentence = 1
                }
                else if elementsInSentence.count() == 12 {
                    numOfSatsInSentence = 2
                }
                else if elementsInSentence.count() == 16 {
                    numOfSatsInSentence = 3
                }
                else if elementsInSentence.count() == 20 {
                    numOfSatsInSentence = 4
                }
                else {
                    return
                }
                
                for i in 0..<numOfSatsInSentence {
                    let index: Int = i * 4 + 4
                    inUse = false ? 1 : 0
                    satNum = elementsInSentence[index]
                    satElev = elementsInSentence[(index + 1)]
                    satAzi = elementsInSentence[(index + 2)]
                    // The stream data will not contain a comma after the last value and before the checksum.
                    // So, for example, this sentence can occur:
                    //      PGSV,3,3,10,04,12,092,,21,06,292,29*73
                    // But if the last SNR value is NULL, the device will skip the comma separator and
                    // just append the checksum. For example, this sentence can occur if the SNR value for the last
                    // satellite in the sentence is 0:
                    //    PGSV,3,3,10,15,10,189,,13,00,033,*7F
                    // The SNR value for the second satellite is NULL, but unlike the same condition with the first
                    // satellite, the sentence does not include two commas with nothing between them (to indicate NULL).
                    // All of that said, the line below handles the conversion properly.
                    satSNR = elementsInSentence[(index + 3)]
                    // On random occasions, either the data is bad or the parsing fails. Handle any not-a-number conditions.
                    if isnan(satSNR) != 0 {
                        satSNR = 0.0
                    }
                    for n: NSNumber in satsUsedInPosCalc {
                        if Int(n) == satNum {
                            inUse = true ? 1 : 0
                            break
                        }
                    }
                    satInfo = [satAzi, satElev, satSNR, inUse]
                    dictOfSatInfo[satNum] = satInfo
                }
                // It can take multiple PGSV sentences to deliver all of the satellite data. Update the UI after
                // the last of the data arrives. If the current PGSV sentence number (2nd element in the sentence)
                // is equal to the total number of PGSV messages (1st element in the sentence), that means you have received
                // the last of the satellite data.
                if elementsInSentence[2] == elementsInSentence[1] {
                    // print the captured data
                    if DEBUG_PGSV_INFO {
                        var satNums: [Any]
                        var satData: [Any]
                        satNums = [Any](arrayLiteral: dictOfSatInfo.keys)
                        // sort the array of satellites in numerical order
                        let sorter = NSSortDescriptor(key: "intValue", ascending: true)
                        NSMutableArray(array: satNums).sort(using: [sorter])
                        
                        // sort the array of satellites in numerical order
                        for i in 0..<satNums.count {
                            satData = dictOfSatInfo[satNums[i]] as? [Any] ?? [Any]()
                            print("\(#function). SatNum=\(satNums[i]). Elev=\(satData[0]). Azi=\(satData[1]). SNR=\(satData[2]). inUse=\((satData[3] != 0) ? "Yes" : "No")")
                        }
                    }
                    // Post a notification to the view controllers that the satellite data has been updated
                    let satDataUpdated = Notification(name: "SatelliteDataUpdated", object: self)
                    NotificationCenter.default.post(satDataUpdated)
                }
            }
        }
        else if (elementsInSentence[0] == "PGSA") {
            // Case 4: parse the dilution of precision info. Sentence will look like:
            //        eg1. PGSA,A,1,,,,,,,,,,,,,0.0,0.0,0.0*30
            //        eg2. PGSA,A,3,24,14,22,31,11,,,,,,,,3.7,2.3,2.9*3D
            //
            // Skytraq chipset:
            // e.g. PGSA,A,1,,,,,,,,,,,,,0.0,0.0,0.0*30     (no signal)
            //
            // uBlox chipset:
            // e.g. PGSA,A,1,,,,,,,,,,,,,99.99,99.99,99.99*30      (no signal)
            //      PGSA,A,3,02,29,13,12,48,10,25,05,,,,,3.93,2.06,3.35*0D
            
            /* Wikipedia (http://en.wikipedia.org/wiki/Dilution_of_precision_(GPS)) has a good synopsis on how to interpret
             DOP values:
             
             DOP Value    Rating        Description
             ---------    ---------    ----------------------
             1            Ideal        This is the highest possible confidence level to be used for applications demanding
             the highest possible precision at all times.
             1-2        Excellent    At this confidence level, positional measurements are considered accurate enough to meet
             all but the most sensitive applications.
             2-5        Good        Represents a level that marks the minimum appropriate for making business decisions.
             Positional measurements could be used to make reliable in-route navigation suggestions to
             the user.
             5-10        Moderate    Positional measurements could be used for calculations, but the fix quality could still be
             improved. A more open view of the sky is recommended.
             10-20        Fair        Represents a low confidence level. Positional measurements should be discarded or used only
             to indicate a very rough estimate of the current location.
             >20        Poor        At this level, measurements are inaccurate by as much as 300 meters and should be discarded.
             
             */
            if DEBUG_PGSA_INFO {
                print("\(#function). sentence contains DOP info.")
                print("\(#function). buffer text = \(pLine).")
            }
            if elementsInSentence.count() < 18 {
                return
            }
            // malformed sentence
            // extract whether the fix type is 0=no fix, 1=2D fix or 2=3D fix
            fixType = elementsInSentence[2]
            if DEBUG_PGSA_INFO {
                print("\(#function). fix value = \(fixType).")
            }
            // extract PDOP
            pdop = elementsInSentence[15]
            if DEBUG_PGSA_INFO {
                print("\(#function). PDOP value = \(pdop).")
            }
            // extract HDOP
            hdop = elementsInSentence[16]
            if DEBUG_PGSA_INFO {
                print("\(#function). HDOP value = \(hdop).")
            }
            // extract VDOP
            vdop = elementsInSentence[17]
            if DEBUG_PGSA_INFO {
                print("\(#function). VDOP value = \(vdop).")
            }
            // extract the number of satellites used in the position fix calculation
            var satInDOP: String
            var satsInDOPCalc = [Any]()
            waasInUse = false
            for i in 3..<15 {
                satInDOP = elementsInSentence[i]
                if (satInDOP.characters.count ?? 0) > 0 {
                    satsInDOPCalc.append(satInDOP)
                    if Int(satInDOP) ?? 0 > 32 {
                        waasInUse = true
                    }
                }
                satInDOP = nil
            }
            numOfSatInUse = Int(satsInDOPCalc.count)
            satsUsedInPosCalc = satsInDOPCalc
            if DEBUG_PGSA_INFO {
                print("\(#function). # of satellites used in DOP calc: \(numOfSatInUse)")
                var logTxt = "Satellites used in DOP calc: "
                for s: String in satsUsedInPosCalc {
                    logTxt += "\(s), "
                }
                print("\(#function). \(logTxt)")
            }
            satsInDOPCalc = nil
        }
        else if (elementsInSentence[0] == "PRMC") {
            // Case 6: extract whether the speed and course data are valid, as well as magnetic deviation
            //        eg1. PRMC,220316.000,V,2845.7226,N,08121.9825,W,000.0,000.0,220311,,,N*65
            //        eg2. PRMC,220426.988,A,2845.7387,N,08121.9957,W,000.0,246.2,220311,,,A*7C
            //
            // Skytraq chipset:
            // e.g. PRMC,120138.000,V,0000.0000,N,00000.0000,E,000.0,000.0,280606,,,N*75   (no signal)
            //
            //
            // uBlox chipset:
            // e.g. PRMC,,V,,,,,,,,,,N*53      (no signal)
            //      PRMC,162409.00,A,2845.73357,N,08121.99127,W,0.911,39.06,281211,,,D*4D
            if DEBUG_PRMC_INFO {
                print("\(#function). sentence contains speed & course info.")
                print("\(#function). buffer text = \(pLine).")
            }
            if elementsInSentence.count() < 9 {
                return
            }
            // malformed sentence
            // extract the time the coordinate was captured. UTC time format is hhmmss.sss
            var timeStr: String
            var hourStr: String
            var minStr: String
            var secStr: String
            timeStr = elementsInSentence[1]
            // Check for malformed data. NMEA 0183 spec says minimum 2 decimals for seconds: hhmmss.ss
            if (timeStr.characters.count ?? 0) < 9 {
                return
            }
            // malformed data
            hourStr = (timeStr as NSString).substring(with: NSRange(location: 0, length: 2))
            minStr = (timeStr as NSString).substring(with: NSRange(location: 2, length: 2))
            secStr = (timeStr as NSString).substring(with: NSRange(location: 4, length: 5))
            utc = "\(hourStr):\(minStr):\(secStr)"
            if DEBUG_PRMC_INFO {
                print("\(#function). UTC Time is \(utc).")
            }
            // is the track and course data valid? An "A" means yes, and "V" means no.
            let valid: String = elementsInSentence[2]
            if (valid == "A") {
                speedAndCourseIsValid = true
            }
            else {
                speedAndCourseIsValid = false
            }
            if DEBUG_PRMC_INFO {
                print("\(#function). speed & course data valid: \(speedAndCourseIsValid).")
            }
            // extract latitude info
            // ex:    "4124.8963, N" which equates to 41d 24.8963' N or 41d 24' 54" N
            var mins: Float
            var deg: Int
            var sign: Int
            var lat: Double
            var lon: Double
            if elementsInSentence[3].length() == 0 {
                // uBlox chip special case
                deg = 0
                mins = 0.0
            }
            else if elementsInSentence[3].length() < 7 {
                return
            }
            else {
                sign = 1
                lat = elementsInSentence[3]
                if DEBUG_PRMC_INFO {
                    print("latitude text = \(elementsInSentence[3]). converstion to float = \(lat).")
                }
                deg = Int(lat / 100)
                mins = Float((lat - (100 * Float(deg))) / 60.0)

                if DEBUG_PRMC_INFO {
                    print("degrees = \(deg). mins = %.5f.")
                }
                if (elementsInSentence[4] == "S") {
                    sign = -1
                }   // capture the "N" or "S"
            }
            self.lat = (deg + mins) * sign
            if DEBUG_PRMC_INFO {
                print("\(#function). latitude = %.5f")
            }
            // extract longitude info
            // ex: "08151.6838, W" which equates to    81d 51.6838' W or 81d 51' 41" W
            if elementsInSentence[5].length() == 0 {
                // uBlox chip special case
                deg = 0
                mins = 0.0
            }
            else if elementsInSentence[3].length() < 8 {
                return
            }
            else {
                sign = 1
                lon = elementsInSentence[5]
                if DEBUG_PRMC_INFO {
                    print("longitude text = \(elementsInSentence[5]). converstion to float = \(lon).")
                }
                deg = Int(lon / 100)
                mins = (lon - (100 * Float(deg))) / 60.0
                if DEBUG_PRMC_INFO {
                    print("degrees = \(deg). mins = %.5f.")
                }
                if (elementsInSentence[6] == "W") {
                    sign = -1
                }   // capture the "E" or "W"
            }
            lon = (deg + mins) * sign
            if DEBUG_PRMC_INFO {
                print("\(#function). longitude = %.5f")
            }
            // Pull the speed information from the RMC sentence since this updates at the fast refresh rate in the Skytraq chipset
            if (elementsInSentence[7] == "") {
                speedKnots = 0.0
            }
            else {
                speedKnots = elementsInSentence[7]
            }
            speedKph = speedKnots * 1.852
            if DEBUG_PRMC_INFO {
                print("\(#function). knots = %.1f. kph = %.1f.")
            }
            // Extract the course heading
            if (elementsInSentence[8] == "") {
                trackTrue = 0.0
            }
            else {
                trackTrue = elementsInSentence[8]
            }
            if DEBUG_PVTG_INFO {
                print("\(#function). true north course = %.1f.")
            }
            // trigger a notification to the view controllers that the satellite data has been updated
            let posDataUpdated = Notification(name: "PositionDataUpdated", object: self)
            NotificationCenter.default.post(posDataUpdated)
        }
        else if (elementsInSentence[0] == "PVTG") {
            // Case 5: parse the speed and course info. Sentence will look like:
            //        eg1. PVTG,304.5,T,,M,002.3,N,004.3,K,N*06
            //
            // Skytraq chipset:
            // e.g. PVTG,000.0,T,,M,000.0,N,000.0,K,N*02      (no signal)
            //
            // uBlox chipset:
            // e.g. PVTG,,,,,,,,,N*30      (no signal)
            //      PVTG,45.57,T,,M,0.550,N,1.019,K,D*02
            if DEBUG_PVTG_INFO {
                print("\(#function). PVTG sentence contains speed & course info.")
                print("\(#function). buffer text = \(pLine).")
            }
        }
        else if (elementsInSentence[0] == "PGLL") {
            // Case 6: Latitude, longitude and time info. Only generated by the uBlox chipset, not the Skytraq chipset.
            // Sentence will look like:
            //      eg1. PGLL,3751.65,S,14507.36,E*77
            //      eg2. PGLL,4916.45,N,12311.12,W,225444,A
            //
            // uBlox chipset:
            // e.g. PGLL,,,,,,V,N*64      (no signal)
            //      PGLL,2845.73342,N,08121.99104,W,162408.00,A,D*72
            if DEBUG_PGLL_INFO {
                print("\(#function). PGLL sentence with location info.")
                print("\(#function). buffer text = \(pLine)")
            }
        }
        else {
            if DEBUG_SENTENCE_PARSING {
                print("\(#function). Unknown sentence found: \(pLine)")
            }
        }
    }
    
    // MARK: - Application lifecycle methods
    
    func observeNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.queueConnectNotifications), name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.queueDisconnectNotifications), name: .EAAccessoryDidDisconnect, object: nil)
        // Register for notifications from the iOS that accessories are connecting or disconnecting
        EAAccessoryManager.shared().registerForLocalNotifications()
    }
    
    func stopObservingNotifications() {
        NotificationCenter.default.removeObserver(self, name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .EAAccessoryDidDisconnect, object: nil)
        EAAccessoryManager.shared().unregisterForLocalNotifications()
    }
    
    init() {
        super.init()
        
        isConnected = false
        firmwareRev = ""
        serialNumber = ""
        batteryVoltage = 0
        isCharging = false
        queueTimerStarted = false
        // Watch for local accessory connect & disconnect notifications.
        observeNotifications()
        // Check to see if device is attached.
        if isPuckAnAvailableAccessory() {
            openSession()
        }
        
    }
    
    // MARK: - BT Connection Management Methods
    // MARK: • Application lifecycle methods
    
    func puck_applicationWillResignActive() {
        /*
         Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
         Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
         */
        
        // NOTE: this method is called when:
        //        - when a dialog box (like an alert view) opens.
        //        - by a double-tap on the home button to bring up the multitasking menu
        //        - when the iPod/iPad/iPhone goes to sleep (manually or after the timer runs out)
        //        - when app exits becuase the home button is tapped (once)
        
        // Close any open streams. The OS sends a false "Accessory Disconnected" message when the home button is double tapped
        // to bring up the mutitasking menu. So the safest thing is to disconnect from the XGPS150/XGPS160 when that happens, and reconnect
        // later.
        closeSession()
        // stop watching for Accessory notifications
        stopObservingNotifications()
    }
    
    func puck_applicationDidEnterBackground() {
        // NOTE: this method is called when:
        //        - another app takes forefront.
        //        - after applicationWillResignActive in response to the home button is tapped (once)
        // Close any open streams
        closeSession()
        // stop watching for Accessory notifications
        stopObservingNotifications()
    }
    
    func puck_applicationWillEnterForeground() {
        // Called as part of the transition from the background to the inactive state: here you can undo many of the changes
        // made on entering the background.
        // NOTE: this method is called:
        //        - when an app icon is already running in the background, and the app icon is clicked to resume the app
        // Begin watching for Accessory notifications again. Do this first because the rest of the method may complete before
        // the accessory reconnects.
        observeNotifications()
        // Recheck to see if the XGPS150/XGPS160 disappeared while away
        if isConnected() == false {
            if isPuckAnAvailableAccessory() {
                openSession()
            }
        }
    }
    
    func puck_applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive.
        // If the application was previously in the background, optionally refresh the user interface.
        
        // NOTE: this method is called:
        //        - when an app first opens
        //        - when an app is running & the iPod/iPad/iPhone goes to sleep and is then reawoken, e.g. when the app is
        //          running->iPod/iPad/iPhone goes to sleep (manually or by the timer)->iPod/iPad/iPhone is woken up & resumes the app
        //        - when the app is resumed from when the multi-tasking menu is opened (in the scenario where the
        //          app was running, the multitasking menu opened by a double-tap of the home button, followed by a tap on the screen to
        //          resume the app.)
        
        // begin watching for Accessory notifications again
        observeNotifications()
        // Recheck to see if the XGPS150/XGPS160 disappeared while away
        if isConnected() == false {
            if isPuckAnAvailableAccessory() {
                openSession()
            }
        }
        // NOTE: if the iPod/iPad/iPhone goes to sleep while a view controller is open, there is no notification
        // that the app is back to life, other than this applicationDidBecomeActive method being called. The viewWillAppear,
        // viewDidAppear, or viewDidOpen methods are not triggered when the iPod/iPad/iPhone is woken and the app resumes.
        // Consequently, notify the view controllers in case they need to adjust their UI if the XGPS150/XGPS160 status changed
        // while the iPod/iPad/iPhone was asleep.
        let notification = Notification(name: "RefreshUIAfterAwakening", object: self)
        NotificationCenter.default.post(notification)
    }
    
    func puck_applicationWillTerminate() {
        // Called when the application is about to terminate. See also applicationDidEnterBackground:.
        // Close session with XGPS150/XGPS160
        closeSession()
        // stop watching for Accessory notifications
        stopObservingNotifications()
    }
    
    // MARK: • Session Management Methods
    // open a session with the accessory and set up the input and output stream on the default run loop
    func openSession() -> Bool {
        if isConnected() {
            return true
        }
        accessory.delegate = self
        session = EASession(accessory: accessory, forProtocol: protocolString!)
        if session {
            session.inputStream.delegate = self
            session.inputStream.schedule(in: RunLoop.current, forMode: .defaultRunLoopMode)
            session.inputStream.open()
            session.outputStream.delegate = self
            session.outputStream.schedule(in: RunLoop.current, forMode: .defaultRunLoopMode)
            session.outputStream.open()
            isConnected() = true
        }
        else {
            //NSLog(@"Session creation failed");
            accessory = nil
            accessoryConnectionID = 0
            protocolString = nil
        }
        return session != nil
    }
    
    // close the session with the accessory.
    
    func closeSession() {
        // Closing the streams and releasing session disconnects the app from the XGPS150/XGPS160, but it does not disconnect
        // the XGPS150/XGPS160 from Bluetooth. In other words, the communication streams close, but the device stays
        // registered with the OS as an available accessory.
        //
        // The OS can report that the device has disconnected in two different ways: either that the stream has
        // ended or that the device has disconnected. Either event can happen first, so this method is called
        // in response to a NSStreamEndEventEncountered (from method -stream:handlevent) or in response to an
        // EAAccessoryDidDisconnectNotification (from method -accessoryDisconnected). It seems that the speed of
        // the Apple device being used, e.g. iPod touch gen vs. iPad, affects which event occurs first.
        // Turning off the power on the XGPS150/XGPS160 tends to cause the NSStreamEndEventEncountered to occur
        // before the EAAccessoryDidDisconnectNotification.
        //
        // Note also that a EAAccessoryDidDisconnectNotification is generated when the home button
        // is tapped (bringing up the multitasking menu) beginning in iOS 5.
        if session == nil {
            return
        }
        session.inputStream.remove(from: RunLoop.main, forMode: .defaultRunLoopMode)
        session.inputStream.close()
        session.inputStream.delegate = nil
        session.outputStream.remove(from: RunLoop.main, forMode: .defaultRunLoopMode)
        session.outputStream.close()
        session.outputStream.delegate = nil
        session = nil
        isConnected() = false
        accessory = nil
        accessoryConnectionID = 0
        protocolString = nil
    }
    
    func isPuckAnAvailableAccessory() -> Bool {
        var connect = false
        if isConnected() {
            return true
        }
        // get the list of all attached accessories (30-pin or bluetooth)
        let attachedAccessories = EAAccessoryManager.shared().connectedAccessories
        for obj: EAAccessory in attachedAccessories {
            if obj.protocolStrings.contains("com.dualav.xgps150") {
                // At this point, the XGPS150/XGPS160 has a BT connection to the iPod/iPad/iPhone, but the
                // communication streams have not been opened yet
                connect = true
                firmwareRev = obj.firmwareRevision
                serialNumber = obj.serialNumber
                accessory = obj
                accessoryConnectionID = obj.connectionID
                protocolString = "com.dualav.xgps150"
            }
        }
        if !connect {
            //NSLog(@"%s. XGPS150/160 NOT detected.", __FUNCTION__);
            firmwareRev = nil
            serialNumber = nil
            accessory = nil
            accessoryConnectionID = 0
            protocolString = nil
        }
        return connect
    }
    
    // MARK: • Accessory watchdog methods
    /* When the XGPS150/XGPS160 connects after being off, the iOS generates a very rapid seqeunce of
     connect-disconnect-connect events. The solution is wait until all of the notifications have
     come in, and process the last one.
     */
    
    func processConnectionNotifications() {
        queueTimerStarted = false
        if notificationType != CKNotificationType(rawValue: 0)! {
            if isPuckAnAvailableAccessory() == true {
                if openSession() == true {
                    // Notify the view controllers that the XGPS150/XGPS160 is connected and streaming data
                    let notification = Notification(name: "PuckConnected", object: self)
                    NotificationCenter.default.post(notification)
                }
            }
        }
        else {
            // The iOS can send a false disconnect notification when the home button is double-tapped
            // to enter the multitasking menu. So in the event of a EAAccessoryDidDisconnectNotification, double
            // check that the device is actually gone before disconnecting from the XGPS150/XGPS160.
            if accessory.connected == true {
                return
            }
            else {
                closeSession()
                // Notify the view controllers that the XGPS150/XGPS160 disconnected
                let notification = Notification(name: "PuckDisconnected", object: self)
                NotificationCenter.default.post(notification)
            }
        }
    }
    
    func queueDisconnectNotifications(_ notification: Notification) {
        // Make sure it was the XGPS150/XGPS160 that disconnected
        if accessory == nil {
            return
        }
        let eak = notification.userInfo?[EAAccessoryKey] as? EAAccessory
        if eak?.connectionID != accessoryConnectionID {
            return
        }
        // It was an XGPS150/160 that disconnected
        mostRecentNotification = notification
        notificationType = false as? CKNotificationType ?? CKNotificationType(rawValue: 0)!
        if queueTimerStarted == false {
            perform(#selector(self.processConnectionNotifications), with: nil, afterDelay: kProcessTimerDelay)
            queueTimerStarted = true
        }
    }
    
    func queueConnectNotifications(_ notification: Notification) {
        // Make sure it was the XGPS150/160 that connected
        let eak = notification.userInfo?[EAAccessoryKey] as? EAAccessory
        if eak?.protocolStrings?.contains("com.dualav.xgps150") ?? false {
            mostRecentNotification = notification
            notificationType = true as? CKNotificationType ?? CKNotificationType(rawValue: 0)!
            if queueTimerStarted == false {
                perform(#selector(self.processConnectionNotifications), with: nil, afterDelay: kProcessTimerDelay)
                queueTimerStarted = true
            }
        }
        else {
            return
        }
    }

}
