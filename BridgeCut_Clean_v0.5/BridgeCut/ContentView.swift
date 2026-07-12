import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedURL: URL?
    @State private var status =
        "Choose an .fcpxml file or an .fcpxmld bundle."
    @State private var changes: [ConversionChange] = []
    @State private var isTargeted = false
 
    private let converter = FCPXMLConverter()

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 5) {
                Text("BridgeCut")
                    .font(.system(size: 34, weight: .bold))

                Text("Final Cut Pro multicam audio roles → DaVinci Resolve")
                    .foregroundStyle(.secondary)
            }

            dropArea

               .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Multicam structure stays intact",
                    systemImage: "checkmark.shield"
                )
                Label(
                    "Mono, stereo and channel mappings stay untouched",
                    systemImage: "waveform"
                )
                Label(
                    "Cuts, offsets and durations stay untouched",
                    systemImage: "timeline.selection"
                )
                Label(
                    "The original Final Cut file is never modified",
                    systemImage: "lock.shield"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)

            Button("Convert for Resolve") {
                convert()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedURL == nil)

            Text(status)
                .multilineTextAlignment(.center)

            if !changes.isEmpty {
                List(changes) { item in
                    HStack {
                        Text(item.oldName)
                            .foregroundStyle(.secondary)

                        Image(systemName: "arrow.right")

                        Text(item.newName)
                            .bold()

                        Spacer()

                        Text(item.sourceRole)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(28)
    }

    private var dropArea: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                isTargeted
                    ? Color.accentColor
                    : Color.secondary.opacity(0.45),
                style: StrokeStyle(lineWidth: 2, dash: [8])
            )
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 44))

                    Text(
                        selectedURL?.lastPathComponent
                        ?? "Drop .fcpxml or .fcpxmld here"
                    )
                    .font(.headline)

                    Button("Choose Final Cut XML…") {
                        chooseFile()
                    }
                }
            }
            .frame(height: 180)
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $isTargeted
            ) { providers in
                guard let provider = providers.first else {
                    return false
                }

                provider.loadDataRepresentation(
                    forTypeIdentifier: UTType.fileURL.identifier
                ) { data, error in
                    guard error == nil,
                          let data,
                          let urlString = String(
                            data: data,
                            encoding: .utf8
                          ),
                          let url = URL(
                            string: urlString.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                          )
                    else {
                        return
                    }

                    DispatchQueue.main.async {
                        accept(url)
                    }
                }

                return true
            }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Final Cut XML"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false

        // .item keeps both legacy .fcpxml files and modern .fcpxmld
        // bundles selectable. The extension is validated after selection.
        panel.allowedContentTypes = [.item]

        if panel.runModal() == .OK,
           let url = panel.url {
            accept(url)
        }
    }

    private func accept(_ url: URL) {
        let ext = url.pathExtension.lowercased()

        guard ext == "fcpxml" || ext == "fcpxmld" else {
            selectedURL = nil
            changes = []
            status =
                "Choose an .fcpxml file or an .fcpxmld bundle."
            return
        }

        selectedURL = url
        changes = []
        status = url.lastPathComponent
    }

    private func convert() {
        guard let selectedURL else {
            return
        }

        do {
            let result = try converter.convert(
                inputURL: selectedURL
                )

            changes = result.changes
            status =
                "Created \(result.outputURL.lastPathComponent)"

            NSWorkspace.shared.activateFileViewerSelecting(
                [result.outputURL]
            )
        } catch {
            changes = []
            status = error.localizedDescription
        }
    }
}
