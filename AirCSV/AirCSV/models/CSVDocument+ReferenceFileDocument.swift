import SwiftUI
import UniformTypeIdentifiers

extension CSVDocument: ReferenceFileDocument {

  static let readableContentTypes: [UTType] = [.commaSeparatedText]

  func snapshot(contentType: UTType) throws -> Data {
    exportContent().data(using: .utf8) ?? Data()
  }

  func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: snapshot)
  }

}

extension CSVDocument {
  func exportContent() -> String {
    let headerRow = headers.map { $0.name }.joined(separator: ",")
    let dataRows = rows.map { exportContent(for: $0) }
    return ([headerRow] + dataRows).joined(separator: "\n") + "\n"
  }

  /// The row serialized as a single CSV line.
  func exportContent(for row: CSVRow) -> String {
    row.cells.map { $0.exportContent }.joined(separator: ",")
  }

  /// The column's cells serialized as one CSV value per line.
  func exportContent(for header: CSVHeader) -> String {
    rows.compactMap { row in
      row.cells.indices.contains(header.columnIndex)
        ? row.cells[header.columnIndex].exportContent
        : nil
    }.joined(separator: "\n")
  }
}
