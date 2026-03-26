import AppKit
import ScreenCaptureKit
import UserNotifications

final class CaptureManager {
    private var elementPicker: ElementPicker?
    private var deepElementPicker: DeepElementPicker?

    // MARK: - Element Capture

    func captureElement(settingsManager: SettingsManager) {
        elementPicker = ElementPicker()
        elementPicker?.start { [weak self] rect in
            guard let self = self, let rect = rect else { return }
            self.captureRect(rect, settingsManager: settingsManager)
            self.elementPicker = nil
        }
    }

    // MARK: - Deep Element Capture (Web App support)

    func captureDeepElement(settingsManager: SettingsManager) {
        deepElementPicker = DeepElementPicker()
        deepElementPicker?.start { [weak self] rect in
            guard let self = self, let rect = rect else { return }
            self.captureRect(rect, settingsManager: settingsManager)
            self.deepElementPicker = nil
        }
    }

    private func captureRect(_ rect: CGRect, settingsManager: SettingsManager) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                // Find the display containing the rect
                guard let display = content.displays.first(where: { display in
                    let displayBounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
                    return displayBounds.intersects(rect)
                }) ?? content.displays.first else {
                    print("No display found")
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()

                // Set capture rect relative to the display
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                config.sourceRect = rect
                config.width = Int(rect.width * scale)
                config.height = Int(rect.height * scale)
                config.showsCursor = false
                config.captureResolution = .best

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

                let tempPath = tempFilePath()
                try pngData.write(to: URL(fileURLWithPath: tempPath))

                await MainActor.run {
                    processCapture(tempPath: tempPath, settingsManager: settingsManager)
                }
            } catch {
                print("ScreenCaptureKit error: \(error)")
            }
        }
    }

    // MARK: - Window Capture

    func captureWindow(settingsManager: SettingsManager) {
        let tempPath = tempFilePath()
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-w", "-t", "png", tempPath]

        task.terminationHandler = { [weak self] process in
            guard process.terminationStatus == 0 else { return }
            DispatchQueue.main.async {
                self?.processCapture(tempPath: tempPath, settingsManager: settingsManager)
            }
        }

        do {
            try task.run()
        } catch {
            print("Failed to launch screencapture: \(error)")
        }
    }

    // MARK: - Process & Save

    private func processCapture(tempPath: String, settingsManager: SettingsManager) {
        guard FileManager.default.fileExists(atPath: tempPath) else { return }

        let timestamp = DateFormatter.filenameFormatter.string(from: Date())
        let filename = "Scoosho_\(timestamp)"
        let saveDir = settingsManager.saveDirectory
        let format = settingsManager.imageFormat

        let destinationPath: String

        switch format {
        case .png:
            destinationPath = "\(saveDir)/\(filename).png"
            movePNG(from: tempPath, to: destinationPath)
        case .avif:
            destinationPath = "\(saveDir)/\(filename).avif"
            convertToAVIF(from: tempPath, to: destinationPath, quality: settingsManager.avifQuality)
        }

        if settingsManager.copyToClipboard {
            copyImageToClipboard(path: destinationPath, format: format)
        }

        if settingsManager.showNotification {
            showSaveNotification(path: destinationPath)
        }

        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    private func movePNG(from source: String, to destination: String) {
        do {
            if FileManager.default.fileExists(atPath: destination) {
                try FileManager.default.removeItem(atPath: destination)
            }
            try FileManager.default.moveItem(atPath: source, toPath: destination)
        } catch {
            print("Failed to move PNG: \(error)")
        }
    }

    private func convertToAVIF(from sourcePath: String, to destinationPath: String, quality: Double) {
        guard let image = NSImage(contentsOfFile: sourcePath) else {
            print("Failed to load image from \(sourcePath)")
            return
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            print("Failed to create bitmap representation")
            return
        }

        // Use CGImageDestination with HEIF/AVIF
        let destinationURL = URL(fileURLWithPath: destinationPath)

        // Try AVIF via ImageIO (available on macOS 14+)
        if let cgImage = bitmap.cgImage {
            let avifUTType = "public.avif" as CFString
            guard let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                avifUTType,
                1,
                nil
            ) else {
                print("Failed to create AVIF image destination, falling back to HEIC")
                convertToHEIC(bitmap: bitmap, destinationPath: destinationPath, quality: quality)
                return
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality / 100.0
            ]

            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            if !CGImageDestinationFinalize(destination) {
                print("Failed to finalize AVIF, falling back to HEIC")
                convertToHEIC(bitmap: bitmap, destinationPath: destinationPath, quality: quality)
            }
        }
    }

    private func convertToHEIC(bitmap: NSBitmapImageRep, destinationPath: String, quality: Double) {
        let heicPath = destinationPath.replacingOccurrences(of: ".avif", with: ".heic")
        let heicURL = URL(fileURLWithPath: heicPath)

        guard let cgImage = bitmap.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                  heicURL as CFURL,
                  "public.heic" as CFString,
                  1,
                  nil
              ) else { return }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality / 100.0
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    // MARK: - Clipboard

    private func copyImageToClipboard(path: String, format: ImageFormat) {
        guard let image = NSImage(contentsOfFile: path) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    // MARK: - Notification

    private func showSaveNotification(path: String) {
        let content = UNMutableNotificationContent()
        content.title = "Scoosho"
        content.body = "Screenshot saved to \(URL(fileURLWithPath: path).lastPathComponent)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func tempFilePath() -> String {
        let tempDir = NSTemporaryDirectory()
        return "\(tempDir)/scoosho_temp_\(UUID().uuidString).png"
    }
}

extension DateFormatter {
    static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
