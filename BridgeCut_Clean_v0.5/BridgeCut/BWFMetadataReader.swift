import Foundation

struct BWFTrack {
    let interleaveIndex: Int
    let name: String
}

enum BWFMetadataError: LocalizedError {
    case unreadableFile
    case invalidWAV
    case missingIXML
    case invalidIXML

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The WAV file could not be read."
        case .invalidWAV:
            return "The selected file is not a valid RIFF/WAVE file."
        case .missingIXML:
            return "No iXML metadata was found in the WAV file."
        case .invalidIXML:
            return "The WAV iXML metadata could not be parsed."
        }
    }
}

final class BWFMetadataReader {
    func readTracks(from url: URL) throws -> [BWFTrack] {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw BWFMetadataError.unreadableFile
        }
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: 12),
              header.count == 12,
              String(data: header.subdata(in: 0..<4), encoding: .ascii) == "RIFF",
              String(data: header.subdata(in: 8..<12), encoding: .ascii) == "WAVE"
        else {
            throw BWFMetadataError.invalidWAV
        }

        while true {
            guard let chunkHeader = try handle.read(upToCount: 8),
                  chunkHeader.count == 8 else {
                break
            }

            let chunkID = String(
                data: chunkHeader.subdata(in: 0..<4),
                encoding: .ascii
            ) ?? ""

            let chunkSize = Int(
                chunkHeader.subdata(in: 4..<8).withUnsafeBytes {
                    UInt32(littleEndian: $0.load(as: UInt32.self))
                }
            )

            guard let chunkData = try handle.read(upToCount: chunkSize),
                  chunkData.count == chunkSize else {
                throw BWFMetadataError.unreadableFile
            }

            if chunkSize % 2 == 1 {
                _ = try handle.read(upToCount: 1)
            }

            if chunkID == "iXML" {
                return try parseIXML(chunkData)
            }
        }

        throw BWFMetadataError.missingIXML
    }

    private func parseIXML(_ data: Data) throws -> [BWFTrack] {
        var cleaned = data

        while let last = cleaned.last,
              last == 0 || last == 32 || last == 9 ||
              last == 10 || last == 13 {
            cleaned.removeLast()
        }

        guard let document = try? XMLDocument(
            data: cleaned,
            options: []
        ),
        let root = document.rootElement()
        else {
            throw BWFMetadataError.invalidIXML
        }

        let trackNodes = try root.nodes(
            forXPath: ".//TRACK_LIST/TRACK"
        )

        var tracks: [BWFTrack] = []

        for node in trackNodes {
            guard let trackElement = node as? XMLElement else {
                continue
            }

            let interleaveIndexText = try trackElement.nodes(
                forXPath: "./INTERLEAVE_INDEX"
            ).first?.stringValue

            let channelIndexText = try trackElement.nodes(
                forXPath: "./CHANNEL_INDEX"
            ).first?.stringValue

            let indexText = interleaveIndexText ?? channelIndexText
            guard let indexText,
                  let index = Int(indexText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ))
            else {
                continue
            }

            let rawName = try trackElement.nodes(
                forXPath: "./NAME"
            ).first?.stringValue

            let name = rawName?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            tracks.append(
                BWFTrack(
                    interleaveIndex: index,
                    name: (name?.isEmpty == false)
                        ? name!
                        : "Channel \(index)"
                )
            )
        }

        guard !tracks.isEmpty else {
            throw BWFMetadataError.invalidIXML
        }

        return tracks.sorted {
            $0.interleaveIndex < $1.interleaveIndex
        }
    }
}
