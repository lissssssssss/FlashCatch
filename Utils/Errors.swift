import Foundation

enum ClipBufferError: LocalizedError {
    case recorderUnavailable
    case bufferingAlreadyActive
    case exportFailed(underlying: Error?)
    case notBuffering

    var errorDescription: String? {
        switch self {
        case .recorderUnavailable:
            return "屏幕录制不可用，请检查系统设置"
        case .bufferingAlreadyActive:
            return "缓冲已在运行中"
        case .exportFailed(let underlying):
            return "导出失败: \(underlying?.localizedDescription ?? "未知错误")"
        case .notBuffering:
            return "当前未在缓冲状态"
        }
    }
}

enum ExportError: LocalizedError {
    case trackCreationFailed
    case exportSessionFailed
    case noVideoTrack
    case unknown

    var errorDescription: String? {
        switch self {
        case .trackCreationFailed:
            return "视频轨道创建失败"
        case .exportSessionFailed:
            return "导出会话创建失败"
        case .noVideoTrack:
            return "未找到视频轨道"
        case .unknown:
            return "未知导出错误"
        }
    }
}

enum PhotoError: LocalizedError {
    case notAuthorized
    case saveFailed(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未授权访问相册，请在设置中开启"
        case .saveFailed(let underlying):
            return "保存失败: \(underlying?.localizedDescription ?? "未知错误")"
        }
    }
}
