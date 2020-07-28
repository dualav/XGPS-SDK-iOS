import Foundation

public struct LogData {
    public let sig: Int
    public let interval: Int
    public let startBlock: Int
    public let countEntry: Int
    public let countBlock: Int
    public let createDate: String
    public let createTime: String
    public let fileSize: Int
    public let defaultString: String
    public var localFilename: String
    
    public init(sig: Int, interval: Int, startBlock: Int, countEntry: Int, countBlock: Int, createDate: String, createTime: String, fileSize: Int, defaultString: String, localFilename: String) {
        self.sig = sig
        self.interval = interval
        self.startBlock = startBlock
        self.countEntry = countEntry
        self.countBlock = countBlock
        self.createDate = createDate
        self.createTime = createTime
        self.fileSize = fileSize
        self.defaultString = defaultString
        self.localFilename = localFilename
    }
}
