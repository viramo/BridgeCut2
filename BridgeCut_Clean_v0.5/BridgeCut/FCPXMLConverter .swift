import Foundation

final class FCPXMLConverter {
    private let bwfReader = BWFMetadataReader()

    func convert(inputURL: URL) throws -> ConversionResult {
        let actualXMLURL = try resolveXMLURL(from: inputURL)
        let data = try Data(contentsOf: actualXMLURL)

        guard let document = try? XMLDocument(
            data: data,
            options: [.nodePreserveAll]
        ) else {
            throw BridgeCutError.invalidDocument
        }

        guard let root = document.rootElement(),
              root.name == "fcpxml" else {
            throw BridgeCutError.noFCPXMLRoot
        }

        let assets = try assetIndex(in: root)
        var changes: [ConversionChange] = []
        var angleExpansionMap: [String: [String]] = [:]

        let multicams = try root.nodes(
            forXPath: "./resources/media/multicam"
        )

        for multicamNode in multicams {
            guard let multicam = multicamNode as? XMLElement else {
                continue
            }

            let angles = try multicam.nodes(
                forXPath: "./mc-angle"
            ).compactMap { $0 as? XMLElement }

            for angle in angles {
                guard let oldAngleID = angle
                    .attribute(forName: "angleID")?
                    .stringValue
                else {
                    continue
                }

                guard let audio = try angle.nodes(
                    forXPath: "./clip/audio"
                ).first as? XMLElement,
                let assetRef = audio
                    .attribute(forName: "ref")?
                    .stringValue,
                let asset = assets[assetRef]
                else {
                    continue
                }

                let channelCount = Int(
                    asset.attribute(forName: "audioChannels")?
                        .stringValue ?? "1"
                ) ?? 1

                if channelCount > 1,
                   let wavURL = try originalMediaURL(for: asset),
                   wavURL.pathExtension.lowercased() == "wav",
                   FileManager.default.fileExists(atPath: wavURL.path),
                   let tracks = try? bwfReader.readTracks(from: wavURL),
                   !tracks.isEmpty {

                    let newAngleIDs = try expandPolyphonicAngle(
                        angle,
                        inside: multicam,
                        audioElement: audio,
                        assetRef: assetRef,
                        tracks: tracks,
                        changes: &changes
                    )

                    angleExpansionMap[oldAngleID] = newAngleIDs
                } else {
                    try renameMonoAngleFromExistingRole(
                        angle,
                        changes: &changes
                    )
                }
            }
        }

        try replaceTimelineAudioSources(
            in: root,
            using: angleExpansionMap
        )

        guard !changes.isEmpty else {
            throw BridgeCutError.noChanges
        }

        let outputURL = makeOutputURL(for: inputURL)
        let outputData = document.xmlData(
            options: [.nodePrettyPrint, .nodePreserveAll]
        )
        try outputData.write(to: outputURL, options: .atomic)

        return ConversionResult(
            outputURL: outputURL,
            changes: changes
        )
    }

    private func expandPolyphonicAngle(
        _ originalAngle: XMLElement,
        inside multicam: XMLElement,
        audioElement: XMLElement,
        assetRef: String,
        tracks: [BWFTrack],
        changes: inout [ConversionChange]
    ) throws -> [String] {
        guard let originalClip = try originalAngle.nodes(
            forXPath: "./clip"
        ).first as? XMLElement else {
            return []
        }

        let oldAngleName = originalAngle
            .attribute(forName: "name")?
            .stringValue ?? "Polyphonic WAV"

        guard let parent = originalAngle.parent as? XMLElement,
              let originalIndex = parent.children?
                .firstIndex(where: { $0 === originalAngle })
        else {
            return []
        }

        var newAngleIDs: [String] = []
        var insertionIndex = originalIndex

        for track in tracks {
            let angleID = UUID().uuidString
            newAngleIDs.append(angleID)

            let newAngle = XMLElement(name: "mc-angle")
            newAngle.addAttribute(
                XMLNode.attribute(
                    withName: "name",
                    stringValue: track.name
                ) as! XMLNode
            )
            newAngle.addAttribute(
                XMLNode.attribute(
                    withName: "angleID",
                    stringValue: angleID
                ) as! XMLNode
            )

            let newClip = XMLElement(name: "clip")
            copyAttributes(
                from: originalClip,
                to: newClip
            )

            let newAudio = XMLElement(name: "audio")
            copySelectedAttributes(
                from: audioElement,
                to: newAudio,
                names: ["ref", "offset", "start", "duration"]
            )

            setAttribute(
                named: "ref",
                value: assetRef,
                on: newAudio
            )
            setAttribute(
                named: "srcCh",
                value: String(track.interleaveIndex),
                on: newAudio
            )
            setAttribute(
                named: "role",
                value: "dialogue.\(track.name)",
                on: newAudio
            )

            newClip.addChild(newAudio)

            let channelSource = XMLElement(
                name: "audio-channel-source"
            )
            setAttribute(
                named: "srcCh",
                value: String(track.interleaveIndex),
                on: channelSource
            )
            setAttribute(
                named: "role",
                value: "dialogue.\(track.name)",
                on: channelSource
            )
            newClip.addChild(channelSource)

            if let metadata = try originalClip.nodes(
                forXPath: "./metadata"
            ).first {
                newClip.addChild(metadata.copy() as! XMLNode)
            }

            newAngle.addChild(newClip)
            parent.insertChild(
                newAngle,
                at: insertionIndex
            )
            insertionIndex += 1

            changes.append(
                ConversionChange(
                    oldName: oldAngleName,
                    newName: track.name,
                    sourceRole:
                        "WAV channel \(track.interleaveIndex)"
                )
            )
        }

        originalAngle.detach()
        return newAngleIDs
    }

    private func replaceTimelineAudioSources(
        in root: XMLElement,
        using expansionMap: [String: [String]]
    ) throws {
        let sourceNodes = try root.nodes(
            forXPath: ".//sequence/spine/mc-clip/mc-source"
        )

        for node in sourceNodes {
            guard let source = node as? XMLElement,
                  let oldAngleID = source
                    .attribute(forName: "angleID")?
                    .stringValue,
                  let newAngleIDs = expansionMap[oldAngleID]
            else {
                continue
            }

            let enabled = source
                .attribute(forName: "srcEnable")?
                .stringValue ?? "all"

            guard enabled == "audio" || enabled == "all",
                  let parent = source.parent as? XMLElement,
                  let index = parent.children?
                    .firstIndex(where: { $0 === source })
            else {
                continue
            }

            var insertionIndex = index

            for newAngleID in newAngleIDs {
                let newSource = XMLElement(name: "mc-source")
                setAttribute(
                    named: "angleID",
                    value: newAngleID,
                    on: newSource
                )
                setAttribute(
                    named: "srcEnable",
                    value: "audio",
                    on: newSource
                )

                parent.insertChild(
                    newSource,
                    at: insertionIndex
                )
                insertionIndex += 1
            }

            source.detach()
        }
    }

    private func renameMonoAngleFromExistingRole(
        _ angle: XMLElement,
        changes: inout [ConversionChange]
    ) throws {
        let roleNodes = try angle.nodes(
            forXPath: ".//audio-channel-source[@role]"
        )

        guard let role = roleNodes.compactMap({
            ($0 as? XMLElement)?
                .attribute(forName: "role")?
                .stringValue
        }).first,
        let desired = displayName(from: role)
        else {
            return
        }

        let oldName = angle
            .attribute(forName: "name")?
            .stringValue ?? ""

        guard oldName != desired else {
            return
        }

        setAttribute(
            named: "name",
            value: desired,
            on: angle
        )

        changes.append(
            ConversionChange(
                oldName: oldName,
                newName: desired,
                sourceRole: role
            )
        )
    }

    private func assetIndex(
        in root: XMLElement
    ) throws -> [String: XMLElement] {
        let assets = try root.nodes(
            forXPath: "./resources/asset[@id]"
        )

        var result: [String: XMLElement] = [:]

        for node in assets {
            guard let asset = node as? XMLElement,
                  let id = asset
                    .attribute(forName: "id")?
                    .stringValue
            else {
                continue
            }

            result[id] = asset
        }

        return result
    }

    private func originalMediaURL(
        for asset: XMLElement
    ) throws -> URL? {
        guard let mediaRep = try asset.nodes(
            forXPath: "./media-rep[@kind='original-media']"
        ).first as? XMLElement,
        let src = mediaRep
            .attribute(forName: "src")?
            .stringValue
        else {
            return nil
        }

        return URL(string: src)
    }

    private func resolveXMLURL(
        from inputURL: URL
    ) throws -> URL {
        let ext = inputURL.pathExtension.lowercased()

        if ext == "fcpxml" {
            return inputURL
        }

        guard ext == "fcpxmld" else {
            throw BridgeCutError.invalidInput
        }

        let directInfo = inputURL
            .appendingPathComponent("Info.fcpxml")

        if FileManager.default.fileExists(
            atPath: directInfo.path
        ) {
            return directInfo
        }

        guard let enumerator = FileManager.default.enumerator(
            at: inputURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw BridgeCutError.missingInfoXML
        }

        for case let candidate as URL in enumerator {
            if candidate.pathExtension.lowercased()
                == "fcpxml" {
                return candidate
            }
        }

        throw BridgeCutError.missingInfoXML
    }

    private func displayName(
        from role: String
    ) -> String? {
        let parts = role
            .split(separator: ".", maxSplits: 1)
            .map(String.init)

        let main = parts.first?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""

        let sub = parts.count > 1
            ? parts[1].trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            : ""

        let generic: Set<String> = [
            "dialogue", "music",
            "effects", "ambience"
        ]

        if !main.isEmpty,
           !generic.contains(main.lowercased()) {
            return main
        }

        let cleanSub = sub.replacingOccurrences(
            of: #"-\d+$"#,
            with: "",
            options: .regularExpression
        )

        if !cleanSub.isEmpty,
           !generic.contains(cleanSub.lowercased()) {
            return cleanSub
        }

        return nil
    }

    private func copyAttributes(
        from source: XMLElement,
        to destination: XMLElement
    ) {
        for attribute in source.attributes ?? [] {
            destination.addAttribute(
                attribute.copy() as! XMLNode
            )
        }
    }

    private func copySelectedAttributes(
        from source: XMLElement,
        to destination: XMLElement,
        names: [String]
    ) {
        for name in names {
            guard let value = source
                .attribute(forName: name)?
                .stringValue else {
                continue
            }

            setAttribute(
                named: name,
                value: value,
                on: destination
            )
        }
    }

    private func setAttribute(
        named name: String,
        value: String,
        on element: XMLElement
    ) {
        if let existing = element
            .attribute(forName: name) {
            existing.stringValue = value
        } else {
            element.addAttribute(
                XMLNode.attribute(
                    withName: name,
                    stringValue: value
                ) as! XMLNode
            )
        }
    }

    private func makeOutputURL(
        for inputURL: URL
    ) -> URL {
        let stem = inputURL
            .deletingPathExtension()
            .lastPathComponent

        return inputURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(stem)_BridgeCut.fcpxml"
            )
    }
}
