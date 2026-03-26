import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            HotKeySettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showDirectoryPicker = false

    var body: some View {
        Form {
            Section("Image Format") {
                Picker("Default format", selection: $settingsManager.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if settingsManager.imageFormat == .avif {
                    HStack {
                        Text("Quality")
                        Slider(value: $settingsManager.avifQuality, in: 1...100, step: 1)
                        Text("\(Int(settingsManager.avifQuality))%")
                            .frame(width: 40)
                    }
                }
            }

            Section("Save Location") {
                HStack {
                    Text(shortenedPath(settingsManager.saveDirectory))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        chooseSaveDirectory()
                    }
                }
            }

            Section("After Capture") {
                Toggle("Copy to clipboard", isOn: $settingsManager.copyToClipboard)
                Toggle("Show notification", isOn: $settingsManager.showNotification)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose save location"

        if panel.runModal() == .OK, let url = panel.url {
            settingsManager.saveDirectory = url.path
        }
    }

    private func shortenedPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

struct HotKeySettingsView: View {
    var body: some View {
        Form {
            Section("Capture Shortcuts") {
                HStack {
                    Text("Element capture")
                    Spacer()
                    KeyboardShortcutBadge(modifiers: ["Cmd", "Shift"], key: "5")
                }

                HStack {
                    Text("Window capture")
                    Spacer()
                    KeyboardShortcutBadge(modifiers: ["Cmd", "Shift"], key: "6")
                }

                HStack {
                    Text("Deep element capture (Web)")
                    Spacer()
                    KeyboardShortcutBadge(modifiers: ["Cmd", "Shift"], key: "7")
                }
            }

            Section {
                Text("Deep element capture drills into Web content.\nScroll up/down to adjust element depth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("These shortcuts are active globally while Scoosho is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct KeyboardShortcutBadge: View {
    let modifiers: [String]
    let key: String

    private let symbolMap: [String: String] = [
        "Cmd": "\u{2318}",
        "Shift": "\u{21E7}",
        "Option": "\u{2325}",
        "Ctrl": "\u{2303}"
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modifiers, id: \.self) { mod in
                Text(symbolMap[mod] ?? mod)
            }
            Text(key)
        }
        .font(.system(.body, design: .rounded).weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
