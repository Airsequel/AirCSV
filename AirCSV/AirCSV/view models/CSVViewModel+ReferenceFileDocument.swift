import SwiftUI
import UniformTypeIdentifiers

extension CSVViewModel: ReferenceFileDocument {

  static let readableContentTypes: [UTType] = [.commaSeparatedText]

  func snapshot(contentType: UTType) throws -> Data {
    exportContent().data(using: .utf8) ?? Data()
  }

  func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: snapshot)
  }

}

extension CSVViewModel {
  func exportContent() -> String {
    let headers = filteredHeaders()
    let rows = filteredRows(for: headers)

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

  func filteredHeaders() -> [CSVHeader] {
    var filteredHeaders: [CSVHeader] = []

    for header in self.headers {
      if tableCustomization[visibility: header.id.uuidString] != .hidden {
        filteredHeaders.append(header)
      }
    }

    return filteredHeaders
  }

  func filteredRows(for headers: [CSVHeader]) -> [CSVRow] {
    var filteredRows: [CSVRow] = []

    for row in self.rows {
      var copy = CSVRow(cells: [CSVCell]())
      for header in headers {
        copy.cells.append(row.cells[header.columnIndex])
      }

      filteredRows.append(copy)
    }

    return filteredRows
  }
}
