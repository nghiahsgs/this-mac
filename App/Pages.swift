import AppKit
import SwiftUI
import ThisMacCore

/// The This Mac page: Quick Access folders and every Drive with its capacity.
struct HomeView: View {
    let drives: [Drive]
    let quickFolders: [QuickFolder]
    let open: (URL) -> Void

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                section("Quick Access") {
                    ForEach(quickFolders, id: \.self) { folder in
                        tile(url: folder.url) {
                            Text(folder.title).font(.headline)
                            Text(folder.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                section("Drives") {
                    ForEach(drives, id: \.self) { drive in
                        tile(url: drive.url) {
                            Text(drive.name).font(.headline)
                            ProgressView(value: drive.usedFraction)
                                .tint(drive.usedFraction > 0.9 ? .red : .accentColor)
                            Text("\(Format.bytes(drive.availableBytes)) free of \(Format.bytes(drive.totalBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14, content: content)
        }
    }

    private func tile<Content: View>(url: URL, @ViewBuilder content: () -> Content) -> some View {
        Button {
            open(url)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 5, content: content)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(url.path)
    }
}

/// The sheet that lists every keyboard shortcut.
struct ShortcutsView: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.title2.weight(.semibold))
                .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Shortcuts.groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            ForEach(group.shortcuts) { shortcut in
                                HStack {
                                    Text(shortcut.action)
                                    Spacer()
                                    Text(shortcut.keys)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .quaternaryLabelColor)))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            HStack {
                Text("On a MacBook, hold fn to press F2 and F5.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 460, height: 560)
    }
}
