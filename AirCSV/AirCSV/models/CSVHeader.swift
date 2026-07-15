import Foundation

struct CSVHeader: Identifiable, Equatable {
  var id: UUID = UUID()
  var name: String
  var columnIndex: Int = 0

  static func createHeaders(data: [String]) -> [CSVHeader] {
    data.enumerated().map { index, name in
      CSVHeader(name: name, columnIndex: index)
    }
  }

}

struct CSVRow: Identifiable, Equatable {
  var id: UUID = UUID()
  var cells: [CSVCell]
}

struct CSVCell: Identifiable, Equatable {
  var id: UUID = UUID()
  var content: String

  /// Serializes the value, quoting it when it contains the delimiter, a
  /// quote, or a newline.
  func exportContent(delimiter: Character = ",") -> String {
    if content.contains(where: { $0 == delimiter || $0 == "\"" || $0.isNewline }) {
      return "\"\(content.replacingOccurrences(of: "\"", with: "\"\""))\""
    } else {
      return content
    }
  }
}
