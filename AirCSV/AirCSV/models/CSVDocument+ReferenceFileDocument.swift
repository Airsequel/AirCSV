import SwiftUI
import UniformTypeIdentifiers

extension CSVDocument: ReferenceFileDocument {

  static let readableContentTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText]

  func snapshot(contentType: UTType) throws -> Data {
    exportContent().data(using: .utf8) ?? Data()
  }

  func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: snapshot)
  }

}

extension CSVDocument {
  func exportContent() -> String {
    let separator = String(delimiter.rawValue)
    let headerRow = headers.map { $0.name }.joined(separator: separator)
    let dataRows = rows.map { exportContent(for: $0) }
    return ([headerRow] + dataRows).joined(separator: "\n") + "\n"
  }

  /// The row serialized as a single line using the document's delimiter.
  func exportContent(for row: CSVRow) -> String {
    row.cells.map { $0.exportContent(delimiter: delimiter.rawValue) }
      .joined(separator: String(delimiter.rawValue))
  }

  /// The column's cells serialized as one value per line.
  func exportContent(for header: CSVHeader) -> String {
    rows.compactMap { row in
      row.cells.indices.contains(header.columnIndex)
        ? row.cells[header.columnIndex].exportContent(delimiter: delimiter.rawValue)
        : nil
    }.joined(separator: "\n")
  }
}
