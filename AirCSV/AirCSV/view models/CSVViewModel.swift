import SwiftCSV
import SwiftUI

class CSVViewModel: ObservableObject {

  @Published var url: URL?
  @Published var content: String = ""
  @Published var headers: [CSVHeader] = []
  @Published var rows: [CSVRow] = []
  @Published var tableCustomization: TableColumnCustomization<CSVRow> = .init()

  init() {

  }

  required init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }

    guard let fileContent = String(data: data, encoding: .utf8) else { return }
    self.content = fileContent
    parseCSV(content: fileContent)
  }

  func handleFileImport(for result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      readFile(url)
    case .failure(let error): print("error loading file \(error)")
    }
  }

  func readFile(_ url: URL) {
    guard url.startAccessingSecurityScopedResource() else { return }
    self.url = url

    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      self.content = content
      parseCSV(content: content)
    } catch {
      print(error)
    }

    url.stopAccessingSecurityScopedResource()
  }

  func parseCSV(content: String) {
    do {
      let data = try EnumeratedCSV(string: content, loadColumns: false)

      self.headers = CSVHeader.createHeaders(data: data.header)
      self.rows = data.rows.map({ CSVRow(cells: $0.map({ CSVCell(content: $0) })) })

    } catch {
      print(error)
    }
  }

  //MARK: - Layout

  var rowNumberColumnWidth: CGFloat {
    let digits = String(max(rows.count, 1)).count
    return max(40, CGFloat(digits) * 8.5 + 16)
  }

  func rowNumber(for row: CSVRow) -> Int {
    (rows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1
  }

  func idealWidth(for header: CSVHeader) -> CGFloat {
    let headerLength = header.name.count
    let maxCellLength =
      rows.compactMap { row in
        row.cells.count > header.columnIndex ? row.cells[header.columnIndex].content.count : nil
      }.max() ?? 0
    let maxLength = max(headerLength, maxCellLength)
    return min(400, max(50, CGFloat(maxLength) * 8.5 + 24))
  }

  /// Minimum width that shows all content of the column, without the cap
  /// applied by `idealWidth(for:)`. Measures the rendered text widths.
  func fitWidth(for header: CSVHeader) -> CGFloat {
    let cellFont = NSFont.monospacedSystemFont(
      ofSize: NSFont.systemFontSize, weight: .regular)
    let headerFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    let headerWidth = (header.name as NSString)
      .size(withAttributes: [.font: headerFont]).width
    let maxCellWidth =
      rows.compactMap { row -> CGFloat? in
        guard row.cells.count > header.columnIndex else { return nil }
        return (row.cells[header.columnIndex].content as NSString)
          .size(withAttributes: [.font: cellFont]).width
      }.max() ?? 0

    let horizontalPadding: CGFloat = 16
    return max(50, ceil(max(headerWidth, maxCellWidth)) + horizontalPadding)
  }

  //MARK: - Edit

  func delete(row: CSVRow, selection: Set<CSVRow.ID>) {
    if selection.contains(row.id) {
      self.rows.removeAll { selection.contains($0.id) }
    } else {
      self.rows.removeAll(where: { $0.id == row.id })
    }
  }

  func clear(row: CSVRow, selection: Set<CSVRow.ID>) {
    clear(rows: selection.contains(row.id) ? selection : [row.id])
  }

  func clear(rows selection: Set<CSVRow.ID>) {
    for index in rows.indices where selection.contains(rows[index].id) {
      for cellIndex in rows[index].cells.indices {
        rows[index].cells[cellIndex].content = ""
      }
    }
  }

  func clear(columns selection: Set<CSVHeader.ID>) {
    for header in headers where selection.contains(header.id) {
      clear(column: header)
    }
  }

  func clear(column header: CSVHeader) {
    for index in rows.indices where rows[index].cells.indices.contains(header.columnIndex) {
      rows[index].cells[header.columnIndex].content = ""
    }
  }

  func delete(column header: CSVHeader) {
    guard let headerIndex = headers.firstIndex(where: { $0.id == header.id }) else { return }
    headers.remove(at: headerIndex)
    for index in rows.indices where rows[index].cells.indices.contains(header.columnIndex) {
      rows[index].cells.remove(at: header.columnIndex)
    }
    for index in headers.indices {
      headers[index].columnIndex = index
    }
  }

  func addRow() {
    rows.append(CSVRow(cells: headers.map { _ in CSVCell(content: "") }))
  }

  func addColumn() {
    headers.append(
      CSVHeader(name: "Column \(headers.count + 1)", columnIndex: headers.count))
    for index in rows.indices {
      while rows[index].cells.count < headers.count {
        rows[index].cells.append(CSVCell(content: ""))
      }
    }
  }

  func headerBinding(for header: CSVHeader) -> Binding<String> {
    Binding {
      self.headers.first(where: { $0.id == header.id })?.name ?? ""
    } set: { newValue in
      if let index = self.headers.firstIndex(where: { $0.id == header.id }) {
        self.headers[index].name = newValue
      }
    }
  }

  func cellBinding(for row: CSVRow, header: CSVHeader) -> Binding<String> {
    Binding {
      if let r = self.rows.first(where: { $0.id == row.id }),
        r.cells.count > header.columnIndex
      {
        return r.cells[header.columnIndex].content
      }
      return ""
    } set: { newValue in
      if let rowIndex = self.rows.firstIndex(where: { $0.id == row.id }) {
        self.rows[rowIndex].cells[header.columnIndex].content = newValue
      }
    }
  }

  //MARK: - Clipboard

  /// The selected rows serialized as CSV lines, in table order.
  func copyContent(rows selection: Set<CSVRow.ID>) -> String {
    rows.filter { selection.contains($0.id) }
      .map { exportContent(for: $0) }
      .joined(separator: "\n")
  }

  /// The selected columns serialized as CSV lines, one per row, in table
  /// order.
  func copyContent(columns selection: Set<CSVHeader.ID>) -> String {
    let selectedHeaders = headers.filter { selection.contains($0.id) }
    return rows.map { row in
      selectedHeaders.map { header in
        row.cells.indices.contains(header.columnIndex)
          ? row.cells[header.columnIndex].exportContent
          : ""
      }.joined(separator: ",")
    }.joined(separator: "\n")
  }

  /// The cell block serialized as CSV lines. Both ranges must lie within
  /// the table bounds.
  func copyContent(rowRange: ClosedRange<Int>, columnRange: ClosedRange<Int>) -> String {
    rowRange.map { rowIndex in
      columnRange.map { columnIndex in
        rows[rowIndex].cells.indices.contains(columnIndex)
          ? rows[rowIndex].cells[columnIndex].exportContent
          : ""
      }.joined(separator: ",")
    }.joined(separator: "\n")
  }

  /// Clear all cells in the block. Both ranges must lie within the table
  /// bounds.
  func clear(rowRange: ClosedRange<Int>, columnRange: ClosedRange<Int>) {
    for rowIndex in rowRange {
      for columnIndex in columnRange
      where rows[rowIndex].cells.indices.contains(columnIndex) {
        rows[rowIndex].cells[columnIndex].content = ""
      }
    }
  }

  /// Paste delimited text with its top-left field at the given position,
  /// adding rows and columns as needed.
  func paste(_ text: String, atRow startRow: Int, column startColumn: Int) {
    for (rowOffset, fields) in parseFields(text).enumerated() {
      let rowIndex = startRow + rowOffset
      while rows.count <= rowIndex { addRow() }
      for (columnOffset, field) in fields.enumerated() {
        let columnIndex = startColumn + columnOffset
        while headers.count <= columnIndex { addColumn() }
        while rows[rowIndex].cells.count <= columnIndex {
          rows[rowIndex].cells.append(CSVCell(content: ""))
        }
        rows[rowIndex].cells[columnIndex].content = field
      }
    }
  }

  /// Parse pasted text into a grid of fields, guessing the delimiter
  /// (comma, tab, or semicolon). Falls back to one field per line when the
  /// text isn't parseable.
  private func parseFields(_ text: String) -> [[String]] {
    var trimmed = text
    while let last = trimmed.last, last.isNewline { trimmed.removeLast() }
    guard !trimmed.isEmpty else { return [] }
    if let csv = try? EnumeratedCSV(string: trimmed, loadColumns: false) {
      return [csv.header] + csv.rows
    }
    return trimmed.components(separatedBy: .newlines).map { [$0] }
  }

  //MARK: - Preview

  static var preview: CSVViewModel {
    let vm = CSVViewModel()
    vm.content = sampleCSV
    vm.parseCSV(content: sampleCSV)
    return vm
  }

  static var sampleCSV: String {
    """
    Keyword,Search volume
    swiftui components list,10
    swiftui list not showing,20
    swiftui uitableview,20
    swift tab view,20
    ios tabview,20
    table view swiftui,20
    table swiftui,20
    swift listview,30
    swift list view,30
    swiftui list example,30
    tabitem swiftui,30
    tableview swiftui,40
    tab bar swiftui,50
    swift ui table view,50
    swiftui table view,50
    """
  }
}
