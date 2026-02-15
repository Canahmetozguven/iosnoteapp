import Foundation

enum DownloadState: Equatable {
    case notStarted
    case queued
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64?)
    case paused(resumeAvailable: Bool)
    case failed(message: String)
    case completed
}

