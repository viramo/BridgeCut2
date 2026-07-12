import Foundation

final class FCPXMLConverter {
    private let genericRoles: Set<String> = [
        "dialogue", "music", "effects", "ambience"
    ]

    func convert(
        inputURL: URL,
        includeGenericRoles: Bool = false
    ) throws -> ConversionResult {
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

        let activeAudioAngleIDs = Set(
            try root.nodes(
                forXPath:
                ".//sequence/spine/mc-clip/mc-source[" +
                "@angleID and " +
                "(@srcEnable='audio' or @srcEnable='all' or not(@srcEnable))" +
                "]"
            )
            .compactMap {
                ($0 as? XMLElement)?
                    .attribute(forName: "angleID")?
                    .stringValue
            }
        )

        let angleNodes = try root.nodes(
            forXPath: "./resources/media/multicam/mc-angle"
        )

        var changes: [ConversionChange] = []

        for node in angleNodes {
            guard let angle = node as? XMLElement,
                  let angleID = angle
                    .attribute(forName: "angleID")?
                    .stringValue,
                  activeAudioAngleIDs.contains(angleID)
            else {
                continue
            }

            let roleNodes = try angle.nodes(
                forXPath: ".//audio-channel-source[@role]"
            )

            let roles = roleNodes.compactMap {
                ($0 as? XMLElement)?
                    .attribute(forName: "role")?
                    .stringValue
            }

            let candidates = roles.compactMap {
                displayName(
                    from: $0,
                    includeGenericRoles: includeGenericRoles
                )
            }

            guard let desired = mostFrequent(candidates),
                  !desired.isEmpty else {
                continue
            }

            let oldName = angle
                .attribute(forName: "name")?
                .stringValue ?? ""

            guard oldName != desired else {
                continue
            }

            if let existingName = angle.attribute(forName: "name") {
                existingName.stringValue = desired
            } else {
                angle.addAttribute(
                    XMLNode.attribute(
                        withName: "name",
                        stringValue: desired
                    ) as! XMLNode
                )
            }

            changes.append(
                ConversionChange(
                    oldName: oldName,
                    newName: desired,
                    sourceRole: roles.first ?? ""
                )
            )
        }

        guard !changes.isEmpty else {
            throw BridgeCutError.noChanges
        }

        let outputURL = makeOutputURL(for: inputURL)

        // Critical rule:
        // Only active mc-angle "name" attributes are changed.
        // We do not touch cuts, offsets, durations, lanes, srcCh,
        // audioChannels, audioLayout, mono/stereo or multicam nesting.
        let outputData = document.xmlData(
            options: [.nodePrettyPrint, .nodePreserveAll]
        )
        try outputData.write(to: outputURL, options: .atomic)

        return ConversionResult(
            outputURL: outputURL,
            changes: changes
        )
    }

    private func resolveXMLURL(from inputURL: URL) throws -> URL {
        let ext = inputURL.pathExtension.lowercased()

        if ext == "fcpxml" {
            return inputURL
        }

        guard ext == "fcpxmld" else {
            throw BridgeCutError.invalidInput
        }

        let directInfo = inputURL.appendingPathComponent("Info.fcpxml")
        if FileManager.default.fileExists(atPath: directInfo.path) {
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
            if candidate.pathExtension.lowercased() == "fcpxml" {
                return candidate
            }
        }

        throw BridgeCutError.missingInfoXML
    }

    private func displayName(
        from role: String,
        includeGenericRoles: Bool
    ) -> String? {
        let parts = role
            .split(separator: ".", maxSplits: 1)
            .map(String.init)

        let main = parts.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let sub = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        if !main.isEmpty,
           !genericRoles.contains(main.lowercased()) {
            return main
        }

        let cleanSub = sub.replacingOccurrences(
            of: #"-\d+$"#,
            with: "",
            options: .regularExpression
        )

        if !cleanSub.isEmpty,
           !genericRoles.contains(cleanSub.lowercased()) {
            return cleanSub
        }

        return includeGenericRoles && !main.isEmpty
            ? main
            : nil
    }

    private func mostFrequent(_ values: [String]) -> String? {
        guard !values.isEmpty else {
            return nil
        }

        let counts = Dictionary(
            grouping: values,
            by: { $0 }
        )
        .mapValues(\.count)

        return counts.max {
            $0.value < $1.value
        }?.key
    }

    private func makeOutputURL(for inputURL: URL) -> URL {
        let stem = inputURL
            .deletingPathExtension()
            .lastPathComponent

        return inputURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(stem)_BridgeCut.fcpxml")
    }
}
