import Foundation

struct ConversionChange: Identifiable {
    let id = UUID()
    let oldName: String
    let newName: String
    let sourceRole: String
}

struct ConversionResult {
    let outputURL: URL
    let changes: [ConversionChange]
}

enum BridgeCutError: LocalizedError {
    case invalidInput
    case missingInfoXML
    case invalidDocument
    case noFCPXMLRoot
    case noChanges

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Choose an .fcpxml file or an .fcpxmld bundle."
        case .missingInfoXML:
            return "BridgeCut could not find Info.fcpxml inside the .fcpxmld bundle."
        case .invalidDocument:
            return "The selected FCPXML could not be read."
        case .noFCPXMLRoot:
            return "The selected XML does not contain an fcpxml root element."
        case .noChanges:
            return "No custom Final Cut Pro audio roles or subroles were found on active multicam audio angles."
        }
    }
}
