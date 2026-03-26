import Foundation
import SwiftUI

enum ImageFormat: String, CaseIterable, Identifiable {
    case png
    case avif

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .avif: return "AVIF"
        }
    }
}

final class SettingsManager: ObservableObject {
    @AppStorage("imageFormat") var imageFormat: ImageFormat = .png
    @AppStorage("saveDirectory") var saveDirectory: String = defaultSaveDirectory()
    @AppStorage("avifQuality") var avifQuality: Double = 80
    @AppStorage("showNotification") var showNotification: Bool = true
    @AppStorage("copyToClipboard") var copyToClipboard: Bool = true

    static func defaultSaveDirectory() -> String {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.path
    }
}

extension ImageFormat: RawRepresentable {
    // Already RawRepresentable via String enum
}
